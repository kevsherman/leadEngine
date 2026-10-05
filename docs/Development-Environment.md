# Development environment and verification

Inspected before implementation on October 4, 2026.

| Tool | Initial finding | Project setup |
| --- | --- | --- |
| Ruby | RVM Ruby 3.3.3 installed; changing directories could select macOS Ruby 2.6 | Reuse 3.3.3 via `script/env`; `.ruby-version` pins it |
| Rails | `/usr/local/bin/rails` used system Ruby and could not load railties | Rails 8.1.4 pinned in Gemfile, use `bin/rails` |
| Bundler | 2.5.11 installed | Gems and compiled extensions installed inside `.tools/gems`; lockfile retained |
| PostgreSQL | Homebrew 14.10 client available, service stopped; server failed because ICU 73 libraries were missing | PostgreSQL 17.11 built locally from the source archive downloaded by Homebrew, installed in `.tools/postgres` |
| Node / npm | 22.23.1 / 10.9.8 | Already usable; Rails importmaps and Tailwind gem require no npm installation |
| Git | Apple Git 2.39.3 | Project source isolated in its own repository |
| Build tools | Apple command-line tools available | Used to compile native gems and PostgreSQL |
| Browser | Google Chrome installed, no callable browser connector | Selenium headless Chrome, with driver cached under `.tools/selenium` |

The setup choices were explained before installation. A permitted Homebrew PostgreSQL 17 installation first added `docbook` and `docbook-xsl` and built/staged CMake 4.4.4. It was stopped because macOS 13 required a long chain of dependency source builds. The application does not depend on that unfinished Homebrew installation. No existing database cluster was started, migrated or replaced, and no login shell defaults were edited.

The final PostgreSQL build is project-local and omits ICU, readline and zlib. It is for this local demo, not a production database provisioning recipe. The cluster is `.local/postgres17`, bound to 127.0.0.1 on port 55432, with local trust authentication. Application and worker use separate PostgreSQL databases, plus separate test databases. Gems, database data, build artifacts, browser driver, logs and screenshots are ignored by Git. Bundler's security check also downloaded its advisory database into the normal user tooling cache.

The execution sandbox required permission for dependency downloads, PostgreSQL shared memory, local database connections and Chrome. Ordinary terminal startup does not use that sandbox. No live email, CRM, Shopify, LLM or freight credentials were requested or configured. No real email, order, invoice, booking or deployment was performed.

## Verification

- Rails eager loading (`zeitwerk:check`) passed.
- Rails tests: 9 runs, 52 assertions, no failures or errors. Checks include unauthorized reads/writes, incorrect passwords, search, editing, exact approval, stale version rejection, new-message approval invalidation, escaped customer HTML, duplicate submission/job safety, provider failure retry and queue enqueue outage recovery.
- Chrome system test: 1 run, 15 assertions, no failures or errors. Login, Turbo navigation, draft edits, saved review, approval, simulated history, logout and a true 390px viewport with no horizontal overflow.
- Development Chrome smoke test used a separate live Solid Queue worker: worker heartbeat healthy, exactly one local fake receipt, one outbound message, one completed background job, and waiting-for-customer state. No inline job invocation in this smoke check.
- Desktop and mobile screenshots were opened and visually inspected.
- Tailwind CSS build and Ruby lint passed.
- Brakeman found no security warnings; Bundler audit found no known vulnerabilities.
- Seed preparation ran twice without duplicate conversations. Re-seeding preserves operator edits and the simulated receipt.

The first `bin/dev` verification exposed the Tailwind watcher's noninteractive-stdin exit behavior. `tailwindcss:watch[always]` fixes it, and the web/watcher/worker combination then stayed running through browser and real-worker checks.
