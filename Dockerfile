FROM alpine:3.22

RUN apk add --no-cache dnsmasq docker-cli

COPY dnz.sh /usr/local/bin/dnz

ENTRYPOINT ["dnz"]
