# OpenTelemetry export — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship telemetry from the app and its share extension to the household OpenTelemetry collector over the network, through a server-side proxy, without ever exporting user content.

**Architecture:** A shared `Telemetry` bootstrap in `Sources/Shared` builds an OTLP/HTTP `LoggerProvider` and `TracerProvider` whose resource names the service and the process. Every call site that logs today also emits a log record; the records are mirrored to the existing `os.Logger` channels by a `LogRecordProcessor`. The phone posts to `<server>/api/otlp/v1/{logs,traces}` with its OAuth bearer, and a SvelteKit proxy in the private deployment repository forwards the body to the in-cluster collector.

**Tech Stack:** Swift 5.10 / iOS 26, xcodegen, opentelemetry-swift 2.5.2 (SPM), SvelteKit + bun + vitest on the server.

**Spec:** `docs/superpowers/specs/2026-09-23-otel-export-design.md`

## Global Constraints

- Never export user content: vault names, titles, text, attachment paths, the server address, tokens. Attributes carry only counts, flags, OSStatus/HTTP codes and fixed key names from this code base.
- `service.name` is `oyloo-ios`; `process` is `app` or `extension`.
- The collector is reachable only from inside the cluster; its address lives in the private deployment repository, never here.
- SPM packages: `https://github.com/open-telemetry/opentelemetry-swift` from `2.5.2`.
- The proxy accepts OAuth access tokens only (`caller.kind === 'oauth'`).
- Server work lives in the private deployment repository; nothing about the deployment enters this repo.
- Commit messages in this repo are English; in the private deployment repository they follow its own convention.

---

### Task 1: Server proxy — module

**Files:**
- Create (private repo): `web/src/lib/server/otlp/forward.ts`
- Create (private repo): `web/src/lib/server/otlp/forward.test.ts`

**Interfaces:**
- Produces: `collectorEndpoint(signal: 'logs' | 'traces'): string`,
  `MAX_OTLP_BYTES: number`,
  `isAcceptedContentType(raw: string | null): boolean`,
  `forwardToCollector(signal, request: Request): Promise<Response>`.

- [ ] **Step 1: Write the failing tests** covering: the endpoint defaults to the in-cluster gateway and honours `OTLP_COLLECTOR_URL`; `application/x-protobuf` and `application/json` accepted, `text/plain` refused; a body over the limit refused; a successful forward returns the upstream status; an upstream failure returns 502.
- [ ] **Step 2: Run** `cd web && bun run test:unit -- --run src/lib/server/otlp/forward.test.ts` — expect failure (module missing).
- [ ] **Step 3: Implement** the module: read `OTLP_COLLECTOR_URL` from `$env/dynamic/private` with `process.env` as the second source (the pattern `uploads/store.ts` uses for vitest), post the raw `ArrayBuffer` with the caller's content type, return the upstream status and a short text body, map a thrown fetch into 502.
- [ ] **Step 4: Run the tests** — expect pass.
- [ ] **Step 5: Commit** `feat(otlp): пересылка телеметрии приложения в коллектор`.

### Task 2: Server proxy — routes and the access gate

**Files:**
- Create (private repo): `web/src/routes/api/otlp/v1/logs/+server.ts`, `web/src/routes/api/otlp/v1/traces/+server.ts`
- Modify (private repo): `web/src/lib/server/access.ts` (public-path predicate), `web/src/lib/server/csrf.ts` (cookieless exemption), `web/src/lib/server/access.routes.test.ts` (the census)

**Interfaces:**
- Consumes: `forwardToCollector`, `isAcceptedContentType`, `MAX_OTLP_BYTES` from Task 1; `resolveCaller` from `$lib/server/uploads/store`.
- Produces: `POST /api/otlp/v1/logs`, `POST /api/otlp/v1/traces`.

- [ ] **Step 1: Write the failing census entries** — add both paths to `PUBLIC` in `access.routes.test.ts`.
- [ ] **Step 2: Run** the census test — expect failure (paths not public, routes absent).
- [ ] **Step 3: Implement** both routes: `resolveCaller` → 401 without a caller, 403 unless `caller.kind === 'oauth'`, 415 on a wrong content type, 413 over the limit, otherwise forward. Add a narrow regex `^/api/otlp/v1/(logs|traces)$` to `isPublicPath` with a comment saying why (bearer, no session, own gate), and add both paths to the cookieless CSRF exemption.
- [ ] **Step 4: Run** the whole server test project — expect pass.
- [ ] **Step 5: Commit** `feat(otlp): приём телеметрии с телефона по OAuth-токену`.

### Task 3: Server deployment

Deployment happens entirely in the private deployment repository, which
owns the manifests, the build and the rollout. In summary: point the web
service at the collector through an environment variable, build and roll
out the image, then confirm that an anonymous request is refused and an
authorised one reaches the collector.

### Task 4: SPM dependency

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add** a `packages:` block with `opentelemetry-swift` from `2.5.2`, and to both targets dependencies on `OpenTelemetryApi`, `OpenTelemetrySdk`, `OpenTelemetryProtocolExporterHTTP`.
- [ ] **Step 2: Run** `xcodegen` and build both schemes for a device.
- [ ] **Step 3: Commit** `build: add opentelemetry-swift to both targets`.

### Task 5: Telemetry bootstrap, transport and mirror

**Files:**
- Create: `Sources/Shared/Telemetry.swift`, `Sources/Shared/TelemetryTransport.swift`, `Sources/Shared/TelemetryEvents.swift`
- Modify: `Sources/Shared/Diagnostics.swift`

**Interfaces:**
- Produces: `Telemetry.start()`, `Telemetry.event(_:scope:severity:_:)`,
  `Telemetry.span(_:parent:)`, `Telemetry.end(_:status:)`,
  `Telemetry.flush(timeout:)`, `Telemetry.refreshAuthorization()`,
  `TelemetryScope` (`storage`/`share`/`sync`), and an attribute builder that
  takes `[String: TelemetryValue]`.

- [ ] **Step 1: Implement** the resource (service name, version from the bundle, process, OS and model), lazy idempotent start, both providers with batch processors, the OTLP/HTTP exporters bound to `<base>api/otlp/v1/...`, the bearer `headersProvider`, the `OSLogMirror` processor, and the feedback handler replacement.
- [ ] **Step 2: Implement** `TelemetryTransport`: late endpoint binding, synchronous send, spool directory with the count and age caps, replay before send.
- [ ] **Step 3: Build** both targets for a device.
- [ ] **Step 4: Commit** `feat(telemetry): OTLP export with an os_log mirror`.

### Task 6: Call sites

**Files:**
- Modify: `Sources/Shared/SharedDefaults.swift`, `Sources/Shared/VaultStore.swift`, `Sources/Shared/SharedStore.swift`, `Sources/Shared/Uploader.swift`, `Sources/Shared/CaptureFeed.swift`, `Sources/Shared/OAuthClient.swift`, `Sources/Extension/ShareViewController.swift`, `Sources/App/OylooApp.swift`

- [ ] **Step 1: Emit** the events of the spec's table beside every existing `Diagnostics` line, keeping the private lines private.
- [ ] **Step 2: Add** the spans: `share` with `share.extract` and `sync` in the extension, `sync` with `sync.item` in the app.
- [ ] **Step 3: Add** `kind` to `OAuthClient.Failure` and use it instead of the error description in the relay and in attributes.
- [ ] **Step 4: Flush** in the extension before completing or cancelling, and in the app on foreground and background; drain and clear the relay on launch, emitting `share.relay`.
- [ ] **Step 5: Build** both targets for a device.
- [ ] **Step 6: Commit** `feat(telemetry): report the share and upload flow as records and spans`.

### Task 7: Verify end to end

- [ ] **Step 1: Install** the build on the phone.
- [ ] **Step 2: Share** something from the share sheet.
- [ ] **Step 3: Query** the logs backend for `service.name="oyloo-ios"` and confirm records with `process=extension`.
- [ ] **Step 4: Query** the traces backend for a `share` trace.
- [ ] **Step 5: Record** the result in the spec's testing section if anything differed.
