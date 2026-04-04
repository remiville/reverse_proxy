# reverse_proxy

Caddy-based reverse proxy manager for a personal VPS. Routes HTTP paths to
internal services via a simple CLI.

## Quick start

```bash
# Install dependencies and initialize config
./install.sh --install

# Add a project
./manage.sh --add myapp 3000 /myapp/

# Start Caddy
./manage.sh --start

# List registered projects
./manage.sh --list

# Check proxy status
./manage.sh --status
```

## Requirements

- `caddy` in PATH
- `jq` installed
- Sufficient rights to run Caddy (`caddy start` / `caddy stop`)

## Configuration

State is stored in `~/.config/reverse_proxy/projects.json`.  
The `Caddyfile` at `~/.config/reverse_proxy/Caddyfile` is a generated
artefact — do not edit it by hand.

Run the test suite:

```bash
./test.sh           # run and clean up
./test.sh --keep-tmp  # keep temp dirs for inspection
```

See [AGENTS.md](AGENTS.md) for full command reference.
