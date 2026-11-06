FROM nimlang/nim:2.2.12-alpine AS build

WORKDIR /app
COPY yuicafe_tg.nimble ./
COPY src ./src
RUN nim c -d:release --opt:speed --define:ssl --path:src --out:yuicafe src/yuicafe.nim

FROM alpine:3.22

RUN apk add --no-cache ca-certificates libssl3
RUN addgroup -S yuicafe && adduser -S yuicafe -G yuicafe
COPY --from=build /app/yuicafe /usr/local/bin/yuicafe
USER yuicafe
ENTRYPOINT ["/usr/local/bin/yuicafe"]
