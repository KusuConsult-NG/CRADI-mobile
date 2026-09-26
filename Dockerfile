# Builds the Railway backend (backend/) from the REPOSITORY ROOT.
#
# Why this exists next to backend/Dockerfile:
#   Railway decides what to build from its service "Root Directory" setting. If
#   that is left blank, it scans the repo root, finds a Flutter app, and fails
#   with "Railpack could not determine how to build the app". This file makes
#   the root build the backend anyway, so the service deploys either way:
#
#     Root Directory = backend  -> backend/railway.json + backend/Dockerfile
#     Root Directory = (blank)  -> railway.json + this file
#
#   The two produce the same image; only the paths differ, because the build
#   context is the repo root here and backend/ there.
#
# Nothing Flutter is copied in — see .dockerignore.

FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY backend/src ./src

USER node
EXPOSE 8080
CMD ["node", "src/index.js"]
