#!/usr/bin/env bash
set -euo pipefail

declare -r SCRIPT_NAME="$(basename "$0")"
declare -r CONFIG_DIR="${RP_CONFIG_DIR:-${HOME}/.config/reverse_proxy}"
declare -r PROJECTS_FILE="${CONFIG_DIR}/projects.json"
declare -r CADDYFILE="${CONFIG_DIR}/Caddyfile"

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
    jq -r '
      .projects[]
      | select(.status == "active")
      | "    redir \(.path | rtrimstr("/")) \(.path)\n    handle_path \(.path | rtrimstr("/"))/* {\n        reverse_proxy localhost:\(.port) {\n        }\n    }\n"
    ' "${PROJECTS_FILE}"
    printf '}\n'
  } > "${tmp}"
  mv "${tmp}" "${CADDYFILE}"
}

require_caddy() {
  command -v caddy &>/dev/null || die "caddy not found in PATH"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_start() {
  require_caddy
  generate_caddyfile
  caddy start --config "${CADDYFILE}" 2>&1 || die "caddy start failed"
  ok "Caddy started."
}

cmd_restart() {
  require_caddy
  generate_caddyfile
  caddy stop 2>&1 || true
  caddy start --config "${CADDYFILE}" 2>&1 || die "caddy restart failed"
  ok "Caddy restarted."
}

cmd_stop() {
  require_caddy
  caddy stop 2>&1 || die "caddy stop failed"
  ok "Caddy stopped."
}

cmd_reload() {
  require_caddy
  generate_caddyfile
  caddy reload --config "${CADDYFILE}" 2>&1 || die "caddy reload failed"
  ok "Caddyfile regenerated and Caddy reloaded."
}

cmd_status() {
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

cmd_log() {
  local follow=0
  for arg in "$@"; do
    [[ "${arg}" == "-f" ]] && follow=1
  done

  if command -v journalctl &>/dev/null; then
    if [[ "${follow}" -eq 1 ]]; then
      journalctl -u caddy -f
    else
      journalctl -u caddy
    fi
  else
    die "journalctl not available; check your system's service manager for caddy logs"
  fi
}

cmd_add() {
  local name="${1:-}"
  local port="${2:-}"
  local path="${3:-}"
  local no_reload=0

  [[ -n "${name}" ]] || die "usage: ${SCRIPT_NAME} --add <name> <port> <path> [--no-reload]"
  [[ -n "${port}" ]] || die "usage: ${SCRIPT_NAME} --add <name> <port> <path> [--no-reload]"
  [[ -n "${path}" ]] || die "usage: ${SCRIPT_NAME} --add <name> <port> <path> [--no-reload]"
  shift 3
  for arg in "$@"; do
    [[ "${arg}" == "--no-reload" ]] && no_reload=1
  done

  [[ "${name}" =~ ^[a-zA-Z0-9-]+$ ]] || die "invalid name '${name}': only alphanumeric and hyphens allowed"
  [[ "${port}" =~ ^[0-9]+$ ]] || die "invalid port '${port}': must be an integer"
  (( port >= 3000 && port <= 9999 )) || die "port ${port} out of range (3000–9999)"
  [[ "${path}" =~ ^/.+/$ ]] || die "invalid path '${path}': must start and end with '/'"

  local name_exists
  name_exists=$(jq --arg n "${name}" '.projects[] | select(.name == $n) | .name' "${PROJECTS_FILE}")
  [[ -z "${name_exists}" ]] || die "name '${name}' already exists"

  local port_exists
  port_exists=$(jq --argjson p "${port}" '.projects[] | select(.port == $p) | .port' "${PROJECTS_FILE}")
  [[ -z "${port_exists}" ]] || die "port ${port} already in use"

  local tmp
  tmp="$(mktemp)"
  jq --arg name "${name}" --argjson port "${port}" --arg path "${path}" \
    '.projects += [{"name": $name, "port": $port, "path": $path, "status": "active"}]' \
    "${PROJECTS_FILE}" > "${tmp}"
  mv "${tmp}" "${PROJECTS_FILE}"

  generate_caddyfile
  ok "Project '${name}' added (port ${port}, path ${path})."

  [[ "${no_reload}" -eq 1 ]] || cmd_reload
}

cmd_remove() {
  local name="${1:-}"
  local no_reload=0

  [[ -n "${name}" ]] || die "usage: ${SCRIPT_NAME} --remove <name> [--no-reload]"
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

  [[ "${no_reload}" -eq 1 ]] || cmd_reload
}

cmd_set_status() {
  local new_status="${1}"
  local name="${2:-}"
  local no_reload=0

  [[ -n "${name}" ]] || die "usage: ${SCRIPT_NAME} --${new_status} <name> [--no-reload]"
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

  [[ "${no_reload}" -eq 1 ]] || cmd_reload
}

cmd_list() {
  printf '%-16s %-6s %-20s %s\n' "NAME" "PORT" "PATH" "STATUS"
  jq -r '.projects[] | [.name, (.port | tostring), .path, .status] | @tsv' "${PROJECTS_FILE}" \
    | while IFS=$'\t' read -r n p pa s; do
        printf '%-16s %-6s %-20s %s\n' "${n}" "${p}" "${pa}" "${s}"
      done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
usage: ${SCRIPT_NAME} <option> [args]

Options:
  --start                         Start Caddy
  --restart                       Restart Caddy
  --stop                          Stop Caddy
  --reload                        Regenerate Caddyfile and reload Caddy
  --status                        Show Caddy and project status
  --log [-f]                      Show Caddy logs (use -f to follow)
  --add <name> <port> <path>      Add a project [--no-reload]
  --remove <name>                 Remove a project [--no-reload]
  --enable <name>                 Enable a project [--no-reload]
  --disable <name>                Disable a project [--no-reload]
  --list                          List all projects
EOF
}

main() {
  ensure_config_dir

  local option="${1:-}"
  [[ -n "${option}" ]] || { usage; exit 1; }
  shift

  case "${option}" in
    --start)   cmd_start ;;
    --restart) cmd_restart ;;
    --stop)    cmd_stop ;;
    --reload)  cmd_reload ;;
    --status)  cmd_status ;;
    --log)     cmd_log "$@" ;;
    --add)     cmd_add "$@" ;;
    --remove)  cmd_remove "$@" ;;
    --enable)  cmd_set_status "active" "$@" ;;
    --disable) cmd_set_status "disabled" "$@" ;;
    --list)    cmd_list ;;
    *) die "unknown option '${option}'" ;;
  esac
}

main "$@"
