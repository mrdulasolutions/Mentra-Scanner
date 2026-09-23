#!/usr/bin/env bash
set -euo pipefail

GSTREAMER_ROOT="${GSTREAMER_ROOT_IOS:-$HOME/Library/Developer/GStreamer/iPhone.sdk}"
SRC="${GSTREAMER_ROOT}/GStreamer.framework"
DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
DEST_FW="${DEST}/GStreamer.framework"

if [[ ! -d "$SRC" ]]; then
  echo "error: GStreamer.framework not found at $SRC" >&2
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST_FW"
mkdir -p "$DEST_FW"

# iOS expects a shallow framework bundle (Info.plist next to the binary).
cp "${SRC}/Versions/Current/GStreamer" "${DEST_FW}/GStreamer"
cp "${SRC}/Versions/Current/Resources/Info.plist" "${DEST_FW}/Info.plist"

if [[ "${CODE_SIGNING_ALLOWED}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${DEST_FW}/GStreamer" || true
fi

echo "Embedded shallow GStreamer.framework into ${DEST}"
