#!/bin/zsh

set -euo pipefail

mod_root="${0:A:h}"
game_root="${1:-}"

if [[ -z "$game_root" ]]; then
  print -u2 "Usage: ./build.sh '/path/to/The Witcher 2.app'"
  print -u2 "   or: ./build.sh '/path/to/The Witcher 2.app/Contents/Resources/Data'"
  exit 64
fi

game_root="${game_root:A}"
if [[ "$game_root" == *.app ]]; then
  game_root="$game_root/Contents/Resources/Data"
fi

source="$game_root/CookedPC/base_scripts.dzip"
if [[ ! -f "$source" ]]; then
  print -u2 "base_scripts.dzip was not found at $source"
  exit 66
fi

work_root="$(mktemp -d /private/tmp/witcher2-medallion-cooldown.XXXXXX)"
trap 'rm -rf "$work_root"' EXIT

python3 "$mod_root/tools/dzip.py" extract \
  "$source" \
  "$work_root/base_scripts"

player="$work_root/base_scripts/game/player/player.ws"
if [[ ! -f "$player" ]]; then
  print -u2 "game/player/player.ws was not found after extracting base_scripts.dzip"
  exit 67
fi

python3 "$mod_root/tools/patch_player.py" "$player"

output="$mod_root/base_scripts.dzip"
python3 "$mod_root/tools/dzip.py" pack \
  "$work_root/base_scripts" \
  "$output"

print "Built $output"
print "Install the generated base_scripts.dzip through Boreal or copy it to CookedPC after making a backup."
