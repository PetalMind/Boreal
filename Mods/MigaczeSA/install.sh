#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: ./install.sh '/path/to/GTA San Andreas'"
  exit 64
fi

game_root="${1:A}"
script_source="${0:A:h}/MigaczeSA.js"
cleo_root="$game_root/CLEO"
destination="$cleo_root/MigaczeSA.js"

if [[ ! -f "$game_root/gta_sa.exe" && ! -f "$game_root/gta-sa.exe" && ! -f "$game_root/gta_sa_compact.exe" ]]; then
  print -u2 "A classic GTA San Andreas executable was not found in $game_root"
  exit 66
fi

if [[ ! -f "$game_root/cleo.asi" ]]; then
  print -u2 "CLEO Library was not found in $game_root (expected cleo.asi)"
  exit 69
fi

if [[ ! -f "$game_root/cleo_redux.asi" ]]; then
  print -u2 "CLEO Redux was not found in $game_root (expected cleo_redux.asi)"
  exit 69
fi

mkdir -p "$cleo_root"
if [[ -e "$destination" ]] && ! cmp -s "$script_source" "$destination"; then
  backup="$destination.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$destination" "$backup"
  print "Previous Migacze SA script backed up to $backup"
fi

cp "$script_source" "$destination"
if ! cmp -s "$script_source" "$destination"; then
  print -u2 "The deployed Migacze SA script does not match the source file."
  exit 70
fi

print "Migacze SA installed at $destination"
