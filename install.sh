#!/usr/bin/env bash
set -euo pipefail

declare -r SCRIPT_NAME="$(basename "$0")"
declare -ra DEPS=(caddy jq)
declare -r CONFIG_DIR="${HOME}/.config/reverse_proxy"
declare -r PROJECTS_FILE="${CONFIG_DIR}/projects.json"
declare -r CADDYFILE="${CONFIG_DIR}/Caddyfile"
declare -r SERVICE_NAME="caddy-rp"
declare -r SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
declare -r SERVICE_FILE="${SYSTEMD_USER_DIR}/${SERVICE_NAME}.service"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
  echo "error: $*" >&2
  exit 1
}

ok() {
  echo -e "$*"
}

detect_pkg_manager() {
  local pkg_mgr=""
  local install_cmd=""

  if [[ "$(uname)" == "Darwin" ]]; then
    pkg_mgr="brew"
    install_cmd="brew install"
  elif grep -qi -E "ubuntu|debian" /etc/os-release 2>/dev/null; then
    pkg_mgr="apt"
    install_cmd="sudo apt update && sudo apt install -y"
  elif grep -qi -E "fedora" /etc/os-release 2>/dev/null; then
    pkg_mgr="dnf"
    install_cmd="sudo dnf install -y"
  elif grep -qi -E "rhel|centos|amzn|rocky|almalinux" /etc/os-release 2>/dev/null; then
    pkg_mgr="yum"
    install_cmd="sudo yum install -y"
  elif grep -qi -E "arch" /etc/os-release 2>/dev/null; then
    pkg_mgr="pacman"
    install_cmd="sudo pacman -Syu --noconfirm"
  elif grep -qi -E "alpine" /etc/os-release 2>/dev/null; then
    pkg_mgr="apk"
    install_cmd="sudo apk add"
  fi

  echo "${pkg_mgr}|${install_cmd}"
}

install_deps() {
  local missing=()
  local dep

  for dep in "${DEPS[@]}"; do
    if ! command -v "${dep}" &>/dev/null; then
      missing+=("${dep}")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "All dependencies already installed: ${DEPS[*]}"
    return 0
  fi

  local pkg_info
  pkg_info="$(detect_pkg_manager)"
  local pkg_mgr="${pkg_info%%|*}"
  local install_cmd="${pkg_info##*|}"

  printf "Missing dependencies: %s\n" "${missing[*]}"

  if [[ -n "${pkg_mgr}" ]]; then
    ok "Detected package manager: ${pkg_mgr}"
    ok "Run the following command to install missing dependencies:"
    echo
    echo "  ${install_cmd} ${missing[*]}"
    echo
  else
    echo "Unable to detect a supported package manager automatically."
    echo "Please install dependencies manually for your distribution:"
    for dep in "${missing[@]}"; do
      echo "  - ${dep}"
    done
  fi

  exit 1
}

init_config_dir() {
  if [[ ! -d "${CONFIG_DIR}" ]]; then
    mkdir -p "${CONFIG_DIR}"
    ok "Created config directory: ${CONFIG_DIR}"
  fi
  if [[ ! -f "${PROJECTS_FILE}" ]]; then
    printf '{"projects":[]}\n' > "${PROJECTS_FILE}"
    ok "Initialized projects file: ${PROJECTS_FILE}"
  fi
}

create_service() {
  local caddy_bin
  caddy_bin="$(command -v caddy)"

  mkdir -p "${SYSTEMD_USER_DIR}"
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Caddy Reverse Proxy
After=network.target

[Service]
Type=simple
ExecStart=${caddy_bin} run --config ${CADDYFILE}
ExecReload=${caddy_bin} reload --config ${CADDYFILE}
Restart=on-failure
TimeoutStopSec=5s

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable "${SERVICE_NAME}"
  ok "Service '${SERVICE_NAME}' installed and enabled.\nWARNING: sudo loginctl enable-linger $USER must be called at least once for the service to not stop when the user logs out."
}

remove_service() {
  if systemctl --user is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    systemctl --user stop "${SERVICE_NAME}"
    ok "Service '${SERVICE_NAME}' stopped."
  fi
  if systemctl --user is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
    systemctl --user disable "${SERVICE_NAME}"
    ok "Service '${SERVICE_NAME}' disabled."
  fi
  if [[ -f "${SERVICE_FILE}" ]]; then
    rm -f "${SERVICE_FILE}"
    systemctl --user daemon-reload
    ok "Removed service file: ${SERVICE_FILE}"
  fi
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_install() {
  install_deps
  init_config_dir
  create_service
  ok "Installation complete."
}

cmd_uninstall() {
  remove_service
  if [[ -d "${CONFIG_DIR}" ]]; then
    rm -rf "${CONFIG_DIR}"
    ok "Removed config directory: ${CONFIG_DIR}"
  else
    ok "Nothing to remove: ${CONFIG_DIR} does not exist."
  fi
}

cmd_update() {
  local pkg_info
  pkg_info="$(detect_pkg_manager)"
  local pkg_mgr="${pkg_info%%|*}"
  local install_cmd="${pkg_info##*|}"

  if [[ -z "${pkg_mgr}" ]]; then
    die "Unable to detect a supported package manager. Please update dependencies manually: ${DEPS[*]}"
  fi

  ok "Detected package manager: ${pkg_mgr}"
  ok "Run the following command to update dependencies:"
  echo
  echo "  ${install_cmd} ${DEPS[*]}"
  echo
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
  echo "usage: ${SCRIPT_NAME} <--install|--uninstall|--update>"
}

main() {
  local option="${1:-}"

  case "${option}" in
    --install)   cmd_install ;;
    --uninstall) cmd_uninstall ;;
    --update)    cmd_update ;;
    --help)      usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
