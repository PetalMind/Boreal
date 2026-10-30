# Changelog

## 1.0.22 — 2026-10-30

- Preserve shared Skyrim and GTA SA DE packages when removing mods from a profile. Stop loading or deploying mods when an existing deployment record is damaged or incompatible.
- Require an exact payload match for renamed mod updates, preserve distinct missing-master warnings, and serialize profile edits with background library loading.
- Reload saved profiles after failed installation/deployment and activate a switched profile only after it loads successfully. Separate the mod service contract, update identity rules and shared persistence safeguards.

## 1.0.21 — 2026-10-30

- Keep sidebar navigation available from game details. Switching sections, library sources or filters dismisses game details and clears the previous navigation path immediately, including during artwork transitions.

## 1.0.20 — 2026-10-30

- Unify interaction, navigation, scrolling and progress timing; respect Reduce Motion for button and card geometry.
- Apply favorite changes immediately and finish artwork navigation before revealing game details.
- Cache filtered desktop and console library results, skip unused search normalization and avoid repeated controller scene traversal for unchanged input.

## 1.0.19 — 2026-10-30

- Adapt settings and controller layouts to narrower windows, use semantic content surfaces in light and dark appearance, and improve keyboard access to featured games.
- Separate library projection, discovery artwork loading, controller scene construction, settings categories, game installation and media presentation from their root views.
- Respect Reduce Motion in controller previews and increase small detail and overlay labels to at least 11 points.

## 1.0.18 — 2026-10-26

- Fixed Play for Drakensang Online (Steam 2067850): authenticate through the existing Steam client and the official Drakensang portal, then start the game with the verified GPTK 3.0-2 host instead of the failing Qt launcher.
- Bundle the game-specific DirectX 9 cursor correction and keep the game's Wine environment in permanent Boreal storage. Preserve unrelated game DLLs and the selected macOS audio output.
- Keep temporary Steam tickets and portal cookies in memory. A separate native controller retains the ticket for the full game session, including after closing Boreal.
