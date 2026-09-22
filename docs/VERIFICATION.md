# Local verification — 2026-09-21

## Executed results

| Command / check | Actual result |
| --- | --- |
| `serverpod generate` in appnest_server | Generated protocol, clients, Future Calls and test tools with CLI 4.0.0 |
| `dart analyze --fatal-infos` at root | No issues found |
| `dart format --output=none --set-exit-if-changed ...` using verify.sh paths | 90 source files checked, zero formatting changes |
| `dart test` in packages/appnest_spec | 7 passed |
| `flutter test` in packages/appnest_renderer | 8 passed, including reconnect/resume/duplicate invalidations and six family/viewport cases at 150% text |
| `dart test --concurrency=1` in appnest_server | 15 passed (12 runtime, 2 persistence/transaction spike, 1 official scaffold greeting) |
| `dart run scripts/restart_smoke.dart` | Two independent processes, committed run recovered, duplicate wakeup harmless, one durable notification |
| `flutter build web --dart-define=SERVER_URL=http://localhost:8180/ --output ../appnest_server/web/app` | Release build succeeded; Wasm compatibility dry run succeeded, not an actual Wasm deployment |
| `bash scripts/run-local.sh --seed-demo` | Existing secrets preserved, web build completed, migrations checked, real PostgreSQL/server/scheduler started, repeat seed completed |
| `dart run bin/local_demo.dart --accelerated-template-demo` in appnest_client | Real authenticated endpoints: one final-place winner, optional-field publication preserved claim, clients closed, reopened to one persisted notification and one successful run |

`bash scripts/verify.sh` sequences the analysis/format/spec/renderer/backend/restart checks. A test-only import placement issue and an invalid simulated Flutter lifecycle transition were fixed during the run; the reconnect test was rerun successfully. The final analyzer also treats informational diagnostics as failures. The separate test database warns that its Insights service secret is absent; Insights is disabled there, not PostgreSQL, RPC or application authentication. No test failure is being counted as a pass.

The live demo reported app 35 / version 36 / record 41 on its first successful run. IDs are local evidence, not API constants. Additional repeat demos intentionally create fresh synthetic apps.

## Browser evidence

Inspected the actual Flutter release build in the Codex browser at 1280×720 and 390×844:

- Real Serverpod email/password sign-in as a development account.
- Personal workspace empty state and shared workspace launcher with database-backed counts.
- Three template entries and their common renderer. Created “Food pantry setup” with real form fields and capacity; four records remained after reload.
- Desktop builder with dominant isolated preview; mobile Chat / Preview / Changes tabs.
- Manual AddField “Arrival instructions”, visible diff and exact-candidate review; explicit publish returned to all four live records, with no synthetic records copied.
- Visible keyboard focus and Tab traversal from Back to Activity and reminder history.
- No warning/error console entries during the captured authenticated editing flows. Transient connection errors while the development server is deliberately stopped are not treated as application data loss.

Screenshots: [desktop home](evidence/home-desktop.png), [mobile home](evidence/home-mobile.png), [desktop runtime](evidence/runtime-desktop.png), [desktop builder](evidence/builder-desktop.png), [mobile builder](evidence/builder-mobile.png), [mobile runtime](evidence/runtime-mobile.png). Captures contain synthetic local data. Some were taken before final explanatory-copy refinements; the underlying flows were unchanged.

## Design comparison

The frontend design skills guided a calm launcher rather than a permanent chatbot. Compared the generated [concept](design/launcher-concept.png) and real screenshots visually:

1. Preserved warm off-white canvas, white bordered surfaces, charcoal text and restrained teal primary actions.
2. Preserved left workspace/navigation rail on desktop; replaced it with clear bottom navigation at narrow widths.
3. Bundled Lora locally for the editorial headline, with readable system sans-serif control/body text.
4. Preserved the prominent description input, app tiles, small approved icon palette and template rows. Actual record counts/layout respond to real data rather than matching fictional concept counts.
5. Builder/runtime use the same restrained spacing and cards; the desktop preview is dominant, while mobile tabs avoid squeezing three columns into a phone. Full-width record cards and local-time date formatting were corrected during visual inspection.

## Not executed / remaining gates

- Credentialed live AI generation and AI additive editing: no provider secrets configured. Template/manual mode and fake-provider failure tests are not substitutes for this gate.
- Public/cloud deployment, production email/Redis/shared events, hosted Insights, external storage, native signed builds and device installation.
- Full screen-reader/WCAG, cross-browser, load/performance, production retention/backup/recovery and independent security audit.
- The Flutter host's scaffold test file contains no host widget suite; renderer widgets have automated coverage and host flows were inspected in the browser. Do not infer a separate passing host test suite.

Docker's daemon was unavailable; Serverpod 4's documented embedded PostgreSQL ran successfully instead. Serverpod MCP tools were not available, so CLI generation/migrations/startup and browser inspection were used. Nothing was deployed or pushed.
