# AppNest

Describe the tool your group needs. AppNest creates it—with shared data, permissions, and automations.

A working local Flutter web + Serverpod modular monolith. Mini apps are validated declarative definitions, **not generated executable code**. Reading journals, shared chore boards and capacity-limited volunteer shifts share one renderer and one transactional runtime.

## Run locally

Verified toolchain: **Flutter 3.47.0 · Dart 3.13.0 · Serverpod CLI/server/client/auth 4.0.0**. Package resolution is committed in `pubspec.lock`. Use the matching CLI (`dart pub global activate serverpod_cli 4.0.0`) if yours differs. Do not independently upgrade one Serverpod package.

```sh
cd /Users/frank/mygit/AppNest
dart run scripts/init_local.dart
bash scripts/run-local.sh --seed-demo
```

Open **http://localhost:8182/**. API: 8180; Insights: 8181; embedded PostgreSQL: 8190. The first run can download Serverpod's PostgreSQL binaries. This is real PostgreSQL managed by Serverpod 4, not an in-memory substitute. No Docker daemon or Redis is required for this single-process setup. Data survives restarts in ignored `appnest_server/.serverpod/development/pgdata`.

Local demo accounts, created only with the explicit `--seed-demo` flag:

| Email | Password |
| --- | --- |
| morgan@appnest.local | AppNest-local-demo-2026! |
| alex@appnest.local | AppNest-local-demo-2026! |
| sam@appnest.local | AppNest-local-demo-2026! |

These are public **synthetic development accounts**, using real Serverpod email/password authentication. Select **AppNest demo** in the workspace switcher after signing in as Morgan. Each account also has its own workspace. Seeding is repeatable and does not erase arbitrary data. Never expose this seeded environment publicly.

If the server is already running, do not start a second listener. Stop that AppNest process before running the script again. Do not stop another repository's server. To rebuild only:

```sh
cd appnest_flutter
flutter build web --dart-define=SERVER_URL=http://localhost:8180/ --output ../appnest_server/web/app
```

### Local server lifetime and connection recovery

Keep the terminal running when using `scripts/run-local.sh`: closing its process stops both the API and web server. A previously opened browser page can remain visible while its requests fail. Start the server again and select **Retry**; the launcher also retries a failed read when the app returns to the foreground. Retries show a loading state and never replay business commands. Connection, session and permission failures have separate messages without raw transport diagnostics.

On macOS, after the initial setup and web build, a session-local background job can keep AppNest independent of a tool terminal. From the repository root, with `dart` on PATH and no existing AppNest listener:

```sh
launchctl submit -l local.appnest.dev \
  -o /tmp/appnest-local-server.log -e /tmp/appnest-local-server-error.log \
  -- /bin/sh -c 'cd "$1" && exec "$2" run bin/main.dart --apply-migrations' \
  appnest "$PWD/appnest_server" "$(command -v dart)"
launchctl list local.appnest.dev
# Stop only this AppNest job before restarting or using run-local.sh:
launchctl remove local.appnest.dev
```

This does not install a login item or reboot-time startup file. It must be started again after logout/reboot. Logs in `/tmp` are development-only and may include framework diagnostics; do not publish them. Preserve the ignored PostgreSQL data directory and `config/passwords.yaml` when restarting.

## AI setup

Without provider credentials the UI explicitly says **Template mode — AI provider not configured**. Templates, manual editing, publishing, shared data and reminders remain usable. Nothing pretends to be a live AI response.

Add `AI_BASE_URL`, `AI_MODEL`, and `AI_API_KEY` under the appropriate environment in the ignored `appnest_server/config/passwords.yaml`. See `config/passwords.example.yaml`. Use an actual operator-approved chat-completion-compatible provider and its real model ID; the adapter appends `/chat/completions` to the base URL. Restart the server. Secrets are never sent to Flutter or read from an AppSpec. `.env` files alone are not read by this adapter.

The provider receives the schema, capability catalog, templates, request and current definition; it does not receive private records. Output is untrusted and bounded. Generation is durable background work with validation/repair, stale-result guards and explicit publication. The deterministic `FakeAiProvider` is test-only.

**Nebius live generation verified on 2026-09-22:** the local development server uses `nvidia/Nemotron-3-Ultra-550b-a55b` at `https://api.tokenfactory.us-central1.nebius.com/v1`, as listed in that model's Nebius public-endpoint panel. A dedicated AppNest key is stored only in ignored, mode-0600 `config/passwords.yaml`; it is not included in source or Flutter builds. Confirm current model routing in the [Nebius catalog](https://tokenfactory.nebius.com/models/catalog) when configuring another environment. The authenticated browser flow generated and validated “Community Kitchen Helpers” in two attempts. Its saved generation job identifies the Nemotron model and regional provider. The resulting draft remains **unpublished**, with zero live records and zero automations. Credentialed additive editing and the complete publish/share/reminder AI demo have not yet been verified. The existing template/manual demo remains separate evidence.

## Verify and demonstrate

```sh
bash scripts/verify.sh
# With the seeded development server running in another terminal:
cd appnest_client
dart run bin/local_demo.dart --accelerated-template-demo
```

The demo uses actual authenticated RPC calls. It creates a fresh synthetic app, publishes an approved rule, races two users for one place, adds an optional field, closes all clients, then reopens to verify a persisted scheduled notification and run history. The 35-second timing and template/manual path are explicitly labeled. It is **not** evidence of live AI generation.

Executed locally: clean static analysis; spec tests; responsive renderer tests at 390×844 and 1440×1000 with 150% text; real PostgreSQL integration tests including 20 concurrent claim attempts; two-process crash recovery; release web build; authenticated browser CRUD, builder/manual publication and desktop/mobile inspection. See [verification evidence](docs/VERIFICATION.md) for exact counts, screenshots, limitations and dates.

## Repository guide

- `appnest_server`: typed endpoints, trusted services, generated protocol, migrations, durable workers and real-DB tests.
- `appnest_client`: generated Dart transport; `bin/local_demo.dart` is hand-authored verification tooling.
- `appnest_flutter`: authentication, launcher/workspaces, builder, mini-app shell and inbox.
- `packages/appnest_spec`: pure-Dart parser, strict JSON schema, fixtures, semantic patches, compatibility and query validation.
- `packages/appnest_renderer`: shared semantic components; separate preview/live adapter contract.
- [Architecture](ARCHITECTURE.md), [Serverpod feature map](docs/SERVERPOD_FEATURE_MAP.md), [demo guide](docs/DEMO.md), [security limits](docs/SECURITY.md), [requirements checklist](docs/REQUIREMENTS.md).

For source changes, regenerate from `.spy.yaml` and endpoint source with `serverpod generate` in `appnest_server`; create a migration with `serverpod create-migration` when table models change. Never hand-edit generated protocol/client files. See the companion database-integrity discussion in ARCHITECTURE.md before schema repair.

No cloud deployment, external delivery, attachments, offline writes, payments or arbitrary plug-ins are included. This is a verified local MVP, **not a production-readiness claim**.
