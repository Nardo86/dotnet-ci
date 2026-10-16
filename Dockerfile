# Generic CI job image for .NET (GitHub Actions, Forgejo/Gitea runners, act).
# Contents: .NET SDK 10 (base), Node.js 24, Docker CLI 29 + compose + buildx, a few tools.
# Two targets: «generic» (tags 10.0, latest) and «playwright» (same plus Chromium for Playwright, tag suffix -playwright).
# The workflow pins every base by digest through the build args below.

ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0
ARG NODE_IMAGE=node:24-slim
ARG DOCKER_CLI_IMAGE=docker:29-cli
# Chromium of this Playwright release (target playwright): it must match the Playwright package of the projects.
ARG PLAYWRIGHT_VERSION=1.63.0

FROM ${NODE_IMAGE} AS node
FROM ${DOCKER_CLI_IMAGE} AS docker-cli

FROM ${DOTNET_SDK_IMAGE} AS generic

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git gzip jq python3 tar unzip \
 && rm -rf /var/lib/apt/lists/*

# Node.js 24 from the official image (glibc build, works on Ubuntu 24.04); npm and npx included.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Docker client only (static binaries), no daemon: jobs use the runner's daemon (dind or socket).
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-compose \
                       /usr/local/libexec/docker/cli-plugins/docker-buildx \
                       /usr/local/libexec/docker/cli-plugins/

# Microsoft's installer, to add other SDK channels inside a job (e.g. 8.0 for multi-targeting).
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /usr/local/bin/dotnet-install.sh \
 && chmod +x /usr/local/bin/dotnet-install.sh

# Build-time checks: any failure fails the build.
RUN set -eu; \
    sdk="$(dotnet --version)"; \
    dpkg --compare-versions "$sdk" ge 10.0.401 || { echo "dotnet SDK $sdk < 10.0.401" >&2; exit 1; }; \
    node="$(node --version)"; \
    case "$node" in v24.*) ;; *) echo "node $node is not 24.x" >&2; exit 1 ;; esac; \
    echo "dotnet $sdk / node $node"; \
    npm --version; \
    docker --version; \
    docker compose version; \
    docker buildx version; \
    python3 --version; \
    git --version; \
    jq --version; \
    curl --version | head -n 1; \
    unzip -v | head -n 1

CMD ["bash"]

# Variant for browser tests: Chromium and its headless shell, with the system libraries they need, in
# PLAYWRIGHT_BROWSERS_PATH. Playwright for .NET, Node or Python finds them there and never downloads a browser in a job.
# More than 1 GB: kept out of the generic image.
FROM generic AS playwright
ARG PLAYWRIGHT_VERSION
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx -y "playwright@${PLAYWRIGHT_VERSION}" install --with-deps chromium \
 && chmod -R a+rX /ms-playwright \
 && npm cache clean --force \
 && rm -rf /var/lib/apt/lists/* /root/.npm \
 && chrome="$(ls -d /ms-playwright/chromium-*/chrome-linux*/chrome | head -n 1)" \
 && test -x "$chrome" \
 && "$chrome" --version
