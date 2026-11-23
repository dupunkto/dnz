FROM alpine:3.22

RUN apk add --no-cache dnsmasq docker-cli

COPY resolver.sh /usr/local/bin/resolver

ENTRYPOINT ["resolver"]
