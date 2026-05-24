#!/usr/bin/env node
// render-md-previews.mjs — pre-render referenced .md files to docs/preview/*.html
// so the landing page can link readers directly to rendered content without
// GitHub's raw-markdown fallback.
//
// Usage:
//   node scripts/render-md-previews.mjs           # render all, write to docs/preview/
//   node scripts/render-md-previews.mjs --check   # exit 1 if any preview is stale
//
// Output: one self-contained .html per source .md, styled to match the landing
// page's Claude-inspired editorial aesthetic (warm parchment, Source Serif 4).
// Output is fully static — no runtime JS — so Cloudflare Pages serves it flat.

import { readFile, writeFile, mkdir, stat, access } from "node:fs/promises";
import { dirname, relative, resolve, basename, extname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createRequire } from "node:module";
import process from "node:process";

const require = createRequire(import.meta.url);

// -----------------------------------------------------------------------------
// Config — the set of .md files worth rendering to HTML preview.
// -----------------------------------------------------------------------------

const __filename = fileURLToPath(import.meta.url);
const ROOT = resolve(dirname(__filename), "..");
const OUT_DIR = resolve(ROOT, "docs/preview");
const TIMELINE_BASE = resolve(ROOT, "docs/analysis/trial-timelines");
const TIMELINE_TASKS = ["feature", "bugfix", "refactor"];

// Paths kept on the private webpage-source branch but scrubbed from the public
// infina-pfa/claude-tool-benchmark repo (per 18607d9). The "Source on GitHub →"
// button would 404 for these — suppress it instead.
const PUBLIC_REPO_ABSENT_PREFIXES = [
  "PAPER.md",
  "results/",
  "docs/analysis/",
  "docs/announcements/",
  "docs/charts/",
  "docs/RERUN-PRE-PUBLISH.md",
  "docs/IMPROVEMENT-PLAN-NEXT-COHORT.md",
  "METHODOLOGY-FLOW-VISUAL.md",
];
function isPublicRepoAbsent(p) {
  return PUBLIC_REPO_ABSENT_PREFIXES.some(prefix => p === prefix || p.startsWith(prefix));
}

// Colour palette for bash-kind segments — matches the editorial palette in preview.css
const BASH_KIND_COLORS = {
  "tests":         "#d97757",
  "other":         "#87867f",
  "inspection":    "#a3b18a",
  "typecheck":     "#5b8ca8",
  "lint/format":   "#c8a265",
  "git ops":       "#c96442",
  "install/build": "#8a6fa3",
};

const SOURCES = [
  // Top-level papers
  { src: "README.md",                                     out: "readme.html",                 title: "README — AI Tool Benchmark" },
  { src: "PAPER.md",                                      out: "paper.html",                  title: "Paper — AI Tool Benchmark" },

  // Per-task reports
  { src: "results/final-report.md",                       out: "final-report-feature.html",   title: "Final Report — feature (5-judge weighted)" },
  { src: "results/final-report.equal-weight.md",          out: "final-report-feature-eqw.html", title: "Final Report — feature (equal-weight comparator)" },
  { src: "results/bugfix/final-report.md",                out: "final-report-bugfix.html",    title: "Final Report — bugfix (5-judge weighted)" },
  { src: "results/bugfix/final-report.equal-weight.md",   out: "final-report-bugfix-eqw.html", title: "Final Report — bugfix (equal-weight comparator)" },
  { src: "results/refactor/final-report.md",              out: "final-report-refactor.html",  title: "Final Report — refactor (5-judge weighted)" },
  { src: "results/refactor/final-report.equal-weight.md", out: "final-report-refactor-eqw.html", title: "Final Report — refactor (equal-weight comparator)" },
  { src: "results/robust-statistics-companion.md",        out: "robust-statistics-companion.html", title: "Robust-statistics Companion (median / trimmed mean)" },
  { src: "results/_audits/session-audit.md",              out: "session-audit.html",          title: "Session Audit — Cohort Behavioural Fingerprints" },
  { src: "docs/IMPROVEMENT-PLAN-NEXT-COHORT.md",          out: "improvement-plan-next-cohort.html", title: "Improvement Plan — Next Cohort" },
  { src: "docs/RERUN-PRE-PUBLISH.md",                     out: "rerun-pre-publish.html",      title: "Pre-publish Rerun Runbook" },

  // Reader guides
  { src: "docs/README.md",                                out: "docs-index.html",             title: "docs/ — Folder Index" },
  { src: "docs/guides/verification.md",                   out: "guide-verification.html",     title: "Verification Guide" },
  { src: "docs/guides/quickstart.md",                     out: "guide-quickstart.html",       title: "Quickstart — One Trial in 10 Minutes" },
  { src: "docs/guides/extending.md",                      out: "guide-extending.html",        title: "Extending — Add a Tool or Judge" },

  // Tool profiles (auto-generated list; see below)
  { glob: "docs/tools/*.md", outPrefix: "tool-", titlePrefix: "Tool Profile — " },

  // Analysis (Phase 3)
  { glob: "docs/analysis/*.md", outPrefix: "analysis-", titlePrefix: "Analysis — " },

  // (older methodology + trial-timeline pages live under docs/v1-archive/ and are not pre-rendered.)
];

// -----------------------------------------------------------------------------
// Trial-timeline tab injection (tool profile pages only)
// -----------------------------------------------------------------------------

function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function loadTrialData(tool) {
  const out = {};
  for (const task of TIMELINE_TASKS) {
    const p = resolve(TIMELINE_BASE, task, `${tool}.json`);
    try {
      const text = await readFile(p, "utf8");
      out[task] = JSON.parse(text);
    } catch {
      out[task] = [];
    }
  }
  return out;
}

function renderTrialCard(trial) {
  const chips = [];
  const push = (label, value) => {
    if (value === undefined || value === null || value === 0) return;
    chips.push(
      `<li class="trial-chip"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></li>`
    );
  };
  push("Agents", trial.subagents?.count);
  push("New files", trial.mutations?.new_files);
  push("Edits", trial.mutations?.edits);
  push("Bash", trial.bash?.total);
  push("Skills", trial.skill_activations?.total);
  push("Skill files", trial.plugin_skill_files?.total_unique);
  if ((trial.sessions || 1) > 1) push("Sessions", trial.sessions);
  if (trial.planning_todos?.count) push("Todos", trial.planning_todos.count);

  // Bash breakdown bar
  const bashTotal = trial.bash?.total || 0;
  let bashBlock = "";
  if (bashTotal > 0 && Array.isArray(trial.bash?.by_kind)) {
    const segs = trial.bash.by_kind.map((k) => {
      const pct = (k.count / bashTotal) * 100;
      const color = BASH_KIND_COLORS[k.kind] || "#87867f";
      return `<div class="trial-bar-seg" style="width:${pct.toFixed(2)}%;background:${color}" title="${escapeHtml(k.kind)} · ${k.count} (${pct.toFixed(1)}%)"></div>`;
    }).join("");
    const legend = trial.bash.by_kind.map((k) => {
      const color = BASH_KIND_COLORS[k.kind] || "#87867f";
      return `<li><span class="trial-bar-swatch" style="background:${color}"></span>${escapeHtml(k.kind)} <strong>${k.count}</strong></li>`;
    }).join("");
    bashBlock = `
        <div class="trial-bar-section">
          <div class="trial-bar-title">Bash command mix · ${bashTotal} calls</div>
          <div class="trial-bar" role="img" aria-label="Bash command breakdown">${segs}</div>
          <ul class="trial-bar-legend">${legend}</ul>
        </div>`;
  }

  // Skill activations (collapsible)
  let skillsHtml = "";
  if (trial.skill_activations?.total > 0) {
    const items = trial.skill_activations.unique.slice(0, 8).map((s) => {
      const args = s.args ? String(s.args).trim() : "";
      const argSnip = args ? ` — ${escapeHtml(args.length > 120 ? args.slice(0, 120) + "…" : args)}` : "";
      return `<li><code>${escapeHtml(s.skill)}</code>${argSnip} <span class="trial-at">at ${escapeHtml(s.first_at)}</span></li>`;
    }).join("");
    skillsHtml = `
        <details class="trial-details">
          <summary>Skill activations (${trial.skill_activations.total})</summary>
          <ul class="trial-list">${items}</ul>
        </details>`;
  }

  // Plugin/skill file reads (collapsible)
  let skillFilesHtml = "";
  if (trial.plugin_skill_files?.total_unique > 0) {
    const paths = trial.plugin_skill_files.paths || [];
    const items = paths.slice(0, 10).map((p) => `<li><code>${escapeHtml(p)}</code></li>`).join("");
    const more = paths.length > 10 ? `<li class="trial-more">…and ${paths.length - 10} more</li>` : "";
    skillFilesHtml = `
        <details class="trial-details">
          <summary>Plugin/skill files read (${trial.plugin_skill_files.total_unique} unique)</summary>
          <ul class="trial-list trial-list-mono">${items}${more}</ul>
        </details>`;
  }

  // Subagents dispatched (collapsible)
  let subagentsHtml = "";
  if (trial.subagents?.count > 0) {
    const items = (trial.subagents.calls || []).slice(0, 10).map((c) =>
      `<li><code>${escapeHtml(c.type)}</code> · ${escapeHtml(c.description)} <span class="trial-at">at ${escapeHtml(c.at)}</span></li>`
    ).join("");
    const more = trial.subagents.count > 10 ? `<li class="trial-more">…and ${trial.subagents.count - 10} more</li>` : "";
    subagentsHtml = `
        <details class="trial-details">
          <summary>Subagents dispatched (${trial.subagents.count})</summary>
          <ul class="trial-list">${items}${more}</ul>
        </details>`;
  }

  // Subagent transcripts (deeper — optional)
  let transcriptsHtml = "";
  if (Array.isArray(trial.subagent_transcripts) && trial.subagent_transcripts.length > 0) {
    const items = trial.subagent_transcripts.slice(0, 8).map((s) => {
      const tc = Object.entries(s.tool_counts || {}).sort((a, b) => b[1] - a[1]).slice(0, 4);
      const tcStr = tc.map(([k, v]) => `${escapeHtml(k)}×${v}`).join(", ") || "no tools";
      return `<li><code>${escapeHtml(String(s.id).slice(0, 18))}…</code> — ${escapeHtml(s.prompt_snippet)} <span class="trial-at">[${tcStr}]</span></li>`;
    }).join("");
    transcriptsHtml = `
        <details class="trial-details">
          <summary>Subagent transcripts (${trial.subagent_transcripts.length})</summary>
          <ul class="trial-list">${items}</ul>
        </details>`;
  }

  // New files created (collapsible)
  let filesHtml = "";
  const newFiles = trial.mutations?.new_file_paths || [];
  if (newFiles.length > 0) {
    const items = newFiles.slice(0, 10).map((p) => `<li><code>${escapeHtml(p)}</code></li>`).join("");
    const more = newFiles.length > 10 ? `<li class="trial-more">…and ${newFiles.length - 10} more</li>` : "";
    filesHtml = `
        <details class="trial-details">
          <summary>New files created (${newFiles.length})</summary>
          <ul class="trial-list trial-list-mono">${items}${more}</ul>
        </details>`;
  }

  // Diff / commits chips
  const diffChips = [];
  if (trial.final?.commits != null) {
    diffChips.push(
      `<span class="trial-chip-sm">${trial.final.commits} commit${trial.final.commits === 1 ? "" : "s"}</span>`
    );
  }
  if (trial.final?.diff_summary) {
    const m = trial.final.diff_summary.match(/(\d+)\s+files?.*?(\d+)\s+insertions?.*?(?:(\d+)\s+deletions?)?/i);
    if (m) {
      diffChips.push(`<span class="trial-chip-sm">${m[1]} file${m[1] === "1" ? "" : "s"}</span>`);
      diffChips.push(`<span class="trial-chip-sm trial-chip-plus">+${m[2]}</span>`);
      if (m[3]) diffChips.push(`<span class="trial-chip-sm trial-chip-minus">−${m[3]}</span>`);
    } else {
      diffChips.push(`<span class="trial-chip-sm">${escapeHtml(trial.final.diff_summary)}</span>`);
    }
  }

  const duration = trial.duration_minutes != null ? ` · ${trial.duration_minutes} min` : "";
  const timeRange = trial.start_hm && trial.start_hm !== "?"
    ? `${trial.start_hm} → ${trial.end_hm} UTC${duration}`
    : "";

  const prompt = trial.opening_prompt_snippet
    ? `<p class="trial-prompt">“${escapeHtml(trial.opening_prompt_snippet)}”</p>`
    : "";

  return `
      <article class="trial-card" data-trial="${escapeHtml(trial.trial)}">
        <header class="trial-card-header">
          <div class="trial-card-title">
            <span class="trial-badge">${escapeHtml(trial.trial)}</span>
            ${timeRange ? `<span class="trial-card-time">${escapeHtml(timeRange)}</span>` : ""}
          </div>
          <div class="trial-card-diff">${diffChips.join("")}</div>
        </header>
        ${prompt}
        ${chips.length ? `<ul class="trial-chip-row">${chips.join("")}</ul>` : ""}
        ${bashBlock}
        ${skillsHtml}
        ${skillFilesHtml}
        ${subagentsHtml}
        ${transcriptsHtml}
        ${filesHtml}
      </article>`;
}

async function buildTrialTimelinesSection(tool) {
  const data = await loadTrialData(tool);
  const counts = TIMELINE_TASKS.map((t) => (data[t] || []).length);
  if (counts.every((n) => n === 0)) return "";

  const safe = tool.replace(/[^\w]/g, "_");
  const firstNonEmpty = counts.findIndex((n) => n > 0);

  let radios = "";
  let labels = "";
  let panels = "";

  TIMELINE_TASKS.forEach((task, i) => {
    const id = `tt-${safe}-${i}`;
    const trials = data[task] || [];
    const n = trials.length;
    const disabled = n === 0;
    const checked = i === firstNonEmpty;
    const taskLabel = task.charAt(0).toUpperCase() + task.slice(1);

    radios += `    <input type="radio" name="tt-${safe}" id="${id}"${checked ? " checked" : ""}${disabled ? " disabled" : ""}>\n`;
    labels += `      <label for="${id}" class="trial-tab-label${disabled ? " trial-tab-disabled" : ""}">${taskLabel}<span class="trial-tab-count">${n} trial${n === 1 ? "" : "s"}</span></label>\n`;

    const cards = n === 0
      ? `<p class="trial-empty">No trials for this task.</p>`
      : trials.map(renderTrialCard).join("\n");
    panels += `      <div class="trial-tab-panel" data-task="${task}">\n${cards}\n      </div>\n`;
  });

  return `
<section class="trial-timelines" aria-labelledby="trial-timelines-heading">
  <h2 id="trial-timelines-heading">Trial timelines</h2>
  <p class="trial-intro">
    Per-trial session execution extracted from each trial's <code>session-logs/*.jsonl</code>. Each card
    shows the subagents dispatched, skill activations, Bash command mix, and the final diff. Switch task
    tabs to compare behaviour across feature, bugfix, and refactor trials.
  </p>
  <div class="trial-tabs">
${radios}
    <div class="trial-tab-bar" role="tablist">
${labels}
    </div>
    <div class="trial-tab-panels">
${panels}
    </div>
  </div>
</section>
`;
}

// -----------------------------------------------------------------------------
// Markdown-it configuration — GitHub-like, with anchored headings + hljs.
// -----------------------------------------------------------------------------

const MarkdownIt = require("markdown-it");
const mdAnchor = require("markdown-it-anchor").default || require("markdown-it-anchor");
const hljs = require("highlight.js/lib/common").default || require("highlight.js/lib/common");

function slugify(s) {
  return s
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

const md = new MarkdownIt({
  html: false,
  linkify: false,  // off -- bare 'PAPER.md' in running text was getting auto-linkified to 'http://PAPER.md'
  typographer: true,
  highlight(str, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return `<pre class="hljs"><code class="language-${lang}">${
          hljs.highlight(str, { language: lang, ignoreIllegals: true }).value
        }</code></pre>`;
      } catch (_) { /* fall through */ }
    }
    return `<pre class="hljs"><code>${md.utils.escapeHtml(str)}</code></pre>`;
  },
});

md.use(mdAnchor, {
  slugify,
  permalink: mdAnchor.permalink.headerLink({ safariReaderFix: true }),
});

// -----------------------------------------------------------------------------
// HTML shell — matches the landing page's editorial aesthetic, minus widgets.
// -----------------------------------------------------------------------------

function shell({ title, body, relPath, sourceRel }) {
  // Rewrite relative .md/.html links:
  //   /PAPER.md                 → ./paper.html                (inside preview/)
  //   /docs/guides/verification.md → ./guide-verification.html
  // Rewrites are handled below by transformRelLinks(); this shell stays lean.
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<link rel="icon" type="image/svg+xml" href="../favicon.svg">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Source+Serif+4:ital,opsz,wght@0,8..60,400;0,8..60,500;1,8..60,500&family=Inter:wght@400;500&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="preview.css">
</head>
<body>
<nav class="preview-nav">
  <div class="preview-nav-inner">
    <a class="brand" href="../index.html">ai-tool-benchmark<span class="brand-accent">.</span></a>
    <div class="preview-nav-links">
      <a href="../index.html">Landing</a>
      <a href="docs-index.html">Docs index</a>
      <a href="paper.html">Paper</a>
      <a href="final-report-feature.html">feature</a>
      <a href="final-report-bugfix.html">bugfix</a>
      <a href="final-report-refactor.html">refactor</a>
      ${isPublicRepoAbsent(sourceRel) ? "" : `<a class="preview-source" href="https://github.com/infina-pfa/claude-tool-benchmark/blob/main/${sourceRel}" target="_blank" rel="noopener">Source on GitHub →</a>`}
    </div>
  </div>
</nav>
<main class="preview-main">
<article class="preview-article">
${body}
</article>
<footer class="preview-footer">
  <div>Rendered from <code>${sourceRel}</code>. <a href="../index.html">← Back to landing</a></div>
</footer>
</main>
</body>
</html>
`;
}

// -----------------------------------------------------------------------------
// Link rewriter — inline HTML anchors that point at .md files in the repo
// should, in the rendered version, point at the matching preview page.
// -----------------------------------------------------------------------------

function buildMdToPreviewMap(resolved) {
  // resolved: [{ srcAbs, outAbs, sourceRel, outName, title }, ...]
  const map = new Map();
  for (const r of resolved) {
    map.set(r.sourceRel, r.outName);              // 'docs/guides/verification.md' -> 'guide-verification.html'
    map.set("/" + r.sourceRel, r.outName);
  }
  return map;
}

function transformRelLinks(html, mdMap, sourceRel) {
  // Only rewrite href="..." / src="..." where the target is a repo-relative .md.
  // Absolute URLs (http, https, mailto, #) pass through unchanged.
  const srcDir = dirname(sourceRel);              // e.g. 'docs/guides'
  return html.replace(/\b(href|src)="([^"]+)"/g, (match, attr, url) => {
    if (/^(https?:|mailto:|#|\/\/)/.test(url)) return match;
    // Anchor-only?
    if (url.startsWith("#")) return match;

    // Resolve relative to the source file's dir, then normalise.
    let resolved;
    if (url.startsWith("/")) {
      resolved = url.replace(/^\/+/, "");          // '/foo/bar.md' -> 'foo/bar.md'
    } else {
      resolved = join(srcDir, url);
    }
    // Strip any #fragment
    const hashIdx = resolved.indexOf("#");
    const frag = hashIdx >= 0 ? resolved.slice(hashIdx) : "";
    const bareResolved = hashIdx >= 0 ? resolved.slice(0, hashIdx) : resolved;

    // When rewriting to a local preview page, GitHub-flavored slugs in the
    // source (e.g. `#tldr--rank-1-by-...--200`) must be reduced to the local
    // renderer's collapsed form (`#tldr-rank-1-by-...-200`) so the fragment
    // resolves to an emitted heading id. Leave GitHub-blob links untouched.
    const localFrag = frag
      ? "#" + frag.slice(1).replace(/-+/g, "-").replace(/^-|-$/g, "")
      : "";

    // normalise '../' (very rough — Node's posix.normalize would be better)
    const parts = [];
    for (const p of bareResolved.split("/")) {
      if (p === "" || p === ".") continue;
      if (p === "..") parts.pop();
      else parts.push(p);
    }
    const normalised = parts.join("/");

    if (normalised.endsWith(".md")) {
      const mapped = mdMap.get(normalised);
      if (mapped) {
        return `${attr}="${mapped}${localFrag}"`;
      }
      // No preview rendered for this .md — link to GitHub blob instead.
      return `${attr}="https://github.com/infina-pfa/claude-tool-benchmark/blob/main/${normalised}${frag}"`;
    }
    // Non-.md (e.g. a .json artifact): link to GitHub blob.
    if (normalised && !normalised.endsWith(".html")) {
      return `${attr}="https://github.com/infina-pfa/claude-tool-benchmark/blob/main/${normalised}${frag}"`;
    }
    return match;
  });
}

// -----------------------------------------------------------------------------
// Source resolution — flatten static entries + expand glob entries.
// -----------------------------------------------------------------------------

async function listDir(relDir) {
  const abs = resolve(ROOT, relDir);
  try {
    const { readdir } = await import("node:fs/promises");
    const entries = await readdir(abs);
    return entries.filter((f) => f.endsWith(".md")).map((f) => join(relDir, f));
  } catch (_) {
    return [];
  }
}

async function resolveSources() {
  const out = [];
  for (const entry of SOURCES) {
    if (entry.src) {
      const abs = resolve(ROOT, entry.src);
      try {
        await access(abs);
      } catch {
        console.warn(`[warn] skipping missing source: ${entry.src}`);
        continue;
      }
      out.push({
        srcAbs: abs,
        sourceRel: entry.src,
        outName: entry.out,
        outAbs: resolve(OUT_DIR, entry.out),
        title: entry.title,
      });
    } else if (entry.glob) {
      // naive glob: one star at the end, e.g. docs/tools/*.md
      const m = entry.glob.match(/^(.+\/)\*\.md$/);
      if (!m) { console.warn(`[warn] unsupported glob: ${entry.glob}`); continue; }
      const dir = m[1];
      const files = await listDir(dir);
      for (const f of files) {
        const stem = basename(f, ".md");
        const outName = `${entry.outPrefix}${stem}.html`;
        out.push({
          srcAbs: resolve(ROOT, f),
          sourceRel: f,
          outName,
          outAbs: resolve(OUT_DIR, outName),
          title: `${entry.titlePrefix}${stem}`,
        });
      }
    }
  }
  return out;
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

async function main() {
  const checkMode = process.argv.includes("--check");
  const resolved = await resolveSources();
  const mdMap = buildMdToPreviewMap(resolved);

  await mkdir(OUT_DIR, { recursive: true });

  let stale = 0;
  for (const r of resolved) {
    const srcText = await readFile(r.srcAbs, "utf8");
    let body = md.render(srcText);
    body = transformRelLinks(body, mdMap, r.sourceRel);

    // Inject trial-timeline tabs into tool profile pages
    const toolMatch = r.sourceRel.match(/^docs\/tools\/([a-z0-9_-]+)\.md$/i);
    if (toolMatch && toolMatch[1].toLowerCase() !== "readme") {
      const timelineHtml = await buildTrialTimelinesSection(toolMatch[1]);
      if (timelineHtml) body = body + timelineHtml;
    }

    const html = shell({
      title: r.title,
      body,
      relPath: r.outName,
      sourceRel: r.sourceRel,
    });

    if (checkMode) {
      try {
        const existing = await readFile(r.outAbs, "utf8");
        if (existing !== html) {
          console.error(`[stale] ${r.outName}`);
          stale++;
        }
      } catch {
        console.error(`[missing] ${r.outName}`);
        stale++;
      }
    } else {
      await writeFile(r.outAbs, html);
      console.log(`[render] ${r.sourceRel}  ->  docs/preview/${r.outName}`);
    }
  }

  if (checkMode && stale > 0) {
    console.error(`\n${stale} preview(s) stale or missing. Run: npm run preview`);
    process.exit(1);
  }
}

main().catch((err) => { console.error(err); process.exit(1); });
