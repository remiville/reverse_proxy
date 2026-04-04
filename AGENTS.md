# AGENTS.md — reverse_proxy

## Role

This project manages a Caddy-based reverse proxy on a personal VPS. It routes
HTTP paths to internal services running on local ports.

## Configuration location

All runtime configuration lives in `~/.config/reverse_proxy/`:

| File             | Purpose                                          |
|------------------|--------------------------------------------------|
| `projects.json`  | Source of truth — list of registered projects    |
| `Caddyfile`      | Derived artefact — **never edit directly**       |

The `Caddyfile` is always regenerated from `projects.json`. Any manual edit
will be overwritten on the next `manage.sh` operation.

## install.sh

```
./install.sh <option>
```

| Option        | Effect                                                      |
|---------------|-------------------------------------------------------------|
| `--install`   | Check dependencies, print install command if missing, init config dir |
| `--uninstall` | Remove `~/.config/reverse_proxy/` entirely                  |
| `--update`    | Print command to update `caddy` and `jq` via detected package manager |

## manage.sh

```
./manage.sh <option> [arguments]
```

### Caddy lifecycle

| Option      | Effect                                              |
|-------------|-----------------------------------------------------|
| `--start`   | Regenerate Caddyfile and start Caddy                |
| `--restart` | Stop then start Caddy with regenerated Caddyfile    |
| `--stop`    | Stop Caddy                                          |
| `--reload`  | Regenerate Caddyfile and reload Caddy               |
| `--status`  | Show Caddy process state and active routes          |
| `--log`     | Show Caddy logs (`-f` to follow)                    |

### Project management

| Option                          | Effect                                                |
|---------------------------------|-------------------------------------------------------|
| `--add <name> <port> <path>`    | Register project, regenerate Caddyfile, reload Caddy  |
| `--remove <name>`               | Unregister project, regenerate, reload                |
| `--enable <name>`               | Set status → active, regenerate, reload               |
| `--disable <name>`              | Set status → disabled, regenerate, reload             |
| `--list`                        | Print registered projects in tabular form             |

Add `--no-reload` to any mutating project command to skip the `caddy reload` step.

### Examples

```bash
# Full setup
./install.sh --install
./manage.sh --add shootcube 3042 /shootcube/
./manage.sh --start

# Disable temporarily
./manage.sh --disable resto

# Batch add without reloading each time
./manage.sh --add proj-a 3010 /proj-a/ --no-reload
./manage.sh --add proj-b 3011 /proj-b/ --no-reload
./manage.sh --reload

# Follow logs
./manage.sh --log -f
```

## Conventions

- **name**: alphanumeric + hyphens, unique across all projects
- **port**: integer in range 3000–9999, unique across all projects
- **path**: must start and end with `/` (e.g. `/myapp/`)
- **status**: `active` (included in Caddyfile) or `disabled` (excluded)

Only `active` projects appear in the generated Caddyfile and receive traffic.
