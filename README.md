# reverse_proxy

Caddy-based reverse proxy manager for a personal VPS. Routes HTTP paths to
internal services via a simple CLI.

## Quick start

```bash
# Add a project
./manage.sh add myapp 3000 /myapp/

# List registered projects
./manage.sh list

# Check proxy status
./manage.sh status
```

## Requirements

- `caddy` in PATH
- `jq` installed
- Sufficient rights to reload Caddy (`caddy reload` or `systemctl reload caddy`)

## Configuration

State is stored in `~/.config/reverse_proxy/projects.json`.  
The `Caddyfile` at `~/.config/reverse_proxy/Caddyfile` is a generated
artefact — do not edit it by hand.

See [AGENTS.md](AGENTS.md) for full command reference.
