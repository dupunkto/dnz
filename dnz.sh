#!/bin/sh

set -eu

: "${NODE:?}" "${NODES:?}" "${NET:?}" "${IP:?}" "${DOMAIN:?}"

ZONE=$NODE.$DOMAIN
HOSTS_FILE=/run/hosts
CONFIG_FILE=/run/dnsmasq.conf

die() {
  echo "resolver: $1" >&2
  exit 1
}

warn() {
  echo "resolver: $1" >&2
}

resolve() {
  getent ahostsv4 "$1" | awk '{ print $1; exit }' | grep . || die "can't resolve $1"
}

gateway() {
  subnet=$(docker network inspect "$NET" --format '{{(index .IPAM.Config 0).Subnet}}')

  ip -4 route | awk -v subnet="$subnet" '$1 == subnet { for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }' |
    grep . || die "no route for $subnet"
}

containers() {
  docker network inspect "$NET" \
    --format '{{range .Containers}}{{.IPv4Address}} {{.Name}}{{"\n"}}{{end}}' |
    sed -n 's|/[0-9]*||p'
}

build_config() {
  gateway=$(gateway)

  cat <<-EOF
	listen-address=$IP,127.0.0.1,$gateway
	bind-dynamic
	no-hosts
	addn-hosts=$HOSTS_FILE
	local=/$ZONE/
	local-ttl=5
	conf-dir=/etc/dnz/config.d
	EOF

  for node in $NODES; do
    [ "$node" = "$NODE" ] && continue
    ip=$(resolve "$node.$DOMAIN")
    echo "server=/$node.$DOMAIN/$ip"
  done
}

build_hosts() {
  echo "$IP $ZONE"
  containers | while read -r ip name; do
    echo "$ip $name.$ZONE"
  done
}

watch() {
  docker events --since "$1" \
    --filter type=network --filter type=container \
    --filter event=connect --filter event=disconnect --filter event=rename \
    --filter event=create --filter event=destroy \
    --format '{{.Type}} {{.Action}} {{.Actor.Attributes.name}}' |
    while read -r type action name; do
      if [ "$type" = network ] && [ "$action" != connect ] && [ "$action" != disconnect ]; then
        [ "$name" = "$NET" ] || continue
        warn "network $NET was recreated, restarting"
        kill 1
        exit
      fi

      build_hosts > $HOSTS_FILE
      kill -HUP 1
    done

  warn "resolver: lost docker events stream"
  kill 1
}

since=$(date +%s)

build_config > $CONFIG_FILE
build_hosts > $HOSTS_FILE

watch "$since" &

exec dnsmasq --keep-in-foreground --log-facility=- --conf-file=$CONFIG_FILE
