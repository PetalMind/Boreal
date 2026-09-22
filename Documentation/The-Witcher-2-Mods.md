# The Witcher 2 mod support

**Status:** implemented in `Witcher2ModManager.swift`

## Supported layouts

Boreal treats the two Witcher 2 mod systems as separate deployment roots:

| Mod type | Source layout | Boreal destination | Activation |
| --- | --- | --- | --- |
| Regular replacement mod | `CookedPC/…` or loose files | `<game>/CookedPC/…` | automatic when the game starts |
| Native archive | standalone `.dzip` | `<game>/CookedPC/<file>.dzip` | automatic when the game starts |
| REDkit/user-content package | `UserContent/<package>/…` or a recognized package folder | `Documents/Witcher 2/UserContent/<package>/…` | `Config/UserContent.ini`, then the game's `New Game → User Content` menu |

ZIP, 7z and RAR packages are extracted only to Boreal's temporary inspection
directory and then copied into the per-game staging area. A standalone DZIP is
copied byte-for-byte; Boreal does not unpack or rewrite the native REDengine
archive format.

## Safety and profiles

Each imported mod has its own archive, staging directory, manifest and SHA-256
records. Deployment:

- detects duplicate destination paths and reports conflicts by priority;
- backs up an existing game file before replacing it;
- refuses deployment when a Boreal-managed destination changed externally;
- restores the previous file set when a deployment step fails;
- writes the User Content `Mount=` entries while preserving unrelated entries;
- restores backups when a mod is disabled or removed from the active profile.

Boreal does not perform Witcher 2 script/XML merging. Conflicting `.ws`, XML,
localization or other files are shown as ordinary file conflicts, and the
lower row in the Mods view wins only after the user deploys the selected
priority order.

## Runtime boundary

For a Windows installation the user-content root is resolved from the linked
Wine environment's `drive_c/users/<user>/Documents/Witcher 2` (with `My
Documents` as a compatibility fallback). This is intentional: a game
installation may be outside the prefix, while Witcher 2 still reads user
content from the Wine Documents directory.

The native macOS GOG build is packaged as an `.app`; its game root is
`Contents/Resources/Data`, and its user-content root is
`~/Library/Application Support/com.cdprojektred.TheWitcher2/GameDocuments/Witcher 2`.

REDkit adventures remain game-content packages: after deployment the game may
still require selection from `New Game → User Content`. Boreal does not launch
`userContentManager.exe` as a substitute for the game's own content selection.
When the executable is present in `bin`, Boreal keeps it available as a
separate game action; it is not treated as the primary game executable.

## External references

The layout follows CD PROJEKT RED's REDkit documentation, which describes
`userContentManager.exe` and activation of cooked content, and the established
Witcher 2 installation convention of placing loose mods in `CookedPC`. The
Steam AppID is `20920`; the GOG product identifier used for detection is
`1207658930`.
