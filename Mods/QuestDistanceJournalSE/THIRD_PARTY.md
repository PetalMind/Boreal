# Third-party components

The built package contains a modified copy of the user's locally installed
SkyUI `Interface/quest_journal.swf`. SkyUI belongs to its original authors.
Upstream source and licensing: https://github.com/schlangster/skyui

The patch imports two edited ActionScript units and preserves the remaining
compiled code and assets. Patch sources are in `Source/*.as` and `tools/interface.py`.
The local game and SkyUI installation are required to reproduce the package.
Do not redistribute the modified SkyUI artifact without complying with the
upstream license and providing the corresponding source and notices.

Binary record definitions were checked against xEdit's Skyrim definitions:
https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.5/Core/wbDefinitionsTES5.pas

Papyrus declarations follow SKSE64 and the installed game scripts:
https://github.com/ianpatt/skse64

Location parents and exterior-door links are indexed from the local game at build time;
no Papyrus Extender functions or DLL are required by this mod.

Build tools (not included in the package):
https://github.com/Orvid/Caprica
https://github.com/jindrapetrik/jpexs-decompiler
