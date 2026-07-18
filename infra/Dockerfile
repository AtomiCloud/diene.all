# ### go-base-dockerfile
# #### source: go-base
FROM golang:1.26.5-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download && go mod verify
COPY adapters ./adapters
COPY cmd ./cmd
COPY lib ./lib
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/go-base ./cmd/go-base

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
COPY --from=build /out/go-base /go-base
USER 65532:65532
ENTRYPOINT ["/go-base"]
CMD ["slug", "Diene Go Base"]
