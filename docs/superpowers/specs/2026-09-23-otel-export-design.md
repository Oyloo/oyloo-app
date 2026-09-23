# OpenTelemetry export — design

Date: 2026-09-23. Status: approved by the task brief; implemented on the
branch this file arrived on.

## Why

The share extension runs in its own process, on a free provisioning team,
without an App Group. Its only diagnostic channel so far is the system log,
which needs a cable, plus a one-line relay through the shared keychain that
the app prints on its next launch — also readable only with a cable. When a
share fails on a family phone, nobody at the desk can see why.

The household already runs an OpenTelemetry collector with a logs and a
traces backend. This design makes both processes of the app export there
over the network, so a failed share on any phone shows up in the same
place as everything else.

## Shape

- **SDK.** `opentelemetry-swift` 2.5.2 and `opentelemetry-swift-core` 2.5.1
  via Swift Package Manager, declared in `project.yml` for both targets.
  Products used: `OpenTelemetryApi`, `OpenTelemetrySdk`,
  `OpenTelemetryProtocolExporterHTTP`.
- **Bootstrap.** One shared `Telemetry` type in `Sources/Shared` builds a
  `LoggerProvider` and a `TracerProvider` with a resource of
  `service.name=oyloo-ios`, `service.version=<marketing>+<build>`,
  `process=app|extension`, `os.name`, `os.version`,
  `device.model.identifier`. Bootstrap is idempotent and lazy: the first
  event or span triggers it, so nothing recorded before an explicit start
  is lost.
- **Export.** OTLP/HTTP protobuf, uncompressed (payloads are a few
  kilobytes; skipping gzip removes one way a proxy can corrupt them). The
  endpoint is the user's configured server: `<base>api/otlp/v1/logs` and
  `<base>api/otlp/v1/traces`. The phone never talks to the collector
  directly. The server side is a small proxy that checks the app's OAuth
  bearer and forwards the body to the collector; it lives in the private
  deployment repository, not here.
- **Auth.** `Authorization: Bearer <OAuth access token>` supplied through
  the exporter's `headersProvider`, read from an in-memory cache that
  `Telemetry.refreshAuthorization()` fills from `OAuthClient
  .validAccessToken()` at start and before each flush. The static token
  from settings is not used: the proxy accepts OAuth only.
- **Transport.** `TelemetryTransport` implements the exporter's
  `HTTPClient`. It sends synchronously (the SDK's batch worker thread is
  the caller), binds the endpoint late from `SyncSettings.baseURL` so a
  server entered after launch still works, and spools a failed body to
  `Application Support/telemetry-spool` (at most 64 files, dropped after
  7 days). Spooled bodies are replayed, oldest first, before the next
  send. The batch processors keep the SDK defaults except a short
  schedule delay, so an app session ships records while it is still
  running.
- **Spool and reporter** live in `Sources/Core`, free of the SDK, so they
  are unit-tested with `swift test`.
- **Local fallback.** `Telemetry.event` writes the same line to the
  matching `Diagnostics` logger first, unconditionally, before it reaches
  the SDK. A processor would have been tidier, but bootstrapping reads
  settings and reading settings logs: the storage and keychain lines are
  emitted while there is no provider yet, and a processor would lose
  exactly those. Writing at the call site also means a record is never
  lost locally, whatever the SDK does. The lines are `.public` because
  the attribute type admits nothing else; anything private stays a direct
  `Diagnostics` call and never becomes a record.
- **Relay.** Kept as the last resort only. The extension flushes before
  completing its request; when the flush fails it writes the same
  one-line summaries to the keychain as before. The app reads them on
  launch, prints them, emits them as a `share.relay` event and clears
  them, so a relayed line still reaches the collector once the app runs.

## Events

Log records are named events with attributes; the body repeats the event
name and the attributes as `key=value` pairs so the logs backend shows a
readable line while the attributes stay queryable.

| Scope | Event | Attributes |
|---|---|---|
| storage | `storage.backend` | `usesAppGroup`, `group`, `service` |
| storage | `keychain.read` / `keychain.write` / `keychain.clear` | `key` (masked label), `status`, `bytes`, `group` |
| storage | `vaults.load` / `vaults.save` | `result`, `count`, `bytes` |
| storage | `outbox.append` | `result`, `bytes`, `attachment`, `error` (type name) |
| share | `share.opened` | `vaults`, `vaultsReadStatus`, `usesAppGroup`, `syncConfigured`, `baseURLLength`, `tokenReadStatus`, `tokenPresent`, `refreshPresent`, `tokenFresh` |
| share | `share.extracted` | `kind` (url/file/image/text/none), `attachment` |
| share | `share.committed` / `share.cancelled` | `publish`, `uploadsHere` |
| share | `share.relay` | `relay.line` (a summary line the extension left behind) |
| sync | `sync.start` / `sync.done` | `pending`, `sent`, `failed`, `skipped`, `lastFailure`, `auth` |
| sync | `sync.item` | `result`, `kind` |
| sync | `sync.auth` | `source` (oauth/static/none), `failure` (case name) |
| sync | `captures.fetch` | `status`, `count`, `reason` |

## Spans

- Extension: `share` (root, from sheet open to completion) with children
  `share.extract` and `sync` (the extension's own upload).
- App: `sync` (root, on foreground) with children `sync.item`.
- `sync.item` carries `sync.result`, `sync.failure` and
  `http.response.status_code` when there is one; `sync` carries the
  counts and `auth.source`.

Parents are passed explicitly. The SDK's activity-based context does not
survive `Task` boundaries reliably, and explicit parents are easier to
read.

## Privacy

Unchanged rule, now enforced at one entry point: only counts, flags,
OSStatus and HTTP codes, and fixed names from this code base may become
attributes. Vault names, titles, text, attachment paths, the server
address and tokens never do.

Two places needed care:

- `OAuthClient.Failure` gains a `kind` (the case name). The relay used to
  carry the first characters of the error's description, which for a
  token failure is the server's response body. Attributes use the kind.
- The SDK's feedback handler prints exporter errors through `os_log` as
  public text, and a `URLError` description embeds the failing URL — the
  server address. The handler is replaced by a `.private` `Diagnostics`
  line.

The `os_log` privacy split is otherwise kept: mirrored records are public
because their content is, and the pre-existing private lines (container
path, error descriptions) remain separate and private.

## Server side

Summary only; the code and its tests live in the private deployment
repository.

`POST /api/otlp/v1/logs` and `POST /api/otlp/v1/traces` require a bearer
that is an OAuth access token issued by the server to the app; a browser
session or the transcription agent's static token are refused. The body
must be `application/x-protobuf` or `application/json`, at most 2 MiB,
and is forwarded verbatim to the collector's OTLP/HTTP receiver; the
upstream status is returned. The paths are declared public in the access
gate (they do their own authentication, like the uploads endpoints) and
in the route census test.

## Lifecycle

- `Telemetry.start()` is idempotent and guarded by a recursive lock: it
  reads settings, which log, which start telemetry. The nested call
  returns immediately because the started flag is set first.
- Extension: `Telemetry.flush(timeout: 6)` before `completeRequest` and
  before `cancelRequest`, off the cooperative thread pool because the
  flush blocks on the network.
- App: refresh authorization and flush when the scene becomes active
  (drains the spool after a period offline); flush when it goes to the
  background.

## Failure modes

- Server not configured or not signed in: the transport fails fast, the
  batch is spooled, the mirror still writes to the system log.
- Server unreachable: same, and the extension writes the relay.
- Token expired inside the extension: `Uploader` has just refreshed it
  for the upload, and `flush` refreshes again before sending. A 401 is a
  failure like any other: spool plus relay.
- Spool full or too old: oldest files dropped. Diagnostics are best
  effort; the capture itself is never gated on telemetry.

## Testing

Done on 2026-09-23:

- Server: 13 unit tests for the proxy — the collector address and its
  override, the accepted content types, the size limit, an upstream
  status passed through unchanged, an unreachable collector as 502, and
  the gate refusing a session, the agent's static token and an anonymous
  caller. The route census carries both new paths.
- Deployed: both endpoints answer 401 anonymously and to a bogus bearer,
  and the collector accepts a post from the web pod.
- Backend: a synthetic record with `service.name=oyloo-ios` and
  `process=extension` posted from inside the cluster arrives in the logs
  backend and is returned by the query this spec promises, with its
  attributes preserved as labels.
- App: both targets compile for a device.

- Phone, app process: after install, records with `process=app` arrive
  in the logs backend through the proxy with the app's own OAuth token.
- Phone, share extension: a link shared from Safari into Oyloo (driven
  through WebDriverAgent) produces the whole flow as records with
  `process=extension` — sheet opened, extraction, outbox append,
  commit, upload with `auth=oauth` — and a `share` trace in the traces
  backend. The keychain relay is not written when the export succeeds.

Found on the phone and fixed before merging:

- Bootstrap read the server address from settings. The first keychain
  read logs from inside a one-time initialiser, logging bootstraps, and
  the re-entry hung the app on launch. Bootstrap now reads no settings;
  the address is cached by `refreshAuthorization`.
- The transport read settings on every send, and every keychain read is
  a record, so each export queued the next one. Same cache fixes it.
- Keychain reads were a third of all records. `keychain.read` is now
  emitted only for a key's first outcome in a process, when that outcome
  changes, or on a real failure (`KeychainReadReporter`, tested).

Querying: `process` is structured metadata in the logs backend, not a
stream label — filter with `{service_name="oyloo-ios"} | process="extension"`.

Unit tests (`swift test`): the spool's order, count and age caps, and the
keychain read reporter. The rest of the transport is exercised on the
phone only.

## Out of scope

Metrics; sampling; per-user attributes (the proxy knows the user from
the token and deliberately adds nothing); exporting from the desktop
recorder.
