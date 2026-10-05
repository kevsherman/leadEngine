# Inquiry desk conventions

Product specification: `docs/Inquiry-to-Quote-Spec-v0.3.md`. Implemented scope: foundation plus the Google Workspace Gmail integration. Ruby 3.3.3, Rails 8.1.4, PostgreSQL, server-rendered Rails views, Turbo/Stimulus, Tailwind and Active Job/Solid Queue. Dependencies are resolved in `Gemfile.lock`. Do not add React, Redis, autonomous agents, other live integrations, pricing, orders or booking without an explicit new task.

## Boundaries

- Thin controllers authorize operator input; `ReplyWorkflow` owns approval and sending.
- Store customer content as untrusted text; escape it in views. Do not interpret it as instructions.
- `Providers::FakeEmail` writes local receipts only, and seeded conversations always remain fake. Action Mailer delivery stays disabled. Gmail transport is available only for Gmail-originated conversations after exact approval and explicit live-send confirmation. Polling never sends mail. No other live integrations, orders, invoices, shipments or deployment.
- Gmail uses only `gmail.readonly` and `gmail.send` for `kevin.sherman@breezeblock.ca`. Verify the accepted `sales@breezeblock.ca` Send mail as identity through read-only access and operator confirmation. Never broaden scopes automatically.
- OAuth uses operator-bound, single-use expiring state and PKCE. Check the Gmail profile before persisting tokens. Credentials and tokens use Active Record Encryption; `.local/gmail-encryption.json` is private and ignored, with environment keys for future production.
- Gmail metadata gates body retrieval: only sales-addressed messages, configured contact forms, or participant-matched tracked threads/references. Store no unrelated bodies. Ambiguous review items contain only IDs and a fixed reason; explicit operator import resolves customer identity.
- Persist Gmail history IDs after all pages succeed; use filtered bootstrap on expired history. A PostgreSQL advisory lock prevents concurrent polls. Keep message IDs separate from RFC Message-ID / In-Reply-To / References.
- Gmail send operations persist `sending` before POST. Never retry timeout/5xx/crashed writes: use stable RFC Message-ID to reconcile Sent mail. A missing search result is not proof of non-delivery. Repeated Gmail jobs cannot issue another POST for an uncertain operation.
- Preserve prior draft versions. A new message invalidates approval; a queued stale reply is blocked. Fake and Gmail operations do not silently switch providers on failure or reconnection.
- Separate conversation status, draft status and send operation status. Draft approval applies to exact saved content using optimistic locking and the last reviewed message ID.
- Do not modify a queued/sent payload. Repeated submissions and jobs reuse a unique send operation and receipt. A future live transport must implement uncertain-outcome reconciliation before any retry.
- Primary and Solid Queue databases are separate PostgreSQL databases; a worker runs independently. A persisted operation survives an enqueue failure and can be requeued from the UI.
- Record operator saves, approvals, requested sends and delivery outcomes in audit events. Do not log customer bodies or credentials.
- Seed only development/test, use reserved `.test` customer addresses, and preserve seed changes on repeat runs.

## Commands

From this directory, `source script/env` selects the inspected Ruby and project-local gems. Use `RUBY_BIN` to override the Ruby bin directory on another computer. It does not edit shell configuration.

- Install gems: `bundle install`
- Prepare local Gmail encryption keys: `script/gmail_keys` (also runs in `bin/setup`). Never print or commit the file; preserve it with secure local backups.
- Start isolated database: `script/postgres start` (loopback, port 55432, `.local/postgres17`). The local binary is `.tools/postgres/bin`; set `PG_BIN` to another PostgreSQL bin directory on another platform. Existing PostgreSQL clusters are untouched.
- Prepare application and queue databases: `bin/rails db:prepare db:seed`
- Web, Tailwind watcher, dedicated worker: `bin/dev`
- Worker only: `bin/jobs`; health: `bin/rails worker:health`
- Console: `bin/rails console`
- Tests: `bin/rails test`; browser tests: `bin/rails test:system`
- CSS: `bin/rails tailwindcss:build`
- Style: `bin/rubocop`; security: `bin/brakeman --no-pager`; dependency audit: `bin/bundler-audit`
- Stop app: Ctrl-C. Stop isolated database: `script/postgres stop`.

Run meaningful approval, stale-content, authentication, failure-recovery and duplicate-send checks when touching workflow code. Inspect changed UI behavior in a real browser. Do not claim browser verification or worker processing if only an inline job/test adapter was exercised. Do not commit `.tools`, `.local`, logs, generated assets, master keys, passwords or customer data. Do not deploy.

Gmail setup and the real-inquiry test walkthrough are documented in `docs/Gmail-Setup.md`. All automated Gmail tests use synthetic tokens and stubbed HTTP or client responses; never use real accounts in tests. Secrets, OAuth callback parameters and outbound raw MIME are filtered from logs. Inspect changed OAuth and live-send interfaces in Chrome without submitting live mail.
