# Networking

How traffic reaches _FiMOr_: which URLs go where, the _Traefik_ entrypoints behind them, the firewall model, and the **Let's Encrypt** certificates. Start with the [README](../README.md) for the overview.

- [Routing](#routing) - the public and private URLs, and how path prefixes are handled
- [Entrypoints](#entrypoints) - ports `80`, `443`, `PRIVATE_HTTPS_PORT` and `1025`, plus the [Firewall](#firewall) model
- [Certificates](#certificates) - the `stg` / `prd` resolvers, the certificate cache, and switching to production

## Routing

User-facing flows are public; administration is private. Both lanes terminate TLS at _Traefik_.

| What                    | URL                                                   | Entrypoint     |
| ----------------------- | ----------------------------------------------------- | -------------- |
| Self-service UI         | `https://<SERVICE_DOMAIN>`                            | `web-secure`   |
| _Kratos_ public API     | `https://<SERVICE_DOMAIN><KRATOS_PUBLIC_PATH>`        | `web-secure`   |
| _Hydra_ public API      | `https://<SERVICE_DOMAIN><HYDRA_PUBLIC_PATH>`         | `web-secure`   |
| _Kratos_ admin API      | `https://<SERVICE_DOMAIN>:<PRIVATE_HTTPS_PORT><KRATOS_ADMIN_PATH>` | `private-secure` |
| _Hydra_ admin API       | `https://<SERVICE_DOMAIN>:<PRIVATE_HTTPS_PORT><HYDRA_ADMIN_PATH>`  | `private-secure` |
| Admin UI                | `https://<ADMIN_SUBDOMAIN>.<SERVICE_DOMAIN>:<PRIVATE_HTTPS_PORT>`   | `private-secure` |
| _Traefik_ dashboard     | `https://<TRAEFIK_SUBDOMAIN>.<SERVICE_DOMAIN>:<PRIVATE_HTTPS_PORT>` | `private-secure` |
| Consent mock *(debug)*  | `https://<CONSENT_SUBDOMAIN>.<SERVICE_DOMAIN>`        | `web-secure`   |
| Mail UI / API *(debug)* | `https://<MAIL_SUBDOMAIN or SLURP_SUBDOMAIN>.<SERVICE_DOMAIN>:<PRIVATE_HTTPS_PORT>` | `private-secure` |
| `whoami` *(debug)*      | `https://<SERVICE_DOMAIN>:<PRIVATE_HTTPS_PORT><WHOAMI_PUBLIC_PATH>` | `private-secure` |

- **Path-prefix stripping.** The public and admin APIs are served under path prefixes, and a shared `prefix-strip` middleware removes the prefix before the request reaches the service. It is defined once, by labels on the _Traefik_ container, and lists all four API prefixes.
- **Router names are global.** Router names must be unique across every container _Traefik_ sees - reusing one merges or breaks the routes.
- **Changing routing labels requires a full removal.** _Docker_ labels can't be modified after a container is created; adjusting a route means recreating the container (`./fimor down <module>` then `./fimor up <module> -d`). Changing the middleware means recreating _Traefik_ itself, which **_briefly takes your ingress offline_**.
- **Only labelled containers are routed** (`exposedbydefault=false`).

## Entrypoints

| Entrypoint       | Port                 | Purpose |
| ---------------- | -------------------- | ------- |
| `web-insecure`   | `80`                 | Public HTTP. Permanently redirects everything to `web-secure`. |
| `web-secure`     | `443`                | Public HTTPS. Self-service UI and the public _Kratos_ and _Hydra_ APIs. |
| `private-secure`   | `PRIVATE_HTTPS_PORT` (default `8443`) | Private HTTPS. Admin APIs, admin UI, dashboard, and the debug tools. |
| `tcp-smtp`       | `1025`               | Debug SMTP ingress for mailslurper. **Remove for production** (see [Going to Production](operations.md#going-to-production)). |

- **What "private" means here:** `private-secure` is a **standard _Traefik_ entrypoint** on a custom port with TLS enabled. It is **not authenticated**, and **_Docker_ publishes the port on all host interfaces**. Restricting who can reach it is the operator's job, at the host firewall or the cloud security group - see [Firewall](#firewall). Treat the admin APIs as what they are: unauthenticated control of every identity and OAuth2 client.
- **Ports 80 and 443 must stay open to the internet,** whatever else you change. The **ACME** TLS-ALPN challenge connects to 443, and 80 carries the HTTPS redirect.

### Firewall

| Port          | Open to                                              |
| ------------- | ---------------------------------------------------- |
| `22` (SSH)    | Cloud-provider delimited access - **NEVER CLOSE THIS PORT**. |
| `80`, `443`   | Everyone - public flows                              |
| `PRIVATE_HTTPS_PORT`  | Operators only - admin APIs and tools                |
| `1025`        | Debug only - mailslurper SMTP. Open it only while validating. |

`scripts/configure-ufw.sh` backs up the current `ufw` ruleset and then applies the above inbound rules (except `1025`, which is left commented out) with a `default: deny` policy for any other incoming traffic. **_Check the rules before running it._** Please note that _Traefik_ opens the host's private ports to **_all addresses_** and **_Docker_ can bypass basic `ufw` firewalls** - so this script is only guaranteed to lock down ports the stack doesn't use. To protect `PRIVATE_HTTPS_PORT` itself **_you must run a cloud or service firewall_**. Ensuring appropriate network security is in place is the Operator's responsibility.

## Certificates

_Traefik_ runs two **Let's Encrypt** resolvers side-by-side, and `ACME_DEFAULT_RESOLVER` picks which one every route in the stack uses.

| Resolver | Issues                              | State file          | Use it for |
| -------- | ----------------------------------- | ------------------- | ---------- |
| `stg`    | Untrusted staging certificates      | `net/acme/stg.json` | Bring-up and debugging. Generous rate limits; browsers will warn. |
| `prd`    | Real, publicly trusted certificates | `net/acme/prd.json` | Production, once routing is proven on `stg`. |

- **Challenge type:** TLS-ALPN, so public port 443 must reach _Traefik_ from the WAN/internet. Both resolvers need it, and so does every private hostname.
- **Storage:** the certificate cache lives in `./net/acme/` on the host and is mounted into the container at `/acme`. Never commit it - it holds your account key and certificate private keys. `net/acme` is already in `.gitignore`.
- **Switching from `stg` to `prd`:** uncomment the `ACME_DEFAULT_RESOLVER="prd"` line in `.env.local`, then `./fimor down && ./fimor clean && ./fimor up`. A partial restart isn't enough: every module's labels name the resolver, so every module has to be recreated. **Let's Encrypt** rate-limits duplicate certificates, so repeating challenges for **_any reason_** during bring-up can lock that **_entire domain_** out of the production issuer - which is why we always recommend bringing a domain online on staging first. `./fimor clean` deletes the whole certificate cache, so no staging certificate is left to be reused.
