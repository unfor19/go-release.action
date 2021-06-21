#!/bin/bash

set -eu
set -o pipefail

### Functions
error_msg(){
  local msg="$1"
  echo -e "[ERR] $msg"
  exit
}

log_msg(){
  local msg="$1"
  echo -e "[LOG] $msg"
}


# create_release_asset(){
#   local artifact_path="$1"
#   local release_artifact_name="$2"
#   local _UPLOAD_URL="$3"
#   curl \
#     --connect-timeout 30 \
#     --retry 300 \
#     --retry-delay 5 \
#     -X POST \
#     --data-binary @"$_ARTIFACT_PATH" \
#     -H 'Content-Type: application/octet-stream' \
#     -H "Authorization: Bearer ${GITHUB_TOKEN}" \
#     "${_UPLOAD_URL}?name=${_RELEASE_ARTIFACT_NAME}")
# }

_CMD_PATH="${CMD_PATH:-""}"

if [[ -z "$_CMD_PATH" ]]; then
  log_msg "file=entrypoint.sh,line=6,col=1::CMD_PATH not set"
fi

export CMD_PATH="$_CMD_PATH"

#echo "::warning file=/build.sh,line=1,col=5::${FILE_LIST}"

EVENT_DATA=$(cat "$GITHUB_EVENT_PATH")
# echo "$EVENT_DATA" | jq .
_UPLOAD_URL=$(echo "$EVENT_DATA" | jq -r .release.upload_url)
_UPLOAD_URL=${_UPLOAD_URL/\{?name,label\}/}
RELEASE_NAME=$(echo "$EVENT_DATA" | jq -r .release.tag_name)
# shellcheck disable=SC1091
source version_validation.sh "$RELEASE_NAME"
_PUBILSH_CHECKSUM_SHA256="${_PUBILSH_CHECKSUM_SHA256:-"true"}"
_PUBILSH_CHECKSUM_MD5="${_PUBILSH_CHECKSUM_MD5:-"false"}"
_PROJECT_NAME=$(basename "$GITHUB_REPOSITORY")
export PROJECT_NAME="$_PROJECT_NAME"
NAME="${NAME:-${PROJECT_NAME}_${RELEASE_NAME}}_${GOOS}_${GOARCH}"
_EXTRA_FILES="${EXTRA_FILES:-""}"
_COMPRESS="${COMPRESS:-"false"}"
_RELEASE_ARTIFACT_NAME="${RELEASE_ARTIFACT_NAME:-"$NAME"}"
_GO_ARTIFACT_NAME="${GO_ARTIFACT_NAME:-"$_PROJECT_NAME"}"
_OVERWRITE_RELEASE="${_OVERWRITE_RELEASE:-"true"}"

log_msg "Building application for $GOOS $GOARCH"
# shellcheck disable=SC1091
FILE_LIST=$(. /build.sh)
log_msg "Completed building application for $GOOS $GOARCH"

if [[ "$_EXTRA_FILES" = "" ]]; then
  log_msg "file=entrypoint.sh,line=22,col=1::EXTRA_FILES not set"
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
