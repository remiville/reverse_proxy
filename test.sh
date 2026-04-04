#!/usr/bin/env bash
set -euo pipefail

declare -r SCRIPT_NAME="$(basename "$0")"
declare -r SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
declare -r MANAGE_SH="${SCRIPT_DIR}/manage.sh"

declare -i FAILURES
declare -i KEEP_TMP
declare -a TMP_DIRS
declare NEW_TMP_DIR

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
  echo "error: $*" >&2
  exit 1
}

pass() {
  echo "  PASS  $*"
}

fail() {
  echo "  FAIL  $*" >&2
  FAILURES=$(( FAILURES + 1 ))
}

setup_tmp() {
  NEW_TMP_DIR="$(mktemp -d /tmp/reverse_proxy_test.XXXXXX)"
  printf '{"projects":[]}\n' > "${NEW_TMP_DIR}/projects.json"
  TMP_DIRS+=("${NEW_TMP_DIR}")
}

teardown_tmp() {
  local tmp_dir="${1}"
  if [[ "${KEEP_TMP}" -eq 0 ]]; then
    rm -rf "${tmp_dir}"
  fi
}

run_manage() {
  local tmp_dir="${1}"
  shift
  RP_CONFIG_DIR="${tmp_dir}" bash "${MANAGE_SH}" "$@"
}

assert_contains() {
  local file="${1}"
  local pattern="${2}"
  local desc="${3}"
  if grep -qF "${pattern}" "${file}"; then
    pass "${desc}"
  else
    fail "${desc} — '${pattern}' not found"
    echo "    --- actual content ---" >&2
    sed 's/^/    /' "${file}" >&2
    echo "    ---------------------" >&2
  fi
}

assert_not_contains() {
  local file="${1}"
  local pattern="${2}"
  local desc="${3}"
  if ! grep -qF "${pattern}" "${file}"; then
    pass "${desc}"
  else
    fail "${desc} — '${pattern}' unexpectedly found"
  fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_empty_caddyfile() {
  echo "test: empty Caddyfile (no active projects)"
  setup_tmp
  local tmp_dir="${NEW_TMP_DIR}"
  local caddyfile="${tmp_dir}/Caddyfile"

  run_manage "${tmp_dir}" --add dummy 3000 /dummy/ --no-reload >/dev/null
  run_manage "${tmp_dir}" --remove dummy --no-reload >/dev/null

  assert_contains     "${caddyfile}" ':80 {'  "':80 {' block present"
  assert_not_contains "${caddyfile}" 'redir'  "no redir entries"

  teardown_tmp "${tmp_dir}"
}

test_single_project() {
  echo "test: single active project"
  setup_tmp
  local tmp_dir="${NEW_TMP_DIR}"
  local caddyfile="${tmp_dir}/Caddyfile"

  run_manage "${tmp_dir}" --add myapp 3001 /myapp/ --no-reload >/dev/null

  assert_contains "${caddyfile}" 'redir /myapp /myapp/'      "redir without trailing slash → with"
  assert_contains "${caddyfile}" 'handle_path /myapp/* {'    "handle_path block"
  assert_contains "${caddyfile}" 'reverse_proxy localhost:3001' "reverse_proxy on correct port"

  teardown_tmp "${tmp_dir}"
}

test_multiple_projects() {
  echo "test: multiple active projects"
  setup_tmp
  local tmp_dir="${NEW_TMP_DIR}"
  local caddyfile="${tmp_dir}/Caddyfile"

  run_manage "${tmp_dir}" --add proj-a 3010 /proj-a/ --no-reload >/dev/null
  run_manage "${tmp_dir}" --add proj-b 3011 /proj-b/ --no-reload >/dev/null

  assert_contains "${caddyfile}" 'redir /proj-a /proj-a/'       "proj-a: redir"
  assert_contains "${caddyfile}" 'handle_path /proj-a/* {'      "proj-a: handle_path"
  assert_contains "${caddyfile}" 'reverse_proxy localhost:3010'  "proj-a: reverse_proxy"
  assert_contains "${caddyfile}" 'redir /proj-b /proj-b/'       "proj-b: redir"
  assert_contains "${caddyfile}" 'handle_path /proj-b/* {'      "proj-b: handle_path"
  assert_contains "${caddyfile}" 'reverse_proxy localhost:3011'  "proj-b: reverse_proxy"

  teardown_tmp "${tmp_dir}"
}

test_disabled_project_excluded() {
  echo "test: disabled project excluded from Caddyfile"
  setup_tmp
  local tmp_dir="${NEW_TMP_DIR}"
  local caddyfile="${tmp_dir}/Caddyfile"

  run_manage "${tmp_dir}" --add active-app 3020 /active/ --no-reload >/dev/null
  run_manage "${tmp_dir}" --add hidden-app 3021 /hidden/ --no-reload >/dev/null
  run_manage "${tmp_dir}" --disable hidden-app --no-reload >/dev/null

  assert_contains     "${caddyfile}" 'reverse_proxy localhost:3020' "active project present"
  assert_not_contains "${caddyfile}" 'reverse_proxy localhost:3021' "disabled project absent"

  teardown_tmp "${tmp_dir}"
}

test_reenable_project() {
  echo "test: re-enabled project reappears in Caddyfile"
  setup_tmp
  local tmp_dir="${NEW_TMP_DIR}"
  local caddyfile="${tmp_dir}/Caddyfile"

  run_manage "${tmp_dir}" --add toggled 3030 /toggled/ --no-reload >/dev/null
  run_manage "${tmp_dir}" --disable toggled --no-reload >/dev/null
  assert_not_contains "${caddyfile}" 'reverse_proxy localhost:3030' "absent after disable"

  run_manage "${tmp_dir}" --enable toggled --no-reload >/dev/null
  assert_contains     "${caddyfile}" 'reverse_proxy localhost:3030' "present after re-enable"

  teardown_tmp "${tmp_dir}"
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

print_summary() {
  echo ""
  if [[ "${FAILURES}" -gt 0 ]]; then
    echo "${FAILURES} test(s) FAILED."
  else
    echo "All tests passed."
  fi

  if [[ "${KEEP_TMP}" -eq 1 ]] && [[ "${#TMP_DIRS[@]}" -gt 0 ]]; then
    echo ""
    echo "Temporary directories kept:"
    local dir
    for dir in "${TMP_DIRS[@]}"; do
      echo "  ${dir}"
    done
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
  echo "usage: ${SCRIPT_NAME} [--keep-tmp]"
}

parse_args() {
  for arg in "$@"; do
    case "${arg}" in
      --keep-tmp) KEEP_TMP=1 ;;
      *) usage; exit 1 ;;
    esac
  done
}

run_tests() {
  test_empty_caddyfile
  test_single_project
  test_multiple_projects
  test_disabled_project_excluded
  test_reenable_project
}

main() {
  FAILURES=0
  KEEP_TMP=0
  TMP_DIRS=()

  parse_args "$@"
  run_tests
  print_summary

  [[ "${FAILURES}" -eq 0 ]]
}

main "$@"
