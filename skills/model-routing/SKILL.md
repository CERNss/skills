---
name: model-routing
description: >-
  Cost-aware, tier-based model routing: the premium top tier (currently
  Fable 5, Mythos-class) acts only as director — plan, decompose, delegate,
  review, synthesize — while the flagship tier (currently Opus 5) does all
  hands-on execution (coding, refactoring, debugging, tests, long analysis,
  research); mechanical gruntwork may drop to cheaper tiers (Sonnet/Haiku).
  Generation- and harness-agnostic: route by tier, not by model name. Works
  in both directions: a premium-tier session delegates execution DOWN; a
  flagship session executes directly and only escalates rare strategic
  decisions UP. Apply at the start of ANY substantive or multi-step task,
  whenever choosing a subagent model, and when the user mentions cost /
  省钱 / 太贵 / 成本 / 模型调度 / 用 opus 跑 / 别用 fable 写代码 /
  delegate to opus.
---

# Model Routing: top tier directs, flagship executes

**This file is the single source of truth for model routing.** If auto-memory,
CLAUDE.md notes, or prior-session habits conflict with it, this file wins.
Memory entries about routing are pointers here, never rules.

## Universal principle (harness- and generation-agnostic)

Models come in cost tiers. At any point in time there is:

- a **premium tier** — most capable, disproportionately expensive
- a **flagship tier** — the standard high-end working model
- **cheap tiers** — fast models for mechanical work

The rule: **the premium tier only does judgment work** — understand,
decompose, decide, delegate, review, synthesize. **All hands-on execution
runs on the flagship tier.** Mechanical gruntwork may drop to cheap tiers.

Route by TIER, not by model name. When a new generation ships, apply the
same rule to whatever occupies each tier — do not wait for this file to be
updated. The premium tier's price only pays off on judgment; flagship
execution is not a quality compromise, so never treat delegation as
"settling for worse".

## Current tier mapping (as of 2026-08 — re-verify if long past)

| Tier | Current model | Model ID | Claude Code alias |
|---|---|---|---|
| Premium (director) | Fable 5 (Mythos-class, above Opus) | `claude-fable-5` | `"fable"` |
| Flagship (executor) | Opus 5 | `claude-opus-5` | `"opus"` |
| Cheap (mechanical) | Sonnet 5 / Haiku 4.5 | `claude-sonnet-5` / `claude-haiku-4-5-20251001` | `"sonnet"` / `"haiku"` |

Claude Code aliases resolve to the newest model of that tier, so prefer
aliases over pinned IDs — they keep this policy generation-proof.
Background on Fable/Mythos: https://www.anthropic.com/news/claude-fable-5-mythos-5

## Step 0 — Identify the session tier

- Claude Code: the system prompt's Environment section states "You are
  powered by the model named ...".
- Other harnesses: use whatever model identity the harness reports.
- Premium tier → **Mode A (director)**. Flagship or below, or unknown →
  **Mode B (executor)**.

## Task classification

**Director work** — stays in the main loop regardless of mode: understanding
the request, decomposition, architecture/approach decisions, writing
delegation contracts, reviewing subagent output against acceptance criteria,
final synthesis to the user.

**Execution work** — routes to the flagship tier: writing or modifying code,
refactors, debugging legwork, running and fixing tests, long document/code
reading and analysis, routine research, docs writing.

**Mechanical work** — routes cheaper: broad code searches and file inventory
→ Explore-style read-only agents; bulk mechanical edits → cheap tier. Never
route real coding below the flagship tier.

**Threshold**: work is execution-shaped once it needs more than ~3 tool calls
or produces more than ~30 lines of new/changed content. Below that, do it
inline in any mode — subagent overhead costs more than it saves.

## Mode A — premium-tier session (director)

- Do NOT execute inline above the trivial threshold. Inline coding on the
  premium tier is the exact failure mode this skill exists to stop.
- Delegate every execution-shaped task to a flagship-tier subagent (in
  Claude Code: Agent tool with model:"opus").
- The delegation prompt is a complete contract — subagents see none of the
  conversation:
  1. Goal and why (one line)
  2. Exact file paths, commands, constraints
  3. What NOT to touch
  4. Acceptance criteria and expected return format (diff summary, test
     output, findings list)
- Independent subtasks → launch in ONE message so they run in parallel.
  Dependent chains → run synchronously, or sequence on notifications.
- Parallel executors that mutate files need worktree isolation or strictly
  disjoint file sets — otherwise they clobber each other.
- Iterate by messaging the same agent (keeps its context) instead of
  respawning.
- Keep the main loop lean: every token there is billed at premium rates.
  Avoid bulk-reading large files inline; have executors read them and return
  conclusions, diff summaries, or findings lists — never raw file dumps.
- Verify results against the acceptance criteria before reporting done;
  never relay an unverified "done".

## Mode B — flagship or below (executor)

- Execute directly — this session already is the cost-appropriate tier.
  No mandatory delegation.
- Still fan out flagship-tier subagents for large parallelizable work
  (multi-module refactor, wide audit, long independent investigations).
- Escalate UP to a premium-tier subagent only at genuinely strategic
  points: an ambiguous architecture choice with long-term consequences,
  debugging stuck after 2+ fundamentally different failed approaches,
  cross-system design tradeoffs. The premium subagent returns a decision or
  plan only — never let it execute. Keep such calls rare (≤1–2 per task).

## Harness mechanics — Claude Code

Non-obvious defaults this policy depends on — do not assume they are safe:

- Agent tool `model` accepts "haiku" | "sonnet" | "opus" | "fable".
  **If omitted, the subagent inherits the session model** — in a premium
  session an unmarked Agent call runs on the premium tier. Delegating
  execution therefore ALWAYS requires an explicit model:"opus".
- subagent_type "fork" ignores the model override and always inherits the
  parent model. Never use forks for cost routing.
- Custom agent types (.claude/agents/*.md and plugin agents) may pin their
  own model in frontmatter; an explicit `model` on the Agent call overrides
  it. When cost matters, pass the model explicitly instead of trusting the
  agent definition.
- Workflow scripts: `agent()` calls also inherit the main-loop model by
  default. In a premium session set opts.model:'opus' on every
  execution-stage agent (opts.effort:'low' for mechanical stages); only
  judge/strategy stages can justify the premium tier.
- This skill cannot change the main session's model — that is the user's
  /model choice. It only routes subagent work. If even director work should
  be cheap, tell the user to switch the session model instead.
- Skill triggering is probabilistic, not guaranteed. A CLAUDE.md pointer to
  this file is the only way to make it always-on; keep any such pointer a
  one-line reference, never a copy of the rules.

## Other harnesses

- Any framework with subagent delegation and a per-agent model choice:
  apply the same policy with that framework's tier equivalents.
- No delegation capability at all: do the work inline, tell the user the
  routing policy could not be applied, and suggest switching the session to
  the flagship tier.

## Hard rules

- Never assign execution work to the premium tier.
- Never spawn a subagent for something answerable from current context in
  one step.
- If a flagship executor fails review twice, rewrite the contract or split
  the task; taking over inline on the premium tier is a last resort — do it
  only below a moderate size and say so explicitly in the summary.
- Do not silently downgrade: cheap tier is for mechanical work only; when in
  doubt between cheap and flagship, pick flagship.
