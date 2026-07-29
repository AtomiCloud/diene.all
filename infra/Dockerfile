# ### workspace-dockerfile
# #### source: workspace
# The ONE artifact this service ships. It serves HTTP by default and runs the one-shot
# initialisation path when the db-init Job appends `db-init` as an argument, so there is
# exactly one image to build, scan, sign, and promote (App/StartUp/RunMode.cs).
#
# Base images are pinned to an exact version tag and never to a digest (M25): a digest
# would freeze the security patches the tag is there to deliver.

# ── build ────────────────────────────────────────────────────────────────────────────
# Runs on the BUILDER's architecture and cross-publishes for $TARGETARCH, so an arm64
# image never needs emulation. The SDK tag matches global.json exactly; that file sets
# `rollForward: disable`, so a floating tag would fail restore rather than roll forward.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0.300-noble AS build

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

WORKDIR /src

# buildx supplies TARGETARCH. Resolve it to a .NET RID once, print it, and refuse an
# architecture we have not been asked to support — a silent fall back to linux-x64 would
# produce an arm64 image holding amd64 assets.
ARG TARGETARCH
RUN case "${TARGETARCH:-amd64}" in \
      amd64) echo 'linux-x64' >/rid ;; \
      arm64) echo 'linux-arm64' >/rid ;; \
      *) echo "❌ unsupported TARGETARCH '${TARGETARCH}'" >&2; exit 1 ;; \
    esac; \
    echo "🎯 TARGETARCH=${TARGETARCH:-amd64} → RID=$(cat /rid)"

# Restore ahead of the sources so a source-only change reuses the package layer. Central
# package management means the two props files are part of the restore input.
COPY global.json Directory.Build.props Directory.Packages.props ./
COPY App/App.csproj App/
COPY Lib/Lib.csproj Lib/
RUN dotnet restore App/App.csproj -r "$(cat /rid)"

COPY Lib/ Lib/
COPY App/ App/
# Framework-dependent: the runtime lives in the chiseled base, so the published output
# stays small and picks up the base image's runtime patches.
RUN dotnet publish App/App.csproj \
      -c Release \
      -r "$(cat /rid)" \
      --self-contained false \
      --no-restore \
      -o /publish

# ── runtime ──────────────────────────────────────────────────────────────────────────
# Chiseled: no shell, no package manager, no ICU. Every command below must therefore be
# exec-form — there is no /bin/sh to interpret a string.
FROM mcr.microsoft.com/dotnet/aspnet:10.0.9-noble-chiseled AS runtime

# Host and port are overridable (M34): these ARGs bake the default and ASPNETCORE_URLS
# stays an ordinary environment variable, so `docker run -e ASPNETCORE_URLS=...` or a
# Helm `env:` entry moves the binding without a rebuild.
ARG APP_HOST=+
ARG APP_PORT=8080
ENV ASPNETCORE_URLS=http://${APP_HOST}:${APP_PORT}

# The layered YAML is read relative to the content root, which is the working directory,
# so /app must hold Config/ next to the assemblies.
WORKDIR /app
COPY --from=build /publish ./

# Non-root (M26). The chiseled base ships APP_UID=1654 and already defaults to it; naming
# it here means a future base whose default changed cannot silently hand us root.
USER $APP_UID

EXPOSE 8080

# No CMD: no arguments means server mode. The db-init Job supplies `db-init` as the
# container's args and the same image runs the one-shot path.
ENTRYPOINT ["dotnet", "/app/App.dll"]
