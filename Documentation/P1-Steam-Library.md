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

This is an integration with an existing signed-in Steam installation. It does not yet implement a standalone Steam login inside Boreal, download Windows depots, install Steam games into a Boreal Wine environment, or enumerate owned-but-never-seen games that are absent from Steam's local account cache. Those require a separately authorized account/provider integration and are not inferred from private credentials.

