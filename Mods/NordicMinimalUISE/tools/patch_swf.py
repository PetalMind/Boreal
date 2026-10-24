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
        swfs = {
            "hudmenu.swf": "hud",
            "dialoguemenu.swf": "dialogue",
            "sleepwaitmenu.swf": "sleepwait",
        }
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
        replace_once(hud, "   function RunMeterAnim(aMeter)\n   {", '''   function CreateNordicDot()\n   {\n      this.NordicDot = this.createEmptyMovieClip("NordicMinimalUIDot",10000);\n      this.NordicDot._visible = false;\n      this.NordicDot.lineStyle(1,0x20201D,90);\n      this.NordicDot.beginFill(0xD8CDA5,100);\n      this.NordicDot.moveTo(2.25,0);\n      var i = 1;\n      while(i <= 16)\n      {\n         this.NordicDot.lineTo(Math.cos(i * 0.3926990817) * 2.25,Math.sin(i * 0.3926990817) * 2.25);\n         i++;\n      }\n      this.NordicDot.endFill();\n   }\n   function UpdateNordicCrosshair()\n   {\n      if(this.NordicDot == undefined) this.CreateNordicDot();\n      // HUD frames also change during pickup animations; select the active reticle clip by visibility.\n      var nativeCrosshair = this.CrosshairAlert._visible ? this.CrosshairAlert : this.CrosshairInstance;\n      var center = {x:0,y:0};\n      nativeCrosshair.localToGlobal(center);\n      this.globalToLocal(center);\n      this.NordicDot._x = center.x;\n      this.NordicDot._y = center.y;\n      var alertState = this.CrosshairAlert._visible;\n      var phase = getTimer() / (alertState ? 70 : 360);\n      var pulse = (Math.sin(phase) + 1) / 2;\n      var scale = alertState ? 125 + pulse * 45 : 94 + pulse * 12;\n      this.NordicDot._xscale = scale;\n      this.NordicDot._yscale = scale;\n      this.NordicDot._alpha = alertState ? 78 + pulse * 22 : 84 + pulse * 16;\n      this.NordicDot._visible = this.bCrosshairEnabled && (this.CrosshairAlert._visible || this.CrosshairInstance._visible);\n      this.CrosshairInstance._alpha = 0;\n      this.CrosshairAlert._alpha = 0;\n   }\n   function RunMeterAnim(aMeter)\n   {''')
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
        sleepwait = exports["sleepwait"] / "__Packages/SleepWaitMenu.as"
        replace_once(
            sleepwait,
            "   var bDisableControls;",
            """   var bDisableControls;
   var NordicWaitDial;
   var NordicDialCenterX;
   var NordicDialCenterY;
   var NordicDialRadius = 58;
   var NordicDialDragging = false;""",
        )
        replace_once(
            sleepwait,
            '      this.HoursSlider.addEventListener("change",this,"sliderChange");',
            '      this.HoursSlider.addEventListener("change",this,"sliderChange");\n      this.CreateNordicWaitDial();',
        )
        replace_once(
            sleepwait,
            "   function handleInput(details, pathToFocus)",
            r'''   function CreateNordicWaitDial()
   {
      this.HoursSlider.track._visible = false;
      this.HoursSlider.thumb._visible = false;
      this.NordicDialCenterX = this.HoursSlider._x + this.HoursSlider._width / 2;
      this.NordicDialCenterY = this.HoursSlider._y + this.HoursSlider._height / 2;
      this.NordicWaitDial = this.createEmptyMovieClip("NordicWaitDial",10000);
      this.NordicWaitDial._x = this.NordicDialCenterX;
      this.NordicWaitDial._y = this.NordicDialCenterY;
      var hoursFormat = this.HoursText.getTextFormat();
      hoursFormat.align = "center";
      hoursFormat.size = 24;
      this.HoursText.setNewTextFormat(hoursFormat);
      this.HoursText.setTextFormat(hoursFormat);
      this.HoursText._width = 72;
      this.HoursText._height = 36;
      this.HoursText._x = this.NordicDialCenterX - 36;
      this.HoursText._y = this.NordicDialCenterY - 18;
      this.HoursText.text = Math.floor(this.HoursSlider.value).toString();
      this.DrawNordicWaitDial();
   }
   function DrawNordicWaitDial()
   {
      if(this.NordicWaitDial == undefined)
      {
         return;
      }
      var radius = this.NordicDialRadius;
      var hours = Math.max(this.HoursSlider.minimum,Math.floor(this.HoursSlider.value));
      var maximum = Math.max(1,this.HoursSlider.maximum);
      var progress = Math.min(1,Math.max(0,hours / maximum));
      var i = 0;
      var angle = -Math.PI / 2;
      this.NordicWaitDial.clear();
      this.NordicWaitDial.lineStyle(4,0xD8CDA5,22);
      this.NordicWaitDial.moveTo(0,-radius);
      i = 1;
      while(i <= 96)
      {
         angle = -Math.PI / 2 + Math.PI * 2 * i / 96;
         this.NordicWaitDial.lineTo(Math.cos(angle) * radius,Math.sin(angle) * radius);
         i++;
      }
      i = 0;
      while(i < 24)
      {
         angle = -Math.PI / 2 + Math.PI * 2 * i / 24;
         var tickInner = radius + (i % 6 == 0 ? 7 : 9);
         var tickOuter = radius + (i % 6 == 0 ? 15 : 12);
         this.NordicWaitDial.lineStyle(i % 6 == 0 ? 2 : 1,0xD8CDA5,i % 6 == 0 ? 88 : 52);
         this.NordicWaitDial.moveTo(Math.cos(angle) * tickInner,Math.sin(angle) * tickInner);
         this.NordicWaitDial.lineTo(Math.cos(angle) * tickOuter,Math.sin(angle) * tickOuter);
         i++;
      }
      this.NordicWaitDial.lineStyle(4,0xE4D7B1,100);
      this.NordicWaitDial.moveTo(0,-radius);
      var arcSegments = Math.max(1,Math.ceil(progress * 96));
      i = 1;
      while(i <= arcSegments)
      {
         angle = -Math.PI / 2 + Math.PI * 2 * progress * i / arcSegments;
         this.NordicWaitDial.lineTo(Math.cos(angle) * radius,Math.sin(angle) * radius);
         i++;
      }
      var markerX = Math.cos(angle) * radius;
      var markerY = Math.sin(angle) * radius;
      this.NordicWaitDial.lineStyle(1,0x26231D,100);
      this.NordicWaitDial.beginFill(0xE4D7B1,100);
      this.NordicWaitDial.moveTo(markerX + 4,markerY);
      i = 1;
      while(i <= 16)
      {
         this.NordicWaitDial.lineTo(markerX + Math.cos(i * Math.PI / 8) * 4,markerY + Math.sin(i * Math.PI / 8) * 4);
         i++;
      }
      this.NordicWaitDial.endFill();
   }
   function IsNordicDialPoint()
   {
      var dx = this._xmouse - this.NordicDialCenterX;
      var dy = this._ymouse - this.NordicDialCenterY;
      var distance = Math.sqrt(dx * dx + dy * dy);
      return distance >= this.NordicDialRadius - 20 && distance <= this.NordicDialRadius + 18;
   }
   function UpdateNordicDialValue()
   {
      if(this.disableControls)
      {
         return;
      }
      var dx = this._xmouse - this.NordicDialCenterX;
      var dy = this._ymouse - this.NordicDialCenterY;
      var angle = Math.atan2(dy,dx) + Math.PI / 2;
      if(angle < 0)
      {
         angle += Math.PI * 2;
      }
      var minimum = this.HoursSlider.minimum;
      var maximum = this.HoursSlider.maximum;
      var count = maximum - minimum + 1;
      var value = minimum + Math.floor(angle / (Math.PI * 2) * count);
      this.HoursSlider.value = Math.min(maximum,Math.max(minimum,value));
      this.sliderChange();
   }
   function onMouseDown()
   {
      if(!this.disableControls && this.IsNordicDialPoint())
      {
         this.NordicDialDragging = true;
         this.UpdateNordicDialValue();
      }
   }
   function onMouseMove()
   {
      if(this.NordicDialDragging)
      {
         this.UpdateNordicDialValue();
      }
   }
   function onMouseUp()
   {
      this.NordicDialDragging = false;
   }
   function handleInput(details, pathToFocus)''',
        )
        replace_once(
            sleepwait,
            "      this.HoursText.text = Math.floor(this.HoursSlider.value).toString();\n      if(_loc2_ != Math.floor(this.HoursSlider.value))",
            "      this.HoursText.text = Math.floor(this.HoursSlider.value).toString();\n      this.DrawNordicWaitDial();\n      if(_loc2_ != Math.floor(this.HoursSlider.value))",
        )
        outputs = work / "compiled"
        outputs.mkdir()
        for key, filename in (("hud", "hudmenu.swf"), ("dialogue", "dialoguemenu.swf"), ("sleepwait", "sleepwaitmenu.swf")):
            source = next(extracted.rglob(filename))
            result = outputs / filename
            run(["java", "-jar", str(FFDEC), "-importScript", str(source), str(result), str(exports[key])])
        archive = Path(os.environ.get("SWF_ARCHIVE", ROOT / "NordicMinimalUISE-SWF.zip"))
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as package:
            package.write(outputs / "hudmenu.swf", "Data/Interface/hudmenu.swf")
            package.write(outputs / "dialoguemenu.swf", "Data/Interface/dialoguemenu.swf")
            package.write(outputs / "sleepwaitmenu.swf", "Data/Interface/sleepwaitmenu.swf")
    print(f"Built {archive}")


if __name__ == "__main__":
    main()
