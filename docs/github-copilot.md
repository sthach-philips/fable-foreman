# GitHub Copilot

[Back to the project overview](../README.md)

The GitHub Copilot implementation is native to VS Code. The open chat is the
coordinator, and each scout, worker, or verifier runs as a one-shot custom
subagent. The coordinator selects a model per dispatch through `runSubagent`.

## Components

| Component | Path |
| --- | --- |
| Coordinator skill | [`.github/skills/fable-foreman/`](../.github/skills/fable-foreman/SKILL.md) |
| Scout | [`.github/agents/foreman-scout.agent.md`](../.github/agents/foreman-scout.agent.md) |
| Worker | [`.github/agents/foreman-worker.agent.md`](../.github/agents/foreman-worker.agent.md) |
| Verifier | [`.github/agents/foreman-verifier.agent.md`](../.github/agents/foreman-verifier.agent.md) |
| Verifier mutation backstop | [`.github/hooks/verifier-readonly.sh`](../.github/hooks/verifier-readonly.sh) |

## Requirements

- VS Code with GitHub Copilot custom agents, skills, and `runSubagent` support.
- Linux or WSL. Windows-native and macOS are outside v1.
- Git worktrees.
- Python 3 with `jsonschema`:

```bash
python3 -m pip install jsonschema
```

- For the preview verifier hook, enable `chat.useCustomAgentHooks`.
  Organization policy can disable hooks.

The coordinator needs tools equivalent to `read`, `edit`, `search`, `execute`,
`agent/runSubagent`, and `vscode/askQuestions`. A skill inherits the active
coordinator's tools; `SKILL.md` cannot grant them.

## Workspace Install

The repository already contains the complete workspace-scoped install. Open it
in VS Code and invoke `/fable-foreman`, or ask Copilot to orchestrate a
multi-file task with Fable Foreman.

## Personal Install

Copy the skill and agents to the user locations:

```bash
cp -R .github/skills/fable-foreman ~/.copilot/skills/
cp .github/agents/*.agent.md <active-vscode-profile-prompts-folder>/
```

VS Code profile paths vary between local, remote, and named profiles. The Agent
Customizations editor shows the active prompts folder. Put `*.agent.md`
directly in that folder.

The bundled verifier agent's hook command is workspace-relative:
`.github/hooks/verifier-readonly.sh`. For a personal install, either add that
hook to each participating workspace or remove the inline `hooks:` block and
use the read-only-toolset fallback. Do not claim hook-backed verification
unless a fresh-session probe proves it fired.

## Run Flow

1. Start with a top-tier lead model when the task needs FRONTIER judgment. A
   subagent cannot exceed the parent model's cost tier.
2. Create a linked worktree through Source Control -> Worktrees -> Create
   Worktree, or run:

   ```bash
   .github/skills/fable-foreman/scripts/foreman-init.sh feature/my-change
   ```

3. Open the printed `../{repo}.worktrees/{feature}` path as the workspace and
   restart the chat there. The script creates a git-excluded `.foreman` symlink
   to `~/.foreman/{repo}/{feature}`.
4. Resume `/fable-foreman`. The coordinator replays `ledger.jsonl`, reconciles
   the tree, acquires the single-writer lease, and dispatches one-shot agents.
5. After merge, PR, cancellation, failed bootstrap, or abandonment, inspect
   status and remove the worktree:

   ```bash
   .github/skills/fable-foreman/scripts/foreman-init.sh --teardown feature/my-change
   ```

The central `~/.foreman/{repo}` repository remains as the orchestration audit
history.

## Copilot-Specific Behavior

- FRONTIER, WORKHORSE, and FAST resolve to models currently visible in the
  user's picker. The exact picker name is passed on each dispatch.
- The runtime does not expose the actually selected model in the subagent
  return contract. Foreman records `model_actual: unknown` and
  `model_family: unknown` rather than claiming cross-family verification.
- Worker and verifier artifacts are JSON validated against the schemas in
  [assets/schemas](../.github/skills/fable-foreman/assets/schemas/).
- Durable orchestration state is an append-only JSONL event log in the central
  store. Product commits remain in the linked code worktree.
- Premium-request multipliers, not Claude quota behavior, drive model-routing
  economics.

## Verified Capabilities

Tested with VS Code 1.132 on Linux/WSL on 2026-08-11:

| Capability | Result |
| --- | --- |
| Custom agents | Scout loaded successfully as a custom subagent |
| Questions | `vscode/askQuestions` is available |
| Tool identifiers | Coarse aliases and namespaced identifiers are supported |
| Absolute paths | Read/edit/execute work; search and language services remain bound to the opened workspace |
| Native worktrees | `git.createWorktree` and `git.openWorktreeInNewWindow` are present |
| JSON Schema | Python 3.12.13 with `jsonschema` 4.26.0 is available |
| Bootstrap | Create, resume, symlink/exclude, clean status, and teardown passed in a separate disposable repository |

Workspace hooks are supported, but agent-scoped hooks are preview and require
`chat.useCustomAgentHooks`. A marker was not intercepted in the already-running
test session, so Step 0 requires a fresh-session proof. The fallback is the
verifier's read-only toolset plus post-verification `HEAD` and status checks.

The hook raises the cost of accidental mutation but is not a sandbox. An
interpreter or external process can bypass a command blocklist.
