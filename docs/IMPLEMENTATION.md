# AppNest implementation checklist

The product specification supplied in the build task is authoritative. No deployment is authorized.

- [x] A: Official Serverpod 4 scaffold, real auth/PostgreSQL, serialization spike, AppSpec, generic renderer, persistent CRUD.
- [x] B: Explicit grants, hashed invitations, capacity, atomic receipts, invalidation streams, independent-session concurrency tests.
- [x] C: Durable outbox, real reminders, reconciliation, run history, process interruption/restart test.
- [x] D implementation: Server-only AI adapter, durable generation jobs, isolated preview, exact-candidate review/publication, additive edits.
- [ ] D external verification: credentialed live AI creation/edit; provider not configured. Templates/manual mode remains runnable.
- [x] E: Launcher, three templates, manual edits, remix, responsive states, explicit development seed and real-endpoint demo.
- [x] Local verification: formatting, static analysis, unit/widget/PostgreSQL integration tests, runnable browser checks; see VERIFICATION.md and REQUIREMENTS.md for bounded claims.

## Decisions

- Flutter 3.47.0 / Dart 3.13.0 / Serverpod family 4.0.0. Generate protocol and transport from model/endpoint source.
- Use Serverpod 4 embedded PostgreSQL for development/test and a single API/scheduler process. Redis disabled locally.
- App mutations serialize on an app control row. This trades per-app throughput for simple publication/grant/capacity consistency.
- Flexible record data uses a verified serialization adapter; query projections are typed rows maintained atomically.
- Development login uses real email/password auth. Codes are displayed by the development server; no production user switcher.
- AI configuration is absent until supplied by the operator. Template/demo mode is explicitly labeled; no invented model identifier.
- Attachments and public deployment are deferred.
