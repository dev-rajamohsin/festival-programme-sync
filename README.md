# Festival Programme Sync — Take-Home

**Role:** Senior Rails / Hotwire Developer · **Time box:** 4 hours
**Stack:** Rails 8, Hotwire, PostgreSQL, Sidekiq, Tailwind (all in Docker)

## Context

You're joining a team that maintains a film festival's public website. It's a
Rails monolith that also acts as the editorial CMS, and it pulls programming data
from an external festival-management system over an API.

That external system is the source of truth for films, venues and screenings. Our
database holds a local copy so the site renders fast and stays up under load.
Today that copy is refreshed by a nightly script a colleague wrote in a hurry, and
it's been causing problems.

**Your job is to replace it.**

## What we've given you

A working Rails 8 app with `Film`, `Venue` and `Screening` models, a mock external
API at `/mock_api` that behaves like the real one including its failure modes, an
existing `VenueSync` service and its tests, a screenings index with a filter form,
and seed data.

### Running it

Everything runs in Docker. One step:

```bash
docker compose up --build
```

That starts Postgres, Redis, the Rails web server, a Tailwind watcher and Sidekiq,
and creates/migrates/seeds the database on first boot.

- App: <http://localhost:3000>
- Sidekiq dashboard: <http://localhost:3000/sidekiq>
- Postgres is exposed on host port **5544** (non-standard, so it won't collide)

Handy commands (see the `Makefile`):

```bash
make console   # rails console inside the web container
make test      # run the RSpec suite
make sh        # a shell in the web container
```

## What we'd like you to build

1. **A programme sync.** Pull screenings from `GET /mock_api/screenings` into our
   database. It's paginated, returns nested film and venue data, and behaves like a
   real third-party API: sometimes slow, sometimes failing partway through, and its
   records change between runs.

   Running it twice must not create duplicates. Running it after upstream data
   changes must update the local copy. If the API fails partway, records already
   retrieved shouldn't be lost. It should run on a schedule as a background job, and
   we should be able to tell afterwards whether a run succeeded and what it did.

2. **A filtered screenings list.** The index at `/screenings` has a filter form that
   reloads the whole page. Make it update just the results. Filters are date, venue,
   and a text search across titles. Keep it server-rendered; we're a Hotwire shop and
   aren't looking for a client-side rendering layer.

3. **A short README.** Half a page. What you'd do differently with more time, anything
   in the existing code you'd change and why, and any assumptions you made.

## Testing the mock API

| Parameter      | Effect                                                                                                     |
| -------------- | ---------------------------------------------------------------------------------------------------------- |
| `?page=2`      | Pagination, 25 records per page                                                                            |
| `?generation=2`| The dataset after upstream changes. Screenings have moved venue, some are cancelled, a film has been retitled, two screenings are new. |
| `?fail_after=8`| Returns 8 records, then a 500                                                                              |
| `?slow=true`   | Six-second delay                                                                                           |

Sync `generation=1`, then `generation=2`, and check the database is right. Then try
`generation=1&fail_after=8` and check nothing was lost.

## What we care about

- **Correctness under failure, ahead of feature completeness.** If you run short, a
  sync that handles the edge cases and a filter that doesn't quite work beats the
  reverse.
- Tests are expected — at least for the sync and the models. Tests for the view
  layer aren't. We're looking at how you test, not just that you did, so write
  your own; the repo doesn't hand you a test plan.

## Submitting

A private git repo with your commits. Please don't squash.

---

## Implementation notes

### What I built

- **`ProgrammeSync`** (`app/services/programme_sync.rb`) — walks the paginated API
  via **`FestivalApi::Client`** (Faraday) and upserts each screening with its
  nested film and venue. Everything is keyed on the **external id**, never on a
  title or name, so the sync is idempotent and a retitled film / renamed venue
  updates in place instead of forking a duplicate.
- **Correctness under failure.** Each record is imported in its **own
  transaction (savepoint)**, so a single bad record is isolated and reported
  without aborting the batch, and whatever already committed stays committed. A
  bad *record* (data error) is captured on the run and the sync still succeeds; a
  dead *API* (5xx/timeout) stops the run, keeps the pages already imported, and
  marks it failed. The two are deliberately distinct.
- **Observability** — every run is a **`SyncRun`** row: status, timing, and
  created / updated / failed counts plus the captured per-record errors. Enough
  to alert on (`completed_with_errors?` flags a run that finished but dropped
  records).
- **Background job** — `ProgrammeSyncJob` (Sidekiq via Active Job) runs hourly
  (`config/schedule.yml`, sidekiq-cron). It `retry_on` *only* transient
  `FestivalApi::ServerError`, and takes a **Postgres advisory lock** so a slow
  run that overruns its hour isn't joined by a second, competing one.

### Things I changed in the existing code (and why)

- **`VenueSync` matched venues on `name`.** An upstream rename therefore created a
  *second* venue instead of updating the first — the bug class that leads to
  manual id reconciliation. It also had no error handling, so one bad record
  abandoned the batch, and its one test covered only the create path, so it passed
  while testing the wrong thing. The most important thing is that my new sync
  **doesn't route through it and doesn't copy the pattern** — it keys venues on
  `external_id` directly. `VenueSync` itself is unused inherited code (nothing in
  the app calls it), so touching it is optional; I fixed it to upsert on
  `external_id` with per-record error isolation and replaced the test, because
  this is exactly the failure mode the brief's rename case is built to catch and
  leaving a known id-reconciliation bug in a shared service is worse than a small,
  tested change. The change is loud, not silent: this note plus a comment on the
  service.
- **Screenings index N+1.** The view reads `film` and `venue` for every row; the
  controller now eager-loads both (`includes`), cutting the list from ~125
  queries to 3.
- **The search box was ignored.** The form posted `q` and the controller dropped
  it; it now does a case-insensitive title search (`ILIKE`, input escaped).
- **Hotwire.** The filter form now targets the `#screenings` Turbo Frame (was a
  full-page reload), the frame uses `turbo-action="advance"` so filters stay in
  the URL / Back button, and a small Stimulus controller debounces auto-submit as
  you type. I considered a Turbo **Stream** for the results, but a Frame is the
  simpler fit here: the whole results table is replaced wholesale, there are no
  out-of-band fragments to update, and the Frame gets URL/history for free. A
  Stream would earn its keep if filtering had to touch several regions at once
  (e.g. a live result count elsewhere on the page).

### What I'd do differently with more time

- **An hourly full sync is a poor fit for time-sensitive programming data** — up
  to an hour stale, and it re-fetches everything to change a handful of records.
  The real answer is **event-driven updates** (webhooks / a changes feed) with
  the full sync kept only as a nightly reconciliation backstop.

- Push per-record failures to a dead-letter / review queue rather than only
  logging them on the run, and add metrics (run duration, failure rate) for
  alerting.

### What I deliberately left alone

- The **mock API, models and migrations** — the three index bugs and the
  `VenueSync` keying bug were worth fixing; re-architecting working code around
  them wasn't, on a codebase I didn't write.
- **Deletions** — a conscious non-change, for the reason above.
- No pagination/virtualisation on the index yet (~60 rows); it'd matter at
  festival scale but is premature here.

### Assumptions

- The external id is stable and authoritative across generations (the dataset
  guarantees this).
- A cancelled screening stays in the programme with a `cancelled` status rather
  than being removed — so cancellations are updates, not deletes.