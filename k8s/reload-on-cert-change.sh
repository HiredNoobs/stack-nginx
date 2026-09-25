#!/bin/sh
#
# Run by the nginx image's entrypoint (/docker-entrypoint.d) before nginx starts. Reloads
# nginx when cert-manager renews the certificate, the Secret is updated in place.

CERT=/etc/nginx/ssl/tls.crt
INTERVAL=60

(
  last=$(sha256sum "$CERT" 2> /dev/null | cut -d' ' -f1)

  while sleep "$INTERVAL"; do
    current=$(sha256sum "$CERT" 2> /dev/null | cut -d' ' -f1)

    if [ -n "$current" ] && [ "$current" != "$last" ]; then
      echo "$0: certificate changed, reloading nginx"
      nginx -s reload && last="$current"
    fi
  done
) < /dev/null &
