# Fable Foreman

**Your strongest model shouldn't be swinging the hammer.**

Built in public by [DontSleepOnAI](https://dontsleeponai.com) — the story behind this skill (including the five-round adversarial review where OpenAI's newest model tore apart the first draft) lives there.

Fable Foreman turns the strongest available model in your coding environment into a team lead. It plans, routes each task to the cheapest worker that clears the quality bar, and refuses to accept meaningful changes until independent evidence supports them.

The repository ships native implementations for GitHub Copilot in VS Code and for Claude. They share the same orchestration discipline, but use different agent formats, model-routing mechanisms, state stores, and verification backstops.

Claude v0.3.0 adds visible Codex workers, evidence-graded seat identity, deterministic helper scripts, and an executable setup runbook. See [What's new in Claude v0.3.0](docs/claude.md#whats-new-in-v030) and the [changelog](CHANGELOG.md).

**"Fable" is where it started, not what it needs.** The foreman seat is a capability class, not a provider or dated model ID.

## Why

Anthropic's own engineering shows both sides of the ledger. Their [multi-agent research system writeup](https://www.anthropic.com/engineering/multi-agent-research-system) found an orchestrator-plus-cheaper-subagents design strongly outperformed single agents — an Opus lead with Sonnet workers, exactly this skill's shape — while consuming roughly **15x** the tokens of a single chat, which is why they conclude multi-agent work only pays for high-value tasks. Anthropic's own [cost guidance](https://code.claude.com/docs/en/costs) likewise recommends cheaper-tier teammates under a stronger lead as the default for multi-agent work. And the community has receipts for what happens without discipline — runaway-subagent cost stories are a genre of their own on every AI-coding forum, which is exactly why this skill bounds crew sizes, retries, and spend announcements the way it does.

The difference between those two outcomes is not orchestration machinery — it's **routing judgment and verification discipline**. That's what this skill installs.

## Choose a Runtime

| Runtime | Coordinator | Implementation | Guide |
| --- | --- | --- | --- |
| GitHub Copilot | Open VS Code chat | `.github/` | [Install and runtime details](docs/github-copilot.md) |
| Claude | Frontier-class Claude session | `skills/` + `agents/` | [Install and runtime details](docs/claude.md) |

Use the guide for your runtime. The install trees are intentionally different and should not be mixed.

## What it does

1. **Probes the job site** — establishes the lead seat, available worker capabilities, execution environment, and runtime-specific verification options.
2. **Routes by capability class** — FRONTIER for judgment, WORKHORSE for well-specified implementation, and FAST for scanning or mechanical work.
3. **Delegates with bounded tickets** — gradeable outcomes, explicit constraints, file paths instead of pasted bulk context, and mandatory write sets for implementation.
4. **Records durable outcomes** — statuses, attempts, blockers, artifacts, and routing decisions survive context loss or restart.
5. **Verifies like it trusts no one** — deterministic project checks first, then a blind fresh-context verifier given the original task rather than the builder's narrative.
6. **Keeps economics subordinate to quality** — sequential by default, announced fan-outs, bounded retries, and no silent downgrade below the task's quality bar.

## Install

- [GitHub Copilot in VS Code](docs/github-copilot.md): workspace and personal installation, worktree bootstrap, hooks, schemas, and verified capabilities.
- [Claude](docs/claude.md): Claude Code, plugin, Claude Desktop, Codex integration, and quota behavior.

Start with the runtime guide, then invoke Fable Foreman for work whose multiple files or stages justify orchestration.

## License

MIT © Jordan Olsen
