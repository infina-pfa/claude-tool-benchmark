# tooling/ — Build-time helpers for the docs site

Kept out of the repo root so Cloudflare Pages does **not** auto-detect a Node build and try to run `npm install` on deploy. The site is served as pure static files from `docs/` — the code in this folder runs **only locally** when regenerating pre-rendered markdown previews under `docs/preview/`.

## What's here

- `render-md-previews.mjs` — pre-renders selected `.md` files from the repo to `docs/preview/*.html` with the landing-page's editorial aesthetic. Transforms repo-relative `.md` links into the corresponding preview page (or into a GitHub blob URL when no preview exists).
- `package.json` / `package-lock.json` — pins `markdown-it`, `highlight.js`, `markdown-it-anchor`. Dev-only; nothing in the deployed site depends on Node.

## Usage

From this folder:

```bash
cd tooling
npm install                # one-time, installs dev deps
npm run preview            # re-renders every target .md to docs/preview/*.html
npm run preview:check      # exits 1 if any preview is stale (for CI)
```

The render script resolves file paths relative to the repo root (`dirname(__filename)/..`), so it works identically whether you run it from `tooling/` or from any other working directory.

## When to re-render

After editing any source `.md` that has a pre-rendered preview (see the `SOURCES` list at the top of `render-md-previews.mjs`):

- `README.md`, `PAPER.md`
- `results/FINAL-REPORT-3JUDGE-*.md`, `results/README.md`
- `docs/README.md`, `docs/guides/*.md`, `docs/methodology/**/*.md`, `docs/tools/*.md`, `docs/analysis/*.md`

Re-rendering is idempotent — only changed sources produce changed output bytes. Commit the regenerated `docs/preview/*.html` files alongside the source changes so the site stays consistent.

## Why not run this on the Cloudflare build?

Cloudflare Pages' Node build runner was timing out on cold starts ("build failed to initialize in time"). Keeping the site as pure static HTML sidesteps the build entirely — CF just uploads `docs/` as-is. The pre-rendered previews are checked in; treat them like any other committed artifact.
