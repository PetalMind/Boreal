#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: ./install.sh '/path/to/Dragon Age Origins'"
  exit 64
fi

script_root="${0:A:h}"
game_root="${1:A}"
bin_ship="$game_root/bin_ship"
destination="$bin_ship/SmartHighlight"

if [[ ! -f "$bin_ship/DAOrigins.exe" && ! -f "$bin_ship/DAOriginsLauncher.exe" ]]; then
  print -u2 "DAOrigins.exe or DAOriginsLauncher.exe was not found in $bin_ship"
  exit 66
fi

if [[ ! -f "$script_root/DAO_SmartHighlightTool.exe" ]]; then
  print -u2 "DAO_SmartHighlightTool.exe is missing. Run ./build.sh first."
  exit 66
fi

mkdir -p "$destination"

for file in DAO_SmartHighlightTool.exe SmartHighlight.ini; do
  source="$script_root/$file"
  target="$destination/$file"
  if [[ -e "$target" ]] && ! cmp -s "$source" "$target"; then
    backup="$target.backup-$(date +%Y%m%d-%H%M%S)"
    cp -p "$target" "$backup"
    print "Previous $file backed up to $backup"
  fi
  cp "$source" "$target"
done

print "Smart Highlight installed at $destination"
print "Run $destination/DAO_SmartHighlightTool.exe before starting Dragon Age: Origins."
