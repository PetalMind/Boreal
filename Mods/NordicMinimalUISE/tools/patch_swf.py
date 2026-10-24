#!/usr/bin/env python3
"""Patch Skyrim's original HUD/dialogue SWFs, requiring FFDec and BSArch."""
from __future__ import annotations
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = Path(os.environ.get("SKYRIM_DATA", "/Volumes/Zewnetrzny/Gry windows/The Elder Scrolls V Skyrim Special Edition/Data"))
BSARCH = Path(os.environ.get("BSARCH_EXE", ROOT.parents[1] / ".local-tools/xedit/BSArch64.exe"))
FFDEC_VALUE = os.environ.get("FFDEC_JAR")
FFDEC = Path(FFDEC_VALUE) if FFDEC_VALUE else None


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise RuntimeError(f"Expected one patch point in {path.name}, found {text.count(old)}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def main() -> None:
    if FFDEC is None:
        raise SystemExit("Set FFDEC_JAR to the path of ffdec.jar (JPEXS FFDec).")
    for required in (DATA / "Skyrim - Interface.bsa", BSARCH, FFDEC):
        if not required.is_file():
            raise SystemExit(f"Missing dependency: {required}")
    with tempfile.TemporaryDirectory(prefix="nordic-minimal-ui-") as temp:
        work = Path(temp)
        extracted = work / "base"
        extracted.mkdir()
        # Wine's Z: mapping allows BSArch to read the BSA without touching game files.
        win_bsa = subprocess.check_output(["winepath", "-w", str(DATA / "Skyrim - Interface.bsa")], text=True).strip()
        win_out = subprocess.check_output(["winepath", "-w", str(extracted)], text=True).strip()
        run(["wine", str(BSARCH), "unpack", win_bsa, win_out, "-q", "-mt"])
        swfs = {"hudmenu.swf": "hud", "dialoguemenu.swf": "dialogue"}
        exports: dict[str, Path] = {}
        for filename, key in swfs.items():
            source = next(extracted.rglob(filename), None)
            if source is None:
                raise RuntimeError(f"{filename} was not found in Skyrim - Interface.bsa")
            folder = work / key
            run(["java", "-jar", str(FFDEC), "-format", "script:as", "-export", "script", str(folder), str(source)])
            exports[key] = folder / "scripts"
        hud = exports["hud"] / "__Packages/HUDMenu.as"
        replace_once(hud, "   var METER_PAUSE_FRAME = 40;", "   var METER_PAUSE_FRAME = 40;\n   var NordicFadeDelay = 5;\n   var NordicBarsEnabled = true;\n   var NordicCompassEnabled = true;\n   var NordicCombatActive = false;\n   var NordicFadeTimerID;")
        replace_once(hud, "   function RunMeterAnim(aMeter)\n   {", '''   function CreateNordicDot()\n   {\n      this.NordicDot = this.createEmptyMovieClip("NordicMinimalUIDot",10000);\n      this.NordicDot._visible = false;\n      this.NordicDot.lineStyle(1,0x20201D,90);\n      this.NordicDot.beginFill(0xD8CDA5,100);\n      this.NordicDot.moveTo(2.25,0);\n      var i = 1;\n      while(i <= 16)\n      {\n         this.NordicDot.lineTo(Math.cos(i * 0.3926990817) * 2.25,Math.sin(i * 0.3926990817) * 2.25);\n         i++;\n      }\n      this.NordicDot.endFill();\n   }\n   function UpdateNordicCrosshair()\n   {\n      if(this.NordicDot == undefined) this.CreateNordicDot();\n      var nativeCrosshair = this._currentframe != 1 ? this.CrosshairAlert : this.CrosshairInstance;\n      var center = {x:0,y:0};\n      nativeCrosshair.localToGlobal(center);\n      this.globalToLocal(center);\n      this.NordicDot._x = center.x;\n      this.NordicDot._y = center.y;\n      this.NordicDot._visible = this.bCrosshairEnabled && nativeCrosshair._visible;\n      this.CrosshairInstance._alpha = 0;\n      this.CrosshairAlert._alpha = 0;\n   }\n   function RunMeterAnim(aMeter)\n   {''')
        replace_once(hud, "   function onEnterFrame()\n   {", "   function onEnterFrame()\n   {\n      this.UpdateNordicCrosshair();")
        marker = "   function RunMeterAnim(aMeter)\n   {"
        methods = '''   function SetNordicFadeDelay(seconds)\n   {\n      this.NordicFadeDelay = Math.max(1,Math.min(10,seconds));\n   }\n   function SetNordicBarsEnabled(enabled)\n   {\n      this.NordicBarsEnabled = enabled;\n      this.HealthMeterAnim._visible = enabled;\n      this.MagickaMeterAnim._visible = enabled;\n      this.StaminaMeterAnim._visible = enabled;\n      if(enabled) this.ScheduleNordicFade();\n   }\n   function SetNordicCompassEnabled(enabled)\n   {\n      this.NordicCompassEnabled = enabled;\n      this.CompassShoutMeterHolder._visible = enabled;\n   }\n   function SetNordicCombatActive(active)\n   {\n      this.NordicCombatActive = active;\n      if(active)\n      {\n         clearInterval(this.NordicFadeTimerID);\n         if(this.NordicBarsEnabled)\n         {\n            this.HealthMeterAnim._visible = true;\n            this.MagickaMeterAnim._visible = true;\n            this.StaminaMeterAnim._visible = true;\n         }\n      }\n      else this.ScheduleNordicFade();\n   }\n   function ScheduleNordicFade()\n   {\n      clearInterval(this.NordicFadeTimerID);\n      if(this.NordicBarsEnabled && !this.NordicCombatActive)\n         this.NordicFadeTimerID = setInterval(this,\"NordicFadeMeters\",this.NordicFadeDelay * 1000);\n   }\n   function NordicFadeMeters()\n   {\n      clearInterval(this.NordicFadeTimerID);\n      if(this.NordicBarsEnabled && !this.NordicCombatActive)\n      {\n         this.FadeOutMeter(this.HealthMeterAnim);\n         this.FadeOutMeter(this.MagickaMeterAnim);\n         this.FadeOutMeter(this.StaminaMeterAnim);\n      }\n   }\n'''
        replace_once(hud, marker, methods + marker)
        for meter in ("Health", "Magicka", "Stamina"):
            sig = f"   function Set{meter}MeterPercent(aPercent, abForce)\n   {{"
            replace_once(hud, sig, sig + f"\n      if(this.NordicBarsEnabled)\n      {{\n         this.{meter}MeterAnim._visible = true;\n         this.ScheduleNordicFade();\n      }}")
        dialogue = exports["dialogue"] / "__Packages/DialogueCenteredList.as"
        old = "         aEntryClip.textField.textColor = !(aEntryObject.topicIsNew == undefined || aEntryObject.topicIsNew) ? 6316128 : 16777215;"
        new = "         aEntryClip.textField.textColor = aEntryObject == this.selectedEntry ? 14209701 : (!(aEntryObject.topicIsNew == undefined || aEntryObject.topicIsNew) ? 7829367 : 13421772);"
        replace_once(dialogue, old, new)
        outputs = work / "compiled"
        outputs.mkdir()
        for key, filename in (("hud", "hudmenu.swf"), ("dialogue", "dialoguemenu.swf")):
            source = next(extracted.rglob(filename))
            result = outputs / filename
            run(["java", "-jar", str(FFDEC), "-importScript", str(source), str(result), str(exports[key])])
        archive = Path(os.environ.get("SWF_ARCHIVE", ROOT / "NordicMinimalUISE-SWF.zip"))
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as package:
            package.write(outputs / "hudmenu.swf", "Data/Interface/hudmenu.swf")
            package.write(outputs / "dialoguemenu.swf", "Data/Interface/dialoguemenu.swf")
    print(f"Built {archive}")


if __name__ == "__main__":
    main()
