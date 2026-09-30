# XLiveLess for Grand Theft Auto IV

Boreal can install the XLiveLess 1.0a4 patch for GTA IV to remove the Games for
Windows — LIVE dependency that prevents the game from launching under Wine.

The installer downloads the RAR archive from the Sanny Builder mirror, accepts
only a Windows PE `xlive.dll`, and places it beside the GTA IV executable. If a
file with that name already exists, Boreal saves a verified copy in its
application support folder before replacing it. **Restore Original** returns
that copy or removes the patch file if there was no original.

GFWL and online play are disabled while XLiveLess is installed. This is intended
for offline play and helps prevent cheating through the removed service.

Sources:

- [WineHQ AppDB: Grand Theft Auto IV](https://appdb.winehq.org/objectManager.php?sClass=application&iId=8757)
- [XLiveLess 1.0a4 archive](https://public.sannybuilder.com/GTA4/xliveless-1.0a4.rar)
