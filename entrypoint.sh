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

_CMD_PATH="${CMD_PATH:-""}"

if [[ -z "$_CMD_PATH" ]]; then
  log_msg "file=entrypoint.sh,line=6,col=1::CMD_PATH not set"
fi

export CMD_PATH="$_CMD_PATH"

#echo "::warning file=/build.sh,line=1,col=5::${FILE_LIST}"

EVENT_DATA=$(cat "$GITHUB_EVENT_PATH")
# echo "$EVENT_DATA" | jq .
UPLOAD_URL=$(echo "$EVENT_DATA" | jq -r .release.upload_url)
UPLOAD_URL=${UPLOAD_URL/\{?name,label\}/}
RELEASE_NAME=$(echo "$EVENT_DATA" | jq -r .release.tag_name)
_PUBILSH_CHECKSUM_SHA256="${_PUBILSH_CHECKSUM_SHA256:-"true"}"
_PUBILSH_CHECKSUM_MD5="${_PUBILSH_CHECKSUM_MD5:-"false"}"
_PROJECT_NAME=$(basename "$GITHUB_REPOSITORY")
export PROJECT_NAME="$_PROJECT_NAME"
NAME="${NAME:-${PROJECT_NAME}_${RELEASE_NAME}}_${GOOS}_${GOARCH}"
_EXTRA_FILES="${EXTRA_FILES:-""}"
_COMPRESS="${COMPRESS:-"false"}"

log_msg "Building application for $GOOS $GOARCH"
# shellcheck disable=SC1091
FILE_LIST=$(. /build.sh)
log_msg "Completed building application for $GOOS $GOARCH"

if [[ -z "$_EXTRA_FILES" ]]; then
  log_msg "file=entrypoint.sh,line=22,col=1::EXTRA_FILES not set"
fi

FILE_LIST="${FILE_LIST} ${_EXTRA_FILES}"

# shellcheck disable=SC1091
FILE_LIST=$(echo "${FILE_LIST}" | awk '{$1=$1};1')


log_msg "Preparing final artifact ..."
log_msg "$FILE_LIST"
if [[ "$GOOS" = "windows" ]]; then
  if [[ -z "$FILE_LIST" || "$_COMPRESS" = "true" ]]; then
    _ARTIFECT_SUFFIX=".zip"
    _ARTIFACT_NAME="${NAME}${_ARTIFECT_SUFFIX}"
    zip -9r "$_ARTIFACT_NAME" ${FILE_LIST} # FILE_LIST unquoted on purpose
  else
    _ARTIFECT_SUFFIX=".exe"
    _ARTIFACT_NAME="${NAME}${_ARTIFECT_SUFFIX}"
  fi
else
  # linux or macos-darwin
  if [[ -z "$FILE_LIST" || "$_COMPRESS" = "true" ]]; then
    _ARTIFECT_SUFFIX=".tgz"
    _ARTIFACT_NAME="${NAME}${_ARTIFECT_SUFFIX}"
    tar cvfz "$_ARTIFACT_NAME" ${FILE_LIST} # FILE_LIST unquoted on purpose
  else
    _ARTIFECT_SUFFIX=""
    _ARTIFACT_NAME="${NAME}${_ARTIFECT_SUFFIX}"
  fi
fi
ls -lh
log_msg "Final artifact is ready - $_ARTIFACT_NAME"

_CHECKSUM_MD5=$(md5sum "$_ARTIFACT_NAME" | cut -d ' ' -f 1)
_CHECKSUM_SHA256=$(sha256sum "$_ARTIFACT_NAME" | cut -d ' ' -f 1)
log_msg "md5sum - $_CHECKSUM_MD5"
log_msg "sha256sum - $_CHECKSUM_SHA256"

curl \
  -X POST \
  --data-binary @"$_ARTIFACT_NAME" \
  -H 'Content-Type: application/octet-stream' \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${UPLOAD_URL}?name=${_ARTIFACT_NAME}"

if [[ "$_PUBILSH_CHECKSUM_SHA256" = "true" ]]; then
  curl \
    -X POST \
    --data "$_CHECKSUM_SHA256" \
    -H 'Content-Type: text/plain' \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${UPLOAD_URL}?name=${NAME}_sha256.txt"
fi

if [[ "$_PUBILSH_CHECKSUM_MD5" = "true" ]]; then
  curl \
    -X POST \
    --data "$_CHECKSUM_MD5" \
    -H 'Content-Type: text/plain' \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${UPLOAD_URL}?name=${NAME}_md5.txt"
fi
