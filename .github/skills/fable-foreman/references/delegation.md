# Delegation, Redispatch, and Ledger

Copilot subagents are synchronous, one-shot, and stateless. A dispatch returns one final message or an error. Continuity lives only in the workspace, `.foreman/scratch/`, and `.foreman/ledger.jsonl`.

## Authority and Setup

One run uses one opened workspace root in one of two modes:

- `worktree` (default, recommended): a linked worktree isolates the run. Writers are serialized unless WRITE SETs are provably disjoint.
- `in_place` (explicit opt-in, reduced isolation): the current named branch is the run root. Setup requires a clean tree. Every worker is serialized, and the user and coordinator must not edit while a worker is active.

The coordinator alone writes the ledger and git history; workers leave source edits uncommitted. In either mode, all tickets carry the selected `workspace_mode` and use paths rooted in the opened workspace.

The `.foreman` symlink points to `~/.foreman/{repo}/{feature}`. Each `~/.foreman/{repo}` is a separate git repository. `scripts/foreman-init.sh` creates or adopts the worktree; `--in-place` adopts the current branch without creating one. Both check basename collisions through `.repo-root`, create scratch and ledger files, link the store, and locally exclude the symlink.

An in-place resume may be dirty only when the expected `.foreman` symlink plus initialized ledger and scratch directory prove an existing run. Replay the ledger and reconcile that drift before dispatching. A new in-place run always requires a clean tree.

At resume, acquire a single-writer lease before reconciliation:

```bash
python3 .github/skills/fable-foreman/scripts/ledger.py acquire \
  --ledger .foreman/ledger.jsonl --owner <session-uuid>
```

An active different owner fails closed. A stale lease requires inspection and an explicit `--force-stale`; never steal it merely because a second coordinator wants to resume.

## Tickets

Use `../assets/ticket.template.md`. Every request has one objective, gradeable criteria, paths for bulk context, explicit MUST DO/MUST NOT boundaries, and a worker WRITE SET. The UUID `task_id` points to the only copy of the user's verbatim ask.

Scout returns compact findings inline. Worker and verifier write only their own `output_path`. Worker and verifier self-validate role artifacts; the coordinator validates artifacts and all return envelopes again on consume.

## Vocabularies

Scout and worker statuses are `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, and `BLOCKED`. Verifier verdicts are `PASS`, `FAIL`, and `PASS_WITH_NOTES`. Do not mix them.

The normalized `disposition` controls the next action:

| Disposition | Next action |
| --- | --- |
| `complete` | Check evidence; implementation proceeds to coordinator checks |
| `complete_with_concerns` | Resolve every required concern first |
| `needs_context` | Add context and redispatch the same seat with changed input |
| `needs_redispatch` | Reconcile partial work, then raise effort/seat or take over |
| `blocked` | External or user-owned decision; ask immediately |
| `failed` | Batch verifier findings into one fix wave |

Every nonterminal envelope includes `redispatch`: reason, needs, attempted work, partial-state facts, artifact pointer, and a recommendation. The coordinator decides; the role only advises.

## Parallel Work

Sequential is default. Before any parallel wave:

1. Require `workspace_mode == worktree`; in-place mode never runs parallel workers.
2. Compare exhaustive WRITE SETs, including generated files, manifests, and lockfiles.
3. Serialize any overlap. There are no per-subagent worktrees.
4. Append the baseline before dispatch.
5. Do not edit while workers run.

In in-place mode, record `HEAD` and `git status --porcelain` before every dispatch. After return, require the same `HEAD` and only the worker's expected WRITE SET changes. Any unrelated drift stops the run for user reconciliation; never auto-reset it.

## Returned Errors and Partial Edits

A failed `runSubagent` call replaces the old silent-worker timeout case. It still may have left edits:

1. Append an `attempt` event with `LOST`, the surfaced error, and known paths.
2. Diff against the baseline and inspect scratch artifacts.
3. Revert, complete by coordinator takeover, or name retained partial work in `resume_from`.
4. Never redispatch onto an unreconciled tree.

## Retry Precedence

Apply the first matching row. Every dispatch appends an attempt and consumes one of the current generation's three slots, even when a bad ticket does not count as a real seat failure.

| # | Condition | Action |
| --- | --- | --- |
| 1 | Ticket ambiguity or missing context | Correct the ticket; same seat |
| 2 | First real failure at this seat | Same seat with changed context, approach, or deeper effort |
| 3 | Second real failure at this seat | Raise one class or coordinator takeover |
| 4 | Top-seat/takeover failure or user-owned decision | Ask the user immediately |
| 5 | Two consecutive failed fix waves on one findings list | Ask the user immediately |
| 6 | Third unresolved attempt in this generation | Ask the user; no fourth dispatch |

Escalate earlier when more attempts cannot solve credentials, permissions, an external dependency, ambiguity, or a design/scope choice. Three is a ceiling, not a target.

## User Escalation

Call `vscode/askQuestions` with:

1. The original task and correlated issue/resolution history from the ledger.
2. At least four options, each with concrete pros and cons.
3. One recommended option marked recommended, with a reason.
4. Free-form input enabled.

Append an `escalation` event with trigger `early` or `cap`, attempts used, options, recommendation, and answer.

- Same objective after the decision: increment `generation`, reset attempt numbering, keep `task_id` and `original_task`.
- Changed objective: append a new `task` with a new UUID and `depends_on` the old task. Never mutate the original ask.

## JSONL Event Log

Each line validates against `../assets/schemas/ledger-line.schema.json` and carries a UUID `event_id` for idempotency:

| Type | Purpose |
| --- | --- |
| `baseline` | Commit, status, raw branch, active repository root, and optional `workspace_mode` (missing means legacy `worktree`) |
| `task` | UUID, verbatim ask, optional dependency, class, initial state, owned paths |
| `routing` | Requested/actual model, family, seat, effort, and why |
| `attempt` | Generation, attempt, disposition, evidence, issue/resolution, redispatch, cost |
| `escalation` | Interactive handoff and answer |
| `decision` | Seat, capability, degradation, or consent choice |
| `scratch` | Artifact path |

Append through the validated writer:

```bash
python3 .github/skills/fable-foreman/scripts/ledger.py append \
  --ledger .foreman/ledger.jsonl --owner <session-uuid> <event.json>
```

The writer holds an OS file lock, writes each JSON line in one append syscall, fsyncs, rejects malformed/truncated history, tolerates an identical duplicate `event_id`, and rejects a conflicting duplicate.

Views are projections, not mutable state:

```bash
python3 .github/skills/fable-foreman/scripts/ledger.py view \
  --ledger .foreman/ledger.jsonl --view tasks
```

Available views: `tasks`, `attempts`, `failures`, and `escalations`; add `--status` to filter. Replay JSONL, then trust the workspace and artifacts over stale projected state.

Commit the central store repository at task completion, escalation, and run end. Release the coordinator lease only after the final ledger append and checkpoint.

## Cleanup

In worktree mode, use `scripts/foreman-init.sh --teardown <branch>` after merge/PR, cancel, failed bootstrap, or abandonment. It refuses dirty removal and retains the central audit store. Resolve dirty state or locks, retry once, then inspect `git worktree list`; never force-delete unreviewed work. Stale branches are removed only by explicit user choice.

In in-place mode, use `scripts/foreman-init.sh --in-place --teardown`. It validates and removes only the `.foreman` symlink and retains the store, branch, and working tree.
