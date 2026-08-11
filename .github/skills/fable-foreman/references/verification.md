# Blind Verification

Verification spends rigor after cheap evidence. Worker reports are claims; the coordinator and verifier reproduce facts.

## When Required

Every accepted implementation change requires a blind verifier except a single-file change with no logic content, such as formatting, comments, or prose. Delegate-only mode still requires a verifier, but an unrun deterministic gate remains `UNVERIFIED` and blocks acceptance. Discipline modes use a separate pass labeled `self-reviewed, not blind-verified`.

## Layer 1: Coordinator Checks

After the worker returns:

1. Validate its envelope and artifact.
2. Review the actual diff and WRITE SET.
3. Run the project's real build/test command, not a weaker proxy.
4. Resolve all concerns.

A deterministic failure skips model review and goes directly to one batched fix ticket.

## Commit Before Verify

The coordinator is the sole committer. Commit the candidate so the verifier sees the change in a clean tree. Record `HEAD` and `git status --porcelain` before dispatch.

Never stash the candidate: that removes the work being verified. The `.foreman` symlink is locally excluded and points outside product history, so verifier artifacts do not dirty the candidate tree.

## Layer 2: Fresh Verifier

Dispatch `foreman-verifier` with:

1. `task_id`, which dereferences the user's verbatim original ask.
2. Changed-file paths and acceptance criteria.
3. Exact real verification commands.
4. `builder_model_family` from known actual metadata, or `unknown`.
5. No builder reasoning, summary, or conclusions.

The verifier reruns checks, grades each criterion, checks the user-visible goal, writes a schema-valid artifact, and returns `PASS`, `FAIL`, or `PASS_WITH_NOTES`. Unexamined areas go in `not_checked` and are not passed.

`PASS_WITH_NOTES` is legal only when every required criterion passed. A note hiding a required failure is `FAIL`.

## Isolation and Hook

The verifier agent has enumerated read/search/check tools and no edit tool. Its agent-scoped `PreToolUse` hook calls `.github/hooks/verifier-readonly.sh` to deny common edit and mutating shell operations.

Hooks are preview, organization-policy controlled, and agent-scoped hooks require `chat.useCustomAgentHooks`. The hook is defense in depth, not a sandbox: an interpreter, build script, ignored path, or external process can still mutate state. If Step 0 cannot prove the hook active, record the fallback and continue only with the read-only toolset plus mutation detection.

After return, require:

```text
git rev-parse HEAD == recorded verifier-start HEAD
git status --porcelain == empty
```

Any tracked-content or ref mutation voids the verdict and becomes a finding. Inspect relevant ignored/generated outputs separately when the task can affect them.

## Cross-Family Rule

Prefer a verifier whose known actual family differs from the builder's known actual family. The requested model is not proof of selection.

Assurance labels:

1. Known different families: `blind-verified (cross-family)`.
2. Known same family, fresh context: `blind-verified (same family, independent context)`.
3. Unknown actual family: `blind-verified (model family unconfirmed, independent context)`.
4. No subagent: `self-reviewed, not blind-verified`.

For security, concurrency, destructive operations, or pivotal architecture, unknown family metadata is a blocker to claiming independent model review; ask the user for an observable route.

## Disagreement and Flakes

- A reproduced deterministic failure outranks any verdict.
- Rerun a suspected flaky test at most three times to characterize it. Inconsistent results remain a failure and the flake is a finding.
- If deterministic evidence and verdict remain unresolved, block the change and present both artifacts.
- Batch all verifier findings into one fix ticket. Two consecutive failed fix waves trigger immediate user escalation.

On PASS, append the verifier attempt, retain the candidate commit, and checkpoint the central foreman store. On FAIL or mutation, append evidence before reverting or opening the fix wave.
