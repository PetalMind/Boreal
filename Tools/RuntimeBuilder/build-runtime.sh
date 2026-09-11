#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 <upstream-wine.tar.xz> <runtime.json> <dependencies-dir> <support-dir> <licenses-dir> <sbom.spdx.json> <output.tar.xz>" >&2
  exit 64
}

[[ $# -eq 7 ]] || usage

upstream_archive="$1"
runtime_manifest="$2"
dependencies_source="$3"
support_source="$4"
licenses_source="$5"
sbom_source="$6"
output_archive="$7"

for required in "$upstream_archive" "$runtime_manifest" "$dependencies_source" "$support_source" "$licenses_source" "$sbom_source"; do
  [[ -e "$required" ]] || { echo "Missing input: $required" >&2; exit 66; }
done

/usr/bin/python3 -m json.tool "$runtime_manifest" >/dev/null
schema_version=$(/usr/bin/python3 -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("schemaVersion", ""))' "$runtime_manifest")
[[ "$schema_version" == "1" ]] || { echo "Only runtime schemaVersion 1 is supported." >&2; exit 65; }

builder_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/BorealRuntimeBuilder.XXXXXX")
cleanup() { /bin/chmod -R u+w "$builder_root" 2>/dev/null || true; /bin/rm -rf "$builder_root"; }
trap cleanup EXIT

upstream_root="$builder_root/upstream"
package_root="$builder_root/package"
/bin/mkdir -p "$upstream_root" "$package_root/Runtime" "$package_root/Dependencies" "$package_root/Support" "$package_root/Licenses"
/usr/bin/tar -xJf "$upstream_archive" -C "$upstream_root"

wine_app=$(/usr/bin/find "$upstream_root" -type d -name 'Wine*.app' -print -quit)
[[ -n "$wine_app" ]] || { echo "The upstream archive does not contain Wine*.app." >&2; exit 65; }

/usr/bin/ditto "$wine_app" "$package_root/Runtime/Wine.app"
/usr/bin/ditto "$dependencies_source" "$package_root/Dependencies"
/usr/bin/ditto "$support_source" "$package_root/Support"
/usr/bin/ditto "$licenses_source" "$package_root/Licenses"
/bin/cp "$runtime_manifest" "$package_root/runtime.json"
/bin/cp "$sbom_source" "$package_root/SBOM.spdx.json"

# GPTK 3.0.2 may contain a second MoltenVK image in GStreamer's private
# directory. When both images are loaded into one Wine process, Objective-C
# sees duplicate MVKBlockObserver classes and Metal can abort while creating a
# device. Keep the canonical Wine copy; GStreamer's @rpath resolves to it.
primary_moltenvk="$package_root/Runtime/Wine.app/Contents/Resources/wine/lib/libMoltenVK.dylib"
gstreamer_moltenvk="$package_root/Runtime/Wine.app/Contents/Resources/wine/lib/GStreamer.framework/Versions/1.0/lib/libMoltenVK.dylib"
if [[ -f "$primary_moltenvk" && -f "$gstreamer_moltenvk" ]]; then
  /bin/rm -f "$gstreamer_moltenvk"
fi
[[ ! -e "$primary_moltenvk" || ! -e "$gstreamer_moltenvk" ]] || {
  echo "The normalized runtime still contains duplicate MoltenVK images." >&2
  exit 65
}

for executable in wine wineserver wineboot; do
  path="$package_root/Runtime/Wine.app/Contents/Resources/wine/bin/$executable"
  [[ -x "$path" ]] || { echo "Missing executable in normalized layout: $path" >&2; exit 65; }
done
[[ -s "$package_root/Licenses/THIRD_PARTY_NOTICES.txt" ]] || { echo "Licenses/THIRD_PARTY_NOTICES.txt is required." >&2; exit 65; }
[[ -s "$package_root/SBOM.spdx.json" ]] || { echo "A non-empty SPDX SBOM is required." >&2; exit 65; }

while IFS= read -r binary; do
  while IFS= read -r dependency; do
    case "$dependency" in
      @*|/usr/lib/*|/System/Library/*) ;;
      /*)
        echo "Non-relocatable dependency in $binary: $dependency" >&2
        exit 65
        ;;
    esac
  done < <(/usr/bin/otool -L "$binary" 2>/dev/null | /usr/bin/tail -n +2 | /usr/bin/awk '{print $1}')
done < <(/usr/bin/find "$package_root/Runtime" "$package_root/Dependencies" -type f -perm -111)

/bin/mkdir -p "$(/usr/bin/dirname "$output_archive")"
/usr/bin/tar -cJf "$output_archive" -C "$package_root" .

echo "Created $output_archive"
/usr/bin/shasum -a 256 "$output_archive"
/usr/bin/stat -f 'Compressed size: %z bytes' "$output_archive"
