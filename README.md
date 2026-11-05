# Coverline — Real-Time Agent Board

Live agent status, time in status, adherence against the schedule, and team totals on one screen.
The full plan is in `coverline-build-plan.md` (source of truth); it is built one phase at a time.

**Stack:** Rails 8.1 · Ruby 3.4.11 · PostgreSQL 17 · Hotwire · Bootstrap 5 · Pundit · Solid Cable / Queue / Cache (all in the one Postgres database)

## Status

- [x] Phase 1: foundation, auth, roles, Pundit
- [x] Phase 2: admin setup (agents, teams, team access, statuses, audit log)
- [x] Phase 3: status engine (webhook, status events, manual override, bin/simulate)
- [x] Phase 4: live board (filters, sorting, live timers, footer counts, today's bar)
- [ ] Phase 5: schedules
- [ ] Phase 6: adherence, TST, CFT and markers
- [ ] Phase 7: real phone test

## Run it locally

```sh
rvm use 3.4.11
bundle install
yarn install
bin/rails db:create db:migrate db:seed
bin/dev            # Rails server + Sass watcher -> http://localhost:3000
```

Seeded fake logins (password `password`): `super@example.com` (Super User), `admin@example.com` (Admin),
`maya@example.com` (Manager of Teams A and B), `marco@example.com` (Manager of Team C), and 24 agents
(e.g. `alex.dunmore@example.com`), plus 8 colored statuses with phone codes. Seed data is all invented.

## Live events (Phase 3)

The phone system posts agent status changes to `POST /api/v1/status_events` with `Authorization: Bearer <key>`.
A Super User generates the key and sees the URL on the **Integration** screen. Each event needs an `event_id`,
so retries are harmless. Try it without a phone system:

```sh
bin/rails server
bin/rails coverline:dev_api_key           # prints a key (development only)
COVERLINE_API_KEY=cvl_... bin/simulate    # moves the seeded agents between statuses every few seconds
```

`bin/simulate --help`-style options are listed at the top of the script (`--interval`, `--moves`, `--count`, `--rounds`, `--url`).

## The board (Phase 4)

`/board` (managers and up). One row per agent grouped by team: status pill, live time-in-status timer, first login today,
and a horizontal bar of today's statuses with a "now" line. Rows update over Turbo Streams the moment the webhook (or a
manual override) records a change; the footer counts, filters and sorting run in the browser, so they stay right as rows change.
Admins and Super Users watch the whole organization; managers only the teams they were granted.

## Tests

```sh
bin/rails test           # unit + request tests
bin/rails test:system    # real headless Chrome: status preview, drag-reorder, password generator
```

`test/policies/matrix_test.rb` is the permission matrix from plan section 2, row by row.

## Production (Railway)

- Database: Railway Postgres via `DATABASE_URL`. App data, Solid Queue, Solid Cache and Solid Cable all share it; their tables are normal migrations, so `bin/rails db:migrate` creates everything.
- Secrets live in environment variables (`SECRET_KEY_BASE` / `RAILS_MASTER_KEY`, `DATABASE_URL`), never in the repo.
- Set `SOLID_QUEUE_IN_PUMA=1` to run background jobs inside the web process.
- No Kamal. Deployment walkthrough comes when we're ready.
