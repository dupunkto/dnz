FROM alpine:3.22

RUN apk add --no-cache dnsmasq docker-cli

RUN mkdir -p /etc/dnz/config.d
COPY dnz.sh /usr/local/bin/dnz

ENTRYPOINT ["dnz"]
