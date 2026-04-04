# Claude GH Actions

Reusable GitHub Actions for automated PR code review using Claude Code. Works with **any tech stack** — project-specific rules are loaded from `CLAUDE.md` at runtime.

## How it works

```
claude-gh-actions (generic)     +     Your repo's CLAUDE.md (specific)
─────────────────────────────         ──────────────────────────────────
Review process, severity system       Architecture rules, naming conventions,
Comment format, submission flow       DB constraints, response formats, etc.
Deep analysis methodology             Project-specific review criteria
```

The prompt reads your project's `CLAUDE.md` and `.claude/review-config.yml` at review time, so **one action works for all repos** without modification.

## Features

- **Scope-based review** — adapts focus based on commit types (fix, feat, refactor, etc.)
- **CLAUDE.md-driven** — enforces your project's specific architecture rules
- **Inline line-level comments** with severity badges (Major/Minor/Nitpick)
- **Deep analysis** — traces callers, reads utility implementations, verifies edge cases
- **Re-review support** — tracks previous comments, handles author rebuttals
- **Token usage reporting** in GitHub Step Summary
- **Per-repo config** overrides via `.claude/review-config.yml`
- **Auto-skip** draft PRs and bot authors

## Setup

### 1. Add as git subtree in your repo

```bash
git subtree add --prefix=.github/actions/review \
    git@github.com:pancake-vn/claude-gh-actions.git main --squash
```

### 2. Create workflow file

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
        uses: ./.github/actions/review
        with:
          claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Add secrets

Go to **Settings > Secrets and variables > Actions** and add:

| Secret | Description |
|--------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude OAuth token (run `claude setup-token` locally) |

`GITHUB_TOKEN` is automatically provided by GitHub Actions.

### 4. Add project rules (optional but recommended)

Create a `CLAUDE.md` at your repo root with project-specific rules. The reviewer will read and enforce these automatically. Example:

```markdown
# My Project Rules
- All database queries must include `tenant_id` in WHERE clause
- Controllers must be thin — no business logic
- Use `Ecto.Multi` for atomic operations
```

## Configuration

### Per-repo review config (optional)

Create `.claude/review-config.yml` in your repo:

```yaml
review:
  ignore_patterns:
    - "priv/repo/seeds/*"
    - "assets/vendor/*"
    - "*.min.js"
  include_patterns:
    - "priv/repo/migrations/*.exs"
  extra_rules:
    - "Custom review rule for this project"
```

### Action inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `claude_token` | Yes | — | Claude OAuth token |
| `github_token` | Yes | — | GitHub token for PR operations |
| `pr_number` | No | auto-detect | PR number (auto-detected from event) |
| `max_turns` | No | `30` | Maximum agentic turns |
| `model` | No | `claude-sonnet-4-20250514` | Claude model to use |
| `extra_prompt` | No | — | Additional review instructions |

### Action outputs

| Output | Description |
|--------|-------------|
| `total_cost_usd` | Cost of the review run |
| `num_turns` | Number of turns used |
| `session_id` | Claude session ID |

## Updating

Pull latest changes from upstream:

```bash
git subtree pull --prefix=.github/actions/review \
    git@github.com:pancake-vn/claude-gh-actions.git main --squash
```

## Triggering a review

| Method | How |
|--------|-----|
| Auto on PR | Opens or pushes new commits |
| Comment | Type `/review` in PR comment |
| Manual | Actions tab > Claude Code Review > Run workflow > enter PR number |

## Severity levels

| Badge | Meaning | Action required |
|-------|---------|-----------------|
| ![Major](https://img.shields.io/badge/Major-red?style=flat-square) | Bugs, security, data loss, architecture violations | Must fix before merge |
| ![Minor](https://img.shields.io/badge/Minor-orange?style=flat-square) | Design issues, error handling, regressions | Should fix or explain |
| ![Nitpick](https://img.shields.io/badge/Nitpick-cyan?style=flat-square) | Style, naming, optional improvements | Optional |

## Example: using with different projects

**Elixir/Phoenix project** — just add a `CLAUDE.md` with Elixir rules:
```yaml
# No changes to the action needed — CLAUDE.md drives the rules
- name: Claude Code Review
  uses: ./.github/actions/review
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

**Vue.js/TypeScript project** — same action, different `CLAUDE.md`:
```yaml
# Same action, your CLAUDE.md has Vue/TS-specific rules
- name: Claude Code Review
  uses: ./.github/actions/review
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

**Extra prompt for one-off rules:**
```yaml
- name: Claude Code Review
  uses: ./.github/actions/review
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    extra_prompt: "Pay special attention to SQL injection in this PR"
```
