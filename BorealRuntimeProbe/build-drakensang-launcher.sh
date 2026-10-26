#!/bin/bash
set -euo pipefail
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "$destination"
xcrun swiftc -O -parse-as-library -swift-version 5 \
    -target "${NATIVE_ARCH_ACTUAL}-apple-macos${MACOSX_DEPLOYMENT_TARGET}" -sdk "$SDKROOT" \
    "${SRCROOT}/BorealRuntimeProbe/DrakensangLauncher.swift" \
    "${SRCROOT}/Boreal/DrakensangPortal.swift" \
    -o "${destination}/BorealDrakensangLauncher"
cp "${SRCROOT}/BorealRuntimeProbe/BorealDrakensangTicket.exe" "$destination/"
cp "${SRCROOT}/BorealRuntimeProbe/BorealDrakensangCursor.dll" "$destination/"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "${destination}/BorealDrakensangLauncher"
fi
