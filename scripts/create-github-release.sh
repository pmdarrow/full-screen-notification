#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/create-github-release.sh [--draft] [--prerelease] [--dry-run]

Builds a universal macOS app, packages it, then creates a GitHub release and
uploads the zip with gh. The release tag comes from MARKETING_VERSION in the
Xcode build settings.

Examples:
  bash scripts/create-github-release.sh
  bash scripts/create-github-release.sh --draft
  bash scripts/create-github-release.sh --dry-run

Environment overrides:
  FULL_SCREEN_NOTIFICATION_RELEASE_BUILD_DIR  Build dir. Default: build-release
  FULL_SCREEN_NOTIFICATION_RELEASE_ARCHS      Architectures. Default: arm64 x86_64
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

dry_run=0
gh_flags=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --draft)
      gh_flags+=(--draft)
      ;;
    --prerelease)
      gh_flags+=(--prerelease)
      ;;
    --dry-run)
      dry_run=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

[[ "$(uname -s)" == "Darwin" ]] || die "releases must be built on macOS."
[[ -f project.local.yml ]] || die "project.local.yml is required to build the release OAuth configuration."
command -v xcodegen >/dev/null 2>&1 || die "xcodegen is required. Install it with: brew install xcodegen"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is required. Install Xcode first."
command -v ditto >/dev/null 2>&1 || die "ditto is required."
command -v codesign >/dev/null 2>&1 || die "codesign is required."
command -v lipo >/dev/null 2>&1 || die "lipo is required."

branch="$(git branch --show-current)"
[[ -n "${branch}" ]] || die "cannot create a release from a detached HEAD."

if [[ "${dry_run}" -eq 0 ]]; then
  command -v gh >/dev/null 2>&1 || die "gh is required. Install it with: brew install gh"
  [[ -z "$(git status --porcelain)" ]] || die "working tree is not clean; commit or stash changes before releasing."

  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" ||
    die "current branch has no upstream; push it before releasing."
  git fetch --quiet --tags
  local_head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse "${upstream}")"
  [[ "${local_head}" == "${remote_head}" ]] ||
    die "local ${branch} does not match ${upstream}; push or pull before releasing."
fi

build_dir="${FULL_SCREEN_NOTIFICATION_RELEASE_BUILD_DIR:-build-release}"
archs="${FULL_SCREEN_NOTIFICATION_RELEASE_ARCHS:-arm64 x86_64}"

if [[ "${build_dir}" = /* ]]; then
  build_dir_abs="${build_dir}"
else
  build_dir_abs="${repo_root}/${build_dir}"
fi

xcodegen

version="$(
  xcodebuild \
    -project FullScreenNotification.xcodeproj \
    -scheme FullScreenNotification \
    -configuration Release \
    -showBuildSettings 2>/dev/null |
    awk -F' = ' '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { print $2; exit }'
)"
[[ -n "${version}" ]] || die "could not read MARKETING_VERSION from the Xcode build settings."

tag="v${version}"
package_name="full-screen-notification-${version}-macos"
dist_dir="${repo_root}/dist"
stage_dir="${dist_dir}/${package_name}"
zip_path="${dist_dir}/${package_name}.zip"
app_name="Full Screen Notification.app"
app_src="${build_dir_abs}/Build/Products/Release/${app_name}"
app_stage="${stage_dir}/${app_name}"

if [[ "${dry_run}" -eq 0 ]]; then
  existing_tag_commit="$(git rev-parse -q --verify "refs/tags/${tag}^{commit}" 2>/dev/null || true)"
  if [[ -n "${existing_tag_commit}" && "${existing_tag_commit}" != "${local_head}" ]]; then
    die "tag ${tag} already exists at ${existing_tag_commit}, but HEAD is ${local_head}"
  fi
fi

echo "Building Full Screen Notification ${version} (${tag})"

xcodebuild \
  -project FullScreenNotification.xcodeproj \
  -scheme FullScreenNotification \
  -configuration Release \
  -derivedDataPath "${build_dir_abs}" \
  -destination "generic/platform=macOS" \
  "ARCHS=${archs}" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

[[ -d "${app_src}" ]] || die "built app was not found at ${app_src}."

rm -rf "${stage_dir}" "${zip_path}"
mkdir -p "${stage_dir}"
ditto --noqtn "${app_src}" "${app_stage}"
xattr -dr com.apple.quarantine "${app_stage}" 2>/dev/null || true

codesign --force --deep --timestamp=none --sign - "${app_stage}"
codesign --verify --deep --strict "${app_stage}"

built_archs="$(lipo -archs "${app_stage}/Contents/MacOS/Full Screen Notification")"
for arch in ${archs}; do
  [[ " ${built_archs} " == *" ${arch} "* ]] || die "release app is missing the ${arch} architecture."
done

(
  cd "${stage_dir}"
  ditto -c -k --sequesterRsrc --keepParent --zlibCompressionLevel 9 "${app_name}" "${zip_path}"
)

echo "Created ${zip_path} (${built_archs})"

if [[ "${dry_run}" -eq 1 ]]; then
  echo "Dry run: skipped GitHub release creation."
  exit 0
fi

release_notes="macOS release for Apple Silicon and Intel Macs.

Install:
\`\`\`
curl -fsSL https://raw.githubusercontent.com/pmdarrow/full-screen-notification/main/scripts/install.sh | bash
\`\`\`

This build is intended for trusted manual installation. It is ad-hoc signed and not notarized."

gh release create "${tag}" "${zip_path}#Full Screen Notification for macOS" \
  --target "${branch}" \
  --title "Full Screen Notification ${tag}" \
  --notes "${release_notes}" \
  "${gh_flags[@]}"
