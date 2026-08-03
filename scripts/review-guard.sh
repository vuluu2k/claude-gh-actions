#!/usr/bin/env bash
# Token-saving guard for the Claude Code Review action.
# Decides WHETHER to review, and if so whether to review the FULL PR or only
# the commits pushed since the previous review.
#
# Rules:
#   1. Merged / closed / draft / bot PR            -> skip (nobody reads that review).
#   2. Duplicate PR                                -> skip, link to the PR already reviewed.
#      Hotfixes are commonly opened twice (once against master, once against develop):
#        (a) same head branch + same head commit
#        (b) cherry-picked onto a sibling branch -> compared by diff-content fingerprint
#   3. New commits pushed                          -> review only those commits, with the
#      previous review's findings as context (were they addressed?).
#
# Outputs (GITHUB_OUTPUT): skip, skip_reason, mode, head_sha, diff_fp,
#                          since_sha, new_commits, incremental_prompt
set -euo pipefail

: "${REPO:?}" "${PR:?}" "${GITHUB_OUTPUT:?}"

SKIP_MERGED="${SKIP_MERGED:-true}"
DEDUP="${DEDUP_SIMILAR_PRS:-true}"
INCREMENTAL="${INCREMENTAL_REVIEW:-true}"
FORCE="${FORCE:-false}"

MARKER_RE='<!-- claude-review-state'
PATCH_DIR=/tmp/pr-context
PATCH_FILE="${PATCH_DIR}/incremental.patch"
META_FILE="${PATCH_DIR}/pr-meta.json"
MAX_PATCH_BYTES="${MAX_INCREMENTAL_BYTES:-300000}"
MARK_SCRIPT="$(dirname "$0")/review-mark.sh"

mkdir -p "$PATCH_DIR"

out() { printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; }

out_multiline() {
  { printf '%s<<CLAUDE_PROMPT_EOF\n' "$1"; printf '%s\n' "$2"; printf 'CLAUDE_PROMPT_EOF\n'; } >> "$GITHUB_OUTPUT"
}

skip() {
  echo "::notice::Skipping review — $1"
  out skip true
  out skip_reason "$1"
  exit 0
}

markers_of() {
  gh api "repos/${REPO}/issues/$1/comments" --paginate \
    --jq ".[] | select(.body | test(\"${MARKER_RE}\")) | .body" 2>/dev/null || true
}

last_reviewed_sha() { markers_of "$1" | grep -oE 'sha=[0-9a-f]{7,40}' | tail -1 | cut -d= -f2 || true; }
last_reviewed_fp()  { markers_of "$1" | grep -oE 'fp=[0-9a-f]{8,64}'  | tail -1 | cut -d= -f2 || true; }

# Fingerprint of a diff (stdin). `index <sha>..<sha>` lines and `@@` hunk headers are
# dropped because they shift with the base — so the same change cherry-picked onto a
# different branch still fingerprints identically.
diff_fingerprint() {
  sed -E '/^index [0-9a-f]+\.\.[0-9a-f]+/d; /^@@ /d; /^similarity index /d; /^dissimilarity index /d' \
    | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-16
}

# Reduce a branch name to its stem so sibling branches match:
# 4587-master / 4587-from-develop / 4587_no_develop -> 4587
branch_stem() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#^(from[-_/])##; s#[-_](no[-_])?(from[-_])?(spa[-_])?(master|develop|dev|staging|main)$##; s#[-_](spa)$##' \
    | sed -E 's#[-_]+$##'
}

norm_title() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed -E 's/^ | $//g'; }

# ------------------------------------------------------------------ PR metadata
# Written to pr-meta.json as well: the review prompt reads it instead of calling gh.
gh pr view "$PR" --repo "$REPO" \
  --json number,state,isDraft,files,commits,headRefName,headRefOid,baseRefName,title,body,author \
  > "$META_FILE"

STATE=$(jq -r '.state' "$META_FILE")
IS_DRAFT=$(jq -r '.isDraft' "$META_FILE")
HEAD_REF=$(jq -r '.headRefName' "$META_FILE")
HEAD_SHA=$(jq -r '.headRefOid' "$META_FILE")
BASE_REF=$(jq -r '.baseRefName' "$META_FILE")
AUTHOR=$(jq -r '.author.login' "$META_FILE")
TITLE=$(jq -r '.title' "$META_FILE")

out skip false
out head_sha "$HEAD_SHA"
echo "PR #${PR} | ${HEAD_REF} -> ${BASE_REF} | ${HEAD_SHA} | state=${STATE} draft=${IS_DRAFT} author=${AUTHOR}"

# ------------------------------------------------------------------ rule 1
if [[ "$AUTHOR" == *"[bot]"* ]] || [[ "$AUTHOR" == *"dependabot"* ]]; then
  skip "PR authored by a bot (${AUTHOR})"
fi
if [ "$FORCE" != true ]; then
  if [ "$SKIP_MERGED" = true ] && [ "$STATE" != "OPEN" ]; then
    skip "PR is ${STATE} — a review would land after the fact"
  fi
  if [ "$IS_DRAFT" = "true" ]; then
    skip "PR is a draft"
  fi
fi

# ------------------------------------------------------------------ rule 2a: twin PR, same commit
if [ "$DEDUP" = true ] && [ "$FORCE" != true ]; then
  SIBLINGS=$(gh pr list --repo "$REPO" --state all --head "$HEAD_REF" --limit 30 \
    --json number,headRefOid \
    | jq -r --arg sha "$HEAD_SHA" --argjson pr "$PR" \
        '.[] | select(.number != $pr) | select(.headRefOid == $sha) | .number')

  for SIB in $SIBLINGS; do
    if [ "$(last_reviewed_sha "$SIB")" = "$HEAD_SHA" ]; then
      SIB_BASE=$(gh pr view "$SIB" --repo "$REPO" --json baseRefName --jq '.baseRefName')
      bash "$MARK_SCRIPT" "$PR" "$HEAD_SHA" "$(gh pr diff "$PR" --repo "$REPO" 2>/dev/null | diff_fingerprint)" \
        "Same content was already reviewed in #${SIB} (same branch \`${HEAD_REF}\`, same commit, base \`${SIB_BASE}\`) — skipped to avoid a duplicate review."
      skip "duplicate of PR #${SIB} (same head commit, already reviewed)"
    fi
  done
fi

# ------------------------------------------------------------------ rule 2b: twin PR, cherry-picked
DIFF_FP=$(gh pr diff "$PR" --repo "$REPO" 2>/dev/null | diff_fingerprint || true)
out diff_fp "${DIFF_FP:-}"
echo "Diff fingerprint of PR #${PR}: ${DIFF_FP:-<empty>}"

if [ "$DEDUP" = true ] && [ "$FORCE" != true ] && [ -n "${DIFF_FP:-}" ]; then
  STEM=$(branch_stem "$HEAD_REF")
  TITLE_KEY=$(norm_title "$TITLE")

  CANDIDATES=$(gh pr list --repo "$REPO" --state all --limit 60 \
    --json number,headRefName,title,author \
    | jq -r --argjson pr "$PR" '.[] | select(.number != $pr) | [.number, .headRefName, .author.login, .title] | @tsv')

  CHECKED=0
  while IFS=$'\t' read -r C_NUM C_REF C_AUTHOR C_TITLE; do
    [ -n "${C_NUM:-}" ] || continue
    [ "$CHECKED" -lt 6 ] || break

    MATCH=""
    if [ -n "$STEM" ] && [ "$(branch_stem "$C_REF")" = "$STEM" ] && [ "$C_REF" != "$HEAD_REF" ]; then
      MATCH="sibling branch of \`${STEM}\`"
    elif [ "$(norm_title "$C_TITLE")" = "$TITLE_KEY" ] && [ "$C_AUTHOR" = "$AUTHOR" ]; then
      MATCH="same title and author"
    fi
    [ -n "$MATCH" ] || continue

    CHECKED=$((CHECKED + 1))
    if [ "$(last_reviewed_fp "$C_NUM")" = "$DIFF_FP" ]; then
      bash "$MARK_SCRIPT" "$PR" "$HEAD_SHA" "$DIFF_FP" \
        "Identical diff was already reviewed in #${C_NUM} (${MATCH}) — skipped to avoid a duplicate review."
      skip "duplicate of PR #${C_NUM} (identical diff fingerprint ${DIFF_FP})"
    fi
  done <<< "$CANDIDATES"
fi

# ------------------------------------------------------------------ rule 3: incremental
SINCE=""
if [ "$INCREMENTAL" = true ] && [ "$FORCE" != true ]; then
  SINCE=$(last_reviewed_sha "$PR")
  # Never reviewed here, but the twin PR (master/develop) was -> start from its mark.
  if [ -z "$SINCE" ]; then
    for SIB in $(gh pr list --repo "$REPO" --state all --head "$HEAD_REF" --limit 30 \
      --json number --jq ".[] | select(.number != ${PR}) | .number"); do
      CAND=$(last_reviewed_sha "$SIB")
      if [ -n "$CAND" ]; then SINCE="$CAND"; echo "Using review mark from twin PR #${SIB}: ${SINCE}"; break; fi
    done
  fi
fi

MODE=full
NEW_COMMITS=0

if [ -n "$SINCE" ]; then
  # An issue_comment run checks out the default branch, so PR objects may be missing.
  git cat-file -e "${SINCE}^{commit}" 2>/dev/null \
    || git fetch --no-tags --quiet origin "$SINCE" 2>/dev/null || true
  git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null \
    || git fetch --no-tags --quiet origin "$HEAD_SHA" 2>/dev/null || true

  if ! git cat-file -e "${SINCE}^{commit}" 2>/dev/null || ! git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null; then
    echo "::warning::Commit ${SINCE} / ${HEAD_SHA} not present locally (missing fetch-depth: 0?) — falling back to full review."
  elif ! git merge-base --is-ancestor "$SINCE" "$HEAD_SHA" 2>/dev/null; then
    echo "::warning::Mark ${SINCE} is no longer an ancestor of HEAD (force-push/rebase) — falling back to full review."
  else
    NEW_COMMITS=$(git rev-list --no-merges --count "${SINCE}..${HEAD_SHA}")
    if [ "$NEW_COMMITS" -eq 0 ]; then
      skip "no new commits since the last review (${SINCE:0:7})"
    fi
    git log -p --no-merges --reverse --stat "${SINCE}..${HEAD_SHA}" > "$PATCH_FILE"
    SIZE=$(wc -c < "$PATCH_FILE")
    if [ "$SIZE" -gt "$MAX_PATCH_BYTES" ]; then
      echo "::notice::Incremental diff too large (${SIZE} bytes) — falling back to full review."
      rm -f "$PATCH_FILE"
    else
      MODE=incremental
      echo "Incremental: ${NEW_COMMITS} new commit(s) since ${SINCE:0:7} (${SIZE} bytes)"
    fi
  fi
fi

out mode "$MODE"
out since_sha "$SINCE"
out new_commits "$NEW_COMMITS"

if [ "$MODE" = incremental ]; then
  out_multiline incremental_prompt "## INCREMENTAL REVIEW MODE (highest priority — overrides Step 2, Step 3 and Step 6)

This PR was already reviewed up to commit \`${SINCE}\`. Everything up to that commit already has review comments.

Do NOT read \`/tmp/pr-context/pr-diff.patch\` (the full PR diff) — re-reading already-reviewed code is the single biggest token waste.

Instead:
1. Read \`/tmp/pr-context/incremental.patch\` — the ${NEW_COMMITS} NEW commit(s) (with patches) pushed since the last review. This is your entire review scope.
2. Read \`/tmp/pr-context/pr-comments.json\` — the findings from the previous review.
3. Then:
   - Check each previous finding against the new commits. If it is now fixed, reply in that existing thread (\"Resolved\") and do NOT repeat it in the summary.
   - Look for NEW defects introduced by the new commits only. Step 5 deep analysis still applies — you may open repo files for context — but do not re-review code that is not in incremental.patch.
   - Previous findings still open: list them in the \"Previous Review Follow-up\" table only, no new inline comments.
4. If the new commits are clean, post one short confirmation comment instead of a full summary.

Skip the Walkthrough table and the Mermaid diagram in this mode — keep the summary compact."
else
  out_multiline incremental_prompt ""
fi
