# Local demo

Start with the README command and explicit `--seed-demo`; sign in as Morgan. Use separate browser profiles for Alex and Sam if demonstrating simultaneous people. Do not use a production account or expose the public demo passwords.

## UI walkthrough

1. Select AppNest demo. Open each of Reading Journal, Chore Board and Volunteer Shifts. They are interpreted by the same renderer; add/edit records and reload.
2. Use a template to open the builder. Preview records are visibly synthetic and local; joining a preview shift does not create a live claim.
3. If the operator has configured a real provider, describe “Volunteer shifts for our food pantry, with one place per shift and an in-app reminder.” Watch persisted queued/generating/validating/preview-ready stages. Without credentials, use the visibly labeled template/manual path. Do not narrate it as AI generation.
4. Review the exact candidate, policy/capabilities, optional existing-record scope and reminder requests. Publish explicitly. Create a live shift with capacity one.
5. Copy separate member invitation links for Alex and Sam. Both open the same app, not copies. Have them join concurrently. One is confirmed; the other sees exhausted capacity. There is no optimistic reservation guarantee.
6. Owner: Edit with AI, request an optional preparation field (credentialed path), or Edit manually → AddField (explicit manual fallback). Review and publish. Sign-ups and stable IDs survive.
7. In the accelerated automated demo, the shift starts in one hour plus 35 seconds, so its approved one-hour-before reminder is due in about 35 seconds. This is synthetic demo timing, not a changed platform clock. Close clients, wait, reopen the winner's Inbox and owner's Activity and reminder history.

## Automated real-endpoint walkthrough

```sh
cd appnest_client
dart run bin/local_demo.dart --accelerated-template-demo
```

This creates a new app on each run and leaves it available for inspection. It uses genuine email/password logins and generated clients, role-specific invitation acceptance, concurrent capacity commands, explicit candidate publication and the running server's scheduled work. It does not call worker internals. The winner is nondeterministic. A successful run prints one notification and one successful run after all clients close/reopen.

## Crash recovery

```sh
dart run scripts/restart_smoke.dart
```

Run from repo root. Uses `appnest_server/.serverpod/restart/pgdata` / `appnest_restart_smoke`, not your development database. Process one commits a run and exits immediately before scheduling. Process two starts independently and reconciles it, then repeats the wakeup and checks one persisted notification. Each run uses unique synthetic identities; it never wipes the database. This validates a real process boundary, not a mocked restart.

Live AI credentials, production email delivery, native-device installation and public deployment are outside the evidence collected here.
