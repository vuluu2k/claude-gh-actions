# Claude GH Actions

Reusable GitHub Action for automated PR code review using Claude Code. Works with **any tech stack** — project-specific rules are loaded from `CLAUDE.md` at runtime.

## How it works

```
claude-gh-actions (generic)           Your repo (specific)
───────────────────────────           ────────────────────
action.yml    → orchestration         CLAUDE.md           → architecture rules
prompts/      → review methodology    .claude/review-config.yml → ignore/include patterns
                                      extra_prompt        → one-off instructions
```

The reviewer reads your project's `CLAUDE.md` and `.claude/review-config.yml` at review time, so **one action works for all repos**.

## Quick Start

### 1. Add secret

Go to **Settings > Secrets and variables > Actions** and add:

| Secret | How to get |
|--------|------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Run `claude setup-token` locally |

### 2. Create workflow

Create `.github/workflows/code-review.yml`:

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, reopened, synchronize]
  issue_comment:
    types: [created]
  workflow_dispatch:
    inputs:
      pr_number:
        description: "PR number to review"
        required: true

jobs:
  review:
    runs-on: ubuntu-latest
    if: |
      github.event_name == 'pull_request' ||
      github.event_name == 'workflow_dispatch' ||
      (github.event_name == 'issue_comment' &&
       github.event.issue.pull_request &&
       contains(github.event.comment.body, '/review'))
    permissions:
      contents: read
      pull-requests: write
      issues: write
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Claude Code Review
        uses: pancake-vn/claude-gh-actions@v1
        with:
          claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

That's it. No subtree, no copy — just reference the action with a version tag.

## Usage Methods

### Method 1: Direct reference (recommended)

```yaml
uses: pancake-vn/claude-gh-actions@v1
```

Version pinned, auto-updates with tag. No files to manage in your repo.

### Method 2: Git subtree (if you need to modify the prompt)

```bash
git subtree add --prefix=.github/actions/review \
    git@github.com:pancake-vn/claude-gh-actions.git main --squash
```

```yaml
uses: ./.github/actions/review
```

Update with: `git subtree pull --prefix=.github/actions/review git@github.com:pancake-vn/claude-gh-actions.git main --squash`

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `claude_token` | Yes | — | Claude OAuth token |
| `github_token` | Yes | — | GitHub token for PR operations |
| `pr_number` | No | auto-detect | PR number (auto-detected from event) |
| `max_turns` | No | `30` | Maximum agentic turns |
| `model` | No | `claude-sonnet-4-20250514` | Claude model |
| `review_prompt` | No | built-in | Override default review prompt entirely |
| `extra_prompt` | No | — | Append additional instructions |

## Outputs

| Output | Description |
|--------|-------------|
| `total_cost_usd` | Cost of the review run |
| `num_turns` | Number of turns used |
| `session_id` | Claude session ID |

## Per-repo Configuration

### CLAUDE.md (project rules)

The reviewer reads `CLAUDE.md` at repo root and enforces its rules. This is the main way to customize reviews per project — no action changes needed.

### .claude/review-config.yml (review-specific)

```yaml
review:
  ignore_patterns:
    - "assets/vendor/*"
    - "*.min.js"
  include_patterns:
    - "priv/repo/migrations/*.exs"
  extra_rules:
    - "Custom rule specific to code review"
```

## Examples

See [`examples/`](./examples/) for ready-to-use configs:

| Project | Stack | What's different |
|---------|-------|-----------------|
| [`builderx_api`](./examples/builderx_api/) | Elixir/Phoenix/Citus | review-config with sharding rules, Elixir ignore patterns |
| [`builderx_spa`](./examples/builderx_spa/) | Vue 3/Vite/Pinia | review-config with Vue rules, frontend ignore patterns |

**The workflow file is identical** — only `.claude/review-config.yml` differs per project.

## Triggering

| Method | How |
|--------|-----|
| Auto on PR | Opens, reopens, or pushes new commits |
| Comment | Type `/review` in PR comment |
| Manual | Actions tab > Run workflow > enter PR number |

## Severity Levels

| Badge | Meaning | Action |
|-------|---------|--------|
| ![Major](https://img.shields.io/badge/Major-red?style=flat-square) | Bugs, security, data loss, architecture violations | Must fix |
| ![Minor](https://img.shields.io/badge/Minor-orange?style=flat-square) | Design issues, error handling, regressions | Should fix |
| ![Nitpick](https://img.shields.io/badge/Nitpick-cyan?style=flat-square) | Style, naming, optional improvements | Optional |

## Releasing a new version

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# Move the major version tag (v1) to latest
git tag -fa v1 -m "Update v1 to v1.0.0"
git push origin v1 --force
```

Users on `@v1` automatically get the latest patch.
