#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG_DIR="${HOME}/.config/reverse_proxy"
PROJECTS_FILE="${CONFIG_DIR}/projects.json"
CADDYFILE="${CONFIG_DIR}/Caddyfile"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() {
    echo "error: $*" >&2
    exit 1
}

ok() {
    echo "$*"
}

ensure_config_dir() {
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        mkdir -p "${CONFIG_DIR}"
    fi
    if [[ ! -f "${PROJECTS_FILE}" ]]; then
        printf '{"projects":[]}\n' > "${PROJECTS_FILE}"
    fi
}

generate_caddyfile() {
    local tmp
    tmp="$(mktemp)"
    {
        printf ':80 {\n'
        jq -r '.projects[] | select(.status == "active") | "    handle \(.path)* {\n        reverse_proxy localhost:\(.port)\n    }\n"' "${PROJECTS_FILE}"
        printf '}\n'
    } > "${tmp}"
    mv "${tmp}" "${CADDYFILE}"
}

reload_caddy() {
    if command -v caddy &>/dev/null; then
        caddy reload --config "${CADDYFILE}" 2>&1 || die "caddy reload failed"
        ok "Caddy reloaded."
    else
        die "caddy not found in PATH"
    fi
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_add() {
    local name="${1:-}"
    local port="${2:-}"
    local path="${3:-}"
    local no_reload=0

    [[ -n "${name}" ]] || die "usage: manage.sh add <name> <port> <path> [--no-reload]"
    [[ -n "${port}" ]] || die "usage: manage.sh add <name> <port> <path> [--no-reload]"
    [[ -n "${path}" ]] || die "usage: manage.sh add <name> <port> <path> [--no-reload]"
    shift 3
    for arg in "$@"; do
        [[ "${arg}" == "--no-reload" ]] && no_reload=1
    done

    # Validate name
    [[ "${name}" =~ ^[a-zA-Z0-9-]+$ ]] || die "invalid name '${name}': only alphanumeric and hyphens allowed"

    # Validate port
    [[ "${port}" =~ ^[0-9]+$ ]] || die "invalid port '${port}': must be an integer"
    (( port >= 3000 && port <= 9999 )) || die "port ${port} out of range (3000–9999)"

    # Validate path
    [[ "${path}" =~ ^/.+/$ ]] || die "invalid path '${path}': must start and end with '/'"

    # Check uniqueness
    local name_exists
    name_exists=$(jq --arg n "${name}" '.projects[] | select(.name == $n) | .name' "${PROJECTS_FILE}")
    [[ -z "${name_exists}" ]] || die "name '${name}' already exists"

    local port_exists
    port_exists=$(jq --argjson p "${port}" '.projects[] | select(.port == $p) | .port' "${PROJECTS_FILE}")
    [[ -z "${port_exists}" ]] || die "port ${port} already in use"

    # Atomic write
    local tmp
    tmp="$(mktemp)"
    jq --arg name "${name}" --argjson port "${port}" --arg path "${path}" \
        '.projects += [{"name": $name, "port": $port, "path": $path, "status": "active"}]' \
        "${PROJECTS_FILE}" > "${tmp}"
    mv "${tmp}" "${PROJECTS_FILE}"

    generate_caddyfile
    ok "Project '${name}' added (port ${port}, path ${path})."

    [[ "${no_reload}" -eq 1 ]] || reload_caddy
}

cmd_remove() {
    local name="${1:-}"
    local no_reload=0

    [[ -n "${name}" ]] || die "usage: manage.sh remove <name> [--no-reload]"
    shift 1
    for arg in "$@"; do
        [[ "${arg}" == "--no-reload" ]] && no_reload=1
    done

    local exists
    exists=$(jq --arg n "${name}" '.projects[] | select(.name == $n) | .name' "${PROJECTS_FILE}")
    [[ -n "${exists}" ]] || die "project '${name}' not found"

    local tmp
    tmp="$(mktemp)"
    jq --arg n "${name}" 'del(.projects[] | select(.name == $n))' "${PROJECTS_FILE}" > "${tmp}"
    mv "${tmp}" "${PROJECTS_FILE}"

    generate_caddyfile
    ok "Project '${name}' removed."

    [[ "${no_reload}" -eq 1 ]] || reload_caddy
}

cmd_set_status() {
    local new_status="${1}"
    local name="${2:-}"
    local no_reload=0

    [[ -n "${name}" ]] || die "usage: manage.sh ${new_status} <name> [--no-reload]"
    shift 2
    for arg in "$@"; do
        [[ "${arg}" == "--no-reload" ]] && no_reload=1
    done

    local exists
    exists=$(jq --arg n "${name}" '.projects[] | select(.name == $n) | .name' "${PROJECTS_FILE}")
    [[ -n "${exists}" ]] || die "project '${name}' not found"

    local tmp
    tmp="$(mktemp)"
    jq --arg n "${name}" --arg s "${new_status}" \
        '(.projects[] | select(.name == $n) | .status) |= $s' \
        "${PROJECTS_FILE}" > "${tmp}"
    mv "${tmp}" "${PROJECTS_FILE}"

    generate_caddyfile
    if [[ "${new_status}" == "active" ]]; then
        ok "Project '${name}' enabled."
    else
        ok "Project '${name}' disabled."
    fi

    [[ "${no_reload}" -eq 1 ]] || reload_caddy
}

cmd_list() {
    printf '%-16s %-6s %-20s %s\n' "NAME" "PORT" "PATH" "STATUS"
    jq -r '.projects[] | [.name, (.port | tostring), .path, .status] | @tsv' "${PROJECTS_FILE}" \
        | while IFS=$'\t' read -r n p pa s; do
            printf '%-16s %-6s %-20s %s\n' "${n}" "${p}" "${pa}" "${s}"
        done
}

cmd_reload() {
    generate_caddyfile
    ok "Caddyfile regenerated."
    reload_caddy
}

cmd_status() {
    # Caddy process
    if pgrep -x caddy &>/dev/null; then
        echo "Caddy: running"
    else
        echo "Caddy: stopped"
    fi

    echo ""
    echo "Caddyfile: ${CADDYFILE}"
    echo ""
    echo "Active routes:"
    jq -r '.projects[] | select(.status == "active") | "  \(.path)  →  localhost:\(.port)"' "${PROJECTS_FILE}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
ensure_config_dir

COMMAND="${1:-}"
[[ -n "${COMMAND}" ]] || die "usage: manage.sh <add|remove|enable|disable|list|reload|status> [args]"
shift

case "${COMMAND}" in
    add)     cmd_add "$@" ;;
    remove)  cmd_remove "$@" ;;
    enable)  cmd_set_status "active" "$@" ;;
    disable) cmd_set_status "disabled" "$@" ;;
    list)    cmd_list ;;
    reload)  cmd_reload ;;
    status)  cmd_status ;;
    *)       die "unknown command '${COMMAND}'" ;;
esac
