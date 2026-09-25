#!/bin/sh
#
# Run by the nginx image's entrypoint (/docker-entrypoint.d) before nginx starts. Copies the
# config from the ConfigMaps into place, dropping syslog targets that don't resolve (e.g. rsyslog
# isn't deployed) as nginx won't start otherwise. They're checked again when the pod restarts.

SRC=/etc/nginx-k8s
CONFIGS="/etc/nginx/nginx.conf /etc/nginx/conf.d/proxy_host/*.conf"

cp "$SRC/config/nginx.conf" /etc/nginx/nginx.conf
cp "$SRC/config/logs.conf" /etc/nginx/conf.d/logs.conf

rm -rf /etc/nginx/conf.d/proxy_host
mkdir -p /etc/nginx/conf.d/proxy_host
for conf in "$SRC"/proxy_host/*.conf; do
  [ -f "$conf" ] && cp "$conf" /etc/nginx/conf.d/proxy_host/
done

# shellcheck disable=SC2086 # CONFIGS is a glob
servers=$(cat $CONFIGS 2> /dev/null | grep -o 'syslog:server=[^,; ]*' | cut -d= -f2 | sort -u)

for server in $servers; do
  host="${server%:*}"

  if ! getent hosts "$host" > /dev/null; then
    echo "$0: $host doesn't resolve, not logging to it"
    # shellcheck disable=SC2086
    sed -i "/syslog:server=$server[,; ]/d" $CONFIGS 2> /dev/null
  fi
done

exit 0
