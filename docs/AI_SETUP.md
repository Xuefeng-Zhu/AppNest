# AI provider setup

[Documentation index](README.md) · [Creation flow](CREATION_FLOW.md) ·
[Architecture](../ARCHITECTURE.md)

This guide describes the current source contract, including local working-tree
changes. It does not confirm the configured live provider, provider availability,
or a deployed build. Historical provider results are linked below.

## Configure the server

Without a configured provider, AppNest shows **Template mode — AI provider not
configured**. Templates, manual editing, publication and existing apps remain
available. `FakeAiProvider` is a test helper; it is not a runtime fallback.

Add these entries under the active environment in the ignored
`appnest_server/config/passwords.yaml`, preserving its existing database and
authentication secrets:

```yaml
development:
  # Keep existing database/authentication entries here.
  AI_BASE_URL: https://YOUR_OPERATOR_APPROVED_PROVIDER/v1
  AI_MODEL: YOUR_ACTUAL_PROVIDER_MODEL_ID
  AI_API_KEY: YOUR_SERVER_ONLY_KEY
```

Use the environment the server actually runs in. All three nonblank values are
required. The adapter accepts an HTTP(S) base URL and appends `/chat/completions`;
provide the API base rather than the completed request path. Use HTTPS for a
remote service. `.env` files alone are not read by this adapter, and these names
are Serverpod password entries rather than Flutter build settings.

Keep `passwords.yaml` ignored and owner-readable only (`chmod 600`). Never put
keys in definitions, Flutter assets, screenshots or committed configuration.
Restart the existing server through the project's Serverpod workflow so it
loads changed passwords. See the [example password file](../appnest_server/config/passwords.example.yaml)
and [local startup instructions](../README.md#start-developing).

## Provider request contract

| Operation | Normal request | Context sent |
| --- | --- | --- |
| Fresh creation | `response_format.type: json_schema` for a complete AppSpec or explicit unsupported response | User request, public schema/authoring contract, fixed public examples and any bounded repair context |
| Definition edit | `response_format.type: json_schema` for typed semantic patches or explicit unsupported response | User request, current declarative definition and any bounded repair context |
| Optional **Help shape my idea** | `response_format.type: json_object` | Idea and, for follow-up help, the authorized draft definition |

Fresh creation sends neither the internal placeholder definition nor starter
templates. Selecting a template explicitly establishes edit context. A
successful generated candidate also establishes edit context for follow-up
requests, including after later failures or manual edits. None of these
operations sends stored mini-app records or device readings to the provider.

The normal adapter requires the configured provider to support its requested
response formats. The scoped development route below is the explicit exception.
Provider enforcement is supplementary: AppNest always validates the returned
JSON and semantic references locally. One outer JSON fence is tolerated; prose
and arbitrary embedded-object extraction are rejected.

Fresh creations may add supported `requires` declarations derived by the strict
parser from the already-authored graph. This creation-only compiler changes no
feature, field, action, policy, automation rule or grant. It parses the completed
definition strictly again and records raw-output, input-definition and candidate
hashes plus added declarations in private job metadata. Manual definitions and
edits retain their strict parsing path. Preview remains separate from explicit
publication and reminder approval.

## Scoped OpenRouter development route

The adapter recognizes this exact host/model pair:

```yaml
development:
  # Keep existing database/authentication entries here.
  AI_BASE_URL: https://openrouter.ai/api/v1
  AI_MODEL: nvidia/nemotron-3-ultra-550b-a55b:free
  AI_API_KEY: YOUR_SERVER_ONLY_OPENROUTER_KEY
```

For this pair, the adapter removes `response_format`, supplies generation's
complete schema through system instructions with shared local references, and
requests medium reasoning. Both generation and guidance disable provider
fallbacks and send zero prompt/completion token price limits. This is an
intentional compatibility adaptation, not evidence that the provider enforces
the schema. Local validation remains authoritative.

The generation deadline is 90 seconds for this pair and 45 seconds otherwise.
Changing the model or host leaves the normal response-format path and deadline
in effect. Use synthetic requests for development and review the provider's
current data-handling terms before sending other material. The
[model listing](https://openrouter.ai/nvidia/nemotron-3-ultra-550b-a55b:free)
is an external reference; this guide does not establish current availability,
free quota, pricing or successful live generation.

## Limits and worker behavior

| Limit | Current source behavior |
| --- | --- |
| Active generation jobs | One per signed-in actor |
| Generation jobs | 30 per actor per rolling 24 hours |
| Generation attempts | At most three per job |
| Generation input | At most 16 KiB UTF-8 at the server; the composer also limits characters |
| Worker pool | Eight Future Call slots per process, shared by generation, reminders and reconciliation |
| Generation provider duration | 45 seconds normally; 90 seconds for the scoped route above |
| Generation lease | 120 seconds, with expiration and stale-result fencing |
| Output token allowance | 8,000 normally; a fresh-creation retry after a recognized truncation diagnostic gets a fixed 12,000 allowance |
| Definition output | 128 KiB; provider response envelope is bounded separately to three times that size |
| Guidance requests | 20 per actor per rolling 24 hours, reserved before the provider call |
| Guidance input and duration | 2,000 characters and 4,000 UTF-8 bytes; approximately 20 seconds total |

Jobs are persisted before scheduling. Reconciliation repairs missed generation
wakeups; leases, draft mutation/hash and base-version checks fence duplicate or
obsolete results. No provider request runs while an app transaction is held.
Generation retries honor bounded `Retry-After` hints, capped at 120 seconds, and
classify terminal provider failures. Bounded semantic repair context can survive
an intervening transient provider failure within the same scoped job.

Different actors can generate concurrently. Excess work waits for a shared
worker slot; the pool does not impose a distributed provider request/token
limit or guarantee reminder latency. The [architecture review](ARCHITECTURE_REVIEW.md)
records scheduler isolation and automation retry defects that remain open.

## Inspect failures and verify configuration

Use the builder's **Build details** for the recorded job status, attempt count
and bounded validation diagnostic. A failed create never exposes its internal
placeholder as a successful generated app. A failed edit retains its previous
preview; publication still requires a validated candidate or explicitly keeping
the prior edit preview.

Read server/Flutter logs through the connected Serverpod MCP tools. Provider
telemetry records failure category, timing, byte/token counts and safe correlation
metadata, rather than prompt/response bodies or credentials. Rejected response
text is private database repair context, never routine log content or part of
the builder snapshot. Do not publish raw development logs.

Configuration checks and provider unit tests establish adapter behavior, not
current provider availability or generation quality. To verify a live setup,
use an authorized synthetic request, inspect its durable job/provider metadata,
and distinguish preview success from publication and authenticated record writes.
Never infer a current success rate from the historical examples below.

## Historical evidence

| Record | What it establishes for that dated build |
| --- | --- |
| [AI creation check — 2026-09-22](AI_CREATION_CHECK.md) | Nebius-backed browser creation, refinement, publication and synthetic live CRUD for Plant Corner and Trip Kit |
| [Creation flow — historical verification](CREATION_FLOW.md#historical-verification--2026-09-22) | Earlier automatic clarification and Pocket Library prompt-to-preview behavior |
| [Planner failure investigation — 2026-09-23](GENERATION_FAILURE_CHECK.md) | Bounded provider repair and isolated preview checks; no connected browser recovery claim |
| [Customization evaluation — 2026-09-23](CUSTOMIZATION_AI_CHECK.md) | Targeted creation/edit outcomes with explicit AI-generated versus template baselines |

The Nebius model and endpoint in those records were tested on those dates.
They are evidence, not a promise of current routing. An operator configuring
another environment should verify its approved model and endpoint independently.

## Source map

- [Provider adapter and request builders](../appnest_server/lib/src/modules/builder/provider.dart)
- [Builder authorization, quotas and publication](../appnest_server/lib/src/modules/builder/builder.dart)
- [Durable generation leases and retries](../appnest_server/lib/src/modules/automation/worker.dart)
- [Fresh-creation capability compiler](../appnest_server/lib/src/modules/builder/creation_compiler.dart)
- [Shared definition limits](../packages/appnest_spec/lib/appnest_spec.dart)
