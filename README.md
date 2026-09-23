# AppNest

Make everyday apps your own. Describe what you want, try it, customize it, and start using it.

A working local Flutter web + Serverpod modular monolith. Mini apps are validated declarative definitions, **not generated executable code**. Daily Planner, reading journals, shared chore boards and capacity-limited volunteer shifts share one renderer and one transactional runtime.

## Create, try, customize

Start with an idea or choose Notes, Reminders, Calendar, or Clock & Focus as an
example. Creation goes straight to generation; **Help shape my idea** offers
optional questions. Explicit templates remain available without AI.

Use **Customize** for appearance, content, layout, and supported behavior. The
same controls and chat edits update a reviewable preview. **Use app** publishes
the first version; **Apply changes** updates an existing app through one review,
preserving saved records and explicit reminder approval.

Clock & Focus adds analog/digital local time and a countdown that can start,
pause, resume, and reset. Timer state stays on the current device, separated by
account and mini-app, and restores from its deadline after reopening. Completion
is shown in AppNest; background alerts and phone integrations are not included.
See [the customization contract and verification record](docs/CUSTOMIZATION.md).

## Personal mini-apps

**Daily Planner** introduces app-owned Today, Tasks and Progress tabs, dedicated task details and editing pages, local-day grouping, search and filters, and database-wide progress totals. Due times and personal reminders are independent and optional. Reminders go to the app owner's AppNest inbox only after the rule is explicitly approved at publication.

The builder's **Pages & navigation** editor controls pages, sections, tabs, field presentation, filters, sorting, destinations and approved themes. The AI builder receives the same validated schema and semantic operations. Existing published definitions keep their canonical hashes and legacy rendering until explicitly republished with navigation. See [mini-app behavior and authoring](docs/MINI_APPS.md) and [dated verification evidence](docs/VERIFICATION.md).

## Rich component library

Mini-apps can use tables, calendars, timelines, bar/donut/line charts, numeric
metrics and progress, private image cards/galleries/banners, formatted text,
multi-step forms, richer inputs, checklists and draggable workflow boards.
Choose components in **Pages & navigation → Views**, edit their settings in the
visual inspector, or ask the AI builder. Project Hub, Photo Journal and Habit
Tracker demonstrate the additions. See the [component contract, image limits,
and runtime activation steps](docs/RICH_COMPONENTS.md).

## Distinctive app designs

Mini-apps have coordinated **Clean**, **Editorial** and **Playful** styles with
custom accent colors, heading typography, spacing and corners. The builder's
**Appearance** controls and AI edits share the same validated settings. Page
layouts can stack sections, pair them in columns, or feature the first section;
banners can place images above or beside their text. Existing apps retain their
appearance until explicitly changed and published. Automated integration checks,
346 tests and the web build passed; connected runtime activation remains
unverified. See the [appearance contract, screenshots and verification
record](docs/APPEARANCE.md).

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

After adding or removing Flutter plugins, run `flutter clean` and then `flutter pub get` from `appnest_flutter` before rebuilding the release web app. This refreshes generated web plugin registration; an existing build cache can otherwise omit a newly added plugin.

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

For new apps, the provider receives the request, schema, capability contract and repair diagnostics without starter templates or a placeholder definition. Edits also receive the current definition to preserve stable IDs. Neither flow receives private records. Output is untrusted and bounded. Generation is durable background work with validation/repair, stale-result guards and explicit publication. The deterministic `FakeAiProvider` is test-only. See the [fresh AI creation check](docs/AI_CREATION_CHECK.md) for actual browser results and limitations.

Creation now requests schema-constrained output; guidance and edits request JSON
objects. The configured provider must support those response formats. AppNest
still validates every returned definition, and format failures display a clear
retry message. See the [planner failure investigation and verification](docs/GENERATION_FAILURE_CHECK.md).

**Nebius live generation verified on 2026-09-22:** the local development server uses `nvidia/Nemotron-3-Ultra-550b-a55b` at `https://api.tokenfactory.us-central1.nebius.com/v1`. A dedicated AppNest key is stored only in ignored, mode-0600 `config/passwords.yaml`; it is not included in source or Flutter builds. Confirm current model routing in the [Nebius catalog](https://tokenfactory.nebius.com/models/catalog) when configuring another environment. Real browser chat created and published **Plant Corner** and **Trip Kit** from fresh prompts, with custom fields, pages, tabs and workflows. Live creation/editing, status changes and summary counts passed, and an AI label edit preserved all IDs and other definition values. Initial failures, refinements and exact evidence are recorded in the [AI creation check](docs/AI_CREATION_CHECK.md). This does not establish universal one-shot generation quality or a complete AI-authored sharing/reminder flow.

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
- [Architecture](ARCHITECTURE.md), [Serverpod feature map](docs/SERVERPOD_FEATURE_MAP.md), [Serverpod feedback](docs/SERVERPOD_FEEDBACK.md), [demo guide](docs/DEMO.md), [security limits](docs/SECURITY.md), [requirements checklist](docs/REQUIREMENTS.md).

For source changes, regenerate from `.spy.yaml` and endpoint source with `serverpod generate` in `appnest_server`; create a migration with `serverpod create-migration` when table models change. Never hand-edit generated protocol/client files. See the companion database-integrity discussion in ARCHITECTURE.md before schema repair.

No cloud deployment, external delivery, arbitrary file/video attachments, offline writes, payments or arbitrary plug-ins are included. Private still images are supported through the authenticated media service. This is a local MVP, **not a production-readiness claim**.
