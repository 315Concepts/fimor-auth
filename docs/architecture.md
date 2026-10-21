# Architecture

How _FiMOr_ is put together: the modules, the config rendering that ties them to your environment, and the order they start in. Start with the [README](../README.md) for the overview.

- [Modules](#modules) - what each _Compose_ file runs
- [Config Bridge](#config-bridge) - how templates and your environment become _Kratos_, _Hydra_ and SQL configuration
- [Auto-Migrators](#auto-migrators) - how the database schemas stay in step with `ORY_VERSION`
- [Startup Order](#startup-order) - why `./fimor up` starts things the way it does
- [Built on TIBIA](#built-on-tibia) - what the `net` module shares with TIBIA, and what FiMOr changes

![Stack Architecture](./fimor-architecture.png)

Everything joins one external _Docker_ network, `ory_backend`, created by `./fimor up` and removed by `./fimor down`. _Traefik_ is the only container with published ports; it discovers every other service through `traefik.*` labels and routes by hostname or path.

## Modules

| Module   | Compose file                | What it runs |
| -------- | --------------------------- | ------------ |
| `net`    | `docker-compose-net.yaml`    | _Traefik_ - entrypoints, **ACME** resolvers, dashboard, and the shared path-stripping middleware. |
| `pg`     | `docker-compose-pg.yaml`     | _Postgres_ (persisted to `pg/data`), plus the _Kratos_ and _Hydra_ SQL auto-migrators. |
| `ory`    | `docker-compose-ory.yaml`    | The config bridge, _Kratos_, and _Hydra_. |
| `extras` | `docker-compose-extras.yaml` | [kratos-selfservice-ui-node](https://github.com/ory/kratos-selfservice-ui-node) for the login, registration, consent and settings screens, and [ory-admin-ui](https://github.com/dhia-gharsallaoui/kratos-admin-ui) for administering the _Kratos_ / _Hydra_ universe. |
| `debug`  | `docker-compose-debug.yaml`  | [whoami](https://github.com/traefik/whoami) canary, a [_Hydra_ authorization-code](https://www.ory.com/docs/hydra/cli/hydra-perform-authorization-code) consent mock, and [mailslurper](https://github.com/mailslurper/mailslurper) as an SMTP catch-all. |

## Config Bridge

_Kratos_ and _Hydra_ read static YAML, but the values in it - your domain, paths, secrets - live in the environment. The `ory-config-bridge` container closes that gap: on every start it runs `envsubst` over the templates and writes the results next to them.

| Template                          | Rendered to                  |
| --------------------------------- | ---------------------------- |
| `ory/kratos/kratos-template.yml`  | `ory/kratos/kratos.yml`      |
| `pg/init/kratos.sqlt`             | `pg/init/kratos.sql`         |
| `ory/hydra/hydra-template.yml`    | `ory/hydra/hydra.yml`        |
| `pg/init/hydra.sqlt`              | `pg/init/hydra.sql`          |

- **Edit the templates, never the output.** The rendered files are git-ignored and overwritten on every `./fimor up`.
- **Changing a template or an environment value** means re-rendering: `./fimor down ory` then `./fimor up ory -d` re-runs the bridge before _Kratos_ and _Hydra_ start.
- **Database init scripts only run on an empty data directory.** That is _Postgres_ behaviour, not _FiMOr_'s - rendering new SQL won't create databases in a cluster that already has data. You'll need to run those two PSQL commands by hand, if you're using an existing database.

## Auto-Migrators

_Kratos_ and _Hydra_ each own a database schema that changes between releases. Two one-shot containers in the `pg` module, `kratos-migrate` and `hydra-migrate`, apply it so you never run an _Ory_ migration by hand.

| Container        | Image                  | Runs                                    | Database             |
| ---------------- | ---------------------- | --------------------------------------- | -------------------- |
| `kratos-migrate` | `oryd/kratos:v<ORY_VERSION>` | `migrate sql -e --yes` with `kratos.yml` | `POSTGRES_KRATOS_DB` |
| `hydra-migrate`  | `oryd/hydra:v<ORY_VERSION>`  | `migrate sql -e --yes` with `hydra.yml`  | `POSTGRES_HYDRA_DB`  |

- **Same version as the service.** Each migrator uses the same image tag as the service it migrates, so changing `ORY_VERSION` upgrades the schema and the binary together.
- **Runs on every `./fimor up`.** Once _Postgres_ reports healthy, `./fimor up` runs the _Kratos_ migrator to completion, then the _Hydra_ one, and prints a line for each. Their (verbose) log output is hidden; to see it, run one by hand with `./fimor up pg kratos-migrate`. Each applies anything outstanding and exits, so with nothing to apply it does nothing and is safe to repeat.
- **No prompt.** `-e` reads the DSN from the environment and `--yes` applies the migration without asking, so take a backup before changing `ORY_VERSION` - see [Operating the Stack](operations.md#operating-the-stack).
- **Why the bridge runs first.** The migrators read the rendered `kratos.yml` and `hydra.yml`, so `./fimor up` runs the [Config Bridge](#config-bridge) before it starts `pg`. They also restart on failure, which covers a slow database on a cold start.

## Startup Order

`./fimor up` brings the modules up in a fixed order, because several pieces depend on files or services the previous step produces.

| Step | Module / service                | Why it comes here |
| ---- | ------------------------------- | ----------------- |
| 1    | `ory_backend` network           | Every module joins it as an external network, so it has to exist first. |
| 2    | `net` - _Traefik_               | Starts watching for labelled containers and requesting certificates before anything is routed. |
| 3    | `ory` - `ory-config-bridge`     | Renders the SQL init files from your environment. Runs to completion. |
| 4    | `pg` - _Postgres_               | Needs the rendered SQL to create the databases. `./fimor up` waits for it to report healthy. |
| 5    | `pg` - `kratos-migrate`, then `hydra-migrate` | Need the rendered configs and a healthy database. Each runs to completion, one after the other. |
| 6    | `ory` - _Kratos_ and _Hydra_    | Render the _Ory_ configs and start the stack components. |
| 7    | `extras`                        | The self-service and admin UIs call the _Kratos_ and _Hydra_ APIs. |

`./fimor down` runs the same list in reverse, starting with `debug`, and then removes the network. The `debug` module is never started by a bare `./fimor up`.

## Built on _TIBIA_

The edge in FiMOr's `net` module follows [_TIBIA_](https://github.com/315Concepts/TIBIA-router), and FiMOr deliberately keeps its conventions rather than inventing new ones:

| Shared with _TIBIA_ | How FiMOr uses it |
| ----------------- | ----------------- |
| Entrypoints `web-insecure` (80) and `web-secure` (443), with a permanent HTTP-to-HTTPS redirect | Public flows - the self-service UI and the public _Kratos_ and _Hydra_ APIs - run on `web-secure`. |
| `stg` / `prd` **ACME** resolvers and `ACME_DEFAULT_RESOLVER` | One certificate store for the whole stack, and the same staging-first discipline. See [Certificates](networking.md#certificates). |
| `SERVICE_DOMAIN`, `ACME_CERTIFICATE_EMAIL`, `TRAEFIK_VERSION`, `TRAEFIK_SUBDOMAIN` | Same variable names, same meaning, same `.env` / `.env.local` precedence. |
| Label-driven container routing with `exposedbydefault=false` | Every FiMOr service is routed by labels on its own container; anything unlabelled stays unpublished. |
| Host bring-up scripts (_Docker_ install, `ufw`, swap) and the firewall model | Reused in spirit; see [Firewall](networking.md#firewall) and [Scripts](operations.md#scripts). |

`./fimor` is the stack's control script, with the same verbs as _TIBIA_'s `gateway` helper where they apply (`init`, `up`, `down`, `clean`) in one file.

**What FiMOr Changes:**
- **The shared network** is `ory_backend`, where _TIBIA_'s default is `traefik_backend`.
- **The certificate cache** lives in `net/acme/`, where _TIBIA_'s is `acme/`.
- **A debug-only `tcp-smtp` entrypoint** on port `1025` carries mail to the mailslurper catcher, and is meant to be removed for production.
- **A shared `prefix-strip` middleware** removes the _Kratos_ and _Hydra_ path prefixes before requests reach the services.
- **No `verify` command.** _TIBIA_'s built-in routing checks are replaced here by the [Validation](validation.md) steps, which also cover _Kratos_ and _Hydra_.

**Note:** FiMOr ships its own _Traefik_ in the `net` module rather than attaching to a separate _TIBIA_ stack, and both bind ports 80 and 443. Run one edge per host - _TIBIA_'s generous overlap with the `net` module means that using an existing installation should mostly just be a matter of a new backend network and some changes to the `./fimor` script to prevent interfering with the existing edge gateway.
