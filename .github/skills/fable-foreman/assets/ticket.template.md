# Foreman Dispatch Ticket

Populate this object and send it inline with the `runSubagent` dispatch. Keep bulk context at the listed paths.

```json
{
  "task_id": "<UUID pointing to the task ledger event>",
  "role": "scout|worker|verifier",
  "objective": "<one gradeable sub-goal>",
  "context_paths": ["<absolute worktree path>"],
  "constraints": ["<stack, compatibility, or performance constraint>"],
  "must_do": ["<acceptance criterion>", "<exact verification command>"],
  "must_not": ["do not spawn subagents", "do not commit or write the ledger"],
  "write_set": ["<worker-only path or glob>"],
  "output_path": ".foreman/scratch/<task-id>-<role>-<attempt>.json",
  "builder_model_family": "anthropic|openai|google|unknown",
  "model_requested": "<exact model picker name>",
  "attempt": 1,
  "generation": 1,
  "max_attempts": 3,
  "resume_from": null
}
```

The seven ticket sections map as follows: TASK = `task_id` + `objective`; EXPECTED OUTCOME and MUST DO = `must_do`; CONTEXT = `context_paths`; CONSTRAINTS = `constraints`; MUST NOT = `must_not`; OUTPUT FORMAT = `output_path` plus the role contract; WRITE SET = `write_set`.

Rules:

1. The UUID dereferences the user's verbatim `original_task` in `.foreman/ledger.jsonl`; never copy that text into a ticket.
2. Omit `write_set` only for scout and verifier. Omit `builder_model_family` except for verifier.
3. `context_paths`, `write_set`, and `output_path` are rooted in the opened run worktree. Use absolute paths when the workspace has not yet reopened there.
4. Set `resume_from` to the prior partial artifact only on a changed-input redispatch.
5. One ticket has one objective and one owner. Shared manifests or lockfiles force serialization.
