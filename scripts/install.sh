#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Full Screen Notification.app"
INSTALL_DIR="/Applications"
REPO_SLUG="pmdarrow/full-screen-notification"
ASSET_NAME_PATTERN="full-screen-notification-[0-9A-Za-z._-]+-macos\\.zip"
GITHUB_API_URL="https://api.github.com/repos/${REPO_SLUG}/releases/latest"

target_app="${INSTALL_DIR}/${APP_NAME}"
tmp_dir=""

die() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}"
  fi
}
trap cleanup EXIT

[[ "$(uname -s)" == "Darwin" ]] || die "Full Screen Notification requires macOS."
command -v curl >/dev/null 2>&1 || die "curl is required to download the release."
command -v ditto >/dev/null 2>&1 || die "ditto is required to extract the release zip."
command -v codesign >/dev/null 2>&1 || die "codesign is required to verify the app."

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/full-screen-notification-install.XXXXXX")"
zip_path="${tmp_dir}/full-screen-notification-macos.zip"
extract_dir="${tmp_dir}/release"

echo "Finding the latest Full Screen Notification release..." >&2

asset_urls="$(curl -fsSL "${GITHUB_API_URL}" | grep -Eo "https://[^\"]+/${ASSET_NAME_PATTERN}" || true)"
asset_url="$(printf '%s\n' "${asset_urls}" | head -n 1)"

if [[ -z "${asset_url}" ]]; then
  die "could not find a macOS release zip on the latest GitHub release."
fi

echo "Downloading ${asset_url}..." >&2
curl -fL "${asset_url}" -o "${zip_path}"

mkdir -p "${extract_dir}"
ditto -x -k "${zip_path}" "${extract_dir}"

source_app="$(find "${extract_dir}" -maxdepth 3 -type d -name "${APP_NAME}" -print -quit)"
[[ -n "${source_app}" ]] || die "${APP_NAME} was not found inside the release zip."

codesign --verify --deep --strict "${source_app}" ||
  die "the downloaded app failed code signature verification."

bundle_identifier="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${source_app}/Contents/Info.plist" 2>/dev/null || true
)"
[[ "${bundle_identifier}" == "com.fullscreennotification.app" ]] ||
  die "the downloaded app has an unexpected bundle identifier."

echo "Installing ${APP_NAME}..."
echo "Destination: ${target_app}"
echo "You may be prompted for your macOS password."

killall "Full Screen Notification" >/dev/null 2>&1 || true
sudo mkdir -p "${INSTALL_DIR}"
sudo rm -rf "${target_app}"
sudo ditto --noqtn "${source_app}" "${target_app}"

# Release archives can carry Gatekeeper quarantine metadata after downloading.
sudo xattr -dr com.apple.quarantine "${target_app}" 2>/dev/null || true

codesign --verify --deep --strict "${target_app}" ||
  die "the installed app failed code signature verification."

open "${target_app}"
echo "Installed and launched Full Screen Notification."
