# Operations

Day-two reference for running FiMOr: every setting, the commands that drive the stack, the checklist for going live, and the scripts that ship with it. Start with the [README](../README.md) for the overview, Quick Start, and architecture.

- [Configuration](#configuration) - every environment variable, and how `.env` and `.env.local` combine
- [Operating the Stack](#operating-the-stack) - stop, back up, reset, and upgrade
- [Going to Production](#going-to-production) - the checklist for retiring the debug services and hardening the defaults
- [Scripts](#scripts) - `./fimor`, the host bring-up scripts, and the _Hydra_ client utilities

## Configuration

All stack configuration is through environment variables. `.env` holds the defaults and `.env.local` holds your machine-specific values; `.env.local` is git-ignored and wins over `.env`. `./fimor init` creates `.env.local` from `.env.base`. The `./fimor` helper loads both files for you; the alternative is to `source` them manually before running your own _Docker Compose_ commands.

| Variable                       | Default                    | Description |
| ------------------------------ | -------------------------- | ----------- |
| `SERVICE_DOMAIN`               | *(required)*               | Base domain you control DNS for - everything stops if it is unset |
| `ACME_CERTIFICATE_EMAIL`       | *(required)*               | Contact address registered with **Let's Encrypt** - everything stops if it is unset |
| `POSTGRES_VERSION`             | `18.3`                     | _Postgres_ image tag |
| `ORY_VERSION`                  | `26.2.0`                   | Image tag for _Kratos_, _Hydra_, and the self-service UI |
| `TRAEFIK_VERSION`              | `3.6`                      | _Traefik_ image tag |
| `POSTGRES_USER`                | `orydbuser`                | Cluster user used by the migrators, _Kratos_, and _Hydra_ |
| `POSTGRES_PASSWORD`            | `orydbpass`                | Cluster password. The default is public knowledge - set your own. |
| `POSTGRES_DB`                  | `postgres`                 | Cluster default database |
| `POSTGRES_KRATOS_DB`           | `kratos`                   | _Kratos_ database name |
| `POSTGRES_HYDRA_DB`            | `hydra`                    | _Hydra_ database name |
| `KRATOS_COOKIE_SECRET`         | *(generated)*              | _Kratos_ cookie signing secret |
| `KRATOS_CIPHER_SECRET`         | *(generated)*              | _Kratos_ cipher secret - must be exactly 32 characters |
| `HYDRA_SYSTEM_SECRET`          | *(generated)*              | _Hydra_ system secret |
| `SELFSERVE_COOKIE_SECRET`      | *(generated)*              | Self-service UI cookie secret |
| `SELFSERVE_CSRF_COOKIE_SECRET` | *(generated)*              | Self-service UI CSRF secret |
| `SELFSERVE_CSRF_COOKIE_NAME`   | `ory_csrf_ui`              | Self-service UI CSRF cookie name |
| `ORY_SMTP_AUTH`                | `test:test`                | `user:password` for the SMTP service. Debug value by default. |
| `ORY_SMTP_CONNECTION_URI`      | _mailslurper on `smtp.<SERVICE_DOMAIN>`_ | Full _Kratos_ courier URI. Debug value by default - see [Going to Production](#going-to-production). |
| `PRIVATE_HTTPS_PORT`                   | `8443`                     | Port for the private HTTPS entrypoint (admin APIs, admin UI, dashboard, debug tools) |
| `ACME_DEFAULT_RESOLVER`        | `stg`                      | **ACME** certificate resolver for every route: `stg` or `prd` |
| `TRAEFIK_SUBDOMAIN`            | `traefik`                  | Dashboard host: `<TRAEFIK_SUBDOMAIN>.<SERVICE_DOMAIN>` |
| `ADMIN_SUBDOMAIN`              | `admin`                    | Admin UI host: `<ADMIN_SUBDOMAIN>.<SERVICE_DOMAIN>` |
| `KRATOS_PUBLIC_PATH`           | `/session`                 | Path prefix for the public _Kratos_ API |
| `KRATOS_ADMIN_PATH`            | `/kratos`                  | Path prefix for the admin _Kratos_ API |
| `HYDRA_PUBLIC_PATH`            | `/oauth`                   | Path prefix for the public _Hydra_ API (also the OIDC issuer) |
| `HYDRA_ADMIN_PATH`             | `/hydra`                   | Path prefix for the admin _Hydra_ API |
| `CONSENT_SUBDOMAIN`            | `consent`                  | Debug consent mock host |
| `MAIL_SUBDOMAIN`               | `webmail`                  | Debug mail UI host |
| `SLURP_SUBDOMAIN`              | `slurp`                    | Debug mail API host |
| `SMTP_SUBDOMAIN`               | `smtp`                     | Debug SMTP host |
| `WHOAMI_PUBLIC_PATH`           | `/whoami`                  | Path-routed canary prefix. Bring-up aid; remove once your domain validates |

- **Precedence:** a variable already set in your shell beats `.env.local`, which beats the defaults in `.env`.
- **Required values:** `SERVICE_DOMAIN` and `ACME_CERTIFICATE_EMAIL` are yours to set; the five secrets are filled in by `./fimor init`. Everything else has a sensible default.
- **Placeholders are blocked.** `./fimor up` stops and lists the offending lines if `.env.local` still contains a `CHANGEME` or `_STUB` value.
- **Keep the two path families apart.** The public and admin path prefixes share a single path-stripping middleware, so don't make one a prefix of another (`/session` and `/sessions` is exactly the sort of collision to avoid).
- **Running Compose by hand:** `source` both files first - plain `docker compose` doesn't read `.env.local`: `set -a; source .env.local; source .env; set +a`

## Operating the Stack

- **Stop:** `./fimor down` stops every module in reverse order and removes the network. Data is kept in `pg/data/`, so the next `./fimor up` resumes where you left off.
- **One module at a time:** `./fimor up <module> [args]` and `./fimor down <module> [args]` pass any extra arguments straight to `docker compose` - e.g. `./fimor up ory ory-kratos -d`, or `./fimor down extras -v`.
- **Back up** `pg/data/` (or use `docker exec ory-pg pg_dump -U <POSTGRES_USER> <database>`, once per database), `.env.local`, and `net/acme/`. Losing `.env.local` loses the ability to decrypt data protected by your secrets.
- **Reset completely:** after `./fimor down`, delete `pg/data/` (owned by the _Postgres_ container user; use `sudo`). **All identities, sessions, and OAuth2 clients are lost.**
- **Upgrade _Ory_:** back up first, read the release notes, change `ORY_VERSION`, then `./fimor down && ./fimor up`. The migrators run on every start and upgrade the schema before the services come up.
- **Update clients:** `ory/hydra/utils` has scripts for creating clients, changing a client's secret, and setting post-logout redirect URIs - see [Scripts](#scripts).
- **Administration:** the admin UI at `https://admin.<SERVICE_DOMAIN>:8443` lets you create, monitor, and administer the _Kratos_ and _Hydra_ universe.

## Going to Production

The debug module and its defaults exist to prove the stack works. Before real users arrive:

1. **Switch to the production resolver** - see [Certificates](networking.md#certificates).
2. **Point _Kratos_ at a real SMTP provider.** Set `ORY_SMTP_CONNECTION_URI` in `.env.local` to your provider's connection URI, then re-render and restart: `./fimor down ory && ./fimor up ory -d`.
3. **Stop the debug services:** `./fimor down debug`. Mailslurper stores every verification and recovery code in a mailbox anyone can open on the private port.
4. **Close SMTP ingress.** Remove the `tcp-smtp` entrypoint and the `1025:1025` port mapping from `docker-compose-net.yaml` (both are marked `Remove for production mode`), and make sure port 1025 is closed on your firewall.
5. **Remove the validation client** from _Hydra_ - the admin UI makes this a few clicks.
6. **Change `POSTGRES_PASSWORD`** from its default, before the first start if you can.
7. **Lock down `PRIVATE_HTTPS_PORT`** at your cloud or service firewall to the addresses that administer the stack.

## Scripts

Run these from the repository root.

| Script                                   | What it does |
| ---------------------------------------- | ------------ |
| `./fimor init`                           | Creates `.env.local` from `.env.base` with fresh random secrets, mode 600, and lists the values you still need to set. Refuses to overwrite an existing `.env.local`. |
| `./fimor up`                             | Creates the network, starts _Traefik_, renders configs, starts _Postgres_ and the migrators, then _Kratos_, _Hydra_, and the extras. Refuses to run while placeholders are unset. |
| `./fimor up <module> [args]`             | Runs `docker compose up` for a single module. Modules: `pg`, `ory`, `extras`, `net`, `debug`. |
| `./fimor down`                           | Stops debug, extras, ory, pg, then net, and removes the network. |
| `./fimor down <module> [args]`           | Runs `docker compose down` for a single module. |
| `./fimor clean`                          | Deletes `net/acme/` - the staging and production certificate caches. Refuses to run while _Traefik_ is up; uses `sudo` if the cache is root-owned. |
| `scripts/install-docker-debian.sh`, `scripts/install-docker-ubuntu.sh` | Installs _Docker Engine_ and the _Compose_ plugin from _Docker_'s apt repository, then runs `hello-world`. |
| `scripts/configure-ufw.sh`               | Backs up `/etc/ufw`, allows 22, 80, 443 and `PRIVATE_HTTPS_PORT`, denies other inbound traffic, and enables the firewall. **_Review before running._** |
| `scripts/configure-swap.sh`              | Adds a swap file sized at 100% of RAM (`SWAP_PERCENT`, `SWAP_FILE` to override), persists it in `/etc/fstab`, and sets `vm.swappiness=10`. Skips if swap is already active. |
| `ory/hydra/utils/create-oauth2-client.sh` | Creates an authorization-code client whose callback is the debug consent mock, and prints its ID and secret. |
| `ory/hydra/utils/create-client-credential-client.sh` | Creates a `client_credentials` client and prints its ID and secret. |
| `ory/hydra/utils/get-client-credential-grant.sh` | Requests a token for the client in `CREDENTIAL_CLIENT_ID` / `CREDENTIAL_CLIENT_SECRET`. |
| `ory/hydra/utils/set-client-logout-uris.sh` | Replaces a client's post-logout redirect URIs. Edit `ClientLogoutUriPayload.json` first; the client is `HYDRA_CLIENT_ID`, defaulting to `CONSENT_CLIENT_ID`. |
| `ory/hydra/utils/set-client-password.sh` | Replaces a client's secret. Edit `ClientSecretPayload.json` first; the client is `HYDRA_CLIENT_ID`, defaulting to `CONSENT_CLIENT_ID`. |
