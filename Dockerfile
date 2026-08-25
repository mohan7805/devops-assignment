# syntax=docker/dockerfile:1.7

###############################################################################
# Base image pinned to an explicit, immutable tag - never `latest` - so every
# build is reproducible and the exact OS package set is known to the scanner.
###############################################################################
ARG NODE_IMAGE=node:24.20.0-alpine3.24

###############################################################################
# Stage 1 - dependencies
###############################################################################
FROM ${NODE_IMAGE} AS deps

WORKDIR /build
COPY app/package.json app/package-lock.json ./
# `npm ci` installs exactly what package-lock.json pins - the build is
# reproducible and cannot silently pick up a new transitive version.
RUN npm ci --no-audit --no-fund

###############################################################################
# Stage 2 - test
# Runs the unit tests inside the image. `docker build --target test` is used as
# an extra guard; the primary gate is the `test` job in the CI pipeline.
###############################################################################
FROM ${NODE_IMAGE} AS test

WORKDIR /build
COPY --from=deps /build/node_modules ./node_modules
COPY app/ ./
RUN npm test

###############################################################################
# Stage 3 - production dependencies only
###############################################################################
FROM ${NODE_IMAGE} AS prod-deps

WORKDIR /build
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

###############################################################################
# Stage 4 - runtime
# Production dependencies + source only, executed as a non-root user.
###############################################################################
FROM ${NODE_IMAGE} AS runtime

# Build metadata injected by CI.
ARG APP_VERSION=0.0.0-dev
ARG GIT_COMMIT_SHA=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="devops-assignment-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/OWNER/devops-assignment"

# Apply any OS security patches published since the base image was cut. The
# base tag stays pinned; this only upgrades packages within that Alpine release.
RUN apk --no-cache upgrade

# npm is a build-time tool only. Removing it from the runtime image drops a
# large dependency tree (tar, glob, pacote, sigstore...) that would otherwise
# show up in the Trivy scan even though the application never executes it.
RUN rm -rf /usr/local/lib/node_modules/npm \
           /usr/local/bin/npm \
           /usr/local/bin/npx \
           /opt/yarn* /usr/local/bin/yarn* /usr/local/bin/corepack

# Dedicated unprivileged user with a fixed UID/GID.
RUN addgroup -g 10001 -S appgrp && \
    adduser  -u 10001 -S appuser -G appgrp

WORKDIR /app

COPY --from=prod-deps --chown=10001:10001 /build/node_modules ./node_modules
COPY --chown=10001:10001 app/package.json ./package.json
COPY --chown=10001:10001 app/src ./src

# All configuration comes from the environment; these are defaults only.
ENV NODE_ENV=production \
    PORT=8080 \
    APP_VERSION=${APP_VERSION} \
    GIT_COMMIT_SHA=${GIT_COMMIT_SHA} \
    GREETING="Hello from the DevOps assignment API" \
    APP_ENV=local

# Drop privileges: the process never runs as root.
USER 10001:10001

EXPOSE 8080

# Uses the node runtime itself rather than adding curl to the image.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "require('node:http').get('http://127.0.0.1:'+(process.env.PORT||8080)+'/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]

# Exec form so PID 1 is node itself and receives SIGTERM for graceful shutdown.
CMD ["node", "src/server.js"]
