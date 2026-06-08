# syntax=docker/dockerfile:1
#
# Two-stage build for the bouine documentation site.
#  1. Build the Hugo/Doks site (Doks mounts node_modules/@thulite/* as Hugo
#     modules, so npm install is required before `hugo`).
#  2. Pack the static output into a redbean single-binary web server and ship
#     it on a scratch image — non-root capable, read-only rootfs, no shell.
#
# Build for the cluster arch (Scaleway k3s nodes are amd64):
#   docker buildx build --platform linux/amd64 -t <registry>/bouine-documentation:latest --load .

FROM --platform=linux/amd64 hugomods/hugo:exts AS hugo-build

WORKDIR /src

# Install the Doks npm modules first (better layer caching). The theme's
# config/_default/module.toml mounts node_modules/@thulite/* into Hugo.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund

# Bring in the rest of the site (themes/ holds the doks submodule contents).
COPY hugo.toml ./
COPY archetypes/ archetypes/
COPY assets/ assets/
COPY content/ content/
COPY data/ data/
COPY i18n/ i18n/
COPY layouts/ layouts/
COPY static/ static/
COPY themes/ themes/

# enableGitInfo is on for local dev (where .git exists) but the build context
# has no .git, so disable it here to avoid "Failed to read Git log".
RUN HUGO_ENABLEGITINFO=false hugo --environment production --minify --gc

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
