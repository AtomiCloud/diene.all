# ### bun-base-dockerfile
# #### source: bun-base
FROM oven/bun:1.3.13-alpine AS build
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY tsconfig.json ./
COPY src ./src
RUN bun build ./src/index.ts --outdir ./dist --target bun

FROM oven/bun:1.3.13-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache minio-client && ln -s /usr/bin/mcli /usr/local/bin/mc
COPY --from=build /app/dist ./dist
COPY config ./config
COPY migrations ./migrations
COPY seed ./seed
RUN mkdir -p ./dist/run && chown bun:bun ./dist/run
ENV BUN_CONSUMER_ROOT=/app
USER bun
ENTRYPOINT ["bun", "dist/index.js"]
CMD ["worker"]
