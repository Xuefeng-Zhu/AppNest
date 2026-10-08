# AppNest

Make everyday apps your own. Describe an idea, try it in an isolated preview, customize it, and publish it for use.

AppNest is a local Flutter + Serverpod mini-app platform. Each mini-app is a validated declarative definition rendered by a shared engine. PostgreSQL stores its definition, records, access grants, command receipts, and durable reminder work. AI proposes definitions and semantic edits; it never produces executable application code.

## Start developing

Use **Flutter 3.47.0, Dart 3.13.0, and Serverpod CLI/server/client/auth 4.0.0**. The workspace constraints and committed `pubspec.lock` pin this verified combination.

From the repository root:

```sh
flutter pub get
dart run scripts/init_local.dart
cd appnest_server
serverpod start
```

`serverpod start` generates code, watches source changes, runs the backend, and launches the configured Flutter companion app. Use the app URL shown in its terminal UI. API: **8180**; Insights: **8181**; backend web server: **8182**; development PostgreSQL: **8190**. Port 8182 serves the last built release web app when one exists; use the launched companion app while developing.

Local PostgreSQL is managed by Serverpod; Docker and Redis are not required. Setup creates ignored development/test secrets only if they are absent. Existing passwords and database contents are preserved.

For synthetic demo accounts, stop the current session and run this from `appnest_server`:

```sh
serverpod start -- --seed-demo
```

Seeding is explicit and development-only. See [local development](docs/DEVELOPMENT.md) for demo sign-in, the release-web script, builds, migrations, troubleshooting, and the agent workflow. See [the demo guide](docs/DEMO.md) for the multi-user walkthrough.

## What you can build

| Experience | Supported behavior | Guide |
| --- | --- | --- |
| Personal utilities | Notes, Reminders, Calendar, Clock & Focus, device-local countdown persistence | [Customization](docs/CUSTOMIZATION.md) |
| Personal and shared record apps | Pages, tabs, forms, details, filters, workflows, assignment, capacity claims, approved inbox reminders | [Mini-apps](docs/MINI_APPS.md) |
| Rich data and content | Tables, calendars, timelines, charts, metrics, private images, multi-step forms, checklists, workflow boards | [Rich components](docs/RICH_COMPONENTS.md) |
| App appearance | Clean, Editorial, and Playful styles; typography, spacing, colors, and page composition | [Appearance](docs/APPEARANCE.md) |
| Mobile capabilities | Local device information, flashlight, foreground brightness, keep-awake, and haptics with per-user consent | [Mobile features](docs/MOBILE_FEATURES.md) |

**Customize** and chat edits update the same reviewable preview. **Use app** publishes the first version; **Apply changes** publishes an update. Publication preserves compatible records and requires explicit reminder approval. Preview data stays isolated. Timers and device controls do not provide background phone alerts; physical-device acceptance is recorded separately from source and compilation checks.

## Optional AI

Without provider configuration, the UI shows **Template mode — AI provider not configured**. Templates, manual editing, publication, shared records, and approved reminders remain usable.

Configure `AI_BASE_URL`, `AI_MODEL`, and `AI_API_KEY` in the ignored server `config/passwords.yaml`, then restart the server. `.env` files alone are not read by the adapter. Provider keys stay on the server, and private record contents are excluded from generation context.

See [AI setup and generation behavior](docs/AI_SETUP.md) for response formats, the scoped OpenRouter development route, request limits, repair/compiler behavior, and troubleshooting. Provider-specific historical results are evidence for those dated checks, not a guarantee of current availability or generation quality.

## Verify changes

From the repository root:

```sh
bash scripts/verify.sh
```

The script checks analysis, authored-source formatting, spec tests, renderer tests, Flutter host tests, real-PostgreSQL server tests, and separate-process reminder recovery. It does **not** build a release app or run a live AI/browser/device check. Focused commands and build instructions are in [development](docs/DEVELOPMENT.md#verification).

[Verification records](docs/VERIFICATION.md) separate dated automated, browser, provider, and device evidence. The [architecture review](docs/ARCHITECTURE_REVIEW.md) records authorization lifecycle, stream cleanup, assignment, and CI defects. Retained-command UI retry recovery is implemented and covered by widget tests; pending commands do not survive browser reload. Passing existing tests does not resolve the other findings.

## Repository map

| Path | Responsibility |
| --- | --- |
| `packages/appnest_spec` | Pure-Dart definitions, schema, fixtures, semantic patches, compatibility, query validation |
| `packages/appnest_renderer` | Shared semantic UI, navigation, isolated preview and runtime adapter contracts |
| `appnest_flutter` | Authentication, launcher, builder, routing, live adapter, local device state |
| `appnest_server` | Authenticated endpoints, trusted services, platform models, migrations, durable workers |
| `appnest_client` | Generated transport in `lib`; hand-authored verification tools in `bin` |

Start with [the documentation index](docs/README.md), [architecture](ARCHITECTURE.md), and [requirements](docs/REQUIREMENTS.md). Contributors and coding agents must follow [AGENTS.md](AGENTS.md), including the MCP-first migration/reload workflow and generated-code boundaries.

This is a local MVP. Deployment, external notification delivery, arbitrary executable plug-ins, payments, offline writes, and destructive data migrations are outside the current scope. [Security and operational limits](docs/SECURITY.md) list the remaining release gates.
