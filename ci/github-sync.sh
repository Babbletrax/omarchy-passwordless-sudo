#!/usr/bin/env bash
# Bring changes merged on GitHub back into GitLab, through a merge request.
#
# GitLab pushes main to GitHub (push mirror). When a pull request is merged on
# GitHub instead, this job notices that GitHub's main is ahead and opens a
# GitLab merge request with exactly those commits, labelled by risk:
#   low     pipeline runs and the MR merges itself when it passes
#   medium  waits for a one-tap approval (sent to the owner via Telegram)
#   high    waits for a typed approval
# Medium and high risk changes run no pipeline until approved. Fast-forward
# merges keep the commit IDs identical on both sides.
#
# Runs in GitLab CI only. Needs:
#   GITHUB_SYNC_URL    public clone URL of the GitHub repo (unset = sync off)
#   GITLAB_SYNC_TOKEN  project access token with api + write_repository
set -euo pipefail

: "${CI_API_V4_URL:?}" "${CI_PROJECT_ID:?}" "${CI_SERVER_HOST:?}" "${CI_PROJECT_PATH:?}"
if [[ -z "${GITHUB_SYNC_URL:-}" ]]; then
  echo "github-sync: GITHUB_SYNC_URL is not set, sync is switched off"
  exit 0
fi
: "${GITLAB_SYNC_TOKEN:?github-sync: GITLAB_SYNC_TOKEN is required}"

readonly branch="sync/github-main"
api() { curl -fsS -H "PRIVATE-TOKEN: $GITLAB_SYNC_TOKEN" "$@"; }

git fetch --quiet --no-tags "$GITHUB_SYNC_URL" main
github_sha="$(git rev-parse FETCH_HEAD)"
git fetch --quiet --no-tags origin main
gitlab_sha="$(git rev-parse origin/main)"

if [[ "$github_sha" == "$gitlab_sha" ]]; then
  echo "github-sync: in sync at ${gitlab_sha:0:7}"
  exit 0
fi
if git merge-base --is-ancestor "$github_sha" "$gitlab_sha"; then
  echo "github-sync: GitLab is ahead; the push mirror will update GitHub"
  exit 0
fi
if ! git merge-base --is-ancestor "$gitlab_sha" "$github_sha"; then
  echo "github-sync: GitHub (${github_sha:0:7}) and GitLab (${gitlab_sha:0:7}) have diverged." >&2
  echo "github-sync: rebase one onto the other by hand; nothing was changed." >&2
  exit 1
fi

# Risk is judged by this trusted copy of ci/risk-report.sh (from main), never
# by the incoming change.
report="$(bash ci/risk-report.sh "$gitlab_sha" "$github_sha")"
risk="${report%%$'\n'*}"; risk="${risk#risk=}"
report_body="${report#*$'\n'}"
echo "github-sync: GitHub is ahead (${gitlab_sha:0:7} -> ${github_sha:0:7}), risk: $risk"

enc_branch="${branch//\//%2F}"
open_mr="$(api "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests?state=opened&source_branch=$enc_branch")"
mr_iid="$(jq -r '.[0].iid // empty' <<<"$open_mr")"
if [[ -n "$mr_iid" && "$(jq -r '.[0].sha' <<<"$open_mr")" == "$github_sha" ]]; then
  echo "github-sync: merge request !$mr_iid already covers ${github_sha:0:7}; nothing to do"
  exit 0
fi
rejected="$(api "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests?state=closed&labels=rejected&source_branch=$enc_branch&per_page=100" \
  | jq -r --arg sha "$github_sha" '[.[] | select(.sha == $sha)][0].iid // empty')"
if [[ -n "$rejected" ]]; then
  echo "github-sync: WARNING ${github_sha:0:7} was rejected in !$rejected; revert it on GitHub. Not re-opening." >&2
  exit 0
fi

# Medium and high risk: push without running a pipeline, so none of the
# incoming code runs on the homelab runner until the owner approves.
push_opts=()
[[ "$risk" == low ]] || push_opts=(-o ci.skip)
git push --quiet --force "${push_opts[@]}" \
  "https://github-sync:${GITLAB_SYNC_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" \
  "${github_sha}:refs/heads/${branch}"

case "$risk" in
  low)    labels="risk::low" ; how="Low risk: merges automatically once the pipeline passes." ;;
  medium) labels="risk::medium,awaiting-approval" ; how="Medium risk: waiting for a one-tap approval. No pipeline runs until then." ;;
  high)   labels="risk::high,awaiting-approval" ; how="High risk: waiting for a typed approval (\`APPROVE ${mr_iid:-<iid>} ${github_sha:0:6}\`). No pipeline runs until then." ;;
esac
description="<!-- sync-approval risk=$risk sha=$github_sha base=$gitlab_sha -->
Commits merged on GitHub that GitLab does not have yet.

$how

$report_body"

if [[ -z "$mr_iid" ]]; then
  mr_iid="$(api -X POST "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests" \
    --data-urlencode "source_branch=$branch" \
    --data-urlencode "target_branch=main" \
    --data-urlencode "title=Sync from GitHub (${risk} risk)" \
    --data-urlencode "description=$description" \
    --data-urlencode "labels=$labels" \
    --data-urlencode "remove_source_branch=true" | jq -r .iid)"
  echo "github-sync: opened merge request !$mr_iid"
  # The typed code needs the MR number, which only exists now.
  description="${description//APPROVE <iid>/APPROVE $mr_iid}"
  api -X PUT "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests/$mr_iid" \
    --data-urlencode "description=$description" >/dev/null
else
  api -X PUT "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests/$mr_iid" \
    --data-urlencode "title=Sync from GitHub (${risk} risk)" \
    --data-urlencode "description=$description" \
    --data-urlencode "labels=$labels" >/dev/null
  echo "github-sync: updated merge request !$mr_iid (any earlier approval no longer applies)"
fi

if [[ "$risk" != low ]]; then
  echo "github-sync: !$mr_iid is waiting for the owner's approval"
  exit 0
fi

# Low risk: merge when the pipeline passes. The pipeline for the pushed commit
# may take a moment to appear, so retry briefly.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if api -X PUT "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests/$mr_iid/merge" \
      --data "merge_when_pipeline_succeeds=true&sha=$github_sha" >/dev/null 2>&1; then
    echo "github-sync: !$mr_iid will merge when its pipeline passes"
    exit 0
  fi
  sleep 10
done
echo "github-sync: could not enable auto-merge on !$mr_iid; merge it by hand once green" >&2
exit 1
