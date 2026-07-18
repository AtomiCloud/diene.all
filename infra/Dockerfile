FROM alpine:3.24.1 AS build
WORKDIR /app
COPY . .
RUN printf 'diene dotnet base\n' > /app/message.txt

FROM alpine:3.24.1 AS runtime
RUN addgroup -S app && adduser -S -G app app
WORKDIR /app
COPY --from=build --chown=app:app /app/message.txt ./message.txt
USER app
CMD ["cat", "/app/message.txt"]
