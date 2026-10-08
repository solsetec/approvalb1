# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a static HTML/CSS/JS site with **no build tooling** — no package manager, bundler, linter, or test suite. Every page is a self-contained `.html` file with inline `<style>`/`<script>`. The site is deployed via GitHub Pages under a custom domain (see `CNAME`: `solsetec.approvalb1.com`). All backend logic lives outside this repo, in external n8n-style webhooks hosted at `tangara.cloud`.

## Development commands

There is no build, lint, or test command. To work on a page:
- Open the `.html` file directly in a browser, or serve the repo root with any static file server (e.g. `python -m http.server`) to test relative paths/redirects.
- `Index.HTML` is a **Telegram Mini App** and depends on `window.Telegram.WebApp` (loaded from `https://telegram.org/js/telegram-web-app.js`). Opening it in a plain browser will not exercise real behavior (theme variables, `initData`, native dialogs) — it needs to be loaded through a Telegram bot's configured Mini App URL to test properly.

## Architecture: two unrelated apps share this repo

The git history (mostly "Update Index.HTML") makes it easy to assume `Index.HTML` is part of the approval flow below — it is not. There are two independent applications here:

**1. `Index.HTML` — Telegram Mini App ("Mis Descargas PDF")**
A PDF-download UI for Telegram users. It reads `token` from the query string and the Telegram `initData`, then POSTs to `https://webhook-solsetec.tangara.cloud/webhook/telegram` to list email attachments (`email_attachments`) and again to request a `download_url` for a chosen file (opened via `tg.openLink`). Styling uses Telegram theme CSS variables (`--tg-theme-*`) for automatic light/dark adaptation.

**2. Approve/reject decision form — `comments.html` + `test/t_main.html`, `prod/p_main.html` (and the unsupported `dev/d_main.html`)**
An approve/reject-with-comment workflow, presumably linked from emails. Driven entirely by URL query params:
- `token` — identifies the decision request.
- `decision_inicial` — pre-selected suggestion (`approved`/`rejected`).
- `prf` — environment prefix, used to build the webhook host: `` https://webhook-${prf}.tangara.cloud/webhook/<endpoint-uuid> ``.
- `rcm` — required-comment mode (`none`/`approved`/`rejected`/`both`), controlling when a comment is mandatory before submit.

The outcome is one of five status views (`approved`, `rejected`, `reused`, `invalidtoken`, `error`); how the page submits and learns the outcome differs per file (see "Submission paths" below).

`comments.html` (repo root) is the older, base version of this form: it uses a hardcoded webhook UUID, has no loading-spinner state, and does not enforce required comments. `test/t_main.html` and `prod/p_main.html` are the newer versions with comment validation and a loading state, each hardcoding a different webhook endpoint UUID for its environment.

## Supported environments: TEST and PROD only

The DEV environment is **no longer supported**. Only `test/t_main.html` and `prod/p_main.html` are maintained. `dev/d_main.html` is left as-is: do not port changes to it, add failover/relay logic to it, or treat it as a reference.

**Static outcome pages** (repo root): `approved.html`, `rejected.html`, `reused.html`, `invalidtoken.html`, `invalidcomment.html`. These share the same visual pattern (Inter font via Google Fonts CDN, card layout, fadeIn/pop animations) and represent the terminal states of the decision flow above.

## Editing the environment-specific forms

`test/t_main.html` and `prod/p_main.html` are copy-paste duplicates with no shared/imported code, each hardcoding its own webhook endpoint UUID (TEST `93fb046c-…`, PROD `8209b5ad-…`). A logic or UI change to one usually needs to be manually replicated in the other. Changes are typically tried in TEST first, so the two files can temporarily diverge — currently TEST uses the decision relay (below) while PROD still uses direct `fetchWithFailover`.

## Submission paths

**Decision relay (`test/t_main.html`)**: the form POSTs to a Supabase Edge Function, `decision-relay`, served through a Cloudflare Worker at `https://approvalb1-supabase.scalifa.cloud/functions/v1/decision-relay` (the Worker switches to a Deno Deploy mirror if Supabase is down). The relay handles the Tangara → backup failover to n8n server-side and logs clicks/failovers to the database.
- `{event: 'submit', token, decision, prefix, comentario}` → JSON response whose `status` field selects the view (unknown values fall back to `error`). Timeout 60s, which covers the relay's worst case of about 40s plus the Worker's failover.
- `{event: 'opened', token, decision, prefix}` is sent with `keepalive` (fire-and-forget) only when the comment form is shown.
- If the relay doesn't respond at all (network error, timeout, non-2xx), `submitDirect` makes a single emergency attempt (20s) straight to the backup n8n at `apb1-b.solsetec.com.co`, reading the `redirect` header; Tangara is not called from the browser on this path. Nothing is logged to the database on that path. If the relay *did* respond (even with `status: "error"`), n8n was already attempted, so the page does not retry.

**Direct webhook with browser failover (`prod/p_main.html`, `comments.html`, `Index.HTML`)**: Tangara is the primary infra provider, with a secondary webhook host (`apb1-b.solsetec.com.co`) mirroring the same endpoint UUID/path. Each file defines its own inline `fetchWithFailover(primaryUrl, backupUrl, options, timeoutMs)` (duplicated per file, no shared JS module). It tries the primary URL with an `AbortController` timeout and makes a single attempt against the backup if the primary throws, times out, or returns non-2xx. The decision forms then read the `redirect` response header to choose the status view.

## Known issue

`invalidtoken.html` has UTF-8 mojibake in its Spanish text (renders as `Token inv�lido` instead of `Token inválido`) despite declaring `<meta charset="UTF-8">`. Be careful not to reintroduce or copy this corruption when editing that file or reusing its markup elsewhere.
