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

**2. Approve/reject decision form — `comments.html` + `dev/d_main.html`, `test/t_main.html`, `prod/p_main.html`**
An approve/reject-with-comment workflow, presumably linked from emails. Driven entirely by URL query params:
- `token` — identifies the decision request.
- `decision_inicial` — pre-selected suggestion (`approved`/`rejected`).
- `prf` — environment prefix, used to build the webhook host: `` https://webhook-${prf}.tangara.cloud/webhook/<endpoint-uuid> ``.
- `rcm` — required-comment mode (`none`/`approved`/`rejected`/`both`), controlling when a comment is mandatory before submit.

On submit, the form POSTs `{token, decision, comentario}` as JSON to the webhook and uses a `redirect` response header to choose which status view to render (`approved`, `rejected`, `reused`, `invalidtoken`, `error`).

`comments.html` (repo root) is the older, base version of this form: it uses a hardcoded webhook UUID, has no loading-spinner state, and does not enforce required comments. `dev/d_main.html`, `test/t_main.html`, and `prod/p_main.html` are the newer versions with comment validation and a loading state, each hardcoding a different webhook endpoint UUID for its environment.

**Static outcome pages** (repo root): `approved.html`, `rejected.html`, `reused.html`, `invalidtoken.html`, `invalidcomment.html`. These share the same visual pattern (Inter font via Google Fonts CDN, card layout, fadeIn/pop animations) and represent the terminal states of the decision flow above.

## Editing the environment-specific forms

`dev/d_main.html`, `test/t_main.html`, and `prod/p_main.html` are copy-paste duplicates of each other, differing only in their hardcoded webhook endpoint UUID (and implicitly, environment prefix). A logic or UI change to one of these almost always needs to be manually replicated in the other two — there is no shared/imported code between them.

## Webhook failover (Tangara → backup provider)

Tangara is the primary infra provider, but `Index.HTML`, `comments.html`, `test/t_main.html`, and `prod/p_main.html` also have a secondary webhook host (`apb1-b.solsetec.com.co`) mirroring the same endpoint UUID/path. Each of these files defines its own inline `fetchWithFailover(primaryUrl, backupUrl, options, timeoutMs)` (duplicated per file, same pattern as above — no shared JS module) that tries the primary URL with an 8s timeout via `AbortController`, and falls back to a single attempt against the backup URL if the primary throws, times out, or returns a non-2xx response. All call sites use it in place of a bare `fetch(...)`, so `response.ok`/`response.headers.get('redirect')`/`response.json()` usage downstream is unchanged.

`dev/d_main.html` intentionally has **no** failover yet — no backup webhook exists for that environment.

## Known issue

`invalidtoken.html` has UTF-8 mojibake in its Spanish text (renders as `Token inv�lido` instead of `Token inválido`) despite declaring `<meta charset="UTF-8">`. Be careful not to reintroduce or copy this corruption when editing that file or reusing its markup elsewhere.
