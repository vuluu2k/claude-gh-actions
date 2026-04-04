# Claude GH Actions

Reusable GitHub Action for automated PR code review using Claude Code. Works with **any tech stack** — project-specific rules are loaded from `CLAUDE.md` and `.claude/review-config.yml` at runtime.

[Tiếng Việt](./README_VI.md)

## How It Works

```
claude-gh-actions (shared action)          Your repo (project-specific)
──────────────────────────────────         ───────────────────────────────
action.yml      → setup + run Claude       CLAUDE.md              → architecture rules
prompts/        → review methodology       .claude/review-config.yml → ignore/include patterns
                                           extra_prompt (optional) → additional instructions
```

Claude reads your repo's `CLAUDE.md` + `review-config.yml` before reviewing. If neither exists, Claude auto-detects the stack from config files (`package.json`, `mix.exs`, `go.mod`...) and reviews using generic best practices.

---

## Setup — 3 Steps

### Step 1: Get Claude OAuth Token

Run locally (requires Claude login):

```bash
claude setup-token
```

Copy the token output.

### Step 2: Add secret to your repo

Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Name | Value |
|------|-------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Token from step 1 |

> `GITHUB_TOKEN` is automatically provided by GitHub — no need to add it.

### Step 3: Create workflow file

Create `.github/workflows/code-review.yml` in your repo:

```yaml
name: Claude Code Review

on:
  # Auto review when PR is opened or new commits are pushed
  pull_request:
    types: [opened, reopened, synchronize]

  # Review when someone comments "/review" in the PR
  issue_comment:
    types: [created]

  # Manual review from Actions tab
  workflow_dispatch:
    inputs:
      pr_number:
        description: "PR number to review"
        required: true

jobs:
  review:
    runs-on: ubuntu-latest

    # Run on: PR events, manual trigger, or "/review" comment
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
        uses: vuluu2k/claude-gh-actions@v1
        with:
          claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

**Done.** Open a PR and Claude will review it automatically.

---

## File Structure After Setup

```
your-repo/
├── .github/
│   └── workflows/
│       └── code-review.yml          # ← Step 3: create this file
├── CLAUDE.md                         # ← (Optional) Project-specific rules
├── .claude/
│   └── review-config.yml            # ← (Optional) Ignore/include patterns
└── ... (source code)
```

---

## Customizing Reviews Per Project

### Level 1: No customization (works for any repo)

Just the workflow file from step 3. Claude will:
- Auto-detect stack from config files (`package.json`, `mix.exs`, `go.mod`...)
- Read `README.md` for project overview
- Scan 2-3 source files to infer code style
- Review based on universal rules: security, bugs, performance, error handling

### Level 2: Add `.claude/review-config.yml` (ignore files + extra rules)

Create `.claude/review-config.yml` at repo root:

```yaml
review:
  # Files to skip (merged with default skip patterns)
  ignore_patterns:
    - "docs/**"
    - "scripts/**"
    - "*.config.js"

  # Files to force-review even if they match skip patterns
  include_patterns:
    - "migrations/*.sql"

  # Additional rules for Claude to check and enforce
  extra_rules:
    - "Project rule 1"
    - "Project rule 2"
```

### Level 3: Add `CLAUDE.md` (full project rules — recommended)

Create `CLAUDE.md` at repo root. This is the most powerful option — Claude reads and enforces every rule in this file. Write in Markdown, free-form:

```markdown
# Project Rules

## Architecture
- Controllers must be thin — no business logic
- All DB queries must include tenant_id

## Naming
- Files: snake_case
- Functions: verb prefix (get_, create_, update_, delete_)

## Security
- No hardcoded secrets
- Validate all user input
```

> **Tip**: If your repo already has a `CLAUDE.md` for Claude Code (CLI), this action uses it automatically — no extra setup needed.

### Level 4: `extra_prompt` in workflow (one-off instructions)

Add `extra_prompt` for workflow-level instructions:

```yaml
- name: Claude Code Review
  uses: vuluu2k/claude-gh-actions@v1
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    extra_prompt: |
      Pay extra attention to SQL injection in this PR.
      Skip test files.
```

### Rule Priority Order

```
CLAUDE.md > review-config.yml extra_rules > extra_prompt > auto-detected conventions > generic
```

---

## Real-World Configuration Examples

### Example 1: Elixir/Phoenix API

**`.github/workflows/code-review.yml`** — standard workflow, no changes needed:

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, reopened, synchronize]
  issue_comment:
    types: [created]

jobs:
  review:
    runs-on: ubuntu-latest
    if: |
      github.event_name == 'pull_request' ||
      (github.event_name == 'issue_comment' &&
       github.event.issue.pull_request &&
       contains(github.event.comment.body, '/review'))
    permissions:
      contents: read
      pull-requests: write
      issues: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: vuluu2k/claude-gh-actions@v1
        with:
          claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

**`.claude/review-config.yml`** — Elixir-specific config:

```yaml
review:
  ignore_patterns:
    - "priv/static/*"
    - "priv/gettext/**"
    - "assets/node_modules/**"
    - "assets/vendor/*"
    - "*.json"
  include_patterns:
    - "priv/repo/migrations/*.exs"
  extra_rules:
    - "All sharded table queries MUST include site_id in WHERE clause"
    - "All joins between sharded tables MUST include site_id in ON condition"
    - "Use Citus repo for tenant data, Repo for global tables"
    - "Context functions for tenant data MUST take site_id as first argument"
    - "Controllers must return FallbackController tuples"
    - "No Repo calls in controllers — use context modules"
    - "No String.to_atom/1 on user input"
    - "RabbitMQ/Kafka consumers must be idempotent"
```

---

### Example 2: Vue 3 SPA

**`.github/workflows/code-review.yml`** — **identical** to example 1.

**`.claude/review-config.yml`** — Vue-specific config:

```yaml
review:
  ignore_patterns:
    - "src/i18n/locales/*.json"
    - "tinymce/**"
    - "public/**"
    - "*.min.js"
    - "*.min.css"
    - "dist/**"
  include_patterns: []
  extra_rules:
    - "No console.log() — use console.warn() or console.error()"
    - "Use design system components from src/components/design/"
    - "Use existing API composables (useApiget, useApipost) or axiosClient"
    - "Use Pinia stores for shared state — no provide/inject for cross-component data"
    - "Clean up event listeners, timers, subscriptions in onUnmounted"
    - "Use @/ path alias for imports"
    - "Prettier: 120 char, single quotes, no semicolons, 2-space indent"
```

---

### Example 3: Go Microservice (no CLAUDE.md)

**`.github/workflows/code-review.yml`** — **identical** to example 1.

**No extra files needed.** Claude will:
- Detect Go from `go.mod`
- Read `README.md`
- Review using Go best practices (error handling, goroutine leaks, defer usage...)

**(Optional)** Add `.claude/review-config.yml`:

```yaml
review:
  ignore_patterns:
    - "vendor/**"
    - "*.pb.go"
    - "mock_*.go"
  extra_rules:
    - "Always check error returns — no _ for errors"
    - "Use context.Context as first parameter"
    - "No goroutine without cancellation/timeout"
```

---

### Example 4: Python Django (no CLAUDE.md)

**`.github/workflows/code-review.yml`** — **identical** to example 1.

**(Optional)** `.claude/review-config.yml`:

```yaml
review:
  ignore_patterns:
    - "*/migrations/*.py"
    - "static/**"
    - "media/**"
    - "*.pyc"
  extra_rules:
    - "Use Django ORM — no raw SQL unless justified"
    - "All views must check permissions via decorators or mixins"
    - "No print() in production code — use logging module"
    - "Querysets must be filtered — no Model.objects.all() in views"
```

---

### Example 5: React/Next.js (zero config)

**`.github/workflows/code-review.yml`** — **identical** to example 1. That's it.

Claude auto-detects from `package.json` + `next.config.*` and reviews using React/Next.js best practices.

---

## Inputs Reference

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `claude_token` | **Yes** | — | Claude OAuth token (from `claude setup-token`) |
| `github_token` | **Yes** | — | GitHub token (use `${{ secrets.GITHUB_TOKEN }}`) |
| `pr_number` | No | auto-detect | PR number — auto-detected from event, only needed for `workflow_dispatch` |
| `max_turns` | No | `30` | Maximum agentic turns for Claude |
| `model` | No | `claude-opus-4-6` | Claude model to use |
| `review_prompt` | No | built-in | Override the entire review prompt (advanced) |
| `extra_prompt` | No | — | Append additional instructions to the prompt |

### Change model

```yaml
- uses: vuluu2k/claude-gh-actions@v1
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    model: "claude-opus-4-6"        # Use Opus for deeper review (higher cost)
```

### Limit turns

```yaml
- uses: vuluu2k/claude-gh-actions@v1
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    max_turns: 15                   # Cap at 15 turns (faster, cheaper)
```

## Outputs Reference

| Output | Description |
|--------|-------------|
| `total_cost_usd` | Review cost (USD) |
| `num_turns` | Number of turns used |
| `session_id` | Session ID (for resuming if needed) |

Reading outputs:

```yaml
- name: Claude Code Review
  id: review
  uses: vuluu2k/claude-gh-actions@v1
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}

- name: Print cost
  run: echo "Review cost: ${{ steps.review.outputs.total_cost_usd }}"
```

---

## Triggering Reviews

| Method | When |
|--------|------|
| **Automatic** | PR opened, reopened, or new commits pushed |
| **Comment** | Type `/review` in a PR comment |
| **Manual** | Actions tab → Claude Code Review → Run workflow → enter PR number |

### Comment-only trigger (no auto-review)

```yaml
on:
  issue_comment:
    types: [created]

jobs:
  review:
    if: |
      github.event.issue.pull_request &&
      contains(github.event.comment.body, '/review')
    # ...
```

### Manual-only trigger

```yaml
on:
  workflow_dispatch:
    inputs:
      pr_number:
        description: "PR number"
        required: true

jobs:
  review:
    # ...
    steps:
      - uses: vuluu2k/claude-gh-actions@v1
        with:
          claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          pr_number: ${{ github.event.inputs.pr_number }}
```

---

## Auto-Skip

The action automatically skips review when:
- PR is a **draft**
- PR author is a **bot** (dependabot, renovate, etc.)

No configuration needed.

---

## Severity Levels

Review comments include severity badges:

| Badge | Meaning | Action Required |
|-------|---------|-----------------|
| ![Major](https://img.shields.io/badge/Major-red?style=flat-square) | Bug, security, data loss, architecture violation | **Must fix** before merge |
| ![Minor](https://img.shields.io/badge/Minor-orange?style=flat-square) | Design issue, missing error handling, regression | **Should fix** or explain |
| ![Nitpick](https://img.shields.io/badge/Nitpick-cyan?style=flat-square) | Style, naming, minor suggestion | **Optional** |

---

## Usage Methods

### Method 1: Direct reference (recommended)

```yaml
uses: vuluu2k/claude-gh-actions@v1
```

No files to copy into your repo. Version pinned by tag.

### Method 2: Git subtree (if you need to modify the prompt)

```bash
# Add to your repo
git subtree add --prefix=.github/actions/review \
    git@github.com:vuluu2k/claude-gh-actions.git main --squash

# Use in workflow
uses: ./.github/actions/review

# Update
git subtree pull --prefix=.github/actions/review \
    git@github.com:vuluu2k/claude-gh-actions.git main --squash
```

---

## Releasing (for maintainers)

```bash
# Tag new version
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# Move major version tag (v1) to latest
git tag -fa v1 -m "Update v1 to v1.0.0"
git push origin v1 --force
```

All repos using `@v1` automatically get the latest patch. Pin a specific version with `@v1.0.0`.
