ARG GO_VERSION=1.16

FROM golang:"${GO_VERSION}"-alpine

# LABEL "com.github.actions.name"="Go Release Binary"
# LABEL "com.github.actions.description"="Automate publishing Go build artifacts for GitHub releases"
# LABEL "com.github.actions.icon"="cpu"
# LABEL "com.github.actions.color"="orange"

# LABEL "name"="Automate publishing Go build artifacts for GitHub releases through GitHub Actions"
# LABEL "version"="1.0.2"
# LABEL "repository"="http://github.com/ngs/go-release.action"
# LABEL "homepage"="http://ngs.io/t/actions/"

# LABEL "maintainer"="Atsushi Nagase <a@ngs.io> (https://ngs.io)"

RUN apk add --no-cache curl jq git build-base bash zip

WORKDIR /
RUN wget -O gh.tar.gz https://github.com/cli/cli/releases/download/v1.11.0/gh_1.11.0_linux_386.tar.gz && \
    tar -xzvf gh.tar.gz && \
    mv gh_1.11.0_linux_386/bin/gh /usr/local/bin/gh && \
    rm -rf gh_1.11.0_linux_386 *.tar.gz

COPY . .
ENTRYPOINT ["/entrypoint.sh"]
