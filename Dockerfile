ARG GO_VERSION=1.16

FROM ghcr.io/unfor19/golang-ci:"${GO_VERSION}"
COPY . .
ENTRYPOINT ["/entrypoint.sh"]
