# Live customization evaluation — 2026-09-23

The approved Nebius checks are complete. Latest results across targeted reruns: **5/8 creations and 8/8 edits passed**. Five edits used saved AI-generated apps; three used explicitly selected synthetic templates after creation failed. All eight latest edits passed on the first attempt, in 2.7–5.8 seconds. **Five of eight AI-generated definition-and-edit pairs are validated.**

The configured model was `nvidia/Nemotron-3-Ultra-550b-a55b` on the approved `us-central1` Nebius endpoint. The recorded batches made 84 provider requests including retries and checks after fixes. No user records were sent, no apps were published, and no development server was started.

| Scenario | Latest creation | Latest edit | Edit baseline |
| --- | --- | --- | --- |
| Notes — add Source | Fail; 44.7s; 3 attempt(s) | Pass; 5.8s; 1 attempt(s) | Explicit template |
| Notes — appearance | Pass; 16.8s; 2 attempt(s) | Pass; 3.1s; 1 attempt(s) | AI-generated app |
| Reminders — timing | Fail; 31.5s; 3 attempt(s) | Pass; 4.3s; 1 attempt(s) | Explicit template |
| Reminders — name | Pass; 29.4s; 2 attempt(s) | Pass; 3.4s; 1 attempt(s) | AI-generated app |
| Calendar — category | Pass; 17.6s; 2 attempt(s) | Pass; 2.7s; 1 attempt(s) | AI-generated app |
| Calendar — appearance | Pass; 43.4s; 3 attempt(s) | Pass; 3.7s; 1 attempt(s) | AI-generated app |
| Focus — duration | Fail; 38.7s; 3 attempt(s) | Pass; 5.7s; 1 attempt(s) | Explicit template |
| Focus — clock style | Pass; 35.7s; 3 attempt(s) | Pass; 3.1s; 1 attempt(s) | AI-generated app |

## Remaining creation failures

The notes/Source, reminder-timing, and focus-duration creation cases still exhausted their three-attempt bounds. Across those attempts, failures included missing multiline controls, incorrect action/form links, missing declared capabilities, unnecessary record data in a utility app, and truncated output. Invalid candidates were rejected. Creation reliability remains insufficient for a dependable describe-and-use promise.

## Changes verified

- Edit requests now use a typed semantic-patch schema in both the prompt and response format; full-app schema instructions are limited to creation.
- `AddField.viewIds` binds a server-allocated field to forms/details atomically, including implicit stepped forms. Manual customization uses the same operation.
- Closing the manual editor waits for its route animation before disposing text controllers.
- Retry diagnostics identify the actual missing configuration and reminder recipient requirements.
- The evaluator checks reachable controls, exact requested features, preserved IDs/settings, and valid initial reminder state. It retains synthetic definitions/responses for inspection.

## Evidence and boundaries

The [initial run](evidence/customization/provider-eval-initial.json) accepted 5/8 creations and 0/5 attempted edits under weaker feature checks. The [first strict run](evidence/customization/provider-eval-round2.json) accepted 3/8 creations and 2/3 attempted edits. The [creation recheck](evidence/customization/provider-eval-create-recheck.json), [saved-calendar edit recheck](evidence/customization/provider-eval-edit-recheck.json), and [explicit template edit checks](evidence/customization/provider-eval-template-edits.json) support the latest table. These batches used evolving assertions and targeted fixes; their percentages are not directly comparable.

The notes/Source prompt was clarified to request a details page before its edit, matching the edit requirement. All 13 latest accepted results (5 creations + 8 edits) were replayed offline against the final assertions. [Machine-readable summary](evidence/customization/provider-eval-summary.json).

Final local verification passed **505 tests** (76 spec, 152 renderer, 159 Flutter app, 118 server), analysis, formatting, PostgreSQL integration and two-process restart recovery. Updated web and Android release builds passed. The pre-push suite also includes six mobile/desktop capture cases for Notes, Reminders, and Calendar.

Times include direct provider calls, validation and retries. They exclude server queue timing and user interaction. These checks do not establish publication through the connected UI, physical-device behavior, timer background alerts, or production readiness. iOS compilation still needs the missing Xcode platform component.
