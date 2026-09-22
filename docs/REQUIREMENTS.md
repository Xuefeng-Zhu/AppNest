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

### Rich personal mini-apps (2026-09-22)

Implemented: Daily Planner Today/Tasks/Progress, dedicated detail/editor pages, app identity and themed tabs/desktop navigation, authenticated page/record URLs, guarded unsaved edits, retained filters/search/pagination/scroll, grouped database-wide summaries, independent personal reminder times, owner delivery and typed reminder state. Manual and AI definition editing share capability gates, strict references, publication diffs and canonical compatibility checks.

Automated acceptance covers legacy hashes and records; invalid navigation/action references; semantic page edits; preview/live query parity; rapid navigation, unavailable records, stale responses, revoked access and read-only roles; local midnight/DST boundaries and undated tasks; reminder status transitions, rescheduling/clearing, explicit enrollment, deduplication, archive suppression and restart recovery. Exact executed results and remaining live browser checks are recorded in [VERIFICATION.md](VERIFICATION.md). Isolated rendered screenshots do not prove connected end-to-end delivery. See [MINI_APPS.md](MINI_APPS.md) for the implemented contract.

Typed endpoints cover manifests/list/templates/instantiate/remix/archive/pin; builder begin/get/patch/generate/publish; record query/get and create/patch through the uniform action endpoint; invitations/grants; event streams; inbox/read and run history. Notification effects have no arbitrary client-callable endpoint. All seven semantic components exist; approved view tokens compose list/detail/action/capacity cards, forms, boards and summaries rather than arbitrary widgets.

Generated source and migrations are delivered. The JSONB adapter and custom database guards are documented and tested. Operational request/job/run logs and local guardrails are present. External production auth/email/Redis/storage, cloud deployment, attachments, comprehensive performance/retention operations and full accessibility certification remain deferred as documented in SECURITY.md.

The central **template/manual** demo is verified end to end. Real natural-language generation through Nebius Nemotron also created and published Plant Corner and Trip Kit, with authenticated live record editing, workflow transitions and summary counts. A credentialed semantic label edit preserved the rest of the definition exactly. See [the AI creation check](AI_CREATION_CHECK.md). AI-authored additive field changes and the complete AI sharing/reminder sequence remain separate unverified layers.
