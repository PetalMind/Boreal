#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: ./install.sh '/path/to/GTA San Andreas - The Definitive Edition'"
  exit 64
fi

game_root="${1:A}"
win64_root="$game_root/Gameface/Binaries/Win64"
cleo_root="$win64_root/CLEO"
script_source="${0:A:h}/DamageBloodRegenDE.js"
config_source="${0:A:h}/DamageBloodRegenDE.ini"

if [[ ! -f "$win64_root/SanAndreas.exe" ]]; then
  print -u2 "SanAndreas.exe was not found in $win64_root"
  exit 66
fi

if [[ ! -f "$win64_root/version.dll" ]]; then
  print -u2 "Ultimate ASI Loader x64 (version.dll) is not installed in $win64_root"
  exit 69
fi

if [[ ! -f "$win64_root/cleo_redux64.asi" ]]; then
  print -u2 "CLEO Redux x64 is not installed in $win64_root"
  exit 69
fi

if [[ ! -f "$cleo_root/CLEO_PLUGINS/IniFiles64.cleo" ]]; then
  print -u2 "IniFiles64.cleo is not installed in $cleo_root/CLEO_PLUGINS"
  exit 69
fi

mkdir -p "$cleo_root"
destination="$cleo_root/DamageBloodRegenDE[fs].js"

if [[ -e "$destination" ]] && ! cmp -s "$script_source" "$destination"; then
  backup="$destination.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$destination" "$backup"
  print "Previous Damage Blood & Regeneration DE backed up to $backup"
fi

cp "$script_source" "$destination"
if ! cmp -s "$script_source" "$destination"; then
  print -u2 "The deployed damage script does not match the source file."
  exit 70
fi

config_destination="$cleo_root/DamageBloodRegenDE.ini"
if [[ -e "$config_destination" ]] && ! cmp -s "$config_source" "$config_destination"; then
  cp -p "$config_destination" "$config_destination.backup-$(date +%Y%m%d-%H%M%S)"
fi
cp "$config_source" "$config_destination"
if ! cmp -s "$config_source" "$config_destination"; then
  print -u2 "The deployed INI does not match the source file."
  exit 70
fi

print "Damage Blood & Regeneration DE installed at $destination"
print "Health regeneration starts after the configured no-damage delay. F11 reloads the INI."
