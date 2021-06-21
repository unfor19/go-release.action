#!/bin/bash

set -eu
set -o pipefail

### Functions
error_msg(){
  local msg="$1"
  echo -e "[ERR] $msg"
  exit 1
}

log_msg(){
  local msg="$1"
  echo -e "[LOG] $msg"
}

version_validation(){
  local release_version="$1"
  if [[ $release_version =~ ^[0-9]+(\.[0-9]*)*(\.[0-9]+(a|b|rc)|(\.post)|(\.dev))*[0-9]+$ ]]; then
    log_msg "Passed - Release version is valid - $release_version"
  else
    error_msg "Failed - Release version is invalid - $release_version"
  fi
}

bump_version(){
  # SemVer Regex: ^[0-9]+(\.[0-9]*)*(\.[0-9]+(a|b|rc)|(\.post)|(\.dev))*[0-9]+$
  local version="$1"
  local delimiter="."
  local version_last_block
  local version_last_block_bumped
  local version_last_block_numbers
  local bumped_version
  version_last_block="$(echo "$version" | rev | cut -d${delimiter} -f1 | rev)"
  if  [[ "$version_last_block" =~ ^[0-9]+[a-zA-Z]+[0-9]+$ ]]; then
    # Number and string and number
    version_last_block_numbers=$(echo "$version_last_block" | sed 's~[A-Za-z]~ ~g' | rev | cut -d' ' -f1)
    version_last_block_bumped="$((version_last_block_numbers+1))"
  elif [[ "$version_last_block" =~ ^[0-9]+[a-zA-Z]+$ ]]; then
    # Number and string
    version_last_block_numbers=$(echo "$version_last_block" | tr -dc '0-9')
    version_last_block_bumped="$((version_last_block_numbers+1))"
  elif [[ "$version_last_block" =~ ^[0-9]+$ ]]; then
    # Number only
    version_last_block_bumped="$((version_last_block+1))"
  else
    error_msg "Unknown pattern"
  fi

  bumped_version="${version%.*}.${version_last_block/$version_last_block_numbers/$version_last_block_bumped}"

  if [[ "$bumped_version" =~ ${version} ]]; then
    error_msg "Version did not bump - ${bumped_version}"
  fi

  echo "$bumped_version"
}

build(){
  local project_root="/go/src/github.com/${GITHUB_REPOSITORY}"
  local output
  local file_extenstion
  mkdir -p "$project_root"
  rmdir "$project_root"
  ln -s "$GITHUB_WORKSPACE" "$project_root"
  cd "$project_root"
  # go get -v ./...
  go mod download

  file_extenstion=''

  if [[ "$GOOS" = 'windows' ]]; then
    file_extenstion='.exe'
  fi

  go build "${_CMD_PATH}"
  output="${_PROJECT_NAME}${file_extenstion}"

  echo "$output"
}

_CMD_PATH="${CMD_PATH:-""}"
_PRE_RELEASE="${PRE_RELEASE:-""}"
_PRE_RELEASE_FLAG=""

if [[ -z "$_CMD_PATH" ]]; then
  log_msg "CMD_PATH not set"
fi

log_msg "Event Type: $GITHUB_EVENT_NAME"
if [[ "$_PRE_RELEASE" = "" &&  "$GITHUB_EVENT_NAME" = "push" ]] || [[ "$_PRE_RELEASE" = "true" ]]; then
  _PRE_RELEASE_FLAG="--prerelease"
fi

EVENT_DATA=$(cat "$GITHUB_EVENT_PATH")
if [[ "$GITHUB_EVENT_NAME" = "release" ]]; then
  ### Use this release
  _UPLOAD_URL=$(echo "$EVENT_DATA" | jq -r .release.upload_url)
  _UPLOAD_URL=${_UPLOAD_URL/\{?name,label\}/}
  RELEASE_NAME=$(echo "$EVENT_DATA" | jq -r .release.tag_name)
elif [[ "$GITHUB_EVENT_NAME" = "push" ]]; then
  ### Creates a new release and use it
  # Authenticate with GitHub
  gh config set prompt disabled
  if gh auth status 2>/dev/null ; then
    log_msg "Authenticated with GitHub CLI"
  else
    gh config set prompt enabled
    log_msg "Attempting to login to GitHub with the GitHub CLI and GITHUB_TOKEN"
    echo "$GITHUB_TOKEN" | gh auth login --with-token
  fi

  # Bump version and create release
  log_msg "Getting latest release version ..."
  LATEST_VERSION="$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/latest | grep "tag_name" | cut -d ':' -f2 | cut -d '"' -f2)"
  if [[ -z "$LATEST_VERSION" ]]; then
    error_msg "Error getting latest release version"
  fi
  log_msg "Latest Release version: ${LATEST_VERSION}"
  version_validation "${LATEST_VERSION}"
  RELEASE_NAME=$(bump_version "$LATEST_VERSION")
  log_msg "Bumped Latest Release version: ${LATEST_VERSION}"

  # Create Release (no assets yet)
  if gh release create "$RELEASE_NAME" -t "$RELEASE_NAME" -R "${GITHUB_REPOSITORY}" $_PRE_RELEASE_FLAG ; then
    log_msg "Successfully created the release https://github.com/${GITHUB_REPOSITORY}/releases/tag/${RELEASE_NAME}"
  fi

  _UPLOAD_URL=$(gh release view -R "${GITHUB_REPOSITORY}" --json uploadUrl --jq .uploadUrl 2>/dev/null)
else
  error_msg "Unhandled event type - ${GITHUB_EVENT_PATH}"
fi

log_msg "Target release version: ${RELEASE_NAME}"
log_msg "Target release upload url for assets: ${_UPLOAD_URL}"

# shellcheck disable=SC1091
version_validation "$RELEASE_NAME"

_PUBILSH_CHECKSUM_SHA256="${PUBILSH_CHECKSUM_SHA256:-"true"}"
_PUBILSH_CHECKSUM_MD5="${PUBILSH_CHECKSUM_MD5:-"false"}"
_PROJECT_NAME=$(basename "$GITHUB_REPOSITORY")
NAME="${NAME:-${_PROJECT_NAME}_${RELEASE_NAME}}_${GOOS}_${GOARCH}"
_EXTRA_FILES="${EXTRA_FILES:-""}"
_COMPRESS="${COMPRESS:-"false"}"
_RELEASE_ARTIFACT_NAME="${RELEASE_ARTIFACT_NAME:-"$NAME"}"
_GO_ARTIFACT_NAME="${GO_ARTIFACT_NAME:-"$_PROJECT_NAME"}"
_OVERWRITE_RELEASE="${OVERWRITE_RELEASE:-"true"}"

log_msg "Building application for $GOOS $GOARCH"
# shellcheck disable=SC1091
FILE_LIST="$(build)"
log_msg "Completed building application for $GOOS $GOARCH"

if [[ "$_EXTRA_FILES" = "" ]]; then
  log_msg "EXTRA_FILES not set"
fi

FILE_LIST="${FILE_LIST} ${_EXTRA_FILES}"

# shellcheck disable=SC1091
FILE_LIST=$(echo "${FILE_LIST}" | awk '{$1=$1};1')


log_msg "Preparing final artifact ..."
log_msg "$FILE_LIST"
if [[ "$GOOS" = "windows" ]]; then
  if [[ "$_EXTRA_FILES" != "" || "$_COMPRESS" = "true" ]]; then
    _ARTIFACT_SUFFIX=".zip"
    _RELEASE_ARTIFACT_NAME="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
    _ARTIFACT_PATH="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
    zip -9r "$_ARTIFACT_PATH" ${FILE_LIST} # FILE_LIST unquoted on purpose
  else
    _ARTIFACT_SUFFIX=".exe"
    _RELEASE_ARTIFACT_NAME="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
    _ARTIFACT_PATH="${_GO_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
  fi
else
  # linux or macos-darwin
  if [[ "$_EXTRA_FILES" != "" || "$_COMPRESS" = "true" ]]; then
    _ARTIFACT_SUFFIX=".tgz"
    _RELEASE_ARTIFACT_NAME="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
    _ARTIFACT_PATH="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
    tar cvfz "$_ARTIFACT_PATH" ${FILE_LIST} # FILE_LIST unquoted on purpose
  else
    _ARTIFACT_SUFFIX=""
    _RELEASE_ARTIFACT_NAME="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
    _ARTIFACT_PATH="${_GO_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
  fi
fi
ls -lh
log_msg "Final artifact is ready - $_ARTIFACT_PATH"

_CHECKSUM_MD5=$(md5sum "$_ARTIFACT_PATH" | cut -d ' ' -f 1)
_CHECKSUM_SHA256=$(sha256sum "$_ARTIFACT_PATH" | cut -d ' ' -f 1)
log_msg "md5sum - $_CHECKSUM_MD5"
log_msg "sha256sum - $_CHECKSUM_SHA256"

_PUBLISH_ASSET_RESULTS=$(curl \
  --connect-timeout 30 \
  --retry 300 \
  --retry-delay 5 \
  -X POST \
  --data-binary @"$_ARTIFACT_PATH" \
  -H 'Content-Type: application/octet-stream' \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${_UPLOAD_URL}?name=${_RELEASE_ARTIFACT_NAME}" | jq)

if [[ "$(echo "$_PUBLISH_ASSET_RESULTS" | jq -r .errors)" = "null" && "$(echo "$_PUBLISH_ASSET_RESULTS" | jq .state)" = "uploaded" ]]; then
  log_msg "Successfully published the asset - ${_RELEASE_ARTIFACT_NAME}"
elif [[ "$(echo "$_PUBLISH_ASSET_RESULTS" | jq -r .errors[0].code)" = "already_exists" && "$(echo "$_PUBLISH_ASSET_RESULTS" | jq -r .errors[0].field)" = "name" ]]; then
  log_msg "Release asset already exists - ${_RELEASE_ARTIFACT_NAME}"
  _ASSET_ID=$(echo "$_PUBLISH_ASSET_RESULTS" | jq -r . )
  log_msg "Asset ID $_ASSET_ID"
  if [[ "$_OVERWRITE_RELEASE" = "true" ]]; then
    log_msg "Overwriting existing asset ..."
    _PUBLISH_ASSET_RESULTS=$(curl \
      --connect-timeout 30 \
      --retry 300 \
      --retry-delay 5 \
      -X PATCH \
      --data-binary @"$_ARTIFACT_PATH" \
      -H 'Content-Type: application/octet-stream' \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "${_UPLOAD_URL}?name=${_RELEASE_ARTIFACT_NAME}" | jq)
  fi
fi

if [[ "$_PUBILSH_CHECKSUM_SHA256" = "true" ]]; then
  curl \
    --connect-timeout 30 \
    --retry 300 \
    --retry-delay 5 \
    -X POST \
    --data "$_CHECKSUM_SHA256" \
    -H 'Content-Type: text/plain' \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${_UPLOAD_URL}?name=${_RELEASE_ARTIFACT_NAME}_sha256.txt" | jq
fi

if [[ "$_PUBILSH_CHECKSUM_MD5" = "true" ]]; then
  curl \
    --connect-timeout 30 \
    --retry 300 \
    --retry-delay 5 \
    -X POST \
    --data "$_CHECKSUM_MD5" \
    -H 'Content-Type: text/plain' \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${_UPLOAD_URL}?name=${_RELEASE_ARTIFACT_NAME}_md5.txt" | jq
fi
