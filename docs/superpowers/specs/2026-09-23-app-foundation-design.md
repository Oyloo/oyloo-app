# App foundation — design

Date: 2026-09-23. Sub-project 2 of the family-client programme
(see `2026-09-23-family-client-program-design.md`).

## Goal

A family member signs in and lands on a **Today** screen built from their
own data, with the sections the server lets them see one tap away, all
readable without a network.

## Decisions (agreed)

- First screen is **Today**; sections come second.
- Devices are **personal**: one signed-in account per device.
- Today is **assembled by the app** from the section endpoints (no
  dedicated server endpoint); each block keeps its own cache and says how
  old it is.
- The server decides which sections exist (`GET /api/app/v1/me`,
  `sections`). A section it does not list does not appear.

## Server contract used

All under `<server>api/app/v1/`, bearer token from the existing sign-in.

| Call | Shape used by the app |
|---|---|
| `GET me` | `{ userId, name, sections: ["money"?, "tasks", "captures"] }` |
| `GET tasks?view=today` | `{ today, view, counts, todos: [{ id, title, status, important, due, circleId, priority, overdue }] }` |
| `PATCH tasks/{id}` `{ status: "done" }` | `{ todo }` |
| `GET money` | `{ role: "kid", me, kid }` or `{ role: "parent", me, kids }`; a kid view carries `userId, displayName, hasAccounts, balanceCents, balanceAsOf, freeCents, goals[{ id, title, targetCents, savedCents, percent, achieved, archived }]` |
| `GET <server>api/uploads?limit=100` | existing captures listing |

The app decodes only these fields; anything else the server adds is
ignored, so the server can grow without breaking installed builds.

## Structure

### `Sources/Core` — pure, Foundation only

Compiled into both app targets and described by a `Package.swift` at the
repository root, so its tests run with `swift test` on a Mac — no
simulator runtime is needed.

- `AppModels.swift` — the `Decodable` shapes above (`Me`, `TasksOverview`,
  `TaskItem`, `MoneyOverview`, `KidMoney`, `MoneyGoal`).
- `ResponseCache.swift` — last response of each call on disk with the time
  it arrived, in one folder per server; `clear()` on sign-out.
- `Sections.swift` — `AppSection` and `visibleSections(me:)`: Today and
  Settings always; money, tasks, captures only if listed; before the first
  successful `me` only captures (what works today).
- `TodaySummary.swift` — pure assembly of the Today blocks: open tasks due
  today (at most five, priority order kept), money (kid: balance and the
  nearest unfinished goal; parent: each kid's balance), last three captures.
- `Freshness.swift` — "updated N min ago" as a value, rendered by the view.

### `Sources/Shared` — networking glue

- `AppAPI.swift` — `me()`, `tasks(view:)`, `money()`, `completeTask(id:)`;
  token from `OAuthClient.validAccessToken()`, the same way the uploader
  gets it. Each successful GET stores its body in `ResponseCache`.
- `CachedResource` — observable wrapper: shows the cached value at once,
  refreshes from the network, keeps the cached value and records the error
  if the refresh fails.

### `Sources/App` — screens

- `RootView` — iPhone: tab bar Today · sections from `me` · Settings.
  iPad (regular width): `NavigationSplitView` with the same items.
- `TodayView` — the three blocks, each with its freshness and its own
  error line; tapping a block opens its section.
- `TasksView` — today's list with a "done" toggle.
- `MoneyView` — balance and goals (kid), each kid's balance and goals
  (parent).
- Captures — the existing vault UI, unchanged in behaviour, moved inside
  the Captures section. The vault tab bar becomes a vault picker so there
  are no nested tab bars.
- Settings — the existing vault management and sync settings.

Full money and tasks experiences are sub-projects 3 and 4; the foundation
screens are deliberately plain.

## Offline

Reading works from the cache with its age shown. Changes (marking a task
done) need the network; a failed change shows its error and the item stays
as it was — nothing is dropped silently. A queue for changes arrives with
the sections that need it.

## Languages

A String Catalog (`Localizable.xcstrings`) with English, Russian and
Latvian for every string the foundation adds; the device language picks.
Existing capture screens keep their English strings for now.

## Tests

`swift test` over `Sources/Core`: decoding of each response shape
(including unknown extra fields and the kid/parent money variants), the
cache round trip and clearing, section visibility, Today assembly, and
freshness. The screens are checked on a device.

## Out of scope

Push notifications (not possible on a free team), shared-device account
switching, write queue, full money/tasks/school screens.
