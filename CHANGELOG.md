# Changelog

## 1.0.18 — 2026-10-26

- Fixed Play for Drakensang Online (Steam 2067850): authenticate through the existing Steam client and the official Drakensang portal, then start the game with the verified GPTK 3.0-2 host instead of the failing Qt launcher.
- Bundle the game-specific DirectX 9 cursor correction and keep the game's Wine environment in permanent Boreal storage. Preserve unrelated game DLLs and the selected macOS audio output.
- Keep temporary Steam tickets and portal cookies in memory. A separate native controller retains the ticket for the full game session, including after closing Boreal.
