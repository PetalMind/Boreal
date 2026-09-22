#!/bin/zsh

set -euo pipefail

mod_root="${0:A:h}"
game_root="${1:-}"
ffdec="${FFDEC:-}"

if [[ -z "$game_root" ]]; then
  print -u2 "Usage: FFDEC=/path/to/ffdec.sh ./build.sh '/path/to/Dragon Age Origins'"
  exit 64
fi

game_root="${game_root:A}"
erf="$game_root/packages/core/data/guiexport.erf"

if [[ ! -f "$erf" ]]; then
  print -u2 "guiexport.erf was not found at $erf"
  exit 66
fi

if [[ -z "$ffdec" ]]; then
  for candidate in \
    "/Applications/FFDec.app/Contents/Resources/ffdec.sh" \
    "/private/tmp/ffdec/FFDec.app/Contents/Resources/ffdec.sh"; do
    if [[ -f "$candidate" ]]; then
      ffdec="$candidate"
      break
    fi
  done
fi

if [[ -z "$ffdec" || ! -f "$ffdec" ]]; then
  print -u2 "Set FFDEC to JPEXS Free Flash Decompiler's ffdec.sh"
  exit 69
fi

work_root="$(mktemp -d /private/tmp/dao-cooldown-numbers.XXXXXX)"
trap 'rm -rf "$work_root"' EXIT

mkdir -p "$work_root/exported/scripts"
python3 "$mod_root/tools/erf_extract.py" \
  "$erf" quickbar.gfx "$work_root/quickbar.gfx"

python3 "$mod_root/tools/gfx_to_swf.py" \
  "$work_root/quickbar.gfx" "$work_root/quickbar.swf"

sh "$ffdec" -format script:as -export script "$work_root/exported" "$work_root/quickbar.swf" >/dev/null

python3 "$mod_root/tools/patch_quickbar.py" \
  "$work_root/exported/scripts/__Packages/SharedLibrary/QuickBarAbilityIcon.as"

sh "$ffdec" -importScript \
  "$work_root/quickbar.swf" \
  "$work_root/quickbar-patched.swf" \
  "$work_root/exported" >/dev/null

mkdir -p "$mod_root/override"
python3 "$mod_root/tools/swf_to_gfx.py" \
  "$work_root/quickbar-patched.swf" "$mod_root/override/quickbar.gfx"

rm -f "$mod_root/CooldownNumbersDAO.zip"
(
  cd "$mod_root"
  zip -q -r CooldownNumbersDAO.zip override README.md
)

print "Built $mod_root/override/quickbar.gfx"
print "Built $mod_root/CooldownNumbersDAO.zip"
