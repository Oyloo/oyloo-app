# Oyloo as a family client — programme design

Date: 2026-09-23. Status: approved in outline; each sub-project gets its
own spec and plan before it is built.

## Why

Oyloo today is a capture tool for one person: a share sheet, a list of
vaults, an upload queue. Everything else the household uses — pocket
money, tasks, school, notes — lives on the server and is reached through
a browser. The goal is an app the rest of the family opens by choice: a
full native client for the data they already have on the server.

The chosen shape is a **native client for every section**, not a browser
wrapper and not a hybrid. Screens that exist on the web are rebuilt
natively against a JSON API; the web stays for devices that cannot run
the app (kiosk screens, anything not iOS).

## Constraints that shape everything

- **Free provisioning team.** A build is signed for seven days and must
  be reinstalled from a Mac. No App Groups, no push notifications, no
  Universal Links. The app and its share extension therefore share a
  keychain group instead of a container, and the extension uploads on
  its own (see the sign-in and diagnostics work of 2026-09-22).
- **Devices:** iPhones and iPads for the people; kiosk screens keep
  using the web.
- **Roles already exist server-side:** owner, family member, child. The
  app must show only what the signed-in account may see and must never
  decide access by itself.
- **The server is the source of truth.** The app caches for offline
  reading; it does not own state.

## Sub-projects, in order

Each is independent, has its own spec and plan, and ends with something
usable.

### 0. Build delivery (blocking, small)

A seven-day signature means the app dies on every family device once a
week. A Mac on the home network rebuilds and reinstalls over Wi-Fi on a
schedule, so nobody notices the expiry. Details are deployment-specific
and live in the private repository's spec.

Done when: every family device keeps a working build without anyone
plugging in a cable.

### 1. Family API (medium)

Pocket money and tasks are served today by page loaders and form
actions, so a native screen has nothing to call. Each section gets JSON
endpoints, and the logic moves into a service layer both the page and
the endpoint call, so the two cannot drift. Every endpoint checks the
caller's role the way the pages do now.

Done when: money and tasks can be read and changed over HTTP with an
OAuth bearer, and the existing web pages still work through the same
service layer.

### 2. App foundation (large)

The app's navigation is built around vaults, which only makes sense for
capturing. It becomes sections: money, tasks, notes, school — filtered
by what the account may see. Adds a shared networking layer with an
offline cache, the three languages the web already speaks, and an iPad
layout.

Done when: a family member signs in and sees their sections, each
showing real data, readable without a network.

### 3. Pocket money (medium)

Balance, goals and spending for a child; a parent approves. The section
children will open daily, and the data is already there.

### 4. Tasks (medium)

Today's list, marking things done, adding one quickly by voice.

### 5. Notes and captures (small)

Finish what already works: the shared recording, its transcript, search
over one's own captures.

### 6. School (large)

Timetable, homework, applications. Largest integration, least urgent on
a phone, so it comes last.

## Principles

- **The server decides.** The app renders permissions, never invents
  them. A section absent from the API is absent from the app.
- **Offline is reading.** Cached data is shown with its age; changes are
  queued and retried, never silently dropped.
- **One service layer per feature on the server.** A page and an
  endpoint that compute the same thing differently is a bug waiting for
  the worst moment.
- **Nothing private in this repository.** Device identifiers, profiles
  and deployment details belong to the private repository.

## Open questions, deliberately deferred

- Whether a paid developer account is worth it later: it would remove
  the seven-day cycle, and bring App Groups and push. Declined for now.
- Whether children get their own capture vaults or only their sections.
- Notifications of any kind: impossible without push, revisit only if
  the account question is reopened.
