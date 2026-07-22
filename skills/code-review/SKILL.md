---
name: code-review
description: "Comprehensive code review skill covering PR review, local diff review, and full code quality audit. Includes OpenSpec cross-validation for requirements, tasks, and code consistency. USE FOR: code review, PR review, review PR, review diff, review changes, review code, audit code, code quality, review my code, review this PR, check code quality, staged changes review, git diff review. TASK INVOCATION: when delegating with task(), use category='writing' and load this skill. DO NOT USE FOR: refactoring (use /refactor), writing new code, deployment."
license: MIT
metadata:
  author: custom
  version: "1.2.0"
---

# Code Review Skill

This skill provides structured, thorough code review across three scenarios: GitHub PR review, local diff review, and full code quality audit.

## Agent Routing (Required)

When you invoke this skill through `task()`, use the `writing` category.

```txt
task(
  category="writing",
  load_skills=["code-review"],
  description="Review local changes and produce actionable findings",
  prompt="1. TASK: ... 2. EXPECTED OUTCOME: ... 3. REQUIRED TOOLS: ... 4. MUST DO: ... 5. MUST NOT DO: ... 6. CONTEXT: ...",
  run_in_background=false
)
```

Rules:
- Use `category="writing"` for code review output quality and structure.
- Keep `load_skills` containing `"code-review"`.
- Choose either `category` or `subagent_type` (never both).

## Review Principles

All reviews follow these core principles:

1. **Correctness first** — Does the code do what it claims to do?
2. **Security** — SQL injection, XSS, secrets exposure, auth bypass, path traversal
3. **Performance** — N+1 queries, unnecessary allocations, missing indexes, unbounded loops
4. **Maintainability** — Naming, complexity, DRY violations, unclear intent
5. **Error handling** — Silent failures, missing edge cases, uncaught exceptions
6. **Consistency** — Does it match the existing codebase style and patterns?

## OpenSpec Cross-Validation (Required when `openspec/` exists)

When a repository contains `openspec/`, every review must validate alignment across requirement specs, task checklists, and implementation code.

### Mandatory OpenSpec checks

1. **Discover current OpenSpec state**

```bash
openspec list
openspec list --specs
```

2. **Validate OpenSpec data integrity**

```bash
openspec validate --strict --no-interactive
```

3. **Map changes to requirements/tasks/code**
   - Read relevant files under `openspec/specs/**/spec.md`
   - Read active change files under `openspec/changes/<change-id>/`:
     - `proposal.md`
     - `tasks.md`
     - `specs/**/spec.md`
   - Compare the code diff against requirements/scenarios and task checklist entries.

4. **Flag traceability gaps**
   - Code behavior changed without matching requirement/scenario coverage
   - Task marked complete (`- [x]`) but no code evidence
   - Code implemented but task still pending (`- [ ]`) and not explained
   - OpenSpec active changes that conflict with reviewed code

### Required OpenSpec section in review output

```markdown
### OpenSpec Traceability
- OpenSpec validation: PASS/FAIL (`openspec validate --strict --no-interactive`)
- Active change IDs reviewed: <ids or none>
- Requirement coverage: <mapped requirements/scenarios>
- Task coverage: <task items with code evidence>
- Drift risks: <missing links or conflicts>
```

**Severity Levels:**
- 🔴 **Critical** — Must fix. Bugs, security issues, data loss risk
- 🟡 **Warning** — Should fix. Performance issues, bad patterns, maintainability concerns
- 🟢 **Suggestion** — Nice to have. Style improvements, minor optimizations
- ℹ️ **Note** — Informational. Context, questions, observations

## Scenario 1: GitHub PR Review

**Trigger**: User mentions a PR URL, PR number, or says "review PR"

### Workflow

1. **Fetch PR metadata and diff:**

```bash
# Get PR info
gh pr view <PR_NUMBER> --json title,body,author,baseRefName,headRefName,files,additions,deletions

# Get full diff
gh pr diff <PR_NUMBER>

# Get PR comments (if any)
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments
```

2. **Analyze the diff systematically:**
   - Read each changed file's full context (not just the diff) using the Read tool
   - Understand the purpose from PR title/body
   - Check if tests are included for new functionality
   - Check if documentation is updated if needed
   - Run OpenSpec cross-validation (requirements/tasks/code) when `openspec/` exists

3. **Review checklist:**
   - [ ] PR description clearly explains the "why"
   - [ ] Changes match the stated purpose (no scope creep)
   - [ ] No unrelated formatting/refactoring changes mixed in
   - [ ] New code has test coverage
   - [ ] No secrets, credentials, or sensitive data committed
   - [ ] Error handling is adequate
   - [ ] No obvious performance regressions
   - [ ] Follows existing codebase patterns and conventions
   - [ ] OpenSpec requirements/scenarios map to code changes (when `openspec/` exists)
   - [ ] OpenSpec `tasks.md` status matches code evidence (when active change exists)

4. **Output format:**

```markdown
## PR Review: #<NUMBER> — <TITLE>

### Summary
<1-2 sentence overview of what this PR does>

### Findings

#### 🔴 Critical
- **<file>:<line>** — <description>
  ```
  <code snippet>
  ```
  **Suggestion:** <fix>

#### 🟡 Warnings
- **<file>:<line>** — <description>

#### 🟢 Suggestions
- **<file>:<line>** — <description>

### Verdict
<APPROVE / REQUEST_CHANGES / COMMENT>
<reasoning>

### OpenSpec Traceability
- OpenSpec validation: PASS/FAIL
- Active change IDs reviewed: <ids or none>
- Requirement coverage: <mapped requirements/scenarios>
- Task coverage: <task items with code evidence>
- Drift risks: <missing links or conflicts>
```

5. **Post review comments (if user agrees):**

```bash
# Leave a review
gh pr review <PR_NUMBER> --comment --body "review content"
# Or with approval
gh pr review <PR_NUMBER> --approve --body "review content"
# Or request changes
gh pr review <PR_NUMBER> --request-changes --body "review content"
```

## Scenario 2: Local Diff Review

**Trigger**: User says "review my changes", "review diff", "review staged"

### Workflow

1. **Collect changes:**

```bash
# Staged changes
git diff --cached --stat
git diff --cached

# Unstaged changes
git diff --stat
git diff

# Or changes since a branch point
git diff main...HEAD --stat
git diff main...HEAD
```

2. **For each changed file:**
   - Read the full file (not just diff) for context
   - Run `lsp_diagnostics` to catch type errors and warnings
   - Check if the change introduces new patterns inconsistent with the codebase
   - Run OpenSpec cross-validation (requirements/tasks/code) when `openspec/` exists

3. **Review with the same checklist and output format as PR review**

4. **Additionally check:**
   - [ ] No debug code left (console.log, print, debugger, TODO/FIXME)
   - [ ] No commented-out code blocks
   - [ ] Import statements are clean (no unused imports)
   - [ ] Commit is atomic (single logical change)
   - [ ] OpenSpec requirements/scenarios map to code changes (when `openspec/` exists)
   - [ ] OpenSpec `tasks.md` status matches code evidence (when active change exists)

## Scenario 3: Full Code Quality Audit

**Trigger**: User says "audit code", "review code quality", "check code quality" for specific files/directories

### Workflow

1. **Scope the audit:**
   - Ask user for target files/directories if not specified
   - Sample the codebase structure to understand conventions

2. **For each file in scope:**
   - Read the full file
   - Run `lsp_diagnostics` for type errors and warnings
   - Use `ast_grep_search` to find anti-patterns:
   - Run OpenSpec cross-validation (requirements/tasks/code) when `openspec/` exists

```
# Find empty catch blocks
ast_grep_search(pattern="catch ($ERR) { }", lang="typescript")

# Find console.log statements
ast_grep_search(pattern="console.log($$$)", lang="typescript")

# Find any type assertions
ast_grep_search(pattern="$EXPR as any", lang="typescript")

# Find TODO/FIXME comments
grep(pattern="TODO|FIXME|HACK|XXX")
```

3. **Analyze dimensions:**
   - **Complexity** — Deeply nested conditionals, long functions (>50 lines), high cyclomatic complexity
   - **Duplication** — Similar code blocks across files
   - **Dependencies** — Circular dependencies, tight coupling
   - **Error handling** — Inconsistent patterns, silent failures
   - **Type safety** — `any` usage, type assertions, missing types
   - **Security** — Hardcoded secrets, injection vectors, unsafe operations
   - **Testing** — Coverage gaps, test quality

4. **Output format:**

```markdown
## Code Quality Audit: <scope>

### Overview
- Files analyzed: N
- Total issues: N (🔴 X critical, 🟡 Y warnings, 🟢 Z suggestions)

### Top Issues

#### 🔴 Critical
1. **<file>:<line>** — <description>

#### 🟡 Warnings
1. **<file>:<line>** — <description>

#### 🟢 Suggestions
1. **<file>:<line>** — <description>

### Patterns Observed
- <positive pattern>
- <negative pattern>

### Recommendations
1. <actionable recommendation>
2. <actionable recommendation>

### OpenSpec Traceability
- OpenSpec validation: PASS/FAIL
- Active change IDs reviewed: <ids or none>
- Requirement coverage: <mapped requirements/scenarios>
- Task coverage: <task items with code evidence>
- Drift risks: <missing links or conflicts>
```

## Important Rules

- **NEVER auto-fix** code during review. Review is read-only. Only suggest fixes.
- **Ask before posting** PR comments to GitHub. Never post without user consent.
- **Be specific** — always include file name and line number.
- **Be constructive** — explain WHY something is a problem, not just THAT it is.
- **Acknowledge good code** — note well-written patterns too.
- **Respect context** — a startup MVP has different standards than a banking system.
- **Don't bikeshed** — focus on substance over style (unless style causes real confusion).
- **OpenSpec required** — if `openspec/` exists, do not finalize review without requirement/task/code traceability checks.
