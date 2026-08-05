#!/usr/bin/env bash
#
# aigo CLI installer (binary-only public distribution)
#
# Usage (public channel — no GitHub auth required):
#   curl -fsSL https://raw.githubusercontent.com/AI-GO-APP/aigo-cli-releases/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/AI-GO-APP/aigo-cli-releases/main/install.sh | bash -s 0.2.3
#
# Env:
#   AIGO_DIST_REPO   GitHub repo for install assets (default: AI-GO-APP/aigo-cli-releases)
#   AIGO_BIN_DIR     Install directory (default: ~/.local/bin)
#   AIGO_VERSION     Version without leading v (alternative to bash -s)
#   GITHUB_TOKEN     Optional; only needed if AIGO_DIST_REPO is private
#   GH_TOKEN         Alias for GITHUB_TOKEN
#
# Source code lives in a separate private repository and is not distributed
# by this script. See LICENSE (Binary Distribution License).
#
# Windows: run under Git Bash / MSYS2; WSL uses the Linux binary.

set -euo pipefail

# Public binary-only channel (NOT the private source repo).
REPO="${AIGO_DIST_REPO:-AI-GO-APP/aigo-cli-releases}"
API_BASE="https://api.github.com/repos/${REPO}"
DOWNLOAD_BASE="https://github.com/${REPO}/releases/download"

VERSION="${1:-${AIGO_VERSION:-}}"
BIN_DIR="${AIGO_BIN_DIR:-${HOME}/.local/bin}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

log()  { printf '%s\n' "$*"; }
err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "'$1' is required"; }

# --- platform ---------------------------------------------------------------

detect_target() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "${os}" in
    linux*)                   os="linux" ;;
    darwin*)                  os="darwin" ;;
    msys*|mingw*|cygwin*)     os="windows" ;;
    *) err "unsupported OS: $(uname -s)" ;;
  esac

  case "${arch}" in
    x86_64|amd64)   arch="x86_64" ;;
    aarch64|arm64)  arch="aarch64" ;;
    *) err "unsupported architecture: $(uname -m)" ;;
  esac

  case "${os}-${arch}" in
    linux-x86_64)   echo "x86_64-unknown-linux-gnu" ;;
    darwin-aarch64) echo "aarch64-apple-darwin" ;;
    windows-x86_64) echo "x86_64-pc-windows-msvc" ;;
    darwin-x86_64)
      err "Intel macOS builds are not published yet (need Apple Silicon / aarch64)"
      ;;
    linux-aarch64)
      err "Linux ARM builds are not published yet (need x86_64)"
      ;;
    *)
      err "no prebuilt binary for ${os}/${arch}"
      ;;
  esac
}

binary_name() {
  case "$1" in
    *windows*) echo "aigo.exe" ;;
    *)         echo "aigo" ;;
  esac
}

archive_name() {
  local version="$1" target="$2"
  case "${target}" in
    *windows*) echo "aigo-${version}-${target}.zip" ;;
    *)         echo "aigo-${version}-${target}.tar.gz" ;;
  esac
}

# --- http -------------------------------------------------------------------

# GET api.github.com path or full URL → stdout.
http_get_api() {
  local url="$1"

  if command -v gh >/dev/null 2>&1 && [[ -z "${TOKEN}" ]]; then
    if [[ "${url}" == https://api.github.com/* ]]; then
      gh api "${url#https://api.github.com/}"
      return
    fi
  fi

  local -a args=(-fsSL -H "Accept: application/vnd.github+json")
  if [[ -n "${TOKEN}" ]]; then
    args+=(-H "Authorization: Bearer ${TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28")
  fi
  curl "${args[@]}" "${url}"
}

# Download release asset to dest.
download_asset() {
  local tag="$1" asset="$2" dest="$3"

  # 1) GitHub CLI (handles auth when configured)
  if command -v gh >/dev/null 2>&1; then
    local dir
    dir="$(dirname "${dest}")"
    if gh release download "${tag}" --repo "${REPO}" --pattern "${asset}" --dir "${dir}" --clobber 2>/dev/null; then
      if [[ -f "${dir}/${asset}" ]]; then
        if [[ "${dir}/${asset}" != "${dest}" ]]; then
          mv -f "${dir}/${asset}" "${dest}"
        fi
        return 0
      fi
    fi
  fi

  # 2) Token: resolve asset id, then download via API
  if [[ -n "${TOKEN}" ]]; then
    local release_json asset_id
    release_json="$(http_get_api "${API_BASE}/releases/tags/${tag}")" \
      || err "failed to fetch release ${tag}"
    asset_id=""
    if command -v python3 >/dev/null 2>&1; then
      asset_id="$(
        printf '%s' "${release_json}" | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for a in data.get("assets", []):
    if a.get("name") == name:
        print(a["id"])
        break
' "${asset}" 2>/dev/null || true
      )"
    elif command -v jq >/dev/null 2>&1; then
      asset_id="$(
        printf '%s' "${release_json}" \
          | jq -r --arg n "${asset}" '.assets[] | select(.name == $n) | .id' \
          | head -1
      )"
    fi
    if [[ -z "${asset_id}" || "${asset_id}" == "null" ]]; then
      asset_id="$(
        printf '%s' "${release_json}" \
          | tr '}' '\n' \
          | grep -F "\"name\": \"${asset}\"" \
          | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
          | head -1
      )"
    fi
    [[ -n "${asset_id}" && "${asset_id}" != "null" ]] || err "asset '${asset}' not found on release ${tag}"
    curl -fsSL \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/octet-stream" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -o "${dest}" \
      "${API_BASE}/releases/assets/${asset_id}" \
      || err "failed to download asset id ${asset_id}"
    return 0
  fi

  # 3) Public unauthenticated browser URL (default path for aigo-cli-releases)
  curl -fsSL -o "${dest}" "${DOWNLOAD_BASE}/${tag}/${asset}" \
    || err "failed to download ${asset} from ${REPO}

Expected a public release asset at:
  ${DOWNLOAD_BASE}/${tag}/${asset}

If you are using a private dist repo, set GITHUB_TOKEN or run: gh auth login"
}

# --- version ----------------------------------------------------------------

latest_version() {
  local json tag
  json="$(http_get_api "${API_BASE}/releases/latest" 2>/dev/null)" \
    || err "failed to fetch latest release from ${REPO}
Is the public dist repo published? See docs/distribution.md"
  tag="$(printf '%s' "${json}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "${tag}" ]] || err "could not parse latest release tag (no releases yet on ${REPO}?)"
  printf '%s\n' "${tag#v}"
}

# --- install ----------------------------------------------------------------

find_binary() {
  local root="$1" name="$2"
  local f
  while IFS= read -r -d '' f; do
    printf '%s\n' "${f}"
    return 0
  done < <(find "${root}" -type f -name "${name}" -print0 2>/dev/null)
  return 1
}

install_from_archive() {
  local archive="$1" target="$2" tmp="$3"
  local bin found
  bin="$(binary_name "${target}")"

  mkdir -p "${tmp}/extract"
  case "${archive}" in
    *.zip)
      need unzip
      unzip -q "${archive}" -d "${tmp}/extract"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "${archive}" -C "${tmp}/extract"
      ;;
    *) err "unknown archive format: ${archive}" ;;
  esac

  found="$(find_binary "${tmp}/extract" "${bin}")" \
    || err "binary '${bin}' not found in archive"
  [[ -f "${found}" ]] || err "binary '${bin}' not found in archive"

  mkdir -p "${BIN_DIR}"
  install -m 755 "${found}" "${BIN_DIR}/${bin}"
  log "Installed ${bin} → ${BIN_DIR}/${bin}"
}

ensure_path_hint() {
  local bin_dir="$1"
  case ":${PATH}:" in
    *":${bin_dir}:"*) return 0 ;;
  esac

  log ""
  log "Note: ${bin_dir} is not on your PATH."
  log "Add this to your shell profile (~/.zshrc / ~/.bashrc):"
  log ""
  log "  export PATH=\"${bin_dir}:\$PATH\""
  log ""
  log "Then open a new terminal, or run:  export PATH=\"${bin_dir}:\$PATH\""
}

main() {
  need curl
  need uname
  need tar
  need find
  need install

  local target version tag asset tmp archive
  target="$(detect_target)"

  if [[ -z "${VERSION}" ]]; then
    log "Resolving latest release from ${REPO}…"
    VERSION="$(latest_version)"
  fi
  VERSION="${VERSION#v}"
  tag="v${VERSION}"
  asset="$(archive_name "${VERSION}" "${target}")"

  log "Installing aigo ${VERSION} (${target})"
  log "  dist: ${REPO}"
  log "  → ${BIN_DIR}"

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap 'rm -rf "'"${tmp}"'"' EXIT

  archive="${tmp}/${asset}"
  log "Downloading ${asset}…"
  download_asset "${tag}" "${asset}" "${archive}"
  install_from_archive "${archive}" "${target}" "${tmp}"

  local installed
  installed="$(binary_name "${target}")"
  if [[ -x "${BIN_DIR}/${installed}" ]]; then
    log ""
    log "Done. $("${BIN_DIR}/${installed}" --version 2>/dev/null || echo "aigo ${VERSION}")"
  else
    log ""
    log "Done."
  fi

  if ! command -v aigo >/dev/null 2>&1; then
    ensure_path_hint "${BIN_DIR}"
  fi

  log "Try:  aigo --help"
  log "License: Binary Distribution only — source is not included."
}

main "$@"
