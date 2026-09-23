# Requirements and acceptance evidence

Status meanings: **tested** = locally executed evidence; **implemented** = source present but a listed external/environment layer is unverified; **deferred** = intentionally unavailable, not a fake success path.

| Acceptance requirement | Status | Evidence / qualification |
| --- | --- | --- |
| 1. Same engine, separate definitions, reload persistence | Tested | Three templates plus relabeled fourth definition in PostgreSQL tests; browser-created shift survived web/server reload |
| 2. App/record/invitation/notification/media tenant isolation | Tested locally | Real-DB authorization, bound invitations, private-media authorization and cross-app reference rejection |
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

Typed endpoints cover manifests/list/templates/instantiate/remix/archive/pin; builder begin/get/patch/generate/publish; record query/get/aggregate and create/patch through the uniform action endpoint; private image upload/read; invitations/grants; event streams; inbox/read and run history. Notification effects have no arbitrary client-callable endpoint. The semantic component library uses approved view tokens and validated bindings rather than arbitrary widgets.

Generated source and migrations are delivered. The JSONB adapter and custom database guards are documented and tested. Operational request/job/run logs and local guardrails are present. External production auth/email/Redis/storage, cloud deployment, arbitrary file/video attachments, comprehensive performance/retention operations and full accessibility certification remain deferred as documented in SECURITY.md.

### Rich component library (2026-09-23)

Implemented: tables, local-date calendars/agendas and timelines, database-wide
numeric and time-series charts, metric/target cards, private images and galleries,
static banners/formatted text, typed controls, multi-step forms, checklists and
workflow drag/move controls. AI, manual editing, visual editing, preview and live
adapters use the same capability-gated definitions. Three new templates provide
examples without changing existing published definitions.

Automated coverage includes canonical compatibility, component bindings, more
than 100-record aggregation, DST buckets, form submission and conflict behavior,
private-media quotas/references/revocation/cleanup, actual HTTP upload transport,
and concurrent media requests against ephemeral PostgreSQL. Renderer captures
are isolated synthetic evidence. The development database has the media
migrations, and the updated server and release web app were activated locally.
Connected checks passed for authenticated creation/publication, browser image
upload, final-only multi-step submission, image/record reload persistence,
keyboard workflow movement, checklists, calendar agendas and charts. A separate
authenticated client smoke verified 106 persisted records, authorization,
revision/receipt behavior, private-image revocation and fresh-login persistence.
See [component behavior](RICH_COMPONENTS.md) and the
[dated connected verification record](RICH_COMPONENTS_LIVE_CHECK.md). These
checks do not establish native-device, rich-component live-AI, or production
acceptance.

The central **template/manual** demo is verified end to end. Real natural-language generation through Nebius Nemotron also created and published Plant Corner and Trip Kit, with authenticated live record editing, workflow transitions and summary counts. A credentialed semantic label edit preserved the rest of the definition exactly. See [the AI creation check](AI_CREATION_CHECK.md). AI-authored additive field changes and the complete AI sharing/reminder sequence remain separate unverified layers.

### App appearance and page composition (2026-09-23)

Implemented: coordinated Clean, Editorial and Playful styles; accent colors,
heading typography, spacing and corner overrides; style previews and reset
controls; stacked, two-column and featured-first page layouts; responsive banner
image placement. AI creation/editing and click-to-edit use the same bounded
definition and semantic-patch contract. Absent properties preserve canonical
legacy definitions; presentation changes retain business data and require
publication before reaching the live app.

Automated verification passed: 346 tests across spec, renderer, Flutter authoring
and server packages; real PostgreSQL publication/authorization checks; isolated
two-process reminder recovery; analysis/format checks; and the release web build.
Eight isolated desktop/mobile captures were visually inspected. Connected runtime
activation, preview-to-published visual parity and appearance-specific live-AI
behavior remain unverified; prior connected evidence above does not establish
those layers. See [the appearance contract and verification record](APPEARANCE.md)
for defaults, capability semantics and exact boundaries.
