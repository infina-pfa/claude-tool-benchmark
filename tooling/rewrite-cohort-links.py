#!/usr/bin/env python3
"""
Rewrite cohort-artifact GitHub deep-links to on-site previews.

Phase 2D of .omc/plans/restructure-plan.md (with routing-table amendments from
the user-supplied task brief). Sweeps docs/index.html, docs/preview/*.html,
and docs/tools/*.md, repointing every
  https://github.com/infina-pfa/claude-tool-benchmark/(blob|tree)/main/<path>
URL according to the routing maps below.

Output: per-file summary + totals.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Links we LEAVE alone — framework artifacts that stay on infina/main.
KEEP_PATHS = {
    "LICENSE",
    "README.md",
    "docs/README.md",
    "docs/guides/verification.md",
    "docs/guides/quickstart.md",
    "docs/guides/extending.md",
    "scripts/audit-sessions.py",
    "scripts/compute-robust-stats.py",
    "scripts/manual-bench.sh",
    "versions.lock.json",
}

# Cohort-artifact paths → on-site preview path (relative to docs/).
REPOINT_TO_PREVIEW = {
    "docs/IMPROVEMENT-PLAN-NEXT-COHORT.md":          "preview/improvement-plan-next-cohort.html",
    "PAPER.md":                                       "preview/paper.html",
    "PAPER.md#2-results":                             "preview/paper.html",
    "PAPER.md#4-limitations-and-threats-to-validity": "preview/paper.html",
    "PAPER.md#6-reproducibility":                     "preview/paper.html",
    "docs/analysis/feature-cohort.md":                "preview/analysis-feature-cohort.html",
    "docs/analysis/skill-cost-efficiency.md":         "preview/analysis-skill-cost-efficiency.html",
    "docs/RERUN-PRE-PUBLISH.md":                      "preview/rerun-pre-publish.html",
    "docs/tools/README.md":                           "preview/tool-README.html",
    "docs/tools/bmad.md":                             "preview/tool-bmad.html",
    "docs/tools/claudekit.md":                        "preview/tool-claudekit.html",
    "docs/tools/compound.md":                         "preview/tool-compound.html",
    "docs/tools/ecc.md":                              "preview/tool-ecc.html",
    "docs/tools/gstack.md":                           "preview/tool-gstack.html",
    "docs/tools/omc.md":                              "preview/tool-omc.html",
    "docs/tools/pure.md":                             "preview/tool-pure.html",
    "docs/tools/superpower.md":                       "preview/tool-superpower.html",
    "results/_audits/session-audit.md":               "preview/session-audit.html",
    "results/final-report.md":                        "preview/final-report-feature.html",
    "results/final-report.equal-weight.md":           "preview/final-report-feature-eqw.html",
    "results/bugfix/final-report.md":                 "preview/final-report-bugfix.html",
    "results/bugfix/final-report.equal-weight.md":    "preview/final-report-bugfix-eqw.html",
    "results/refactor/final-report.md":               "preview/final-report-refactor.html",
    "results/refactor/final-report.equal-weight.md":  "preview/final-report-refactor-eqw.html",
    "results/robust-statistics-companion.md":         "preview/robust-statistics-companion.html",
}

# Paths whose link should be DROPPED (anchor text retained).
DROP_LINK_PATHS = {
    "results/robust-statistics.json",
    "results/refactor/_blind-eval/.mapping-DO-NOT-OPEN.json",
    "docs/tools",
    "results",
    "CLAUDE.md",
    "CLAUDE.md#rerun-protocol-pre-registered",
}

URL_RE = re.compile(
    r"https://github\.com/infina-pfa/claude-tool-benchmark/(?:blob|tree)/main/([^\"\)\s<>]+)"
)


def relpath_for(file_rel: Path, preview_target: str) -> str:
    """
    Resolve preview_target (e.g. 'preview/paper.html') relative to file_rel
    (which is a path under docs/, e.g. 'docs/preview/foo.html').
    All file_rel are under docs/, so:
      - docs/index.html     -> 'preview/paper.html'
      - docs/preview/x.html -> 'paper.html'  (sibling) or '../<x>' for non-preview targets
      - docs/tools/x.md     -> '../preview/paper.html'
    preview_target always starts with 'preview/'.
    """
    parts = file_rel.parts
    # file_rel like ("docs", "index.html") or ("docs", "preview", "x.html") or ("docs", "tools", "x.md")
    assert parts[0] == "docs"
    if len(parts) == 2:
        # docs/index.html
        return preview_target
    sub = parts[1]
    if sub == "preview":
        # Strip the leading 'preview/' since we're inside it.
        return preview_target[len("preview/"):]
    if sub == "tools":
        return "../" + preview_target
    # Fallback (shouldn't happen with current scope)
    return preview_target


def rewrite_html(content: str, file_rel: Path) -> tuple[str, int, int, int]:
    """Return (new_content, repointed, kept, dropped) for HTML files."""
    repointed = 0
    kept = 0
    dropped = 0

    # 1) Repoint URLs inside attributes (href/src) and inside <code>/text.
    # Match the URL anywhere; substitute the URL itself with a new URL or relative path.
    # For DROP we'll later strip the <a> wrapper.
    def repoint_url(m: re.Match) -> str:
        nonlocal repointed, kept
        path = m.group(1)
        if path in REPOINT_TO_PREVIEW:
            repointed += 1
            return relpath_for(file_rel, REPOINT_TO_PREVIEW[path])
        if path in KEEP_PATHS:
            kept += 1
            return m.group(0)
        if path in DROP_LINK_PATHS:
            # Leave the URL string in place for now; the <a>-wrapper-strip pass below
            # will drop the wrapping anchor. (If we replaced the URL here, the regex
            # below would still match the anchor; we use a sentinel instead.)
            return "__DROP_LINK_SENTINEL__"
        # Unknown path: leave alone, count as kept (will be flagged by verify step).
        kept += 1
        return m.group(0)

    content = URL_RE.sub(repoint_url, content)

    # 2) For DROP_LINK_PATHS we replaced the URL with __DROP_LINK_SENTINEL__.
    # Now strip <a ...="__DROP_LINK_SENTINEL__"...>TEXT</a> -> TEXT.
    drop_anchor_re = re.compile(
        r'<a\b[^>]*?(?:href|src)="__DROP_LINK_SENTINEL__"[^>]*>(.*?)</a>',
        re.DOTALL,
    )

    def drop_anchor(m: re.Match) -> str:
        nonlocal dropped
        dropped += 1
        return m.group(1)

    content = drop_anchor_re.sub(drop_anchor, content)
    # Any leftover sentinels (URL not wrapped in <a>) just become the empty path.
    leftover = content.count("__DROP_LINK_SENTINEL__")
    if leftover:
        content = content.replace("__DROP_LINK_SENTINEL__", "")
        dropped += leftover
    return content, repointed, kept, dropped


def rewrite_md(content: str, file_rel: Path) -> tuple[str, int, int, int]:
    """Return (new_content, repointed, kept, dropped) for markdown files."""
    repointed = 0
    kept = 0
    dropped = 0

    # 1) Markdown link [text](URL) — handle DROP first by collapsing to text.
    md_link_re = re.compile(
        r"\[([^\]]+)\]\((https://github\.com/infina-pfa/claude-tool-benchmark/(?:blob|tree)/main/([^\)\s]+))\)"
    )

    def md_link(m: re.Match) -> str:
        nonlocal repointed, kept, dropped
        text, _url, path = m.group(1), m.group(2), m.group(3)
        if path in REPOINT_TO_PREVIEW:
            repointed += 1
            return f"[{text}]({relpath_for(file_rel, REPOINT_TO_PREVIEW[path])})"
        if path in KEEP_PATHS:
            kept += 1
            return m.group(0)
        if path in DROP_LINK_PATHS:
            dropped += 1
            return text
        kept += 1
        return m.group(0)

    content = md_link_re.sub(md_link, content)

    # 2) Bare URLs not in a markdown link — repoint URL only (no wrapper to drop).
    def bare_url(m: re.Match) -> str:
        nonlocal repointed, kept, dropped
        path = m.group(1)
        if path in REPOINT_TO_PREVIEW:
            repointed += 1
            return relpath_for(file_rel, REPOINT_TO_PREVIEW[path])
        if path in DROP_LINK_PATHS:
            # No wrapper to drop in markdown; just remove the URL.
            dropped += 1
            return ""
        kept += 1
        return m.group(0)

    content = URL_RE.sub(bare_url, content)
    return content, repointed, kept, dropped


def main() -> int:
    targets: list[Path] = []
    targets.append(ROOT / "docs" / "index.html")
    targets.extend(sorted((ROOT / "docs" / "preview").glob("*.html")))
    targets.extend(sorted((ROOT / "docs" / "tools").glob("*.md")))

    total_files = 0
    total_repointed = 0
    total_kept = 0
    total_dropped = 0

    for path in targets:
        if not path.exists():
            continue
        rel = path.relative_to(ROOT)
        original = path.read_text(encoding="utf-8")
        if path.suffix == ".md":
            new, repointed, kept, dropped = rewrite_md(original, rel)
        else:
            new, repointed, kept, dropped = rewrite_html(original, rel)
        if new != original:
            path.write_text(new, encoding="utf-8")
            total_files += 1
            print(f"{rel}: {repointed} repointed, {kept} kept, {dropped} dropped")
        elif repointed or dropped:
            # Should not happen (no-op rewrite means new == original).
            print(f"{rel}: no diff but {repointed}/{dropped} reported (sanity check)")
        else:
            # All matches were KEEP (or no matches at all) — only report if there were matches.
            if kept:
                print(f"{rel}: 0 repointed, {kept} kept, 0 dropped (no diff)")
        total_repointed += repointed
        total_kept += kept
        total_dropped += dropped

    print()
    print(
        f"TOTALS: {total_files} files modified, "
        f"{total_repointed} links repointed, "
        f"{total_kept} kept, "
        f"{total_dropped} dropped"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
