#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: ./install.sh '/path/to/GTA San Andreas - The Definitive Edition'"
  exit 64
fi

game_root="${1:A}"
win64_root="$game_root/Gameface/Binaries/Win64"
cleo_root="$win64_root/CLEO"
script_source="${0:A:h}/WorldGPSNavigation.js"
config_source="${0:A:h}/WorldGPSNavigationDE.ini"

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
destination="$cleo_root/WorldGPSNavigation[fs].js"

if [[ -e "$destination" ]] && ! cmp -s "$script_source" "$destination"; then
  backup="$destination.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$destination" "$backup"
  print "Previous World GPS Navigation backed up to $backup"
fi

cp "$script_source" "$destination"
config_destination="$cleo_root/WorldGPSNavigationDE.ini"
if [[ ! -e "$config_destination" ]]; then
  cp "$config_source" "$config_destination"
  print "Default configuration installed at $config_destination"
fi

print "World GPS Navigation installed at $destination"
print "Set a normal waypoint in the game map; F11 reloads WorldGPSNavigationDE.ini."
