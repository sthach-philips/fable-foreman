# Routing Live Copilot Models

Resolve FRONTIER, WORKHORSE, and FAST against models visible in the user's current Copilot picker. Do not encode dated model IDs or infer entitlement from documentation.

## Lead Ceiling

The active chat model is the LEAD seat and a hard cost-tier ceiling for `runSubagent`. If FRONTIER judgment is required and the parent is not top-tier, use `vscode/askQuestions`: restore a top-tier lead, split out lower-judgment work, or stop. Never silently cap the requested model.

Re-probe after a picker change, fallback, quota event, organization policy change, or restart. Record the old and new LEAD class as a `decision` event. Frontier-to-frontier changes need no replanning; a real downgrade blocks the next FRONTIER decision.

## Discover Seats

1. Ask the user or inspect the current picker for exact available names and premium-request multipliers.
2. Group known actual models by provider family: Anthropic/Claude = `anthropic`, OpenAI/GPT = `openai`, Google/Gemini = `google`.
3. Classify by current provider positioning and observed capability, not by name similarity.
4. Select the cheapest model that clearly clears the task's judgment bar. Uncertainty moves one class up.
5. Pass the exact picker string in `runSubagent(model="Model Name (Vendor)")` and append a `routing` event.

| Class | Selection rule |
| --- | --- |
| FRONTIER | Top judgment model reachable under the LEAD ceiling |
| WORKHORSE | General coding model suitable for a complete, well-specified ticket |
| FAST | Lowest-multiplier model suitable for bounded scanning or mechanical work |

The built-in `Explore` agent may inherit the expensive LEAD. Use `foreman-scout` with an explicit FAST model for reconnaissance.

## Requested Is Not Actual

`runSubagent` accepts a requested model, but its one-message return might not expose the selected model. Keep separate fields:

- `model_requested`: exact dispatch argument.
- `model_actual`: runtime-provided identity, else `unknown`.
- `model_family`: derived only from a known actual identity, else `unknown`.

Do not trust a role that copies the request into `model_actual`. Unknown identity blocks claims about tier and family; it does not erase the value of fresh context.

## Adversarial Complement

When the builder family is known, choose a verifier from a different available family:

| Builder | Preferred verifier families |
| --- | --- |
| OpenAI | Anthropic, then Google |
| Anthropic | OpenAI, then Google |
| Google | Anthropic or OpenAI |

The verifier must still clear the task's quality bar and remain under the LEAD ceiling. If only one family is available, disclose `blind-verified (same family, independent context)`. If either actual family is unknown, disclose `blind-verified (model family unconfirmed, independent context)`. High-risk unknowns go to the user for an observable independent-review route.

## Effort

Copilot custom-agent frontmatter has no portable effort field. Convey depth in the ticket: `mechanical scan; stop after named paths`, `normal implementation`, or `reason deeply about concurrency`. Use a runtime effort control only when the current surface actually exposes one, and record what applied.

Raising effort on the same affordable seat is the first changed-input retry for a borderline task. Raising class follows only after a real second failure or when the quality bar demands it immediately.

## Premium Economics

Premium-request multipliers, not token quota folklore, drive cost routing. Picker prices and organization policies change, so record the observed multiplier or `unknown` in `budget_used`; never promise savings from stale pricing. Explicit user model preferences override economics but not verification or quality gates.
