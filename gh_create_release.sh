#!/bin/bash

### Requirements
# 1. GitHub CLI - https://cli.github.com/
# 2a. Generate GitHub Personal Access Token - https://github.com/settings/tokens
# 2b. Scope: repo(all), admin:org(read:org), admin:public_key(read:public_key)

### Usage
# bash scripts/gh_create_release.sh ${GITHUB_REPOSITORY} ${RELEASE_VERSION}
###

set -e
_GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-$1}"
_RELEASE_VERSION="${RELEASE_VERSION:-$2}"
_GITHUB_TOKEN="${GITHUB_TOKEN:-$3}"
_VERBOSE="${VERBOSE:-"true"}"
_DEBUG="${DEBUG:-"false"}"
_SAVE_RESULTS="${SAVE_RESULTS:-"true"}"
_RESULTS_PATH="${RESULTS_PATH:-".github-release-$(date +%s).json"}"

msg_error(){
    local msg="$1"
    local exit_code=${2:-1}
    echo -e ">> [ERROR]: $msg"
    exit "$exit_code"
}


msg_log(){
    local msg="$1"
    if [[ $_VERBOSE = "true" ]]; then
        echo -e ">> [LOG]: $msg"
    fi
}


# Arguments validation
if [[ -z $_RELEASE_VERSION ]]; then
    msg_error "Missing argument RELEASE_VERSION"
elif [[ -z $_GITHUB_REPOSITORY ]]; then
    msg_error "Missing argument GITHUB_REPOSITORY"
elif [[ -z  $_GITHUB_TOKEN ]]; then
    msg_error "Missing argument GITHUB_TOKEN"
fi


# Authenticate with GitHub
gh config set prompt disabled
if [[ "$_DEBUG" != "true" ]] ; then
    gh auth login --with-token "$_GITHUB_TOKEN"
fi

# Version validation before publishing
source version_validation.sh "$_RELEASE_VERSION"

# Create release in GitHub
set +e
read -r _EXIT_MSG < <(gh release create "$_RELEASE_VERSION" -t "$_RELEASE_VERSION" -R "${_GITHUB_REPOSITORY}")
_EXIT_CODE=$?
gh config set prompt enabled
if [[ $_EXIT_CODE -eq 0 ]]; then
    msg_log "Created release ${_RELEASE_VERSION} for ${_GITHUB_REPOSITORY}"
else
    [[ -z $_EXIT_MSG ]] && _EXIT_MSG="Error log above"
    msg_error "$_EXIT_MSG" "$_EXIT_CODE"
fi
