#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: ./install.sh '/path/to/GTA San Andreas - The Definitive Edition'"
  exit 64
fi

game_root="${1:A}"
win64_root="$game_root/Gameface/Binaries/Win64"
cleo_root="$win64_root/CLEO"
script_source="${0:A:h}/sa_target_focus.js"
config_source="${0:A:h}/SA_TargetFocus.ini"

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

if [[ ! -f "$cleo_root/CLEO_PLUGINS/ImGuiReduxWin64.cleo" ]]; then
  print -u2 "ImGuiReduxWin64.cleo is not installed in $cleo_root/CLEO_PLUGINS"
  exit 69
fi

if [[ ! -f "$cleo_root/CLEO_PLUGINS/IniFiles64.cleo" ]]; then
  print -u2 "IniFiles64.cleo is not installed in $cleo_root/CLEO_PLUGINS"
  exit 69
fi

mkdir -p "$cleo_root"
destination="$cleo_root/sa_target_focus[fs].js"
legacy_destination="$cleo_root/sa_target_focus.js"

if [[ -e "$legacy_destination" ]]; then
  legacy_backup="$legacy_destination.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$legacy_destination" "$legacy_backup"
  print "Previous permission-less script moved to $legacy_backup"
fi

if [[ -e "$destination" ]] && ! cmp -s "$script_source" "$destination"; then
  backup="$destination.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$destination" "$backup"
  print "Previous SA Target Focus backed up to $backup"
fi

cp "$script_source" "$destination"
config_destination="$cleo_root/SA_TargetFocus.ini"
if [[ ! -e "$config_destination" ]]; then
  cp "$config_source" "$config_destination"
  print "Default configuration installed at $config_destination"
fi
print "SA Target Focus installed at $destination"
print "Start GTA SA Definitive Edition, hold Right Mouse Button or LT, and press F6 for settings."
