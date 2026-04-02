#!/usr/bin/env bash
set -euo pipefail

# reverse_proxy install helper: verify dependencies and suggest install commands

deps=(caddy jq)
missing=()

for dep in "${deps[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    missing+=("$dep")
  fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "All dependencies are installed: ${deps[*]}"
  exit 0
fi

# Determine package manager
pkg_mgr=""
install_cmd=""

if [[ "$(uname)" == "Darwin" ]]; then
  pkg_mgr="brew"
  install_cmd="brew install"
else
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    os_id="${ID,,}"
    os_like="${ID_LIKE,,}"
  else
    os_id=""
    os_like=""
  fi

  if grep -qi -E "ubuntu|debian" /etc/os-release 2>/dev/null; then
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
  else
    pkg_mgr=""  # unknown
  fi
fi

printf "Missing dependencies: %s\n" "${missing[*]}"

if [[ -n "$pkg_mgr" ]]; then
  echo "Detected package manager: $pkg_mgr"
  echo "Run the following command to install missing dependencies:"
  echo
  echo "  $install_cmd ${missing[*]}"
  echo
  if [[ "$pkg_mgr" = "apt" ]]; then
    echo "Note: on Debian/Ubuntu, you may need 'sudo apt update' first (already included in the command above)."
  fi
else
  echo "Unable to detect a supported package manager automatically."
  echo "Please install dependencies manually for your distribution:" 
  for dep in "${missing[@]}"; do
    echo "  - $dep"
  done
fi

exit 1
