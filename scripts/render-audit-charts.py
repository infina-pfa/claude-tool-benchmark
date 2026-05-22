#!/usr/bin/env python3
"""Render SVG charts from the session-audit summary.

Reads results/_audits/session-audit.json (produced by audit-sessions.py) and
emits a handful of small, dependency-free SVG heatmaps + bar charts into
docs/charts/. Designed to be embedded in docs/index.html and the tool profiles.

Pure stdlib — no matplotlib, no plotly, no seaborn. Run from repo root:
`python3 scripts/render-audit-charts.py`.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIT = ROOT / "results" / "_audits" / "session-audit.json"
CHARTS = ROOT / "docs" / "charts"

TOOLS = ["bmad", "claudekit", "compound", "ecc", "gstack", "omc", "pure", "superpower"]
TASKS = ["feature", "bugfix", "refactor"]


def _esc(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _format_value(value: float, *, decimals: int = 1) -> str:
    if value == int(value):
        return f"{int(value)}"
    return f"{value:.{decimals}f}"


def _color_ramp(t: float, *, lo: str = "#e6f0ff", hi: str = "#1f4ed8") -> str:
    """Linearly interpolate between two hex colors for t in [0, 1]."""
    t = max(0.0, min(1.0, t))

    def hex_to_rgb(h: str) -> tuple[int, int, int]:
        h = h.lstrip("#")
        return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)

    r1, g1, b1 = hex_to_rgb(lo)
    r2, g2, b2 = hex_to_rgb(hi)
    r = int(r1 + (r2 - r1) * t)
    g = int(g1 + (g2 - g1) * t)
    b = int(b1 + (b2 - b1) * t)
    return f"#{r:02x}{g:02x}{b:02x}"


def render_heatmap(
    summary: dict,
    metric_path: tuple[str, str],
    *,
    title: str,
    subtitle: str,
    decimals: int = 1,
    invert_color: bool = False,
) -> str:
    """Render an 8-row × 3-col heatmap of a numeric metric.

    metric_path = (cell_key, stat_key). For example ("wall_clock_min", "mean").
    `invert_color`: if True, smaller values get the darker color (used for
    metrics where lower = more interesting, e.g. cache hit ratio when we want
    to highlight the lowest hit ratios).
    """
    cell_key, stat_key = metric_path
    rows = TOOLS
    cols = TASKS

    def extract(cell: dict) -> float:
        raw = cell.get(cell_key)
        if isinstance(raw, dict):
            val = raw.get(stat_key) if stat_key else None
        else:
            val = raw
        return float(val) if val is not None else 0.0

    values: list[list[float]] = [
        [extract((summary.get(tool) or {}).get(task) or {}) for task in cols]
        for tool in rows
    ]

    flat = [v for row in values for v in row]
    vmin, vmax = (min(flat), max(flat)) if flat else (0.0, 1.0)
    span = vmax - vmin if vmax > vmin else 1.0

    # Layout.
    cell_w, cell_h = 130, 38
    pad_left = 110
    pad_top = 68
    pad_bottom = 30
    pad_right = 16
    width = pad_left + cell_w * len(cols) + pad_right
    height = pad_top + cell_h * len(rows) + pad_bottom

    parts: list[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
        f'role="img" aria-label="{_esc(title)}" style="font-family:Inter,system-ui,sans-serif;">'
    )
    # Title + subtitle.
    parts.append(
        f'<text x="{pad_left}" y="24" font-size="15" font-weight="600" fill="#0f172a">{_esc(title)}</text>'
    )
    parts.append(
        f'<text x="{pad_left}" y="44" font-size="11" fill="#64748b">{_esc(subtitle)}</text>'
    )
    # Column headers.
    for j, task in enumerate(cols):
        cx = pad_left + j * cell_w + cell_w / 2
        parts.append(
            f'<text x="{cx}" y="{pad_top - 8}" text-anchor="middle" font-size="11" '
            f'font-weight="500" fill="#334155">{_esc(task)}</text>'
        )
    # Row labels + cells.
    for i, tool in enumerate(rows):
        ry = pad_top + i * cell_h
        parts.append(
            f'<text x="{pad_left - 8}" y="{ry + cell_h / 2 + 4}" text-anchor="end" '
            f'font-size="12" fill="#0f172a">{_esc(tool)}</text>'
        )
        for j, _ in enumerate(cols):
            cx = pad_left + j * cell_w
            v = values[i][j]
            t = (v - vmin) / span
            if invert_color:
                t = 1 - t
            fill = _color_ramp(t)
            # 0.72 threshold keeps white text on fills dark enough to clear WCAG AA
            # ~4.5:1 contrast on a 13px label. At 0.55 the flip happens on medium-blue
            # (~#7997ea) which falls below AA for body text.
            text_color = "#ffffff" if t > 0.72 else "#0f172a"
            parts.append(
                f'<rect x="{cx}" y="{ry}" width="{cell_w}" height="{cell_h}" '
                f'fill="{fill}" stroke="#e2e8f0" />'
            )
            parts.append(
                f'<text x="{cx + cell_w / 2}" y="{ry + cell_h / 2 + 4}" text-anchor="middle" '
                f'font-size="13" font-weight="500" fill="{text_color}">'
                f'{_format_value(v, decimals=decimals)}</text>'
            )
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def render_summary_bar(summary: dict, *, title: str) -> str:
    """Render a horizontal bar chart of feature-task wall-clock per tool, sorted desc."""
    feature_wall = []
    for tool in TOOLS:
        cell = (summary.get(tool) or {}).get("feature") or {}
        v = ((cell.get("wall_clock_min") or {}).get("mean")) or 0.0
        feature_wall.append((tool, float(v)))
    feature_wall.sort(key=lambda x: x[1], reverse=True)

    vmax = max(v for _, v in feature_wall) or 1.0
    row_h = 26
    pad_left = 110
    pad_top = 64
    pad_bottom = 26
    pad_right = 80
    bar_max_w = 380
    width = pad_left + bar_max_w + pad_right
    height = pad_top + row_h * len(feature_wall) + pad_bottom

    parts: list[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
        f'role="img" aria-label="{_esc(title)}" style="font-family:Inter,system-ui,sans-serif;">'
    )
    parts.append(
        f'<text x="{pad_left}" y="24" font-size="15" font-weight="600" fill="#0f172a">{_esc(title)}</text>'
    )
    parts.append(
        f'<text x="{pad_left}" y="44" font-size="11" fill="#64748b">'
        f'Mean across 3 trials. Wall-clock = first→last assistant timestamp in the session.</text>'
    )

    for i, (tool, v) in enumerate(feature_wall):
        ry = pad_top + i * row_h
        bar_w = (v / vmax) * bar_max_w if vmax else 0
        parts.append(
            f'<text x="{pad_left - 8}" y="{ry + row_h / 2 + 4}" text-anchor="end" '
            f'font-size="12" fill="#0f172a">{_esc(tool)}</text>'
        )
        parts.append(
            f'<rect x="{pad_left}" y="{ry + 4}" width="{bar_w}" height="{row_h - 10}" '
            f'fill="#1f4ed8" rx="2" />'
        )
        parts.append(
            f'<text x="{pad_left + bar_w + 6}" y="{ry + row_h / 2 + 4}" '
            f'font-size="12" fill="#0f172a">{_format_value(v, decimals=1)} min</text>'
        )
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def main() -> int:
    if not AUDIT.exists():
        print(f"ERROR: {AUDIT} not found. Run scripts/audit-sessions.py first.", file=sys.stderr)
        return 1

    summary = json.loads(AUDIT.read_text())
    CHARTS.mkdir(parents=True, exist_ok=True)

    charts: dict[str, str] = {
        "subagent-dispatch.svg": render_heatmap(
            summary,
            ("subagent_dispatches", "mean"),
            title="Sub-agent dispatch per tool × task",
            subtitle="Mean `Agent` tool calls per trial (3 trials per cell).",
            decimals=1,
        ),
        "wallclock-min.svg": render_heatmap(
            summary,
            ("wall_clock_min", "mean"),
            title="Wall-clock minutes per trial",
            subtitle="First→last assistant timestamp; ecc-feature ≈634 min is session lifetime.",
            decimals=1,
        ),
        "tool-config-reads.svg": render_heatmap(
            summary,
            ("tool_config_reads", "mean"),
            title="Tool-config file reads per trial",
            subtitle="Reads of the setup's own scaffolding (.claude/, _bmad/, .omc/) — the 'setup tax'.",
            decimals=1,
        ),
        "cache-hit-ratio.svg": render_heatmap(
            summary,
            ("cache_hit_ratio_mean", None),
            title="Cache hit ratio (prompt-cache efficiency)",
            subtitle="cache_read / (cache_read + cache_creation). Lower = more re-creation.",
            decimals=2,
            invert_color=True,
        ),
        "feature-wallclock-bar.svg": render_summary_bar(
            summary,
            title="Feature task — wall-clock minutes per setup (sorted)",
        ),
    }

    for name, svg in charts.items():
        (CHARTS / name).write_text(svg)
        print(f"[charts] {name}")

    # Emit an index.md for the charts directory.
    (CHARTS / "README.md").write_text(
        "# Session-audit charts\n\n"
        "Auto-generated by `scripts/render-audit-charts.py` from "
        "`results/_audits/session-audit.json`. Embed any of these in markdown via "
        "`![](docs/charts/<name>.svg)` or in HTML via `<img src=\"charts/<name>.svg\" />`.\n\n"
        + "\n".join(f"- `{name}`" for name in sorted(charts))
        + "\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
