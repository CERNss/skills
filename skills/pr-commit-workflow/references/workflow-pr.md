# PR Workflow

## Preconditions
- If the repo has `AGENTS.md` or `docs/agents/PROCESS.md`, read it for repo-specific rules.

## Steps
- Ensure branch is clean and only includes the intended commits.
- Check for other open PRs that may conflict.
- Ask the user whether to request reviewers; only request collaborators.
- Build PR body using `references/pr-human-template.md`.
- Fill sections with factual, testable info.
- Use `/tmp` + `gh pr edit --body-file` for updates.
- Create PR with `gh pr create` if not already open.
- Default PRs to draft until tests + review pass; ask user before marking ready.

## Review Comment Checks
- Always check both:
  - `gh pr view <id> --comments`
  - `gh api /repos/<org>/<repo>/pulls/<id>/comments --paginate`
- Summarize inline feedback with file + line + fix status.
