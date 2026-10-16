# dotnet-ci

Generic CI job image for .NET projects: the official .NET SDK 10 image plus what CI jobs usually need on top of it. Works with GitHub Actions (`container:`), Forgejo / Gitea runners and `act`.

`linux/amd64` only. Rebuilt weekly and whenever `mcr.microsoft.com/dotnet/sdk:10.0` changes.

## Contents

| Component | Source |
|---|---|
| .NET SDK 10 (≥ 10.0.401), Ubuntu 24.04 | base `mcr.microsoft.com/dotnet/sdk:10.0` |
| Node.js 24 LTS + npm (for JavaScript actions such as `actions/checkout`) | official `node:24-slim` |
| Docker CLI 29 with the `compose` (v5) and `buildx` plugins, **no daemon** | official `docker:29-cli` |
| `git`, `curl`, `ca-certificates`, `python3`, `jq`, `tar`, `gzip`, `unzip`, `bash` | Ubuntu packages |
| `dotnet-install.sh` (adds other SDK channels on demand) | `https://dot.net/v1/dotnet-install.sh` |

Runs as `root`, `CMD ["bash"]`, no `ENTRYPOINT`, no `HEALTHCHECK`. Telemetry and the first-run banner of the .NET CLI are off (`DOTNET_CLI_TELEMETRY_OPTOUT=1`, `DOTNET_NOLOGO=1`).

Docker commands (Testcontainers, `docker compose`, `docker buildx`) use whatever daemon the runner provides: a Docker-in-Docker sidecar via `DOCKER_HOST`, or a mounted socket.

## Tags

| Tag | Meaning |
|---|---|
| `<sdk>-<yyyymmdd>`, e.g. `10.0.401-20261007` | immutable, one per build, never overwritten (a second build on the same day gets `.2`, `.3`, …) |
| `10.0` | moving: latest build on the .NET 10 SDK |
| `latest` | moving: same as `10.0` |
| `<sdk>-<yyyymmdd>-playwright`, `10.0-playwright`, `playwright` | the same build plus Chromium and Chromium headless shell of **Playwright 1.63.0** with their system libraries, in `/ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH`); the Playwright package of the project must have the same version |

For reproducible CI, pin the immutable tag together with its digest (`nardo86/dotnet-ci:10.0.401-20261007@sha256:…`); the digest of every build is printed in the summary of the workflow run.

OCI labels: `org.opencontainers.image.version` (SDK version), `.source`, `.revision`, `.created`, `.base.name`, `.base.digest`.

## Usage

```yaml
jobs:
  build:
    runs-on: docker            # GitHub: ubuntu-latest
    container:
      image: nardo86/dotnet-ci:10.0
    steps:
      - uses: actions/checkout@v5
      - run: dotnet test
```

## Adding what you need

The image stays small on purpose. Three ways to complete it, from the quickest to the most reusable:

**1. In the job**, for occasional needs (you pay the install time on every run):

```bash
apt-get update && apt-get install -y --no-install-recommends zip postgresql-client

# another SDK next to the 10.0 one, e.g. for multi-targeting
dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
# only a runtime
dotnet-install.sh --channel 8.0 --runtime aspnetcore --install-dir /usr/share/dotnet

dotnet tool install -g dotnet-reportgenerator-globaltool && export PATH="$PATH:$HOME/.dotnet/tools"
```

**2. A derived image**, when the same additions are needed by every run:

```dockerfile
FROM nardo86/dotnet-ci:10.0
RUN dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
 && apt-get update && apt-get install -y --no-install-recommends zip \
 && rm -rf /var/lib/apt/lists/*
```

**3. Browsers / Playwright**: use the `-playwright` variant below; it adds more than 1 GB and most jobs don't need it.

## Build locally

```bash
docker build --pull --target generic -t dotnet-ci:local .
docker build --pull --target playwright -t dotnet-ci:local-playwright .
```

The build fails if any of the version checks at the end of the `Dockerfile` fails (SDK ≥ 10.0.401, Node 24.x, Docker CLI and plugins, Python, Git, jq).
