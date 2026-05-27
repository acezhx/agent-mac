#!/usr/bin/env bash

set -euo pipefail

if [[ "${PLATFORM_NAME:-}" != "macosx" ]]; then
  echo "Skipping embedded Runtime copy for platform: ${PLATFORM_NAME:-unknown}"
  exit 0
fi

case "$(uname -m)" in
  arm64)
    runtime_platform="darwin-arm64"
    ;;
  x86_64)
    runtime_platform="darwin-x64"
    ;;
  *)
    echo "Unsupported runtime architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

src_root="${SRCROOT:?SRCROOT is required}"
vendor_runtime="$src_root/Vendor/Runtime/$runtime_platform"
resources_folder="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?UNLOCALIZED_RESOURCES_FOLDER_PATH is required}"
target_runtime="$resources_folder/Runtime"
runtime_host="$src_root/AgentMac/RuntimeHost/runtime-host.js"

if [[ ! -x "$vendor_runtime/node/bin/node" ]]; then
  echo "Missing executable bundled Node: $vendor_runtime/node/bin/node" >&2
  exit 1
fi

if [[ ! -d "$vendor_runtime/pi/node_modules" ]]; then
  echo "Missing vendored Pi node_modules: $vendor_runtime/pi/node_modules" >&2
  exit 1
fi

if [[ ! -f "$runtime_host" ]]; then
  echo "Missing RuntimeHost entry: $runtime_host" >&2
  exit 1
fi

mkdir -p "$resources_folder"
/usr/bin/rsync -a --delete "$vendor_runtime/" "$target_runtime/"
mkdir -p "$target_runtime/host"
/usr/bin/rsync -a "$runtime_host" "$target_runtime/host/runtime-host.js"
chmod 755 "$target_runtime/node/bin/node"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
  code_sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  if [[ -n "$code_sign_identity" ]]; then
    /usr/bin/codesign --force --sign "$code_sign_identity" "$target_runtime/node/bin/node"
  else
    /usr/bin/codesign --force --sign - "$target_runtime/node/bin/node"
  fi
fi
