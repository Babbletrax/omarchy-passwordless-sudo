#!/usr/bin/env bash
# Bring changes merged on GitHub back into GitLab, through a merge request.
#
# GitLab pushes main to GitHub (push mirror). When a pull request is merged on
# GitHub instead, this job notices that GitHub's main is ahead and opens a
# GitLab merge request with exactly those commits. The MR runs the full
# pipeline (including the private leak check) and merges itself when it
# passes. Fast-forward merges keep the commit IDs identical on both sides.
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

echo "github-sync: GitHub is ahead (${gitlab_sha:0:7} -> ${github_sha:0:7}); opening a merge request"
git push --quiet --force \
  "https://github-sync:${GITLAB_SYNC_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" \
  "${github_sha}:refs/heads/${branch}"

mr_iid="$(api "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests?state=opened&source_branch=${branch//\//%2F}" | jq -r '.[0].iid // empty')"
if [[ -z "$mr_iid" ]]; then
  mr_iid="$(api -X POST "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests" \
    --data-urlencode "source_branch=$branch" \
    --data-urlencode "target_branch=main" \
    --data-urlencode "title=Sync changes merged on GitHub" \
    --data-urlencode "description=Commits merged on GitHub that GitLab does not have yet. Merges automatically once the pipeline passes." \
    --data-urlencode "remove_source_branch=true" | jq -r .iid)"
  echo "github-sync: opened merge request !$mr_iid"
else
  echo "github-sync: updated merge request !$mr_iid"
fi

# Ask GitLab to merge when the pipeline passes. The pipeline for the pushed
# commit may take a moment to appear, so retry briefly.
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
