# syntax=docker/dockerfile:1.7
FROM oven/bun:1.3.13-alpine@sha256:4de475389889577f346c636f956b42a5c31501b654664e9ae5726f94d7bb5349 AS dependencies
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

FROM oven/bun:1.3.13-alpine@sha256:4de475389889577f346c636f956b42a5c31501b654664e9ae5726f94d7bb5349 AS build
WORKDIR /app
COPY package.json bun.lock tsconfig.json ./
RUN bun install --frozen-lockfile
COPY src ./src
COPY scripts/sit-control ./scripts/sit-control
RUN bun build ./src/index.ts --outdir ./dist --target bun --sourcemap=external \
  && bun build ./scripts/sit-control/server.ts --outfile ./dist/sit-control.js --target bun \
  && bun build ./scripts/sit-control/sink.ts --outfile ./dist/sit-sink.js --target bun

FROM oven/bun:1.3.13-alpine@sha256:4de475389889577f346c636f956b42a5c31501b654664e9ae5726f94d7bb5349 AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=8080 \
    TMPDIR=/app/tmp
COPY --from=dependencies --chown=bun:bun /app/node_modules ./node_modules
COPY --from=build --chown=bun:bun /app/dist ./dist
COPY --chown=bun:bun package.json ./
COPY --chown=bun:bun config /config
COPY --chown=bun:bun migrations /app/migrations
RUN apk add --no-cache libcrypto3=3.5.7-r0 libssl3=3.5.7-r0 \
  && mkdir -p /app/tmp \
  && chown bun:bun /app/tmp
USER bun
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["bun", "-e", "const r=await fetch('http://127.0.0.1:8080/health/live');process.exit(r.ok?0:1)"]
ENTRYPOINT ["bun", "dist/index.js"]
CMD ["serve"]
