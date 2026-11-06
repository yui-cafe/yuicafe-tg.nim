FROM nimlang/nim:2.2.12-alpine AS build

WORKDIR /app
COPY yuicafe_tg.nimble ./
RUN cd /tmp && nimble install -y db_connector
COPY src ./src
RUN nimble build

FROM alpine:3.22

RUN apk add --no-cache ca-certificates libssl3 sqlite-libs
RUN addgroup -S yuicafe && adduser -S yuicafe -G yuicafe
RUN install -d -o yuicafe -g yuicafe /var/lib/yuicafe
COPY --from=build /app/yuicafe /usr/local/bin/yuicafe
USER yuicafe
WORKDIR /var/lib/yuicafe
VOLUME ["/var/lib/yuicafe"]
ENTRYPOINT ["/usr/local/bin/yuicafe"]
