# Security boundaries and operational limitations

This describes the checked-out implementation. Dated acceptance records remain
historical evidence; they do not establish production readiness or a clean current
runtime. See the [architecture review](ARCHITECTURE_REVIEW.md) for unresolved
correctness findings and [development guide](DEVELOPMENT.md) for local operation.

## Implemented boundary

Live endpoints require Serverpod authentication. No client-supplied actor or tenant ID is trusted. Workspace and app grant checks precede data access. Mini-app definitions cannot grant rights, contain credentials or choose network destinations. Model output is parsed and validated, never executed. Capacity/claims, workflow transitions, assignment, notifications and automations are trusted handlers, not editable payload authority.

Cross-app/tenant IDs, wrong invitation recipients, protected workflow/capacity edits, viewer mutations, notification access, stale definitions, revision conflicts, changed idempotency requests and invalid database relationships have regression coverage. Owners alone archive. Archive disables writes and stale effects. Invitation tokens are random, hashed, scoped, role-selected, expiring, single-use and revocable. Notification listing/read state rechecks current app access.

Preview has no transport or scheduler dependency. AI prompts omit private records; operators alone control provider configuration. HTTP diagnostics do not expose provider response bodies or secrets. Framework server-side exception stacks can appear in development logs; typed client errors do not expose stacks.

## Known correctness limitations

The 2026-10-07 [architecture review](ARCHITECTURE_REVIEW.md#confirmed-findings)
reproduced these application defects; no fixes are implied by the boundaries above:

- **Client command retries:** another Save allocates a new command key. A lost
  response after a committed create can therefore produce a duplicate record.
  Server receipts deduplicate only retries using the same key and exact input.
- **Authorization UI lifecycle:** the legacy renderer can retain an open editor's
  private text, or accept a late query result, after its access error. This is
  retained client state, not evidence of unauthorized backend reads after revocation.
- **Stream cleanup:** cancellation of an unchanged app's direct endpoint stream can
  remain pending until a revision change produces another yield. The review used
  the real endpoint and PostgreSQL; transport-level cancellation remains untested.
- **Reminder retry timing:** execution does not enforce the persisted
  `nextAttemptAt` deadline, so a due occurrence can run before its retry backoff.
- **Revoked assignments:** existing member references remain after grant
  revocation. Unrelated note edits and workflow transitions then fail member
  validation, including for the owner, until the assignment is changed separately.

## Release gates / not proven

- **Local-only seeded environment.** Public synthetic credentials must never be enabled on an exposed deployment. Seeding refuses non-development run modes; no production user-switcher endpoint exists.
- **No production auth/email verification.** Real local password login is tested. Production email transport, abuse protections, account recovery and operator configuration require deployment-specific verification. The default Serverpod Cloud email configuration is not evidence that a cloud service is connected.
- **Web tokens:** the current official scaffold client stores auth tokens using its SDK storage. Before public deployment, configure HTTPS, strict allowed origins, secure httpOnly cookie auth where supported, CSP and a reviewed host origin policy. Local development listeners must not be exposed to untrusted networks.
- **Startup:** companion integrity guards are installed just after Serverpod starts listeners. Future production orchestration must gate readiness/traffic until setup completes and separate schema-maintenance privileges from runtime privileges.
- **Scale:** app-level serialization, field projections and server-side revision polling are intentional MVP tradeoffs. No throughput/load benchmark or multi-instance Redis/shared-event deployment has been verified. Independent AI jobs share eight Future Call slots per process with reminders and reconciliation; when the pool is full, other work waits for a slot. Due times are persisted, and scheduling lag is logged. The pool does not enforce provider RPM/TPM limits across server processes.
- **Retention/quotas:** chosen query/spec/job/fan-out limits are implemented, but total record storage, audit/outbox retention, database backups/restoration, orphan draft cleanup and per-organization billing/abuse controls need operator policies. Old drafts count toward the workspace app limit. Do not delete database directories as routine cleanup.
- **AI:** provider credentials are read server-side from the ignored environment-specific `config/passwords.yaml`; `.env` files alone do not configure this adapter. Availability depends on the operator's current configuration. Historical [connected AI creation/editing](AI_CREATION_CHECK.md) and [provider-only customization evaluation](CUSTOMIZATION_AI_CHECK.md) establish different layers and retain their failures and limitations. They do not verify provider privacy contracts, current credentials, production expense controls or universal generation quality. Response-format hints are provider-dependent; strict application validation remains authoritative. Saved job usage describes the latest attempt, not cumulative billed usage across retries; use provider billing for totals.
- **Accessibility:** semantic controls, keyboard traversal, responsive screens and renderer tests at 150% text are checked. This is not an exhaustive screen-reader/WCAG audit or a native-device accessibility certification.
- **UI scope:** invitation binding and member pickers use account IDs, not a contacts directory. The member directory returns at most 100 grants without pagination, so larger memberships are incomplete in management and assignment pickers. Page-local grouped record lists are labeled when pagination applies; `runtime.summary` and `runtime.aggregate` compute database-wide results. Existing-record activation selection displays up to 50 rows per relevant collection, with the server enforcing a 500-record explicit maximum.
- **Private images:** authenticated app-scoped image uploads/reads use private storage, byte validation, metadata stripping, same-app reference checks and retained-version protection. Uploads and cleanup are bounded; see [media limits and authorization](RICH_COMPONENTS.md#private-images). Revocation denies subsequent reads; already-delivered bytes cannot be recalled.
- **Future capability limits:** no arbitrary file/video attachments, payments, general external integrations, public marketplace, executable plug-ins, recurring user-local schedules, offline writes or destructive data migrations. Definition versions do not restore deleted data or undo delivered effects.

No production deployment, penetration test, external delivery, signed mobile installation or hackathon eligibility is claimed.
