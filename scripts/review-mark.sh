#!/usr/bin/env bash
# Upsert the Claude review "state marker" comment on a PR.
#
#   review-mark.sh <pr_number> <head_sha> [diff_fingerprint] [note]
#
# The marker is the single source of truth for how far a PR has been reviewed:
#   - sha : the next push only reviews commits added after this one
#   - fp  : fingerprint of the reviewed diff content, so a twin PR (same hotfix
#           opened against both master and develop) can detect the duplicate
# Exactly one marker comment per PR — edited in place, never appended.
set -euo pipefail

PR="$1"
SHA="$2"
FP="${3:-}"
NOTE="${4:-}"

: "${REPO:?REPO is not set}"

BODY="<!-- claude-review-state sha=${SHA}${FP:+ fp=${FP}} -->
🤖 **Claude review state** — reviewed up to \`${SHA:0:7}\`.
${NOTE}
<sub>Next push reviews only the new commits. Comment \`/review full\` to force a full re-review.</sub>"

COMMENT_ID=$(gh api "repos/${REPO}/issues/${PR}/comments" --paginate \
  --jq '.[] | select(.body | test("<!-- claude-review-state")) | .id' | tail -1)

if [ -n "${COMMENT_ID}" ]; then
  gh api -X PATCH "repos/${REPO}/issues/comments/${COMMENT_ID}" -f body="${BODY}" --silent
  echo "Updated review marker (comment ${COMMENT_ID}) on PR #${PR} -> ${SHA} fp=${FP:-none}"
else
  gh api -X POST "repos/${REPO}/issues/${PR}/comments" -f body="${BODY}" --silent
  echo "Created review marker on PR #${PR} -> ${SHA} fp=${FP:-none}"
fi
