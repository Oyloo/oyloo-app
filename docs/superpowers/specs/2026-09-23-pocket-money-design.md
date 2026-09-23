# Pocket money — design

Date: 2026-09-23. Sub-project 3 of the family-client programme (see
`2026-09-23-family-client-program-design.md`). Builds on the app foundation
(`2026-09-23-app-foundation-design.md`).

## Goal

The native Money section does everything the web pocket-money page does,
for both roles, so a child and a parent never need the browser for it.

## Decisions (agreed)

- **No approvals.** A child manages their own goals; moving money into or
  out of a goal is the child's decision, as on the web. The programme's
  earlier wording about a parent approving operations is dropped.
- **Parent admin in full**, including creating a child's account. The
  parent types the new account's password on their own phone.
- **No server changes.** The family API already exposes every action.
- Changes need the network, as in the foundation: a failure is shown and
  nothing is dropped silently.

## What each role sees

### Child

1. Header: balance with the bank's date, free and reserved-for-goals, this
   month received and spent.
2. Warnings, worded as on the web page:
   - no bank account linked (and no numbers shown, so zeros are never
     mistaken for a real balance);
   - data not updated for N days since the last operation;
   - more reserved for goals than the account holds;
   - a non-euro currency among the linked accounts, so the sums cannot be
     trusted.
3. Goals: progress cards with *Put in*, *Take out* (amount in euros) and
   *Archive*; *New goal* (title up to 60 characters, target amount);
   archived goals folded away, each can be restored.
4. Where the money goes (top places) and recent operations.

### Parent

1. Every child as a summary row: balance, free, spent this month. Tapping
   opens that child's screen read-only — the server does not let a parent
   edit a child's goals.
2. Spending by month: a chart comparing the children over the last six
   months.
3. Admin:
   - *Add child*: e-mail, password, display name, and any of the
     unassigned bank accounts;
   - per child, *Accounts*: link unassigned accounts, unlink by swiping.

## Server contract used

All under `<server>api/app/v1/money`, bearer token.

| Call | Body |
|---|---|
| `GET money` | kid: `me, kid`; parent: `me, kids, unassigned[{ identificationHash, name, currency, product, txCount, lastActivity }]` |
| `POST money/goals` | `{ title, targetCents }` |
| `POST money/goals/{id}/moves` | `{ amountCents, direction: "in" \| "out" }` |
| `POST money/goals/{id}/archive`, `/unarchive` | — |
| `POST money/kids` | `{ email, password, displayName, accountHashes }` |
| `POST money/kids/{userId}/accounts` | `{ hashes }` |
| `DELETE money/kids/{userId}/accounts/{hash}` | — |

A child view additionally carries `reservedCents, overReserved, month,
monthly[{ month, receivedCents, spentCents }], places[{ name, cents,
count }], feed[{ date, label, amountCents, kind }], lastActivity,
staleDays, foreignCurrencies, hashes`. These are decoded tolerantly: a
missing field falls back to an empty or neutral value, so a response
cached by the foundation build still reads.

Errors come as `{ error, message }`; `error` is one of the server's codes
(`goal_title_too_long`, `amount_invalid`, `deposit_rejected`,
`email_invalid`, `password_too_short`, `create_user_failed`, …). The app
turns known codes into its own words and shows the server's message for
the rest.

## Structure

- `Sources/Core`: the extended money models; `parseEuroInput` (the web
  page's rule: digits with an optional `.` or `,` and up to two decimals);
  `moneyWarnings(for:)`; active and archived goals; the six-month spending
  series; the known error codes.
- `Sources/Shared/AppAPI.swift`: the seven money actions and the server's
  error body.
- `Sources/App/Money/`: `MoneyView` switches on the role; `KidMoneyScreen`
  (editable or read-only), `GoalActionSheet`, `NewGoalSheet`,
  `ParentMoneyScreen`, `SpendChart`, `AddKidSheet`, `KidAccountsView`.
- New strings in English, Russian and Latvian.

## Tests

`swift test`: tolerant decoding (full and minimal kid views, parent with
unassigned accounts), euro parsing against the web rule, warnings,
goal grouping, the spending series, error codes. Parent screens are
checked on the owner's phone; the child screen by the tests and later on a
child's phone.

## Out of scope

Approvals, notifications, editing a child's goals as a parent, currency
conversion.
