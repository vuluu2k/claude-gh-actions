# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Reusable GitHub Action for automated PR code review using Claude Code CLI. Consumed by other repos via `uses: pancake-vn/claude-gh-actions@v1` — this repo is the action source, not a consumer.

## Repository Structure

- `action.yml` — GitHub Actions composite action definition. Orchestrates: detect PR number → skip bot/draft → install Claude CLI → load prompt → run `claude -p` → log token usage.
- `prompts/review-pr.md` — The core review prompt (~500 lines). Loaded by `action.yml` at runtime via `${{ github.action_path }}/prompts/review-pr.md`. Defines the 8-step review process, severity system, comment format, and submission flow.
- `examples/` — Per-stack example configs (workflow files + `.claude/review-config.yml`) for builderx_api (Elixir), builderx_spa (Vue), Go, Python.
- `README.md` — User-facing setup guide in Vietnamese. Contains all usage examples and input/output docs.

## How the Action Executes

1. `action.yml` runs as a composite action on the **consumer repo's** CI runner
2. It installs Claude Code CLI, sets up auth via `CLAUDE_CODE_OAUTH_TOKEN`
3. Loads `prompts/review-pr.md` (or `review_prompt` input override)
4. Runs `claude -p "<prompt>"` with restricted `--allowedTools` (only `gh`, `jq`, `cat`, `rm /tmp/*`, Read, Grep, Glob, Edit for `/tmp/**`)
5. Claude reads the consumer repo's `CLAUDE.md` and `.claude/review-config.yml` to get project-specific rules
6. Claude submits review via `gh api` using Write tool → `/tmp/review.json` → `gh api --input`

## Key Design Decisions

- **The prompt must be stack-agnostic.** It should never contain rules specific to Elixir, Vue, Go, etc. Stack-specific rules come from the consumer repo's `CLAUDE.md` or `review-config.yml`.
- **Skip patterns in the prompt** cover all common stacks (lock files, build output, generated code, assets, IDE configs). When adding new patterns, add them to the appropriate category in the table in `prompts/review-pr.md` Step 3.
- **CI Rules section** in the prompt is critical — Claude running in GitHub Actions cannot use shell operators (`>`, `|`, `&&`). It must use Write tool for file creation and one-command-per-Bash-call pattern.
- **`${{ github.action_path }}`** resolves to the action's directory (whether subtree or remote ref), not the consumer repo root.

## Editing Guidelines

### When editing `prompts/review-pr.md`
- Keep examples language-agnostic (use mixed file extensions in examples, not all one language)
- The prompt has a specific structure: CI Rules → Project Context Discovery → Step 0-8 → Comment Format → Summary Format → Common Mistakes. Preserve this order.
- Step 5 (Deep Analysis) sub-steps (5a–5g) are the core value — these drive quality beyond surface-level diff reading
- Step 5g handles both "has CLAUDE.md" and "no CLAUDE.md" cases — both paths must be maintained

### When editing `action.yml`
- All steps after "Skip bot and draft PRs" must have `if: steps.skip.outputs.skip != 'true'`
- The `--allowedTools` list is a security boundary — Claude in CI should not have Write access to repo files, only `/tmp/**`
- The `review_prompt` input allows consumers to fully override the built-in prompt

### When editing `README.md`
- Written in Vietnamese for the target audience
- Contains the canonical workflow YAML that consumers copy — keep it minimal and correct
- Examples section shows the workflow is identical across projects; only `review-config.yml` differs

## Versioning

Consumers reference this action by tag: `@v1`, `@v1.0.0`. After pushing changes:

```bash
git tag -a v1.x.x -m "description"
git push origin v1.x.x
git tag -fa v1 -m "Update v1"
git push origin v1 --force
```
