# Requirements and acceptance evidence

Status meanings: **tested** = locally executed evidence; **implemented** = source present but a listed external/environment layer is unverified; **deferred** = intentionally unavailable, not a fake success path.

| Acceptance requirement | Status | Evidence / qualification |
| --- | --- | --- |
| 1. Same engine, separate definitions, reload persistence | Tested | Three templates plus relabeled fourth definition in PostgreSQL tests; browser-created shift survived web/server reload |
| 2. App/record/invitation/notification tenant isolation | Tested | Real-DB authorization + bound invitation tests; file endpoints absent |
| 3. Member cannot grant rights, edit counters/protected workflow | Tested | Policy tests and typed action handlers; generic patch rejects protected input |
| 4. 20 concurrent final-place attempts → one allocation | Tested | Independent committed sessions/transactions, not a single rollback wrapper |
| 5. Identical command retry returns stored outcome; changed input fails | Tested | Receipt regression including retry after publication |
| 6. Cancellation and transaction rollback preserve invariants | Tested | Repeated release, failed capacity/create transaction, business/outbox checks |
| 7. Preview cannot reach live writes/schedules | Tested | Network-free adapter package contract; independent preview mutation test; synthetic UI labels |
| 8. Optional additions preserve records/claims/IDs | Tested | Spec compatibility + PostgreSQL publication test + actual endpoint demo + browser manual publish |
| 9. Stale drafts/jobs and safe publication retries | Tested | Expected-version/hash/receipt and obsolete generation/manual mutation regressions |
| 10. Interruption between committed run and scheduling recovers | Tested | Separate persistent PostgreSQL database and two actual processes; repeat wakeup → one durable notification |
| 11. Rule/date/archive/grant changes suppress stale work | Tested | Execution-state tests plus rule-generation explicit re-enrollment regression |
| 12. Reconnect/repeated invalidations recover state | Tested, bounded | Renderer reconnect/resume/duplicate-event test; stream authorization rechecked; live server restart observed. No multi-instance/load test |
| 13. AI failure does not break apps; template mode explicit | Tested; live generation verified | Malformed output bounded to three attempts; existing app CRUD works; template mode remains explicit without credentials. Nebius Nemotron live generation reached a validated, unpublished preview on 2026-09-22; credentialed additive editing remains unverified |
| 14. Mobile/desktop, keyboard and large text | Tested, bounded | Renderer 390×844/1440×1000 at 150%; browser 1280×720 and 390×844; Tab focus and mobile builder publication. Full accessibility audit deferred |

## Vertical slices

- **A tested:** official Serverpod 4 scaffold; real auth; PostgreSQL dynamic serialization spike; pure-Dart AppSpec/schema; shared renderer; persistent CRUD.
- **B tested:** workspace + explicit app grants; hashed invitations; capacity claims; idempotency/revisions; typed streams; concurrency.
- **C tested:** atomic outbox; recurring reconciler; Future Calls; actual in-app reminder, run history and process restart proof.
- **D implemented/tested, with live generation verified:** recoverable jobs, bounded server-only provider adapter, isolated preview, manual/semantic edits, exact review/publication, safe evolution. Nebius Nemotron creation was verified on 2026-09-22; credentialed additive editing remains unverified.
- **E tested with limitations:** calm launcher, bounded tile request, workspace switcher, templates/inbox, shell/sharing/activity, manual field/label/choice/view order, remix/unpin/archive, responsive layouts and repeatable seed/demo.

## Additional scope

Typed endpoints cover manifests/list/templates/instantiate/remix/archive/pin; builder begin/get/patch/generate/publish; record query/get and create/patch through the uniform action endpoint; invitations/grants; event streams; inbox/read and run history. Notification effects have no arbitrary client-callable endpoint. All seven semantic components exist; approved view tokens compose list/detail/action/capacity cards, forms, boards and summaries rather than arbitrary widgets.

Generated source and migrations are delivered. The JSONB adapter and custom database guards are documented and tested. Operational request/job/run logs and local guardrails are present. External production auth/email/Redis/storage, cloud deployment, attachments, comprehensive performance/retention operations and full accessibility certification remain deferred as documented in SECURITY.md.

The central **template/manual** demo is verified end to end. Real natural-language generation through Nebius Nemotron is now verified through an unpublished preview. The complete **live AI** demo still requires a credentialed edit and the publish/share/reminder sequence; a successful generation alone is not evidence of that full sequence.
