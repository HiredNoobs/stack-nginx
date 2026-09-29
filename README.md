# stack-nginx

Nginx reverse proxy deployment for k8s.

One replica runs on each node labelled `nginx_core_nginx` (set in iac-homelab), the replica count is worked out at deploy time. With one replica per node there's no room for an extra pod during an update, so the replicas are replaced in place one at a time.

It can be deployed on its own, other stacks add to it when they're available:

- `stack-kube-vip` announces `$NGINX_LB_IP`, without it nginx is only reachable inside the cluster.
- `stack-cert-manager` issues the certificate, without it nginx uses a self-signed placeholder.
- rsyslog, a syslog target that doesn't resolve when a pod starts is dropped (see `k8s/render-config.sh`).
- Upstreams, a subdomain whose upstream can't be reached returns an error without affecting the rest.

## Proxy hosts

`NGINX_SERVICES` and `NGINX_WS_SERVICES` (websockets) in `stack.env` list the proxied services as `scheme:subdomain:host:port`, each becomes a `proxy_host` config from `configs/service.conf.tmpl` or `configs/ws_service.conf.tmpl`. The generated configs are stored in a ConfigMap, changing them restarts the pods.

Upstreams are resolved when a request is made (through CoreDNS), so a host that doesn't resolve yet only breaks its own subdomain (502) and pod IP changes are followed. Hosts in the cluster need the full name, e.g.:

```text
https:pihole:pihole-web.pihole-core.svc.cluster.local:443
```

## Authelia

Adding `:auth` to a service puts it behind Authelia (`stack-authelia`), e.g.:

```text
http:homepage:homepage.homepage-core.svc.cluster.local:3000:auth
```

Each request is checked with Authelia (`NGINX_AUTHELIA_URL`) first, anyone not logged in is sent to `auth.$DOMAIN` and back again afterwards. Who gets in is decided by Authelia's access control rules. The user is passed on to the service as `Remote-User`, `Remote-Groups`, `Remote-Name` and `Remote-Email`.

The snippets are `configs/authelia-location.conf.tmpl` and `configs/authelia-authrequest.conf`, from [Authelia's nginx docs](https://www.authelia.com/integration/proxies/nginx/).

Authelia is resolved per request like the upstreams, so nginx starts without it. While it's down, services with `:auth` return 500 and the rest carry on. `deploy` warns if it isn't ready.

If Authelia breaks, set `NGINX_AUTH_ENABLED="false"` and deploy, every service is deployed without it until it's set back.

## Certificate

cert-manager issues the `*.$DOMAIN` certificate from Let's Encrypt (`ACME_SERVER`) using Cloudflare DNS validation and renews it 30 days before it expires. Each pod reloads nginx when the renewed certificate appears (`k8s/reload-on-cert-change.sh`).

`secrets.env` needs:

- `CLOUDFLARE_API_TOKEN` - with Zone → DNS → Edit and Zone → Zone → Read for the zone.
- `CLOUDFLARE_EMAIL` (or `ACME_EMAIL`) - optional, the Let's Encrypt account email.

Without cert-manager or the token, `deploy` skips the certificate and creates a self-signed placeholder so nginx still starts. Once both are available the next `deploy` adds the Certificate, cert-manager replaces the placeholder and the pods reload. If cert-manager is taken down (e.g. for an upgrade) the issued certificate stays in place, it just isn't renewed until it's back.

`deployment clean` keeps the certificate so a redeploy doesn't request a new one (Let's Encrypt limits duplicate certificates to 5 a week), `deployment purge` removes it along with the namespace.

`deployment cert_status` shows the certificate's status.

## Logs

Access logs go to stdout (`kubectl logs`) and, as before, access/error logs are sent to `rsyslog.$DOMAIN`. If rsyslog doesn't resolve when a pod starts, the syslog logging is dropped until the pod is restarted.

## Deployments

- `core/production` - the `production.core` cluster.
- `core/development` - the `development.core` cluster (to be built), `NGINX_LB_IP` still needs setting and it uses the Let's Encrypt staging server.
