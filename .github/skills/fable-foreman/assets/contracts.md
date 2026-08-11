# Foreman A2A Contracts

This file defines the request and return semantics. The JSON schemas in `./schemas/` are authoritative for serialized payloads.

## Configuration

```json
{
  "retry": {
    "max_attempts": 3,
    "on_exhaustion": "ask_user",
    "allow_early_escalation": true
  }
}
```

Attempts are counted within a generation. Three is a ceiling, not a quota.

## Request Envelope

The coordinator sends one self-contained JSON ticket to a one-shot subagent:

| Field | Contract |
| --- | --- |
| `task_id` | UUID of the `task` ledger event containing the single verbatim `original_task` |
| `role` | `scout`, `worker`, or `verifier` |
| `workspace_mode` | Baseline mode: `worktree` or `in_place` |
| `objective` | This dispatch's gradeable sub-goal |
| `context_paths` | Files or directories to read; bulk context stays on disk |
| `constraints` | Compatibility, stack, policy, and performance boundaries |
| `must_do` | Acceptance criteria and exact verification commands |
| `must_not` | Scope fences, no subagents, no commit, no ledger write |
| `write_set` | Worker-only exhaustive edit allowlist |
| `output_path` | Worker/verifier JSON artifact under `.foreman/scratch/` |
| `builder_model_family` | Verifier-only family to complement; `unknown` forbids a cross-family claim |
| `model_requested` | Exact picker name passed to `runSubagent(model=...)` |
| `generation` | Retry generation, starting at 1 |
| `attempt` | 1-based attempt within the generation, maximum 3 |
| `max_attempts` | Always 3 |
| `resume_from` | Optional prior partial artifact path |

The role reads `.foreman/ledger.jsonl` to dereference `task_id`, `workspace_mode`, and prior attempts. It never receives a growing pasted history. In-place tickets are always serialized and carry the reduced-isolation constraints from `references/delegation.md`.

## Return Envelope

Every role returns one JSON object validated by `./schemas/return-envelope.schema.json` when the coordinator consumes it.

Common fields:

| Field | Contract |
| --- | --- |
| `task_id`, `role`, `kind` | Correlation and role discriminator |
| `disposition` | Machine routing value |
| `status` XOR `verdict` | Scout/worker status or verifier verdict |
| `model_requested` | Ticket value, never treated as evidence of selection |
| `model_actual` | Runtime-provided exact model, or literal `unknown` |
| `model_family` | `anthropic`, `openai`, `google`, or `unknown`; derive only from `model_actual` |
| `artifact_path` | Required for worker/verifier; forbidden for scout |
| `summary_line` | One factual sentence |
| `concerns` | Explicit unresolved risks |
| `budget_used` | Premium requests if exposed, otherwise null plus a note |
| `redispatch` | Required only when the disposition is nonterminal |

Scout findings are inline and match `./schemas/scout.artifact.schema.json`. Worker and verifier bulk payloads live at `artifact_path` and match their role schema.

## Dispositions

| Disposition | Role vocabulary | Coordinator action |
| --- | --- | --- |
| `complete` | `DONE` or `PASS` | Check artifact/evidence, then advance |
| `complete_with_concerns` | `DONE_WITH_CONCERNS` or `PASS_WITH_NOTES` | Resolve every required concern before advancing |
| `needs_context` | `NEEDS_CONTEXT` | Add missing context and redispatch the same seat; ticket failures do not count as real failures |
| `needs_redispatch` | `BLOCKED` capability gap | Reconcile partial work and apply the precedence table |
| `blocked` | `BLOCKED` external or decisional blocker | Escalate to the user immediately |
| `failed` | verifier `FAIL` | Open one batched fix wave, then verify again |

## Redispatch Block

`redispatch` contains:

```json
{
  "reason": "Why this one-shot dispatch stopped",
  "needs": "The missing capability, decision, or context",
  "attempted": ["What was tried"],
  "partial": false,
  "partial_artifact_path": null,
  "recommended": {
    "seat_change": "none|up|takeover",
    "effort": "normal|deep",
    "approach_hint": "What must differ next time"
  }
}
```

Never retry unchanged input. `resume_from` points to `partial_artifact_path` when partial work is intentionally retained.

## Model Identity

The `runSubagent` request accepts a model name but its return channel might not expose the model actually selected. A role must then return:

```json
{"model_actual":"unknown","model_family":"unknown"}
```

The coordinator fails closed: it may use a fresh-context verifier, but it cannot claim cross-family verification. For high-risk work, ask the user to confirm an observable model or provide an independent review route.

## Assurance

Worker self-check:

```bash
python3 .github/skills/fable-foreman/scripts/validate.py \
  .github/skills/fable-foreman/assets/schemas/worker.artifact.schema.json \
  .foreman/scratch/<artifact>.json
```

Verifier uses the corresponding verifier schema. The coordinator repeats artifact validation and validates the returned envelope on consume. Schema validation says the payload is well formed; deterministic checks establish behavior.

## Examples

Scout return:

```json
{"task_id":"34ef82ae-f2ad-4b78-b23b-c93c6df21587","role":"scout","kind":"scout","disposition":"complete","status":"DONE","model_requested":"economy picker model","model_actual":"unknown","model_family":"unknown","summary_line":"Located the parser and its tests.","concerns":[],"budget_used":{"premium_requests":null,"notes":"not exposed"},"findings":[{"path":"src/parser.ts","line":41,"fact":"Owns token dispatch."}],"not_checked":["generated fixtures"]}
```

Worker return:

```json
{"task_id":"34ef82ae-f2ad-4b78-b23b-c93c6df21587","role":"worker","kind":"worker","disposition":"complete","status":"DONE","model_requested":"general coding picker model","model_actual":"unknown","model_family":"unknown","artifact_path":".foreman/scratch/34ef82ae-worker-1.json","summary_line":"Implemented the ticket and ran the required test.","concerns":[],"budget_used":{"premium_requests":null,"notes":"not exposed"}}
```

Verifier failure:

```json
{"task_id":"34ef82ae-f2ad-4b78-b23b-c93c6df21587","role":"verifier","kind":"verifier","disposition":"failed","verdict":"FAIL","model_requested":"independent picker model","model_actual":"unknown","model_family":"unknown","artifact_path":".foreman/scratch/34ef82ae-verify-1.json","summary_line":"The required regression test fails.","concerns":["Acceptance criterion 2 failed"],"budget_used":{"premium_requests":null,"notes":"not exposed"},"redispatch":{"reason":"Regression test failed","needs":"A fix wave against the recorded failure","attempted":["pnpm test parser"],"partial":false,"partial_artifact_path":null,"recommended":{"seat_change":"none","effort":"normal","approach_hint":"Fix the null-token branch"}}}
```
