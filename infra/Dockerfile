# ### go-consumer-dockerfile
# #### source: go-consumer
FROM golang:1.26.5-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download && go mod verify
COPY adapters ./adapters
COPY cmd ./cmd
COPY lib ./lib
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/go-consumer ./cmd/go-consumer

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
# WORKDIR is the root anchor every relative config/migration/seed path resolves
# against (M36 — paths resolve against the repository root, never the CWD).
WORKDIR /app
COPY --from=build /out/go-consumer /go-consumer
# Baked-in runtime payload. `config/` is the R14 base layer the app chart's
# ConfigMap mounts over once the build-phase copy has run; db-init reads
# `migrations/` and `seed/` directly, and no chart resource carries them.
COPY config ./config
COPY migrations ./migrations
COPY seed ./seed
USER 65532:65532
ENTRYPOINT ["/go-consumer"]
CMD ["worker"]
