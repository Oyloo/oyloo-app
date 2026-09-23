# Tasks — design

Date: 2026-09-23. Sub-project 4 of the family-client programme. Builds on the
app foundation. The server side (phrase parsing) is specified in the life
server repository as `2026-09-23-task-parse-design.md`.

## Goal

The native Tasks section does what a person does with tasks day to day, so
nobody needs the browser for it: look through the views, filter by tag,
change a status, and add a task by voice.

## Decisions (agreed)

- Voice quick-add: the person dictates a phrase with the keyboard's
  microphone; *Parse* sends it to `POST tasks/parse`, and the form fills
  itself. The phrase goes to OpenAI on the server; on-device models do not
  support Russian or Latvian.
- Nothing is saved until the person taps *Add*. If parsing is unavailable
  or fails, the phrase becomes the title and the form says why.
- Changes need the network, as in the foundation.

## Screen

1. View picker with counts: Today, Overdue, Next, Waiting, Someday, Done.
2. Tag filter from the tags the server lists.
3. Rows: title; due as *today*, *tomorrow*, *in N days*, a date, or
   *N days overdue* in red; circle; *waiting on …*; tags; priority badge
   for P1 and P2; a star for important.
4. Tap the circle to complete or reopen. Swipe for *Waiting*, *Someday*,
   *Next*, *Drop*.
5. *New task* sheet: a phrase field with *Parse*, then title, due date,
   important, circle, tags. *Add* posts the task.

## Server contract used

| Call | Body |
|---|---|
| `GET tasks?view=&tag=` | `today, view, tag, counts, todos[…], tags[{id,label}], circles[{id,label}]` |
| `POST tasks` | `{ title, due?, important, circleId?, tags, source: "app" }` |
| `PATCH tasks/{id}` | `{ status }` |
| `POST tasks/parse` | `{ text }` → `{ title, due, important, circleId, tags }` |

New task fields (`waitingOn`, `tags`, `urgent`) and the overview's `tag`,
`tags`, `circles` decode tolerantly, so a cached foundation response still
reads. Parse errors: `parse_unavailable` (503), `parse_failed` (502),
`rate_limited` (429), `invalid_input` (400).

## Structure

- `Sources/Core/TaskLogic.swift`: views, due wording, swipe actions per
  status, the create body, known parse codes; tolerant decoding in
  `AppModels`.
- `AppAPI`: `tasks(view:tag:)`, `setTaskStatus`, `createTask`, `parseTask`.
- `Sources/App/Tasks/`: `TasksView`, `TaskRow`, `NewTaskSheet`, words.
- New strings in English, Russian and Latvian.

## Tests

`swift test`: tolerant decoding (full and minimal), due wording across
boundaries, swipe actions per status, create body, draft decoding.
Screens are checked on the owner's phone.

## Out of scope

Editing an existing task's fields, notes, subtasks, offline queue,
reminders.
