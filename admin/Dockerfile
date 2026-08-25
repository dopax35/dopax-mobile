# syntax=docker/dockerfile:1

# The staff console is a Next.js server, not a static export: it uses server
# actions, `server-only` modules, and an httpOnly session cookie, and it is the
# only party that ever holds the staff JWT. It cannot be served from a CDN or
# from Static Web Apps.

FROM node:22-bookworm-slim AS base
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1


FROM base AS deps
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --include=dev


FROM deps AS build
COPY tsconfig.json next.config.ts postcss.config.mjs next-env.d.ts ./
COPY app ./app
COPY components ./components
COPY lib ./lib

# NEXT_PUBLIC_* values are inlined into the client bundle at build time, so the
# Firebase web config has to be present now rather than at container start.
# These are public identifiers by design — the API key only identifies the
# project, it does not authorize anything. Staff authorization is the backend's
# staff_users allowlist.
ARG NEXT_PUBLIC_FIREBASE_API_KEY
ARG NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=dopa-x-app.firebaseapp.com
ARG NEXT_PUBLIC_FIREBASE_PROJECT_ID=dopa-x-app
ENV NEXT_PUBLIC_FIREBASE_API_KEY=$NEXT_PUBLIC_FIREBASE_API_KEY \
    NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=$NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN \
    NEXT_PUBLIC_FIREBASE_PROJECT_ID=$NEXT_PUBLIC_FIREBASE_PROJECT_ID

RUN npm run build


FROM base AS runtime
ENV NODE_ENV=production \
    PORT=3100 \
    HOSTNAME=0.0.0.0

# The standalone bundle carries its own minimal node_modules, so there is no
# npm install in this stage at all.
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static

USER node
EXPOSE 3100

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3100)+'/login').then(r=>process.exit(r.status<500?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
