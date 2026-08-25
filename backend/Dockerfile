# syntax=docker/dockerfile:1

# Three published targets, one image family:
#
#   --target runtime   the API. Lean, production dependencies only.
#   --target release   the R5 bootstrap / migration task. Carries devDependencies
#                      because db:bootstrap and db:migrate run through tsx.
#   --target worker    ingestion, Drive drain, and the nightly reconciler.
#
# Keeping them in one Dockerfile is what makes MIGRATION_PLAN.md §5.2's "same
# image, different entrypoints" true in practice rather than on paper.

# Debian rather than Alpine: the study cannot afford to debug a musl-vs-glibc
# difference in a transitive dependency during a data migration.
FROM node:22-bookworm-slim AS base
WORKDIR /app
ENV NODE_ENV=production


FROM base AS deps
# Lockfile first so dependency layers survive source edits.
COPY package.json package-lock.json ./
# npm ci needs devDependencies present to build; NODE_ENV is overridden for
# this layer only.
RUN --mount=type=cache,target=/root/.npm \
    NODE_ENV=development npm ci --include=dev


FROM deps AS build
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build


# Bootstrap and migration task. Inherits the full dependency tree from `deps`,
# so tsx is available to run the TypeScript entrypoints directly.
#
# This is a release task, never the API's boot path: a Drive backfill takes
# hours and must not sit between a container starting and its probe passing.
FROM deps AS release
COPY tsconfig.json tsconfig.build.json drizzle.config.ts ./
COPY src ./src
COPY scripts ./scripts
USER node
CMD ["npm", "run", "db:bootstrap"]


FROM base AS runtime
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

COPY --from=build /app/dist ./dist

# src/db/migrations/ ships as source, not build output. Both src/db/migrate.ts
# and scripts/bootstrap.ts pass drizzle the literal path './src/db/migrations',
# resolved against the working directory — so the folder has to sit at that
# exact path next to dist/ or the first production migration fails.
COPY src/db/migrations ./src/db/migrations

USER node
EXPOSE 8080

# Container Apps uses its own probes against /healthz and /readyz; this only
# matters for `docker run` and compose.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/server.js"]


# Workers share the runtime image and override the command per job. Declared as
# its own target so the intent is visible and the tag can diverge later without
# a rebuild of the API.
FROM runtime AS worker
CMD ["node", "dist/server.js"]
