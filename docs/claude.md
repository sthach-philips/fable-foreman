# Claude

[Back to the project overview](../README.md)

The Claude implementation turns a frontier-class Claude session into the
coordinator. It routes work to Claude subagents and, when available and
explicitly approved, OpenAI Codex CLI workers.

## Components

| Component | Path |
| --- | --- |
| Coordinator skill | [`skills/fable-foreman/`](../skills/fable-foreman/SKILL.md) |
| Scout | [`agents/foreman-scout.md`](../agents/foreman-scout.md) |
| Worker | [`agents/foreman-worker.md`](../agents/foreman-worker.md) |
| Verifier | [`agents/foreman-verifier.md`](../agents/foreman-verifier.md) |
| Codex wrapper | [`agents/foreman-codex-wrapper.md`](../agents/foreman-codex-wrapper.md) |

The skill dispatches all four agents by name. Installing the skill without the
agents disables delegation and blind verification.

## What's New in v0.3.0

v0.3.0 came out of a head-to-head study against
[claudemix](https://github.com/hughminhphan/claudemix), three rounds of
adversarial review by OpenAI's frontier Codex model, and live testing.

1. **Codex workers are visible.** Codex jobs now ride inside a visible wrapper
  subagent. The foreman can keep working, and completion arrives as a
  notification instead of a polling loop. Direct calls remain available for
  sub-minute tasks where wrapper overhead is not worthwhile.
2. **Seat identity follows evidence.** Runtimes can silently substitute models,
  and self-reported identity tracks the prompt rather than the weights. The
  ledger grades identity as `served`, `routed`, or `requested`; when no
  deterministic evidence exists, it records `seat: unverified`.
3. **Deterministic work moved into scripts.** The environment probe, ledger
  bootstrap, and Codex launcher are small POSIX shell scripts. The launcher
  validates arguments and tracks the worker PID. The probe redacts gateway
  URLs before ledger output. Raw launcher JSONL and stderr remain local under
  `.foreman/scratch/` and are not redacted.
4. **The setup runbook is executable.**
  [`setup-runbook.md`](../skills/fable-foreman/references/setup-runbook.md)
  verifies the environment with evidence. Its optional local-splitter recipe
  is consent-gated and documents supply-chain and terms-of-service caveats.

See the full [changelog](../CHANGELOG.md).

## Claude Code Install

Paste this into a Claude Code session:

```text
Install this skill globally on my machine: https://github.com/olsenbrands/fable-foreman
```

Claude clones the repository and installs both required surfaces:

| From the repository | Destination |
| --- | --- |
| `skills/fable-foreman/` (skill, references, and scripts) | `~/.claude/skills/fable-foreman/` |
| `agents/*.md` | `~/.claude/agents/` |

Manual installation:

```bash
cp -R skills/fable-foreman ~/.claude/skills/
cp agents/*.md ~/.claude/agents/
```

Add this line to `CLAUDE.md` when reliable automatic triggering matters:

```text
For any multi-file or multi-stage task, use the fable-foreman skill.
```

The [fables project](https://github.com/czlonkowski/fables) measured
description-only triggering at roughly 50-60% recall.

## Plugin Install

Run these commands one at a time:

```text
/plugin marketplace add olsenbrands/fable-foreman
/plugin install fable-foreman@fable-foreman
```

The first registers the marketplace. The second prompts for an install scope;
choose User.

On Windows, plugin installation currently fails with
`EPERM: operation not permitted, rename` while finalizing the marketplace
cache. This is Claude Code issue
[anthropics/claude-code#52435](https://github.com/anthropics/claude-code/issues/52435),
closed as not planned. Use the paste-in or manual method instead.

## Claude Desktop and claude.ai

Package the skill folder and upload it under Settings -> Customize -> Skills:

```bash
cd skills && zip -r fable-foreman-skill.zip fable-foreman/
```

The ZIP contains the skill but not `agents/`. That is correct for Claude
Desktop, which has no subagent tool, but it is not a complete Claude Code
install. Without subagents, Foreman runs in discipline mode: separate plan,
execute, and self-review passes with honest `self-reviewed, not blind-verified`
labels.

## Claude-Specific Behavior

- WORKHORSE resolves to the `sonnet` alias and FAST to `haiku`. FRONTIER is the
  lead or a frontier-class subagent.
- An optional Codex CLI seat is probed at runtime. Longer jobs use the visible
  `foreman-codex-wrapper`; short jobs may use the direct launcher.
- Codex spends a separate OpenAI account, so Foreman identifies the billing
  mode and obtains consent before the first billable dispatch.
- Seat identity is recorded by evidence tier. A requested route is never
  presented as proof of the model that served the work.
- Cross-family verification pairs Claude and Codex when both are available.
- The Step 0 cache is invalidated when the Claude session model changes because
  of fallback, quota, policy, or an explicit model switch.

## Requirements and Quotas

- Full orchestration requires Claude Code with the Agent tool.
- Claude Desktop and claude.ai run the reduced-assurance discipline mode.
- Codex CLI is optional. If absent, work stays on Claude seats.

Subscription subagents share the Claude plan's quota. Delegation buys
quality-per-token, and cheaper tiers generally consume shared quota more
slowly; it does not create a discount. API users receive direct model-price
savings. Under quota pressure, Foreman reroutes only when a cheaper seat still
clears the task's quality bar.
