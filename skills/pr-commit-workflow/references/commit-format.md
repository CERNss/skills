# Commit Message Format

## Requirements
- Use Conventional Commits: `<type>[optional scope]: <description>`.
- Do not prefix subjects with emoji, robot icons, model names, or agent branding.
- Keep the subject concise, imperative, and lowercase after the type unless a proper noun requires capitalization.
- Use common types such as `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, or `revert`.
- Use multi-line message: subject + what/why + tests.
- Prefer heredoc over `-m` to avoid quoting errors.

## Template
Subject line:
- `<type>[optional scope]: <short summary>`

Body:
- `What: <bullet list>`
- `Why: <bullet list>`
- `Tests: <command + result>`

## Example (heredoc)
```
git commit -F - <<'MSG'
docs: clarify PR workflow expectations

What:
- add explicit human-written intent requirement
- split commit/PR sections in workflow skill

Why:
- enforce reviewer context and transparency
- reduce PR churn from auto-generated summaries

Tests:
- not run (docs-only)
MSG
```

## Multi-Model Attribution
If multiple models contributed, add Co-Authored-By trailers:
```
Co-Authored-By: GPT-5.2-Codex <noreply@openai.com>
Co-Authored-By: Gemini Pro <noreply@google.com>
```
