# Go Release Binary GitHub Action

Automate publishing Go build artifacts for GitHub releases through GitHub Actions.

Detects a build.sh in the go repo and will use that instead.  Expects a list of
file artifacts in a single, space delimited line as output for packaging.

Extra environment variables:
* CMD_PATH
  * Pass extra commands to go build
* EXTRA_FILES
  * Pass a list of extra files for packaging.
    * Example: EXTRA_FILES: "README.md LICENSE"

```yaml
# .github/workflows/release.yaml

  release-linux-binaries:
    name: linux
    runs-on: ubuntu-20.04
    strategy:
      matrix:
        include:
          - GOARCH: "amd64"
          - GOARCH: "386"
          - GOARCH: "arm64"
    steps:
      - uses: actions/checkout@master
      - name: compile and release
        uses: unfor19/go-release.action@master
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GOARCH: ${{ matrix.GOARCH }}
          GOOS: linux

  release-macos-binaries:
    name: macos-darwin
    runs-on: ubuntu-20.04
    strategy:
      matrix:
        include:
          - GOARCH: "amd64"
          - GOARCH: "arm64"
    steps:
      - uses: actions/checkout@master
      - name: compile and release
        uses: unfor19/go-release.action@master
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GOARCH: ${{ matrix.GOARCH }}
          GOOS: darwin

  release-windows-binaries:
    name: windows
    runs-on: ubuntu-20.04
    strategy:
      matrix:
        include:
          - GOARCH: "amd64"
          - GOARCH: "386"
    steps:
      - uses: actions/checkout@master
      - name: compile and release
        uses: unfor19/go-release.action@master
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GOARCH: ${{ matrix.GOARCH }}
          GOOS: windows
```


## Docker

Build base image

```
docker build -t ghcr.io/unfor19/golang-ci:1.16 -f Dockerfile.base .
```