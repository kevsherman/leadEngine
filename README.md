# Breeze Block Canada inquiry desk

The foundation and Gmail integration slices of [the v0.3 specification](docs/Inquiry-to-Quote-Spec-v0.3.md): Rails 8.1.4, Ruby 3.3.3, PostgreSQL 17.11, Hotwire, Tailwind and a dedicated Solid Queue worker. Operator login, searchable conversation queue, chronological history, project context, editable replies, exact-content approval and simulated sending are implemented.

## Start on this computer

```sh
cd /Users/kevinshouse/Projects/inquiry-to-quote
bin/setup
```

Open **http://127.0.0.1:3000**. Sign in with **kevin@example.test** / **local-demo-password**. These are development-only credentials. On the sign-in screen, **Fill demo login** enters them for you; then click **Sign in**. `bin/setup` selects the inspected Ruby, checks dependencies, starts the isolated database, prepares both databases, seeds missing examples, builds CSS, then starts web, CSS watcher and worker together.

On subsequent starts, `bin/dev` starts the application if PostgreSQL is already running. `script/postgres start` starts the database. Ctrl-C stops the web, CSS and worker processes; `script/postgres stop` stops this project's database.

Morgan's example has one simulated outbound reply from browser verification. Alex and Camille have editable drafts. Re-running seeds preserves edits and never duplicates examples. Drafts are deterministic example text, not LLM output. Google Workspace Gmail is now available through the private **Gmail connection** screen. It starts unconnected and with live sending off; fake example conversations remain fake. See [Gmail setup and the real-inquiry walkthrough](docs/Gmail-Setup.md).

## Try the workflow

1. Select Alex or Camille. Search or filter the queue if desired.
2. Edit To, CC, subject or reply and click **Save draft**.
3. Click **Review saved reply** to inspect the exact recipients, subject, body and attachment state. This slice has no attachments.
4. Click **Approve this saved reply**, then **Simulate sending approved reply**.
5. The worker creates a local receipt, adds the outbound message and changes the conversation to **Waiting for customer**. The page and queue refresh automatically while delivery is queued.

Any saved change removes approval. Stale review versions and customer messages arriving after approval block sending. A queued/sent reply is locked. Retries reuse the same persisted operation; repeated jobs cannot create duplicate simulated replies. If the worker is stopped, the reply remains queued. Start the worker to resume. If queue submission fails, the operation remains stored and **Retry simulated sending** requeues it.

Example conversations use the fake provider and store local JSON receipts. Gmail conversations use the Gmail provider only after exact approval and a separate explicit live-send confirmation. Polling never sends. Action Mailer delivery stays disabled. CRM, Shopify orders, freight, LLM, quote calculations, PDFs, invoices, shipment booking and deployment remain outside the implemented scope.

## Development commands

```sh
source script/env
bin/rails test
bin/rails test:system
bin/rails worker:health
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
bin/rails console
```

`script/env` selects Ruby and the project-local bundle without editing shell configuration. Set `RUBY_BIN` to another Ruby 3.3.3 bin directory on another machine. The PostgreSQL helper uses `.tools/postgres/bin` on this computer, or an installed Homebrew PostgreSQL 17. Set `PG_BIN` explicitly elsewhere. Use `PGHOST`, `PGPORT`, `PGUSER` and `PGPASSWORD` for another local server. Rails has separate `primary` and `queue` databases for development and tests; `db:prepare` loads both schemas.

`bundle exec ruby script/verify_worker_browser.rb` checks the running development application in Chrome through the real worker. It sends only a fake seeded Morgan reply on its first run; later runs inspect the existing receipt. `test:system` uses a test database and inline job execution to test UI behavior independently.

See [AGENTS.md](AGENTS.md) for project conventions and [the environment report](docs/Development-Environment.md) for installed-tool findings and verification results. Screenshots are in `tmp/screenshots/` and excluded from Git. CI uses PostgreSQL 17 and runs unit/integration tests, Chrome system tests, lint and security checks; the workflow has not been run on GitHub.

## Ruby to read first

Start with [`app/services/reply_workflow.rb`](app/services/reply_workflow.rb). `self.approve` and `self.enqueue` are class methods called by the controller. `with_lock` wraps a database transaction with a row lock, and `lock_version` rejects a stale review. The service captures the approved email in a persisted operation before queueing work.

Next read [`app/models/email_draft.rb`](app/models/email_draft.rb): validations check the reply and its callback removes approval on content edits or prevents editing a locked reply. Rails models map to PostgreSQL tables; `belongs_to` and `has_one` describe their associations.

Then follow [`app/jobs/send_reply_job.rb`](app/jobs/send_reply_job.rb) into [`app/services/providers/fake_email.rb`](app/services/providers/fake_email.rb). The job receives only the operation ID, uses a lock to make retries safe, and records the receipt, history and state together. `perform_later` requests background processing; `perform` is what the worker runs. This local transactional simulation is safe to retry; a future real provider needs explicit uncertain-outcome reconciliation.

Finally, [`app/controllers/email_drafts_controller.rb`](app/controllers/email_drafts_controller.rb) connects form actions to the service, and `app/views/conversations/show.html.erb` renders the workspace. Controllers handle input and redirects; workflow rules stay in Ruby services and models.
