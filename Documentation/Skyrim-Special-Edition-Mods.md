# Skyrim Special Edition mod support

## What Boreal supports

Boreal recognizes Skyrim Special Edition and Anniversary Edition, imports ZIP,
7z, and RAR archives, and deploys supported files into the game's `Data`
directory. ZIP extraction uses macOS `ditto`; 7z and RAR extraction needs a
7-Zip-compatible command line tool. The archive is copied into Boreal-managed
pending storage before inspection, so access to the original selection can
be released after the preview.

For supported archives, Boreal:

- finds the Skyrim `Data` payload and stages a separate copy of every file;
- detects `.esm`, `.esp`, and `.esl` plugin files and reads TES4 flags and
  master dependencies when the header is readable;
- lets the user enable plugins, change their order, create profiles, and
  resolve file conflicts by mod priority;
- checks active plugin masters, plugin headers, and full/light plugin limits
  before deployment;
- copies files to `Data` with backups and a deployment manifest, and checks
  managed files for unexpected edits before replacing them;
- writes the selected user-mod plugin list to `plugins.txt` in the linked Wine
  prefix. Skyrim's master plugins and the Creation Club plugins listed in
  `Skyrim.ccc` remain in the Boreal profile but are omitted from this generated
  file; duplicate plugin filenames are collapsed before saving or deployment.

Boreal also recognizes the official SKSE64 archive layout. It verifies the
version-specific `skse64_*.dll` against the installed `SkyrimSE.exe`, stages
`skse64_loader.exe` and the matching DLL beside the game executable, and stages
SKSE's `Data` files in the game's `Data` folder. The deployment manifest backs
up and restores files from both locations. When the matching loader is present,
launching the Steam edition starts `skse64_loader.exe` after bootstrapping
Steam.

For other Skyrim archives, the Mods view labels the path as **Skyrim Data
Files / Skyrim Data Folder**. It blocks automatic installation when an archive
contains a FOMOD installer or non-document payload files outside the detected
`Data` folder, because those contents would otherwise be silently omitted or
installed with the wrong options.

## Recognition limits

This is a direct Skyrim file manager. It is not a general Skyrim mod installer
and does not support every mod:

- FOMOD XML choices, scripted installers, and dependency-driven option
  selection are not executed.
- Game-root files from general mods and overlays are not deployed. The only
  supported game-root package is the version-matched SKSE64 loader and runtime
  DLL.
- Boreal does not run SKSE-dependent setup tools or execute output generators
  such as Nemesis, FNIS, or DynDOLOD.
- Boreal does not implement Mod Organizer 2's process-scoped virtual file
  system or Vortex deployment. MO2's USVFS presents files only to selected
  processes; Vortex deploys files from staging into the game directory using
  links. Boreal currently deploys its own staged copies into `Data` and does
  not launch those managers.
- External detection is limited to loose plugin and BSA files directly in
  `Data`, plus files directly under `Data/SKSE/Plugins`. It cannot infer the
  ownership of arbitrary loose textures, meshes, scripts, or other assets
  installed by another manager, so those are not shown as individual mods.
- Boreal reads and writes `plugins.txt`; it does not maintain the separate
  `loadorder.txt` used by some modding utilities to retain positions for all
  plugins. Active Skyrim plugin order is represented in `plugins.txt`, while
  utilities such as LOOT may use `loadorder.txt` for the complete list.
- Plugin validation checks readable headers, declared masters, and count
  limits. It does not prove that a plugin is compatible with the installed
  game version, SKSE version, another plugin, or a particular load order.

Consequently, a successful deployment means Boreal copied the selected files
and synchronized its plugin list; it does not prove that the game loaded every
mod successfully.

## Upstream behavior references

- [Mod Organizer 2 USVFS](https://github.com/ModOrganizer2/usvfs) describes
  its process-scoped virtual file system.
- [Vortex external-change documentation](https://github.com/Nexus-Mods/Vortex/blob/master/docs/mod-management/EXTERNAL-CHANGES.md)
  describes deployment from a staging folder into the game folder using links.
- [LOOT load-order introduction](https://loot.github.io/docs/help/introduction-to-load-orders/)
  describes Skyrim plugin files, active load order, and `loadorder.txt`.
