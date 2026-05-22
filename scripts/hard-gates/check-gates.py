#!/usr/bin/env python3
"""
Static hard-gate probe for Mode 2 CD Batch implementations.

Scope: files changed in the trial's diff (base commit from results/<tool>/t<trial>/commits.txt).

Gates:
  G1: Buy price = face × (1 + rate × aging / 365)  — combined or decomposed form
  G2: Interest principal is face_value, NOT buy_price/marketPrice
  G3: Coupon-aware CD aging (last_payment_date / payment cycle logic)
  G5: Timeout/cancel path releases reserved inventory (spec asserts FAILED/release)

Usage: check-gates.py <tool> <trial>
Writes: results/<tool>/t<trial>/hard-gates.json
"""
import json, re, subprocess, sys
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


def diff_files(clone: Path, base_sha: str) -> list[Path]:
    """Return absolute paths of .ts files changed since base_sha."""
    try:
        out = subprocess.check_output(
            ["git", "-C", str(clone), "diff", "--name-only", f"{base_sha}..HEAD", "--", "*.ts"],
            text=True,
        )
    except subprocess.CalledProcessError:
        return []
    return [clone / line for line in out.splitlines() if line]


_BLOCK_COMMENT = re.compile(r"/\*[\s\S]*?\*/")
_LINE_COMMENT = re.compile(r"//[^\n]*")


def strip_comments(src: str) -> str:
    """Remove TS/JS comments so pattern matching only inspects executable code."""
    return _LINE_COMMENT.sub("", _BLOCK_COMMENT.sub("", src))


def _balanced_block(src: str, open_idx: int) -> str:
    """Return the substring between matching `{` and `}` starting at open_idx (which points at `{`)."""
    if open_idx < 0 or open_idx >= len(src) or src[open_idx] != "{":
        return ""
    depth = 0
    for i in range(open_idx, len(src)):
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return src[open_idx + 1 : i]
    return src[open_idx + 1 :]


def collect_text(paths: list[Path]):
    impl, spec = [], []
    for p in paths:
        if not p.exists():
            continue
        name = p.name
        try:
            content = strip_comments(p.read_text())
        except Exception:
            continue
        bucket = spec if name.endswith(".spec.ts") or name.endswith(".test.ts") else impl
        try:
            rel = p.relative_to(REPO)
        except ValueError:
            rel = p
        bucket.append(f"=== {rel} ===\n{content}")
    return "\n\n".join(impl), "\n\n".join(spec)


def check_g1(impl_text: str) -> str:
    """G1: face × (1 + rate × aging / 365) — combined or decomposed.

    Accepts both `face*` and `principal*` named bases (PRD glossary equates them).
    """
    base = r"(?:face|principal)[A-Za-z_]*"
    combined = [
        rf"{base}\s*\*\s*\(\s*1\s*\+\s*[^;{{}}]{{1,200}}?\/\s*365",
        rf"\(\s*1\s*\+\s*[^;{{}}]{{1,200}}?\/\s*365\s*\)\s*\*\s*{base}",
    ]
    # Decomposed: `accruedInterest = base × rate × days / 365`, then `buy = base + accrued`
    decomposed_accrued = re.search(
        rf"{base}\s*\*\s*[A-Za-z_]*(?:[Rr]ate|[Ii]nterest)[A-Za-z_]*\s*\*\s*[A-Za-z_]*(?:[Aa]ging|[Dd]ays)[A-Za-z_]*\s*\/\s*365",
        impl_text, re.DOTALL,
    )
    # Equivalent: base + base × rate × days / 365
    sum_form = re.search(
        rf"{base}\s*\+\s*{base}\s*\*\s*[^;{{}}]{{1,200}}?\/\s*365",
        impl_text, re.I | re.DOTALL,
    )
    combined_hit = any(re.search(p, impl_text, re.IGNORECASE | re.DOTALL) for p in combined)

    bad_divisor = bool(re.search(
        rf"{base}\s*\*\s*\(\s*1\s*\+\s*[^;{{}}]{{1,200}}?\/\s*360\b",
        impl_text, re.I | re.DOTALL,
    ))
    if bad_divisor:
        return "FAIL"
    if combined_hit or decomposed_accrued or sum_form:
        return "PASS"
    return "FAIL"  # No formula in diff scope → implementation missing


def check_g2(impl_text: str) -> str:
    """G2: interest principal = face/principal, NOT buy/market price."""
    bad = bool(re.search(
        r"(?:buy[_P]rice|market[_P]rice)[A-Za-z_]*\s*\*\s*[^;{}]{0,120}?(?:rate|interest)[A-Za-z_]*\s*\*\s*[^;{}]{0,120}?\/\s*365",
        impl_text, re.I | re.DOTALL,
    ))
    good = bool(re.search(
        r"(?:face[_V]alue|principal[_A]?mount|principal)[A-Za-z_]*\s*\*\s*[^;{}]{0,120}?(?:rate|interest)[A-Za-z_]*\s*\*\s*[^;{}]{0,120}?\/\s*365",
        impl_text, re.I | re.DOTALL,
    ))
    # Balanced-brace extraction of getInterestPrincipal body (handles nested braces).
    gip_match = re.search(r"getInterestPrincipal[^{]*\{", impl_text, re.DOTALL)
    if gip_match:
        gip_body = _balanced_block(impl_text, gip_match.end() - 1)
    else:
        gip_body = ""
    gip_uses_principal = bool(re.search(r"\b(principal|face)", gip_body, re.I))
    gip_uses_buy = bool(re.search(r"(buy[_P]rice|market)", gip_body, re.I))

    if bad or gip_uses_buy:
        return "FAIL"
    if good or gip_uses_principal:
        return "PASS"
    return "UNDETERMINED"


def check_g3(impl_text: str) -> str:
    """G3: coupon-aware CD aging logic."""
    cycle_logic = bool(re.search(
        r"(last[_P]ayment[_D]ate|lastPaymentDate|paymentCycleDays|payment[_C]ycle|PAYMENT_CYCLE|paymentCycleToDays|getPaymentCycleDays)",
        impl_text,
    ))
    freq_handling = bool(re.search(
        r"(QUARTERLY|SEMI[_-]?ANNUALLY|MONTHLY|interestPaymentFrequency|AT_MATURITY)",
        impl_text, re.I,
    ))
    reset_math = bool(re.search(
        r"(Math\.floor\s*\([^)]*?cycle|completedCycles|periodsElapsed|completedPeriods|%\s*paymentCycle)",
        impl_text, re.I | re.DOTALL,
    ))
    score = cycle_logic + freq_handling + reset_math
    if score >= 2:
        return "PASS"
    if score == 1:
        return "UNDETERMINED"
    return "FAIL"


def check_g5(impl_text: str, spec_text: str) -> str:
    """G5: timeout/cancel releases reserved inventory.

    Promotes correct-impl-without-test from UNDETERMINED to PASS when both a
    timeout/cancel branch *and* a release-side token are present in impl.
    """
    spec_trigger = bool(re.search(r"(timeout|cancel|expir)", spec_text, re.I))
    spec_assert = bool(re.search(
        r"(['\"]FAILED['\"]|release|restored|returnToPool|reservedUnits\s*\+|inventory.*release|availableUnits\s*\+)",
        spec_text, re.I,
    ))
    impl_trigger_failed = bool(re.search(
        r"(timeout|expir|cancel)[^{}]{0,300}?FAILED",
        impl_text, re.I | re.DOTALL,
    ))
    impl_release_token = bool(re.search(
        r"(release[A-Za-z]*|returnToPool|restoreInventory|availableUnits\s*\+|reservedUnits\s*-)",
        impl_text, re.I,
    ))
    if spec_trigger and spec_assert:
        return "PASS"
    if impl_trigger_failed and impl_release_token:
        return "PASS"
    if impl_trigger_failed or impl_release_token:
        return "UNDETERMINED"
    return "FAIL"


def check_g6(impl_text: str, spec_text: str) -> str:
    """G6: units = floor(X / buy_price). Strict — only accept floor over a price-named denominator."""
    combined = impl_text + "\n" + spec_text
    floor_div = bool(re.search(
        r"Math\.floor\s*\(\s*[A-Za-z_.]+\s*\/\s*[A-Za-z_.]*(?:buy[_P]rice|buyPrice|marketPrice|price[A-Za-z_]*)",
        combined, re.I,
    ))
    return "PASS" if floor_div else "FAIL"


def check_g7(impl_text: str, spec_text: str) -> str:
    """G7: inventory reservation on CONFIRMED order (units decrement + CONFIRMED state).

    Accepts both string-literal `'CONFIRMED'` and enum form `.CONFIRMED`.
    Window widened to 600 chars (cross-helper-method reservation logic).
    """
    confirmed_token = r"(?:['\"]CONFIRMED['\"]|\.CONFIRMED\b)"
    reservation_token = r"(?:reserve[dA-Za-z]*|availableUnits|reservedUnits|decrement|subtract)"
    reservation_near_confirmed = bool(re.search(
        rf"{reservation_token}[^{{}}]{{0,600}}?{confirmed_token}"
        rf"|{confirmed_token}[^{{}}]{{0,600}}?{reservation_token}",
        impl_text, re.I | re.DOTALL,
    ))
    spec_evidence = bool(
        re.search(r"(reserve|reservation|availableUnits|reservedUnits)", spec_text, re.I)
        and re.search(confirmed_token, spec_text)
    )
    if reservation_near_confirmed:
        return "PASS"
    if spec_evidence:
        return "UNDETERMINED"
    return "FAIL"


def main():
    if len(sys.argv) != 3:
        print("Usage: check-gates.py <tool> <trial>", file=sys.stderr)
        sys.exit(1)
    tool, trial = sys.argv[1], sys.argv[2]
    clone = REPO / "runs" / f"{tool}-t{trial}"
    commits_txt = REPO / "results" / tool / f"t{trial}" / "commits.txt"

    if not commits_txt.exists():
        print(f"FATAL: {commits_txt} missing (base SHA not captured)", file=sys.stderr)
        sys.exit(1)

    base_sha = commits_txt.read_text().splitlines()[0].strip()
    files = diff_files(clone, base_sha)

    if not files:
        result = {
            "tool": tool, "trial": int(trial),
            "base": base_sha, "scope_files": 0,
            "error": "no .ts files in diff",
            "gates": {}, "summary": {},
        }
    else:
        impl_text, spec_text = collect_text(files)
        gates = {
            "G1": check_g1(impl_text),
            "G2": check_g2(impl_text),
            "G3": check_g3(impl_text),
            "G5": check_g5(impl_text, spec_text),
            "G6": check_g6(impl_text, spec_text),
            "G7": check_g7(impl_text, spec_text),
        }
        result = {
            "tool": tool, "trial": int(trial),
            "base": base_sha, "scope_files": len(files),
            "gates": gates,
            "summary": {
                "pass": sum(1 for v in gates.values() if v == "PASS"),
                "fail": sum(1 for v in gates.values() if v == "FAIL"),
                "undetermined": sum(1 for v in gates.values() if v == "UNDETERMINED"),
            },
        }

    out_dir = REPO / "results" / tool / f"t{trial}"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "hard-gates.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
