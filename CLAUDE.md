# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal finance dashboard: Rails 7.2 (Ruby 3.2.2, PostgreSQL) serving a GraphQL API for domain data, a small REST API for JWT authentication, and server-rendered HTML pages that consume both APIs from the browser. Comments and user-facing strings are in Portuguese (pt-BR).

## Development commands

The app is developed with Docker Compose (`Dockerfile.dev` + a Postgres 15 service). Database credentials come from `.env` (`POSTGRES_USER`, `POSTGRES_PASSWORD`).

```bash
docker compose up                 # start app (port 3000) + Postgres
docker compose exec app bin/rails db:migrate
docker compose exec app bin/rails console
```

Test, lint, and security scan (run inside the container with `docker compose exec app ...`, or locally if Ruby/Postgres are set up):

```bash
bin/rails test                                      # all tests (Minitest)
bin/rails test test/models/wallet_test.rb           # single file
bin/rails test test/models/wallet_test.rb:10        # single test by line
bin/rails test:system                               # system tests (Capybara/Selenium, headless Chromium)
bin/rubocop                                         # lint (rubocop-rails-omakase)
bin/brakeman --no-pager                             # security static analysis
bin/importmap audit                                 # JS dependency audit
```

System tests (`test/system/`) drive the real UI in headless Chrome; `ApplicationSystemTestCase` fails any test that leaves a CSP violation or uncaught JS error in the browser console, clears the Rack::Attack counters in `setup` (the whole suite shares 127.0.0.1) and reads `CHROME_BIN`/`CHROMEDRIVER_PATH` (set in `Dockerfile.dev`; CI uses the runner's Chrome). The dev container needs `docker compose build app` once to get Chromium. Pages set `body[data-ready='true']` once their handlers are bound and the first load is done, and `ApplicationSystemTestCase#visit` waits for it — keep setting it in any new page script. Real Chrome (not Chromium) occasionally drops input before it reaches the page (measured ~1 interaction in 100, much more under load): the click or the typed text simply never arrives, with the page ready and nothing covering the element. The `ReliableClick` / `ReliableTyping` modules in `application_system_test_case.rb` detect that (a probe listener for clicks, a value check after typing) and redo only the input the page did not get, via JavaScript; `test/system/click_reliability_test.rb` simulates the loss. Reproduce CI with `RAILS_ENV=test CI=true bin/rails db:test:prepare test test:system` and real Google Chrome, not only the container's Chromium. Browser-native validation (e.g. `min` on the amount field) stops a submit before it reaches the server — to test a server-side error use a value that passes the browser but fails the model.

CI (`.github/workflows/ci.yml`) runs brakeman, importmap audit, rubocop, and tests on every PR and push to main.

## Architecture

### Two APIs, one auth scheme

- **REST (`/api/v1/auth/*`)** — authentication only: `signup` (creates the user — the wallet is created by `User#after_create` — and opens the session), `login` (sets the JWT in an HttpOnly cookie), `me`, `logout` (revokes every token of the user). Controller: `app/controllers/api/v1/auth_controller.rb`.
- **GraphQL (`POST /graphql`)** — everything else: users, the wallet, and transactions (incomes/expenses) CRUD plus financial summaries. GraphiQL is mounted at `/graphiql` in development.

JWT flow: `JsonWebToken` (`app/controllers/concerns/json_web_token.rb`) signs tokens with `secret_key_base` (HS256 pinned on verification), 24h expiry, payload `{ user_id:, tv: }`. `tv` is `users.token_version`: `JsonWebToken.user_for` rejects a token whose `tv` no longer matches, so `User#revoke_tokens!` (logout) and a password change invalidate every token already issued. `user_for` is the single entry point for both consumers:

- REST controllers include `Authenticable` (`before_action :authenticate_request!`, sets `@current_user`, renders 401 on failure).
- `GraphqlController` resolves the user itself and passes it as `context[:current_user]` (plus `ip`); a missing/invalid token is not an error at the transport level — resolvers enforce auth individually via `require_user!` (in `QueryType`) or an inline `raise GraphQL::ExecutionError` check (in mutations).

Both get the token from `TokenAuthentication`: `Authorization: Bearer` for API clients, or the `auth_token` cookie (HttpOnly, SameSite=Strict, Secure under SSL) for the browser. **The cookie only counts on requests carrying `X-Requested-With: XMLHttpRequest`** — that header is the CSRF defense (cross-site requests can't send it without a CORS preflight, and CORS is not enabled). Any new browser `fetch` to the API must send it. Page navigations (`dashboard#index`, `sessions#new`) read the cookie directly via `find_user_from_cookie` and redirect server-side. REST login does not return the token in the body; non-browser clients get a Bearer token from the GraphQL `userLogin` mutation.

Brute force: `AuthThrottle` + Rack::Attack limit login (5/min per IP and per e-mail) and signup (5/h per IP, shared by REST `signup` and GraphQL `userCreate`). REST is throttled by the middleware; GraphQL mutations call `AuthThrottle.exceeded?` themselves, since all GraphQL is `POST /graphql`.

### GraphQL layout

- Schema: `app/graphql/app_schema.rb`; queries in `types/query_type.rb`; mutations registered in `types/mutation_type.rb` and implemented one class per file under `app/graphql/mutations/<resource>/<resource>_<action>.rb` (e.g. `mutations/wallet/wallet_create.rb`).
- Mutations return `{ resource:, errors: [] }` — validation failures go into `errors` as full messages, not GraphQL errors.
- Authorization is by scoping: resolvers always go through `context[:current_user].wallet/transactions/recurring_transactions`, never `Model.find` directly (except the user queries).
- Inside `Mutations::Transaction` / `Mutations::RecurringTransaction` the constants `Transaction` / `RecurringTransaction` resolve to the *module*, not the model — always go through `user.transactions` / `user.recurring_transactions`. Shared mutation helpers (`authenticated_user!`, `find_wallet!`, `with_wallet`) live in `Mutations::Scoped`.
- List fields paginate with `limit` (default 100, max 500) and `offset` via `Types::Pagination`.

### Domain model

Every `User` has exactly **one** `Wallet` (`has_one`, unique index on `wallets.user_id`), created in `User#after_create` and destroyed only with the user — there are no wallet create/delete mutations and `walletUpdate` takes no id (it edits name and initial balance of the caller's wallet). A `Transaction` is an income or an expense, told apart by the integer enum `kind` (`Transaction::KINDS`, GraphQL enum `TransactionKind`: `INCOME`/`EXPENSE`); `amount` is always positive and the sign comes from `kind`. The kind is fixed at creation (`transactionUpdate` has no `kind` argument — reclassifying money means delete + create). Transactions and recurring templates belong to the user **and** to the wallet (`wallet_id NOT NULL`); the `WalletBound` concern assigns the user's wallet on create — clients never pick it, and the GraphQL mutations have no `walletId` — and validates `wallet.user_id == user_id`, since the foreign keys alone would let a row of user A point at user B's wallet. Income/expense used to be two parallel tables and class trees; they were merged because the files were line-for-line identical (see migration `UnifyTransactions`; `OneWalletPerUser` later merged multiple wallets by summing initial balances so no user's total changed).

There is a single balance rule: `Wallet#balance` = `initial_balance + total_income - total_expense`, and the top-level `balance`, `totalIncome` and `totalExpense` are that wallet's numbers, so the dashboard's cards can never disagree.

### Recurrence

`RecurringTransaction` is a *template* (`kind`, description, amount, `day_of_month`, `start_date`, optional `end_date`, `active`) that materializes real `Transaction` rows of the same `kind`; all the logic is in `app/models/recurring_transaction.rb`.

Rules the generator encodes, all load-bearing:

- `day_of_month` is clamped to the month's last valid day — 31 becomes 28/02 (or 29/02 in a leap year).
- Occurrences are never created with a future date; a template with day 10 produces nothing for the current month until the 10th arrives.
- Idempotency has two layers: a `last_generated_on` watermark on the template (month-level) and a unique index on `(recurring_transaction_id, date)` (DB-level backstop). The watermark is what stops an entry the user deliberately deleted from being recreated on the next page load — deriving "already generated" from existing rows would resurrect it.
- Backfill is floored at `MAX_BACKFILL_MONTHS` (120) counted back from today. The cut is on the window, not the list size: the loop walks oldest→newest, so capping by count would drop the *recent* months. Because a cut would silently lose data, a `start_date` older than `RecurringTransaction.earliest_start_date` is **rejected** with a pt-BR error instead (only on create or when `start_date` changes, so old templates stay editable/pausable); the floor in `occurrence_dates` remains as a backstop for templates that predate the rule.
- Deleting a template is `dependent: :nullify` — the entries it already generated really happened and stay in the history.

Scheduling: GoodJob (Postgres-backed queue, tables from migration `CreateGoodJobs`) runs `SyncRecurringEntriesJob` daily at 00:05 `America/Sao_Paulo` from `config.good_job.cron` in `config/application.rb`. `execution_mode = :async` runs the executor and the cron thread inside the web process, so there is no worker service to deploy (GoodJob's production default is `:external`, which would silently never run — keep it explicit). `max_threads = 2` because the DB pool is shared with Puma. The test env uses the `:test` adapter with cron off. A missed tick is harmless: the job is idempotent and backfills. `bin/rails recurring:sync` runs it by hand.

Generation is triggered by the `syncRecurringEntries` mutation (plus implicitly on template create/update), never from a query resolver: the dashboard requests `balance`, `totalIncome` and the two `transactions` lists in one document, so a side-effecting query field would run several times per page load and would also fire on any read, including in tests. `DashboardController` cannot trigger it either — it has no `current_user` (see below).

### Frontend

Server-rendered pages that behave like a static SPA: `sessions#new` and `registrations#new` (`/signup`, reuses `login.css`) and `dashboard#index` are HTML documents rendered with `layout: false`. Their JS and CSS are plain files, not inline: `app/javascript/{dashboard,login,signup}.js` (ES modules pinned in `config/importmap.rb`, loaded with `javascript_importmap_tags "dashboard"`) and `app/assets/stylesheets/{dashboard,login}.css` (`stylesheet_link_tag`). Auth is a server-side concern: the dashboard redirects to `/login` without a valid cookie, and the JS never sees the token (nothing in `localStorage`); it asks `/api/v1/auth/me` for the user and calls `/graphql` with `fetch` + `X-Requested-With`.

A strict CSP (`config/initializers/content_security_policy.rb`) allows scripts only from `'self'` plus a per-response nonce (the importmap tag carries it). There is no inline `<style>` or app JS in the views, and **inline event handlers (`onclick=` etc.) do not work**: elements declare `data-action` and a single delegated click listener (`ACTIONS` in `dashboard.js`) dispatches. Tests fail if a page reintroduces a handler attribute, an inline `<style>`, inline app JS or `localStorage`. `application.css` deliberately has no `require_tree`, so page CSS is not bundled into it. GraphiQL (development only) is exempt from the CSP and its assets are added to `assets.precompile` only in development — do not link them in `manifest.js`, the gem isn't loaded in test/production and Sprockets would fail.

Two timezone traps the JS avoids on purpose: dates are formatted by splitting the `YYYY-MM-DD` string (never `new Date(iso)`, which is UTC midnight and renders as the previous day in Brazil), and "today" is built from `getFullYear/getMonth/getDate` (never `toISOString()`, which after 21:00 in Brasília returns tomorrow).

### Known state

`bin/rubocop` is clean; keep it that way (CI runs it).

### Locale

`config.i18n.default_locale = :"pt-BR"` (gem `rails-i18n` + `config/locales/pt-BR.yml` with the model/attribute names), so validation messages reach the UI in Portuguese ("E-mail já está em uso"). A new model or attribute shown in an error needs its name added to that file, or it falls back to the humanized English name.
