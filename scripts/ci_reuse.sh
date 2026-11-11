#!/usr/bin/env bash
# Decides whether a workflow may skip the macOS build and tests, so every change
# is tested once instead of again after the merge and again for the release tag.
#   scripts/ci_reuse.sh [base-sha]
# Skips when
#   - a pull request or push changes only Markdown files or docs/,
#   - a push to main is the squash merge of a pull request whose head has the
#     same tree and a green "test" check,
#   - a release tag points at a commit with a green "test" check (CI on main).
# Manual runs never skip. Prints the reason and writes skip=true|false to
# $GITHUB_OUTPUT. Needs GH_TOKEN; any failed lookup means "run the tests".
set -uo pipefail

sha="${GITHUB_SHA:-$(git rev-parse HEAD)}"
repo="${GITHUB_REPOSITORY:-FNG-2002/macprompter}"
event="${GITHUB_EVENT_NAME:-push}"
ref="${GITHUB_REF:-refs/heads/main}"
base="${1:-}"

decide() {
    echo "$2"
    [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "skip=$1" >>"$GITHUB_OUTPUT"
    exit 0
}

green() {
    local count
    count="$(gh api "repos/$repo/commits/$1/check-runs?check_name=test" \
        --jq '[.check_runs[] | select(.conclusion == "success")] | length' 2>/dev/null)" || return 1
    [[ "${count:-0}" -gt 0 ]]
}

fetch() { git cat-file -e "$1^{commit}" 2>/dev/null || git fetch --quiet --no-tags --depth=1 origin "$1" 2>/dev/null; }

[[ "$event" == "workflow_dispatch" ]] && decide false "Manual run: build and test."

if [[ "$ref" == refs/tags/* ]]; then
    green "$sha" && decide true "CI already passed for $sha on main: skipping tests."
    decide false "No green CI run for $sha yet: build and test."
fi

if [[ -n "$base" && ! "$base" =~ ^0+$ ]] && fetch "$base"; then
    changed="$(git diff --name-only "$base" "$sha")"
    if [[ -n "$changed" ]] && ! grep -vqE '(\.md$|^docs/)' <<<"$changed"; then
        decide true "Only documentation changed: skipping build and tests."
    fi
fi

if [[ "$event" == "push" ]]; then
    head="$(gh api "repos/$repo/commits/$sha/pulls" --jq '.[0].head.sha // empty' 2>/dev/null)"
    if [[ -n "$head" ]] && fetch "$head" \
        && [[ "$(git rev-parse "$sha^{tree}")" == "$(git rev-parse "$head^{tree}")" ]] && green "$head"; then
        decide true "Same tree as the green pull request head $head: skipping tests."
    fi
fi

decide false "Build and test."
