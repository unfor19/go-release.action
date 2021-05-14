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

if [[ -z "${CMD_PATH+x}" ]]; then
  log_msg "file=entrypoint.sh,line=6,col=1::CMD_PATH not set"
  export CMD_PATH=""
fi

#echo "::warning file=/build.sh,line=1,col=5::${FILE_LIST}"

EVENT_DATA=$(cat "$GITHUB_EVENT_PATH")
echo "$EVENT_DATA" | jq .
UPLOAD_URL=$(echo "$EVENT_DATA" | jq -r .release.upload_url)
UPLOAD_URL=${UPLOAD_URL/\{?name,label\}/}
RELEASE_NAME=$(echo "$EVENT_DATA" | jq -r .release.tag_name)
NAME="${NAME:-${PROJECT_NAME}_${RELEASE_NAME}}_${GOOS}_${GOARCH}"
_PUBILSH_CHECKSUM_SHA256="${_PUBILSH_CHECKSUM_SHA256:-"true"}"
_PUBILSH_CHECKSUM_MD5="${_PUBILSH_CHECKSUM_MD5:-"false"}"
_PROJECT_NAME=$(basename "$GITHUB_REPOSITORY")
export PROJECT_NAME="$_PROJECT_NAME"

log_msg "Building application for $GOOS $GOARCH"
# shellcheck disable=SC1091
FILE_LIST=$(. /build.sh)
log_msg "Completed building application for $GOOS $GOARCH"

if [ -z "${EXTRA_FILES+x}" ]; then
  echo "::warning file=entrypoint.sh,line=22,col=1::EXTRA_FILES not set"
fi

FILE_LIST="${FILE_LIST} ${EXTRA_FILES}"

# shellcheck disable=SC1091
FILE_LIST=$(echo "${FILE_LIST}" | awk '{$1=$1};1')


log_msg "Preparing final artifact ..."
log_msg "$FILE_LIST"
if [[ "$GOOS" = "windows" ]]; then
  _ARCHIVE=tmp.zip
  zip -9r "$_ARCHIVE" ${FILE_LIST} # FILE_LIST unquoted on purpose
else
  _ARCHIVE=tmp.tgz
  tar cvfz "$_ARCHIVE" ${FILE_LIST} # FILE_LIST unquoted on purpose
fi
log_msg "Final artifact is ready - $_ARCHIVE"

_CHECKSUM_MD5=$(md5sum ${_ARCHIVE} | cut -d ' ' -f 1)
_CHECKSUM_SHA256=$(sha256sum ${_ARCHIVE} | cut -d ' ' -f 1)
log_msg "md5sum - $_CHECKSUM_MD5"
log_msg "sha256sum - $_CHECKSUM_SHA256"

curl \
  -X POST \
  --data-binary @${_ARCHIVE} \
  -H 'Content-Type: application/octet-stream' \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${UPLOAD_URL}?name=${NAME}.${_ARCHIVE/tmp./}"

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
