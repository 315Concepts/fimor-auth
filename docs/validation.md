# Validation

How to prove FiMOr works before you trust it - and what to check when it doesn't. Start with the [README](../README.md) for the overview and Quick Start.

- [Validating Your Setup](#validating-your-setup) - the `debug` module checks, in order, from routing through to email delivery
- [Troubleshooting](#troubleshooting) - symptoms and their likely causes

## Validating Your Setup

The `debug` module proves the whole chain - DNS, certificates, routing, _Kratos_ login, _Hydra_ consent, and email delivery - before you attach a real application. Run the checks in order.

1. **Edge and routing.** Start only the canary, then check it from a machine outside the host (`-k` while on staging certificates):
   ```sh
   ./fimor up debug whoami -d
   curl -kI http://<SERVICE_DOMAIN>                               # 301 redirect to HTTPS
   curl -k  https://<SERVICE_DOMAIN>:8443/whoami                  # canary answers
   ```
   `whoami` echoes the request it received, so you can read the path the request took from its response.

2. **Create an OAuth2 client** in _Hydra_ (the stack must be up; `jq` is required):
   ```sh
   ./ory/hydra/utils/create-oauth2-client.sh
   ```
   It prints the new client's ID and secret.

3. **Configure the consent mock.** In `.env.local`, uncomment `CONSENT_CLIENT_ID` and `CONSENT_CLIENT_SECRET` and fill in the values from step 2. Then start the whole debug module:
   ```sh
   ./fimor up debug -d
   ```

4. **Run the authorization-code flow.** Open `https://consent.<SERVICE_DOMAIN>` in a browser and click `Authorize Application`. You'll be bounced to the self-service UI to log in; sign up for an account, then complete the consent screen and confirm the mock finishes the flow.

5. **Read the verification email.** _Kratos_ sends it to the debug SMTP service; open `https://webmail.<SERVICE_DOMAIN>:8443` to find it. The mail UI can show a degraded layout on first load - refresh the browser if needed.

Checking from the host itself proves routing but not your firewall - test `PRIVATE_HTTPS_PORT` from another machine. Some hosts also can't reach their own public address; if everything fails from the host but works elsewhere, that's why.

## Troubleshooting

| Symptom | Likely cause |
| ------- | ------------ |
| `./fimor up` refuses to start and lists lines | `.env.local` still contains a `CHANGEME` or `_STUB` value. Run `./fimor init` for secrets, and set the rest by hand. |
| Compose errors about a required variable | The environment isn't loaded in this shell: `set -a; source .env.local; source .env; set +a`. |
| Certificate never issues | Port 443 isn't reachable from the internet, or DNS doesn't point at this host yet. Fix DNS **before** retrying. `docker logs ory-traefik` shows the **ACME** errors. |
| Staging certificate on `prd` | _Traefik_ reused a cached certificate. See [Certificates](networking.md#certificates). |
| `404 page not found` | No router matched. Check the `Host` rule, that the container has `traefik.enable=true`, that it is on `ory_backend`, and that you used `PRIVATE_HTTPS_PORT` for private routes. The dashboard lists what _Traefik_ actually loaded. |
| `404` from _Kratos_ or _Hydra_ | The path prefix wasn't stripped, or you hit the wrong prefix. Check the `*_PATH` variables and that the `prefix-strip` middleware lists them. |
| `502`/`503` | The target container is down or restarting. _Kratos_ and _Hydra_ restart until _Postgres_ and the migrators are ready, so give a cold start a minute, then `docker ps` and `docker logs <container>`. |
| Login loops, or flows fail with cookie errors | Browser and API must share the registrable domain: the cookie domain is `.<SERVICE_DOMAIN>`. Use the same base domain in every URL. |
| No verification emails | In debug mode, look in the mail UI on `PRIVATE_HTTPS_PORT`. With a real provider, check `ORY_SMTP_CONNECTION_URI` and `docker logs ory-kratos`. |
| Redirect loop | A CDN or load balancer in front of the host is terminating TLS and forwarding plain HTTP. Pass HTTPS through. |

To read logs from the host: `docker logs -f <container>` - containers are named `ory-kratos`, `ory-hydra`, `ory-pg`, `ory-traefik`, `ory-selfservice`, `ory-admin`, and `debug-*`.
