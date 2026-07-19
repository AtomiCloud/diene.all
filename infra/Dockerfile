# Distroless image whose entrypoint is the standalone CLI binary (no Bun/Node runtime layer).
FROM oven/bun:1.3.13 AS build
ARG TARGETARCH
WORKDIR /app
COPY package.json bun.lock tsconfig.json ./
RUN bun install --frozen-lockfile
COPY bin ./bin
COPY src ./src
# Pick the glibc target matching the image arch (baseline x64 for max CPU compatibility).
RUN target="$([ "${TARGETARCH}" = "arm64" ] && echo bun-linux-arm64 || echo bun-linux-x64-baseline)" && \
  bun build ./bin/bun-cli.ts --compile --target="${target}" --outfile /bun-cli

# cc-debian12 carries the libstdc++ the Bun binary links; :nonroot keeps the container unprivileged.
FROM gcr.io/distroless/cc-debian12:nonroot AS runtime
COPY --from=build /bun-cli /usr/bin/bun-cli
ENTRYPOINT ["/usr/bin/bun-cli"]
