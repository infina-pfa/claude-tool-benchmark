#!/usr/bin/env python3
"""Compute minimum detectable effect (MDE) per task for tool-vs-tool comparisons.

Two-sample two-sided t-test, alpha=0.05, power=0.80. The effective sample size
is the trial count per cell (n=5 in the current cohort), NOT the judgment count
(N=75) — judgments within a cell are correlated (same judge repeats across
rounds, same trial repeats across rounds), so trials are the real degree of
freedom for output quality.

We use the per-trial weighted means (matching the canonical aggregator) as
the unit of comparison. σ is pooled across the 8 tools within each task.

MDE formula (two-sample, equal n):
    MDE = (t_{α/2, df} + z_β) × σ_pool × sqrt(2/n),  df = 2(n-1)

The α/2 critical value is the exact Student-t quantile for df = 2(n-1) = 8
(n=5 per arm), NOT the normal z=1.96 — at n=5 the t correction is material
(MDE ~12% larger). z_β=0.84 is retained for the power term as a deliberate
conservative approximation: the exact power term is a noncentral-t inverse
(needs scipy, not a project dependency); keeping the normal z_β makes the
reported MDE a conservative lower bound on the true t-based MDE.

Reports MDE alongside observed pair-gaps so a reader can see which "leads"
exceed the detection threshold.
"""

import json
import math
import os
import re
import statistics
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TASKS = ("feature", "bugfix", "refactor")
JUDGES = ("opus", "grok420", "glm51", "gpt54pro", "mimo25pro")
JUDGE_WEIGHTS = {"opus": 3, "gpt54pro": 2, "grok420": 1, "glm51": 1, "mimo25pro": 1}
ROUND_RE = re.compile(r"^round[0-9]+$")
# Two-sided α=0.05 critical value. Exact Student-t quantile t(0.975, df) for
# df = 2(n-1) = 8 at the locked cohort n=5. Hardcoded because scipy is not a
# project dependency; the use site asserts n==5 so any cohort-size change
# (versions.lock.json cohort_size.trials_per_cell) trips and forces this update.
T_ALPHA_2_DF8 = 2.306004
Z_BETA = 0.84  # power=0.80 (normal approx; conservative — see module docstring)


def task_eval_dir(task):
    return (
        f"{ROOT}/results/_blind-eval"
        if task == "feature"
        else f"{ROOT}/results/{task}/_blind-eval"
    )


def sum_scores(d):
    s = d.get("scores")
    if isinstance(s, dict) and s:
        return float(sum(s.values()))
    return None


def trial_weighted_means(task):
    """Returns {tool: [t1_mean, t2_mean, ...]} over all trials present."""
    eval_dir = task_eval_dir(task)
    mapping = json.load(open(f"{eval_dir}/.mapping-DO-NOT-OPEN.json"))["mapping"]
    raw = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for label, info in mapping.items():
        tool, trial = info["tool"], info["trial"]
        label_dir = f"{eval_dir}/{label}"
        if not os.path.isdir(label_dir):
            continue
        round_dirs = [label_dir] + sorted(
            os.path.join(label_dir, d)
            for d in os.listdir(label_dir)
            if os.path.isdir(os.path.join(label_dir, d)) and ROUND_RE.match(d)
        )
        for rd in round_dirs:
            for j in JUDGES:
                fp = f"{rd}/{j}-judge.json"
                if not os.path.isfile(fp) or os.path.getsize(fp) == 0:
                    continue
                try:
                    total = sum_scores(json.load(open(fp)))
                except Exception:
                    total = None
                if total is not None:
                    raw[tool][trial][j].append(total)
    out = {}
    for tool, trials in raw.items():
        means = []
        for t in sorted(trials):
            judges = trials.get(t) or {}
            num = den = 0.0
            for j in JUDGES:
                vals = judges.get(j) or []
                if not vals:
                    continue
                w = JUDGE_WEIGHTS.get(j, 1)
                num += w * statistics.mean(vals)
                den += w
            if den:
                means.append(num / den)
        out[tool] = means
    return out


def main() -> int:
    out = {
        "method": "Two-sample two-sided t-test, α=0.05, power=0.80, n=trials per arm (cohort n); α/2 critical = exact Student-t t(0.975, df=2(n-1)); z_β normal approx (conservative); σ pooled across tools per task",
        "t_alpha_2": T_ALPHA_2_DF8,
        "df": 8,
        "z_beta": Z_BETA,
        "tasks": {},
    }
    for task in TASKS:
        per_tool = trial_weighted_means(task)
        # σ across the trials per tool, then pool
        per_tool_sd = []
        for tool, means in per_tool.items():
            if len(means) >= 2:
                per_tool_sd.append(statistics.stdev(means))
        if not per_tool_sd:
            continue
        sigma_pool = math.sqrt(sum(s ** 2 for s in per_tool_sd) / len(per_tool_sd))
        n = max((len(m) for m in per_tool.values()), default=0)
        # T_ALPHA_2_DF8 is the exact t(0.975) quantile for df = 2(n-1) = 8,
        # valid only at the locked cohort n=5. If cohort size changes, this
        # constant must be recomputed for the new df.
        assert n == 5, (
            f"T_ALPHA_2_DF8 is hardcoded for n=5 (df=8); got n={n}. "
            f"Recompute t(0.975, df=2(n-1)) for the new cohort size."
        )
        mde = (T_ALPHA_2_DF8 + Z_BETA) * sigma_pool * math.sqrt(2.0 / n)
        # Tool means and pair gaps
        tool_means = {t: statistics.mean(m) if m else 0.0 for t, m in per_tool.items()}
        # find rank-1 lead over rank-2
        ranked = sorted(tool_means.items(), key=lambda x: -x[1])
        rank1_gap = ranked[0][1] - ranked[1][1] if len(ranked) >= 2 else 0
        # gaps between consecutive ranks
        consec_gaps = [
            (ranked[i][0], ranked[i + 1][0], ranked[i][1] - ranked[i + 1][1])
            for i in range(len(ranked) - 1)
        ]
        # gap rank1 vs each lower tool
        gaps_from_rank1 = [
            (ranked[0][0], t, ranked[0][1] - m) for t, m in ranked[1:]
        ]
        out["tasks"][task] = {
            "n_per_arm": n,
            "sigma_pool": sigma_pool,
            "mde_pts": mde,
            "rank1_lead_pts": rank1_gap,
            "rank1_lead_significant": rank1_gap > mde,
            "consec_gaps": [
                {"a": a, "b": b, "gap": g, "significant": g > mde}
                for a, b, g in consec_gaps
            ],
            "gaps_from_rank1": [
                {"top": t, "vs": v, "gap": g, "significant": g > mde}
                for t, v, g in gaps_from_rank1
            ],
        }
        print(
            f"{task:<10} σ_pool={sigma_pool:6.2f}  MDE={mde:6.2f}  rank1_lead={rank1_gap:6.2f}  significant={rank1_gap > mde}",
            file=sys.stderr,
        )

    out_path = f"{ROOT}/results/power-analysis.json"
    with open(out_path, "w") as f:
        json.dump(out, f, indent=2)
    print(f"Wrote {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
