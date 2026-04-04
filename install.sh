#!/usr/bin/env bash
set -euo pipefail

declare -r SCRIPT_NAME="$(basename "$0")"
declare -ra DEPS=(caddy jq)
declare -r CONFIG_DIR="${HOME}/.config/reverse_proxy"
declare -r PROJECTS_FILE="${CONFIG_DIR}/projects.json"

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

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_install() {
  install_deps
  init_config_dir
  ok "Installation complete."
}

cmd_uninstall() {
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
