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
bin/rails test:system                               # system tests (Capybara/Selenium)
bin/rubocop                                         # lint (rubocop-rails-omakase)
bin/brakeman --no-pager                             # security static analysis
bin/importmap audit                                 # JS dependency audit
```

CI (`.github/workflows/ci.yml`) runs brakeman, importmap audit, rubocop, and tests on every PR and push to main.

## Architecture

### Two APIs, one auth scheme

- **REST (`/api/v1/auth/*`)** — authentication only: `login` (returns a JWT), `me`, `logout`. Controller: `app/controllers/api/v1/auth_controller.rb`.
- **GraphQL (`POST /graphql`)** — everything else: users, wallets, incomes, expenses CRUD plus financial summaries. GraphiQL is mounted at `/graphiql` in development.

JWT flow: `JsonWebToken` concern (`app/controllers/concerns/json_web_token.rb`) encodes/decodes tokens signed with `secret_key_base`, 24h expiry, payload `{ user_id: }`. Two consumers:

- REST controllers include the `Authenticable` concern (`before_action :authenticate_request!`, sets `@current_user`, renders 401 on failure).
- `GraphqlController` resolves the user itself from the `Authorization: Bearer <token>` header and passes it as `context[:current_user]`; a missing/invalid token is not an error at the transport level — resolvers enforce auth individually via `require_user!` (in `QueryType`) or an inline `raise GraphQL::ExecutionError` check (in mutations).

### GraphQL layout

- Schema: `app/graphql/app_schema.rb`; queries in `types/query_type.rb`; mutations registered in `types/mutation_type.rb` and implemented one class per file under `app/graphql/mutations/<resource>/<resource>_<action>.rb` (e.g. `mutations/wallet/wallet_create.rb`).
- Mutations return `{ resource:, errors: [] }` — validation failures go into `errors` as full messages, not GraphQL errors.
- Authorization is by scoping: resolvers always go through `context[:current_user].wallets/incomes/expenses`, never `Model.find` directly (except the user queries).

### Domain model

`User` has many `Wallet`s, `Income`s, `Expense`s. Incomes/expenses belong to a user and optionally to a wallet. `Wallet#balance` = `initial_balance + total_income - total_expense`, but the top-level `balance` query deliberately does **not** sum wallet balances — it computes `wallets.sum(:initial_balance) + incomes.sum - expenses.sum`, so that entries with a null `wallet_id` (which `totalIncome`/`totalExpense` always count) don't make the dashboard's three summary cards contradict each other.

### Recurrence

`RecurringIncome` and `RecurringExpense` are *templates* (description, amount, `day_of_month`, `start_date`, optional `end_date`, `active`) that materialize real `Income`/`Expense` rows. All the logic lives once in `app/models/concerns/recurring_schedule.rb`; the two models differ only in which association their `entries` method returns.

Rules the generator encodes, all load-bearing:

- `day_of_month` is clamped to the month's last valid day — 31 becomes 28/02 (or 29/02 in a leap year).
- Occurrences are never created with a future date; a template with day 10 produces nothing for the current month until the 10th arrives.
- Idempotency has two layers: a `last_generated_on` watermark on the template (month-level) and a unique index on `(recurring_*_id, date)` (DB-level backstop). The watermark is what stops an entry the user deliberately deleted from being recreated on the next page load — deriving "already generated" from existing rows would resurrect it.
- Backfill is floored at `MAX_BACKFILL_MONTHS` (120) counted back from today. The cut is on the window, not the list size: the loop walks oldest→newest, so capping by count would drop the *recent* months.
- Deleting a template is `dependent: :nullify` — the entries it already generated really happened and stay in the history.

Generation is triggered by the `syncRecurringEntries` mutation (plus implicitly on template create/update), never from a query resolver: the dashboard requests `balance`, `totalIncome`, `incomes` and `expenses` in one document, so a side-effecting query field would run several times per page load and would also fire on any read, including in tests. `DashboardController` cannot trigger it either — it has no `current_user` (see below).

### Frontend

Server-rendered pages that behave like a static SPA: `sessions#new` and `dashboard#index` are self-contained HTML documents rendered with `layout: false`, using inline CSS and vanilla JS. The browser stores the JWT and user in `localStorage` after login and calls `/graphql` with `fetch` + `Authorization: Bearer` header. There is no server-side session; page auth is enforced client-side by JS redirecting to `/login` when no token exists.

The dashboard is split into partials: `_styles.css.erb`, `_scripts.js.erb` and `_entry_modal.html.erb`. The first two are deliberately **not** `.html.erb` — development has `annotate_rendered_view_with_filenames` enabled, and the `<!-- BEGIN ... -->` comment Rails injects into an HTML partial would, inside a `<script>` block, act as a JS line comment and silently break the first line of code. They are rendered with `raw render(partial: ..., formats: [:js])`.

Two timezone traps the JS avoids on purpose: dates are formatted by splitting the `YYYY-MM-DD` string (never `new Date(iso)`, which is UTC midnight and renders as the previous day in Brazil), and "today" is built from `getFullYear/getMonth/getDate` (never `toISOString()`, which after 21:00 in Brasília returns tomorrow).

### Known state

`bin/rubocop` is clean; keep it that way (CI runs it).
