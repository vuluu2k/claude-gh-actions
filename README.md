# Claude GH Actions

Reusable GitHub Action — automated PR code review bằng Claude Code. Hoạt động với **mọi tech stack**, không cần sửa action. Project-specific rules được load từ `CLAUDE.md` và `.claude/review-config.yml` của từng repo lúc runtime.

## Cách hoạt động

```
claude-gh-actions (action chung)           Repo của bạn (rules riêng)
────────────────────────────────           ─────────────────────────────
action.yml      → setup + chạy Claude      CLAUDE.md              → architecture rules
prompts/        → quy trình review         .claude/review-config.yml → ignore/include patterns
                                           extra_prompt (optional) → chỉ dẫn thêm
```

Claude sẽ đọc `CLAUDE.md` + `review-config.yml` trong repo của bạn trước khi review. Nếu không có, Claude tự detect stack từ config files (`package.json`, `mix.exs`, `go.mod`...) và review theo generic best practices.

---

## Setup — 3 bước

### Bước 1: Lấy Claude OAuth Token

Chạy trên máy local (cần đăng nhập Claude):

```bash
claude setup-token
```

Copy token output.

### Bước 2: Thêm secret vào repo

Vào GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Name | Value |
|------|-------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Token từ bước 1 |

> `GITHUB_TOKEN` không cần thêm — GitHub tự cung cấp.

### Bước 3: Tạo workflow file

Tạo file `.github/workflows/code-review.yml` trong repo của bạn:

```yaml
name: Claude Code Review

on:
  # Auto review khi PR mở hoặc có commit mới
  pull_request:
    types: [opened, reopened, synchronize]

  # Review khi comment "/review" trong PR
  issue_comment:
    types: [created]

  # Review thủ công từ Actions tab
  workflow_dispatch:
    inputs:
      pr_number:
        description: "PR number to review"
        required: true

jobs:
  review:
    runs-on: ubuntu-latest

    # Chỉ chạy khi: PR event, manual trigger, hoặc comment "/review"
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

**Done.** Mở PR là Claude tự review.

---

## Cấu trúc files trong repo sau khi setup

```
your-repo/
├── .github/
│   └── workflows/
│       └── code-review.yml          # ← Bước 3 tạo file này
├── CLAUDE.md                         # ← (Optional) Rules riêng cho project
├── .claude/
│   └── review-config.yml            # ← (Optional) Ignore/include patterns
└── ... (source code)
```

---

## Tuỳ chỉnh review cho từng project

### Cấp 1: Không tuỳ chỉnh gì (mọi repo đều dùng được)

Chỉ cần workflow file ở bước 3. Claude sẽ:
- Tự detect stack từ config files (`package.json`, `mix.exs`, `go.mod`...)
- Đọc `README.md` để hiểu project
- Đọc 2-3 file source để infer code style
- Review dựa trên universal rules: security, bugs, performance, error handling

### Cấp 2: Thêm `.claude/review-config.yml` (ignore files + extra rules)

Tạo file `.claude/review-config.yml` ở root repo:

```yaml
review:
  # Files không cần review (merge với default skip patterns)
  ignore_patterns:
    - "docs/**"
    - "scripts/**"
    - "*.config.js"

  # Files bắt buộc review dù nằm trong skip patterns
  include_patterns:
    - "migrations/*.sql"

  # Rules review thêm (Claude sẽ check + enforce)
  extra_rules:
    - "Rule 1 của project"
    - "Rule 2 của project"
```

### Cấp 3: Thêm `CLAUDE.md` (full project rules — recommended)

Tạo `CLAUDE.md` ở root repo. Đây là file mạnh nhất — Claude sẽ đọc và enforce mọi rule trong này. Viết bằng Markdown, tự do format:

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

> **Tip**: Nếu repo đã có `CLAUDE.md` cho Claude Code (CLI), thì action này tự động dùng luôn — không cần tạo thêm gì.

### Cấp 4: `extra_prompt` trong workflow (one-off instructions)

Thêm `extra_prompt` khi cần chỉ dẫn thêm ở level workflow:

```yaml
- name: Claude Code Review
  uses: vuluu2k/claude-gh-actions@v1
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    extra_prompt: |
      Focus thêm vào SQL injection trong PR này.
      Không review file tests.
```

### Thứ tự ưu tiên rules

```
CLAUDE.md > review-config.yml extra_rules > extra_prompt > auto-detected conventions > generic
```

---

## Ví dụ cấu hình cho các project thực tế

### Ví dụ 1: Elixir/Phoenix API (builderx_api)

**`.github/workflows/code-review.yml`** — workflow chuẩn, không thay đổi:

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

**`.claude/review-config.yml`** — tuỳ chỉnh cho Elixir:

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
    - "Use BuilderxApi.Citus for tenant data, BuilderxApi.Repo for global"
    - "Context functions for tenant data MUST take site_id as first argument"
    - "Controllers must return FallbackController tuples"
    - "No Repo calls in controllers — use context modules"
    - "No String.to_atom/1 on user input"
    - "RabbitMQ/Kafka consumers must be idempotent"
```

**`CLAUDE.md`** — đã có sẵn (32 architecture rules) → Claude tự đọc.

---

### Ví dụ 2: Vue 3 SPA (builderx_spa)

**`.github/workflows/code-review.yml`** — **giống hệt** ví dụ 1.

**`.claude/review-config.yml`** — tuỳ chỉnh cho Vue:

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

### Ví dụ 3: Go microservice (không có CLAUDE.md)

**`.github/workflows/code-review.yml`** — **giống hệt** ví dụ 1.

**Không cần thêm file nào**. Claude sẽ tự:
- Detect Go từ `go.mod`
- Đọc `README.md`
- Review theo Go best practices (error handling, goroutine leaks, defer usage...)

**(Optional)** Thêm `.claude/review-config.yml` nếu muốn:

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

### Ví dụ 4: Python Django (không có CLAUDE.md)

**`.github/workflows/code-review.yml`** — **giống hệt** ví dụ 1.

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

### Ví dụ 5: React/Next.js (chỉ cần workflow, không tuỳ chỉnh)

**`.github/workflows/code-review.yml`** — **giống hệt** ví dụ 1. Xong.

Claude tự detect từ `package.json` + `next.config.*` và review theo React/Next.js best practices.

---

## Inputs reference

| Input | Required | Default | Mô tả |
|-------|----------|---------|-------|
| `claude_token` | **Yes** | — | Claude OAuth token (từ `claude setup-token`) |
| `github_token` | **Yes** | — | GitHub token (dùng `${{ secrets.GITHUB_TOKEN }}`) |
| `pr_number` | No | auto-detect | Số PR — tự detect từ event, chỉ cần khi `workflow_dispatch` |
| `max_turns` | No | `30` | Số lượt tối đa Claude được thao tác |
| `model` | No | `claude-sonnet-4-20250514` | Model Claude sử dụng |
| `review_prompt` | No | built-in | Override toàn bộ review prompt (advanced) |
| `extra_prompt` | No | — | Thêm instructions vào cuối prompt |

### Đổi model

```yaml
- uses: vuluu2k/claude-gh-actions@v1
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    model: "claude-opus-4-6"        # Dùng Opus cho review sâu hơn (tốn hơn)
```

### Giới hạn turns

```yaml
- uses: vuluu2k/claude-gh-actions@v1
  with:
    claude_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    max_turns: 15                   # Giới hạn 15 turns (nhanh hơn, rẻ hơn)
```

## Outputs reference

| Output | Mô tả |
|--------|-------|
| `total_cost_usd` | Chi phí review (USD) |
| `num_turns` | Số turns đã dùng |
| `session_id` | Session ID (dùng để resume nếu cần) |

Đọc outputs:

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

## Cách trigger review

| Cách | Khi nào |
|------|---------|
| **Tự động** | PR opened, reopened, hoặc push commit mới |
| **Comment** | Gõ `/review` trong PR comment |
| **Thủ công** | Actions tab → Claude Code Review → Run workflow → nhập PR number |

### Chỉ trigger khi comment (không auto)

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

### Chỉ trigger manual

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

## Auto-skip

Action tự động bỏ qua khi:
- PR là **draft**
- PR author là **bot** (dependabot, renovate, etc.)

Không cần cấu hình gì.

---

## Severity levels

Review comments sẽ có badge severity:

| Badge | Ý nghĩa | Hành động |
|-------|---------|-----------|
| ![Major](https://img.shields.io/badge/Major-red?style=flat-square) | Bug, security, data loss, vi phạm architecture | **Phải fix** trước merge |
| ![Minor](https://img.shields.io/badge/Minor-orange?style=flat-square) | Design issue, thiếu error handling, regression | **Nên fix** hoặc giải thích |
| ![Nitpick](https://img.shields.io/badge/Nitpick-cyan?style=flat-square) | Style, naming, suggestion nhỏ | **Tuỳ chọn** |

---

## Usage methods

### Method 1: Direct reference (recommended)

```yaml
uses: vuluu2k/claude-gh-actions@v1
```

Không cần copy file nào vào repo. Version pinned bằng tag.

### Method 2: Git subtree (nếu cần sửa prompt)

```bash
# Thêm vào repo
git subtree add --prefix=.github/actions/review \
    git@github.com:vuluu2k/claude-gh-actions.git main --squash

# Dùng trong workflow
uses: ./.github/actions/review

# Cập nhật
git subtree pull --prefix=.github/actions/review \
    git@github.com:vuluu2k/claude-gh-actions.git main --squash
```

---

## Release quy trình (cho maintainer)

```bash
# Tag version mới
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# Move major version tag (v1) đến latest
git tag -fa v1 -m "Update v1 to v1.0.0"
git push origin v1 --force
```

Tất cả repo dùng `@v1` sẽ tự động nhận bản mới. Pin cụ thể: `@v1.0.0`.
