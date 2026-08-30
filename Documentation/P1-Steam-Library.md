# P1 — Steam Library Import

Boreal can import the locally known library of a macOS Steam installation without collecting a Steam password or copying Steam session tokens.

## Data flow

The importer reads Valve KeyValues data already maintained by Steam:

- `config/loginusers.vdf` to match SteamID64 accounts with `userdata` AccountID directories;
- `userdata/<account-id>/config/localconfig.vdf` for locally known App IDs, playtime, and last-played dates;
- `steamapps/libraryfolders.vdf` and `appmanifest_*.acf` across mounted Steam libraries for installed state and install paths;
- `appcache/librarycache/<app-id>/library_600x900.jpg` for cached cover artwork;
- `userdata/<account-id>/config/librarycache/<app-id>.json` for cached descriptions and developer associations.

Names, descriptions, developers, and header art are enriched with Steam's public Store app-details response. Failure to reach that endpoint does not discard the local library; Boreal keeps local metadata and a stable App ID fallback.

Imported entries are persisted in Boreal's `library.json`, retain stable Boreal IDs across refreshes, participate in search and grid/list layouts, and have a dedicated detail view. Installed entries can be launched through Steam's registered `steam://rungameid/<app-id>` URL. Non-installed entries open in Steam or on the Store page.

## Current boundary

The library importer remains read-only for the existing macOS Steam installation. Windows-only Steam games can be downloaded separately through native SteamCMD from the game detail flow; credentials are entered for that operation only and are not inferred from or copied out of the macOS Steam session.
