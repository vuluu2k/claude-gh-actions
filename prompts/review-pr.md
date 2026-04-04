# Review Pull Request

Create GitHub PR reviews with inline line-level comments and a structured summary. Reviews are **scope-based** — focus adapts based on commit types.

## CI Rules (IMPORTANT — applies to ALL steps)

- No shell redirects (`>`), pipes (`|`), chains (`&&`/`||`), or command substitution (`$(cmd)`).
- One simple command per Bash call.
- Do NOT put multi-line strings in Bash command arguments.
- Use **Write** tool (not `cat`/`echo`) to create files.
- **ALWAYS** use Write tool → `/tmp/review.json` → `gh api --input` for submitting reviews. NEVER use inline body text with `gh api --field` or `gh pr review --body`.

## Step 0: Build Project Context

Gather context in priority order:

1. **Read `CLAUDE.md`** at repo root → extract architecture rules, naming conventions, constraints
2. **Read `.claude/review-config.yml`** → extract ignore/include patterns, extra rules
3. **If neither exists**, auto-discover:
   - Read `README.md` for project overview
   - Detect stack from config files (`mix.exs`, `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `pubspec.yaml`, `Gemfile`, `pom.xml`/`build.gradle`)
   - Check linter configs (`.eslintrc*`, `.rubocop.yml`, `.golangci.yml`, `credo.exs`, `ruff.toml`)
   - Scan 2-3 existing source files to understand code style

**Priority**: `CLAUDE.md` > `review-config.yml` extra_rules > auto-detected conventions > generic best practices.

**No CLAUDE.md?** Apply universal rules: security (injection, auth bypass, secrets), correctness (null safety, off-by-one, race conditions), performance (N+1, unbounded loops, memory leaks), maintainability (dead code, duplication, unclear naming), concurrency (data races, deadlocks).

## Step 1: Parse Input

Extract `owner/repo` and PR number from URL or use current directory git context.

## Step 2: Fetch PR Data

```bash
gh pr view <NUMBER> --json files,commits,headRefOid,baseRefName,title,body [--repo owner/repo]
gh pr diff <NUMBER> [--repo owner/repo]
```

**PR body as context:** Read `What happened?` (author's intent) and `Insights` (non-obvious context) before analyzing code. Empty PR body = Minor issue.

**Large diffs (>500 lines):** Use `gh pr diff <N> --name-only` first, then fetch per-file via `gh api repos/{owner}/{repo}/pulls/<N>/files`. Filter (Step 3) before fetching diffs.

### Step 2b: Re-review Support

Check for previous review comments:
```bash
gh api repos/{owner}/{repo}/pulls/<NUMBER>/comments --jq '[.[] | {id, path, line, body, created_at, user: .user.login, in_reply_to_id}]'
```

For each previous comment, classify based on replies and current code state:
- **Resolved**: code changed, issue addressed
- **Unresolved**: code unchanged or issue persists
- **Outdated**: file/line no longer in diff
- **Withdrawn**: author rebuttal was valid — do NOT repeat the issue
- **Discussed**: debatable — acknowledge author's point in follow-up

**Key principle:** When PR author provides a valid technical rebuttal, accept it. Review accuracy > consistency.

**No previous comments?** Skip this step.

## Step 3: Filter Files (Token Optimization)

Apply BEFORE reading any diffs. Skip these patterns:

| Category | Patterns |
|----------|----------|
| **Lock files** | `*-lock.*`, `*.lock`, `*.lockb`, `go.sum` |
| **Build/output** | `build/`, `dist/`, `out/`, `target/`, `_build/`, `deps/`, `node_modules/`, `.next/`, `.nuxt/`, `.output/`, `.dart_tool/`, `__pycache__/`, `.tox/`, `vendor/` |
| **Generated** | `*.generated.*`, `*.gen.*`, `*.g.dart`, `*.freezed.dart`, `*.pb.*`, `*_pb2.py`, `*.swagger.*`, `*.openapi.*`, `generated/`, `__generated__/`, `*.graphql.ts`, `*.graphql.dart` |
| **Assets/binary** | Images, fonts, media, archives (`*.png`, `*.jpg`, `*.woff2`, `*.mp4`, `*.pdf`, `*.zip`, etc.) |
| **IDE** | `.idea/`, `.vscode/`, `*.iml`, `.elixir_ls/`, `.DS_Store` |
| **Minified/maps** | `*.min.js`, `*.min.css`, `*.bundle.js`, `*.chunk.js`, `*.map` |
| **Snapshots** | `__snapshots__/`, `*.snap`, `fixtures/` (unless test-related) |
| **Deletion-only** | Files with `additions: 0` |

**Per-repo overrides** from `.claude/review-config.yml`:
```yaml
review:
  ignore_patterns: ["custom/path/*"]      # Added to defaults
  include_patterns: ["generated/important.ts"]  # Force-include
  extra_rules: ["Custom review rule"]
```

Filter implementation:
```bash
gh pr view <N> --json files --jq '.files[] | select(.additions > 0) | .path'
```

## Step 4: Determine Review Focus

| Commit Type | Focus |
|-------------|-------|
| `fix:` | Root cause solved? Regression risk? Edge cases? Test for bug? |
| `feat:` | Design sound? Follows patterns? Breaking changes? |
| `refactor:` | Behavior preserved? Actually cleaner? No mixed-in features? |
| `chore:` | Config correct? Security implications? |
| `test:` | Tests meaningful? Not testing implementation details? |
| `perf:` | Measurable? Tradeoffs acceptable? |

## Step 5: Deep Analysis (CRITICAL — do NOT skip)

**You MUST investigate the surrounding codebase before forming opinions.** Shallow diff-only reading is the #1 cause of low-quality reviews. Every sub-step below is mandatory when applicable.

**5a: Trace callers** — For every function whose behavior changed, Grep all call sites. Check for: double execution, callers depending on old behavior, performance impact in hot paths.

**5b: Read implementations** — When PR uses framework functions/utilities/library calls, read their source. Check: dedup/conflict behavior, error handling, side effects. **Never assume** — grep and read.

**5c: Stale data in async contexts** — For data stored in payloads consumed later (cron, queues, delayed events): can it change between creation and execution? Should the worker read fresh data instead?

**5d: Arithmetic/time edge cases** — Can input be nil/NaN? Can result be negative/zero/huge? Provide concrete guards, not just "add a nil check."

**5e: Orphaned resources** — When PR creates resources (tasks, subscriptions, timers, records): is the old one cleaned up? What if lookup key changes? Is there cleanup when feature is disabled?

**5f: Error path continuity** — For self-scheduling features or chained operations: what happens on failure? Does the chain break silently? Is there retry/re-schedule?

**5g: Project-specific rules** — If CLAUDE.md exists, cross-check every changed file. If not, infer conventions from 2-3 similar existing files. Only flag clear inconsistencies, focus on universal issues.

## Step 6: Analyze Changed Files

For each file passing Step 3 filter: read diff hunks, apply Step 5 findings, identify issues per Step 4 focus + project rules + `extra_rules`.

**Line number rules (CRITICAL):**
- Only comment on lines within diff hunks — lines outside cause **422 Validation Failed**
- Use `line` (source line number, NOT diff position) + `side: "RIGHT"` for new/changed lines
- Use `side: "LEFT"` only for deleted lines
- For multi-line: use `start_line` + `start_side` + `line` + `side`
- Diff header `@@ -oldStart,oldCount +newStart,newCount @@`: count from `newStart` for RIGHT, `oldStart` for LEFT

**Large PRs (>10 files):** Batch into groups of 5-8, collect all comments before composing summary.

## Step 7: Compose Review Comments

Every comment MUST have:
1. **Severity badge** (separate line)
2. **Specific description** — what goes wrong, under what conditions
3. **Evidence** — reference traced callers, implementations, or data flows from Step 5
4. **Concrete fix** — actual code, not "consider handling this"

**Bad:** "This value might be nil, which could cause issues."
**Good:** "`expire_in` comes from external API. If missing/nil, arithmetic on line N crashes. Values < buffer (86400) schedule in the past. Fix: `max((expire_in || 0) - 86400, 3600)`"

## Step 8: Submit Review

**8a** — Get commit SHA (Bash):
```bash
gh pr view <NUMBER> --json headRefOid -q '.headRefOid'
```

**8b** — Write review JSON (Write tool to `/tmp/review.json`):
```json
{
  "commit_id": "<COMMIT_SHA>",
  "body": "## PR Review Summary\n\n...",
  "event": "COMMENT",
  "comments": [
    {
      "path": "relative/path/to/file",
      "line": 42,
      "side": "RIGHT",
      "body": "Description."
    }
  ]
}
```

**8c** — Submit (Bash):
```bash
gh api repos/{owner}/{repo}/pulls/<NUMBER>/reviews --method POST --input /tmp/review.json
```

**8d** — Cleanup (Bash): `rm /tmp/review.json`

## Comment Format

**Severity badges (copy exactly):**
- `![Major](https://img.shields.io/badge/Major-red?style=for-the-badge)` — bugs, security, data loss, breaking changes, architecture violations
- `![Minor](https://img.shields.io/badge/Minor-orange?style=for-the-badge)` — design issues, missing error handling, regressions, readability
- `![Nitpick](https://img.shields.io/badge/Nitpick-cyan?style=for-the-badge)` — style, naming, optional improvements

**Expected actions:** Major = must fix | Minor = should fix or justify | Nitpick = optional

**Example:**
```
![Major](https://img.shields.io/badge/Major-red?style=for-the-badge)

Null safety — `data` can be undefined when API returns error response.

```suggestion
const value = data?.result ?? defaultValue;
```
```

## Summary Format

```markdown
## PR Review Summary

**Type**: fix | feat | refactor | ...
**Files reviewed**: N | **Issues found**: N major, N minor, N nitpick

### Findings
1. ![Major](https://img.shields.io/badge/Major-red) Brief description (`path/file:42`)
   - *Evidence*: traced caller X which already does Y
2. ![Minor](https://img.shields.io/badge/Minor-orange) Brief description (`path/file:15`)
3. ![Nitpick](https://img.shields.io/badge/Nitpick-cyan) Brief description (`path/file:8`)

### Previous Review Follow-up
> Only if previous comments found (Step 2b).

| Status | File | Issue |
|--------|------|-------|
| :white_check_mark: Resolved | `file:42` | Description |
| :x: Unresolved | `file:15` | Description |
| :arrows_counterclockwise: Withdrawn | `file:10` | Author rebuttal accepted |

**Resolved: N/N | Withdrawn: N/N | Unresolved: N/N**

### Positive Notes
- Notable good practices

### Recommendation
LGTM | Minor changes needed | Significant changes needed

---
*Reviewed by Claude Code*
```

If no issues: `LGTM! No issues found.` + files reviewed count + positive notes.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Comment on line outside diff | Verify line is within diff hunk |
| Wrong `commit_id` | Always fetch HEAD SHA with `gh pr view --json headRefOid` |
| Missing `--repo` flag | Required when outside the repo directory |
| Shallow diff-only review | ALWAYS trace callers + read implementations (Step 5) |
| Vague comments without evidence | Reference traced code: callers, implementations, data flows |
| Assuming utility behavior | Read actual implementation — never guess |
| No concrete fix suggestion | Provide actual code |
