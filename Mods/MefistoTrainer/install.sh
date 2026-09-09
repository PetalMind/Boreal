#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: ./install.sh '/path/to/GTA San Andreas - The Definitive Edition'"
  exit 64
fi

game_root="${1:A}"
win64_root="$game_root/Gameface/Binaries/Win64"
cleo_root="$win64_root/CLEO"
script_source="${0:A:h}/mefisto_trainer.js"
module_source="${0:A:h}/MefistoTrainer"
data_source="${0:A:h}/Data"
generator_source="${0:A:h}/Tools/generate_vehicle_catalog.js"

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

mkdir -p "$cleo_root"
destination="$cleo_root/mefisto_trainer.js"
module_destination="$cleo_root/MefistoTrainer"

if [[ -e "$destination" ]] && ! cmp -s "$script_source" "$destination"; then
  backup="$destination.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$destination" "$backup"
  print "Previous trainer backed up to $backup"
fi

cp "$script_source" "$destination"
mkdir -p "$module_destination/Data"
cp "$module_source/catalog.mjs" "$module_destination/catalog.mjs"
cp "$module_source/item_catalog.mjs" "$module_destination/item_catalog.mjs"
cp "$module_source/item_spawner.mjs" "$module_destination/item_spawner.mjs"
cp "$module_source/vehicle_spawner.mjs" "$module_destination/vehicle_spawner.mjs"
cp "$data_source/categories.json" "$module_destination/Data/categories.json"
cp "$data_source/items.json" "$module_destination/Data/items.json"
cp "$data_source/vehicle_metadata.json" "$module_destination/Data/vehicle_metadata.json"

original_data_ide="$game_root/Gameface/Content/OriginalData/GTASA/data/vehicles.ide"
if [[ -f "$original_data_ide" ]] && command -v node >/dev/null 2>&1; then
  node "$generator_source" "$original_data_ide" "$module_destination/Data/vehicles.json"
else
  cp "$data_source/vehicles.json" "$module_destination/Data/vehicles.json"
  if [[ ! -f "$original_data_ide" ]]; then
    print "OriginalData vehicles.ide was not found; bundled catalog was installed."
  else
    print "Node.js was not found; bundled catalog was installed."
  fi
fi

print "Mefisto Trainer installed at $destination"
print "Catalog modules installed at $module_destination"
print "Start GTA SA Definitive Edition and press F5."
