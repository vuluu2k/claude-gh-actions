# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Reusable GitHub Action for automated PR code review using Claude Code CLI. Consumed by other repos via `uses: vuluu2k/claude-gh-actions@v1` — this repo is the action source, not a consumer.

## Repository Structure

- `action.yml` — GitHub Actions composite action definition. Orchestrates: detect PR number → **review guard** → install Claude CLI → load prompt → run `claude -p` → record review state → log token usage.
- `scripts/review-guard.sh` — token-saving guard, runs before anything is installed. Decides skip vs full vs incremental (see "Review Guard" below).
- `scripts/review-mark.sh` — upserts the single `<!-- claude-review-state sha=… fp=… -->` comment per PR that the guard reads on the next run.
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

## Review Guard (token control)

`scripts/review-guard.sh` runs before the Claude CLI is even installed and emits
`skip` / `mode` / `since_sha` / `diff_fp` / `incremental_prompt`:

1. **Skip** — draft, bot author, or merged/closed PR (`skip_merged`).
2. **Duplicate twin PR** (`dedup_similar_prs`) — the same hotfix is routinely opened twice,
   once against `master` and once against `develop`. Detected either by same head branch +
   same head commit, or by identical diff-content fingerprint (cherry-picked onto a sibling
   branch). Second PR gets a comment linking to the reviewed one, no review runs.
3. **Incremental** (`incremental_review`) — diff `since_sha..HEAD`, write
   `/tmp/pr-context/incremental.patch`, replace `pr-diff.patch` with a stub, and append an
   INCREMENTAL REVIEW MODE block to the prompt. Falls back to full review on force-push
   (mark no longer an ancestor), missing objects (consumer forgot `fetch-depth: 0`), or a
   patch larger than `max_incremental_bytes`.

State lives in one marker comment per PR — no cache, no extra refs — so twin PRs can read
each other's state. `force: true` or a `/review full` comment bypasses all of it.

When changing the guard, keep every skip path emitting `skip=true` **and** `skip_reason`:
`action.yml` reports the reason back to the PR on comment triggers.

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
- All steps after "Review guard" must have `if: steps.guard.outputs.skip != 'true'`
- The `--allowedTools` list is a security boundary — Claude in CI should not have Write access to repo files, only `/tmp/**`
- The `review_prompt` input allows consumers to fully override the built-in prompt

### When editing `README.md`
- Written in Vietnamese for the target audience
- Contains the canonical workflow YAML that consumers copy — keep it minimal and correct
- Examples section shows the workflow is identical across projects; only `review-config.yml` differs

## Versioning

Consumers reference this action by tag: `@v1`, `@v1.0.0`. Releases are automated by `.github/workflows/release-tag.yml`:

- **Preferred:** run the "Release Tag" workflow manually (Actions → Release Tag → Run workflow), pick `patch`/`minor`/`major`. It computes the next version from the latest tag, creates `vX.Y.Z`, and moves the major tag (`v1`) automatically.
- **Alternative:** push a `vX.Y.Z` tag from local — the workflow then moves the major tag for you:

```bash
git tag -a v1.x.x -m "description"
git push origin v1.x.x
```
