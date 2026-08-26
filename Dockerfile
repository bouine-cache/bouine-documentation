# syntax=docker/dockerfile:1
#
# Two-stage build for the bouine documentation site.
#  1. Build the Hugo/Doks site with all documentation versions (latest + archived).
#     Archived versions are built from snapshot branches via git worktree.
#  2. Pack the static output into a redbean single-binary web server and ship
#     it on a scratch image — non-root capable, read-only rootfs, no shell.
#
# Build for the cluster arch (Scaleway k3s nodes are amd64):
#   docker buildx build --platform linux/amd64 -t <registry>/bouine-documentation:latest --load .

FROM --platform=linux/amd64 hugomods/hugo:exts AS hugo-build

WORKDIR /src

# Install git (needed for worktree-based versioned builds) and bash.
RUN apk add --no-cache git bash

# Install the Doks npm modules first (better layer caching). The theme's
# config/_default/module.toml mounts node_modules/@thulite/* into Hugo.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund

# Copy the full repo including .git for worktree-based versioned builds.
# The .dockerignore must not exclude .git, scripts/, or config/.
COPY . .

# Initialize git submodules (themes/doks).
RUN git submodule update --init --recursive

# Build all documentation versions (latest + archived) into ./public/.
# The script uses git worktree to check out snapshot branches.
RUN HUGO_ENABLEGITINFO=false ./scripts/build-versioned.sh public

FROM --platform=linux/amd64 debian:bookworm-slim AS redbean-pack

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fSL -o /bouine-docs.com "https://cosmo.zip/pub/cosmos/v/4.0.2/bin/redbean" \
    && chmod +x /bouine-docs.com

COPY --from=hugo-build /src/public /public
COPY redbean-init.lua /public/.init.lua

# Strip macOS metadata that Hugo copies from static/.
RUN find /public -name '.DS_Store' -delete

# The binary MUST keep an extension (.com): `zip` appends ".zip" to a target
# name that has no extension, which would silently write a separate archive
# instead of embedding the site into the redbean binary.
RUN cd /public && zip -r /bouine-docs.com . && zip /bouine-docs.com .init.lua
RUN /bouine-docs.com --assimilate

FROM scratch

COPY --from=redbean-pack /bouine-docs.com /bouine-docs.com

EXPOSE 8080

ENTRYPOINT ["/bouine-docs.com", "-p", "8080"]