# pr-workflow-skill

A skill for high-signal PR and commit workflows in agentic AI coding. Works with your coding agent of choice.

## What it does

- Enforces a **structured PR body** (Changes / Tests / Risks / Follow-ups)
- Guides **surgical commits** (one logical change per commit, no bulk adds)
- Defaults PRs to **draft until tests + review pass**

## Installation

Give this to your coding agent:

> Install the PR workflow skill from https://github.com/joshp123/pr-workflow-skill — clone it to wherever I keep skills, and wire it up so it activates when I create commits or PRs.

## Usage

The skill activates when creating commits or PRs. It will build the PR body using the template in `references/pr-human-template.md` and fill each section with factual, testable info.

## Example PR

---

### Changes
- New skill: `skills/pr-commit-workflow/` — global PR/commit workflow with a structured PR body
- Reviewer-prompting + default-draft policy: PRs stay draft until tests + review pass
- Surgical commit guidance: one logical change per commit, no bulk `git add`

### Tests
- `nix flake check` — ok (warnings: uncommitted tree, unknown flake output `homeManagerModules`)

### Risks
- Low; docs/skill only

### Follow-ups
- Lightweight template variant for trivial PRs
- Reviewer handles/team mapping for automation

---

## Files

- `SKILL.md` — skill entry point
- `references/workflow-commit.md` — commit workflow steps
- `references/workflow-pr.md` — PR workflow steps
- `references/pr-human-template.md` — the PR template
- `references/commit-format.md` — commit message format

## License

AGPL-3.0
