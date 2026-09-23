# Prompt-first app creation

AppNest's creation workspace follows a describe, preview, refine, publish loop.
It uses the existing authenticated Serverpod builder and validated declarative
definitions. The creation loop reuses the existing provider configuration;
conditional clarification adds a separate, rate-limited server request.

- Home offers a large idea composer and editable starter ideas. When AI is not
  configured, the action explicitly opens templates.
- Creating an app carries the submitted idea into the builder conversation.
  Fresh generation hides the internal starter definition until a validated
  result is available. Queued, generating, and validating states come from the
  durable server job; there is no simulated progress or completion.
- Desktop shows conversation and interactive preview side by side. Smaller
  screens have Chat and Preview tabs. Desktop/mobile preview controls and sample
  data reset operate only on the isolated preview adapter.
- Accepted prompts remain visible for the current builder session. Subsequent
  requests use the existing candidate as context through the server's generation
  mode rules. This change does not add durable conversation history or reopenable
  draft navigation; leaving the builder does not preserve its client transcript.
- Blank requests and overlapping submissions are blocked. Failed requests retain
  the editable prompt. Home retries reuse the begun draft, and recover a request
  whose enqueue succeeded but whose response was lost. A failed later generation
  keeps the last preview visible. Connection recovery rechecks AI availability.
- The edit menu keeps manual field/label editing and Pages & navigation available.
  Publish opens a review sheet; reminder approvals name the trigger, recipient,
  timing and condition. Final confirmation retains exact-candidate publication,
  record scope selection, revision checks and idempotency. Sample records are
  never published.

## Clarifying broad ideas

Pressing **Create app** or **Send** with a nonblank AI request first checks
whether missing details would materially change the app structure or requested
edit. A sufficiently specific request continues into the existing generation
flow. For a broad request, AppNest shows two or three focused questions with
selectable answers before beginning a draft or enqueuing generation. Typing
alone never sends a provider request. New-app checks use the selected workspace;
follow-up checks use the authorized draft definition as context, without
sending record data.

One choice can be selected per question, and questions may be skipped.
Selections remain local until the user chooses **Use selections**. AppNest then
places the current idea and selected question/choice pairs into the existing
composer as ordinary, fully editable text for review before Create or Send.
Users can also continue with their original request. A late assessment is
ignored if the idea, workspace or draft changes. Generation retries do not
reassess an already accepted request. If the provider is unavailable or its
answer is unusable, labeled built-in choices remain available, with an explicit
way to continue
without answering. The clarification check is limited separately from
generation jobs to 20 requests per signed-in user in a rolling day; longer
generation requests that exceed the check's input limit bypass this check.

## Verification

On 2026-09-22, 45 focused Flutter widget tests passed for selectable
clarification, including direct creation, stale responses, changed choices,
malformed provider output, permission errors, retries, and compact layouts.
Nine provider tests and three embedded-PostgreSQL integration tests passed for
option parsing, authorization, no draft mutation, and concurrent quota
enforcement. Full Serverpod and Flutter analysis, formatting checks,
`git diff --check`, and the release web build passed.

The existing guidance quota migration remained applied; selectable options
needed no new database migration. The local Serverpod service was restarted,
and its API and web endpoints both returned HTTP 200. In a separate browser tab,
**A club app** automatically produced three tailored questions, each with
three selectable choices. Selecting **Club members** and **Plan events** placed
both choices in the editable idea composer. The server log showed a successful
`builder.suggestQuestions` call and no `builder.begin` or `builder.generate`
call for that check. This live check did not create a draft or test generation
from the clarified prompt. Serverpod MCP tools were not available, so the
already-running local service was restarted through its existing launchd job.

Flutter regression tests cover the entry composer, starter ideas, duplicate
submission prevention, retained/recovered drafts, fresh-generation placeholders,
follow-up requests, failures and retries, disposal, platform recovery, preview
width controls, reminder approval and exact-candidate publication. Narrow-screen
checks include 390×844 with 150% text.

The updated home screen was visually inspected in the existing local web app at
desktop and mobile sizes. Builder layouts were also inspected using synthetic
widget-test data.

After explicit user approval on 2026-09-22, the browser created one local test
draft through the configured AI provider. The prompt requested **Pocket Library**:
books with author, reading status (To read, Reading, Finished), notes, a list and
progress summary, sage theme, and no reminders. The fresh request showed a queued
build placeholder, then produced Library, Book Details, Add/Edit Book and Progress
pages. A follow-up chat request renamed the app to **Pocket Library Test**; the
visible pages, fields and sage theme remained. Both prompts and completion
messages appeared in the conversation. Publishing was disabled during generation,
and the previous preview remained visible during the follow-up request.

The generated preview's book form accepted a synthetic record. Its list total
rose from 3 to 4, and the Progress page showed 2 To read, 1 Reading and 1 Finished
in both desktop and mobile preview modes. These records are isolated preview data.
The draft was left open and unpublished. This verifies live prompt-to-preview
generation and conversational editing, not publication or persisted record CRUD.
Provider attempt counts and exact definition equality were not inspected in
that earlier generation check.
