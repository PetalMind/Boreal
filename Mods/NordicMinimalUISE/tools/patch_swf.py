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
        replace_once(hud, "   var METER_PAUSE_FRAME = 40;", "   var METER_PAUSE_FRAME = 40;\n   var NordicFadeDelay = 5;\n   var NordicBarsEnabled = true;\n   var NordicCompassEnabled = true;\n   var NordicCombatActive = false;\n   var NordicFadeTimerID;\n   var NordicHorsePanel;\n   var NordicHorseNameField;\n   var NordicHorseHealthLabel;\n   var NordicHorseHealthValue;\n   var NordicHorseStaminaLabel;\n   var NordicHorseStaminaValue;\n   var NordicHorseHealthBar;\n   var NordicHorseStaminaBar;")
        replace_once(hud, '      this.StaminaMeterAnim.Lock("BR");', '      this.StaminaMeterAnim.Lock("BR");\n      this.CreateNordicHorsePanel();')
        replace_once(hud, "   function RunMeterAnim(aMeter)\n   {", '''   function CreateNordicDot()\n   {\n      this.NordicDot = this.createEmptyMovieClip("NordicMinimalUIDot",10000);\n      this.NordicDot._visible = false;\n      this.NordicDot.lineStyle(1,0x20201D,90);\n      this.NordicDot.beginFill(0xD8CDA5,100);\n      this.NordicDot.moveTo(2.25,0);\n      var i = 1;\n      while(i <= 16)\n      {\n         this.NordicDot.lineTo(Math.cos(i * 0.3926990817) * 2.25,Math.sin(i * 0.3926990817) * 2.25);\n         i++;\n      }\n      this.NordicDot.endFill();\n   }\n   function UpdateNordicCrosshair()\n   {\n      if(this.NordicDot == undefined) this.CreateNordicDot();\n      // HUD frames also change during pickup animations; select the active reticle clip by visibility.\n      var nativeCrosshair = this.CrosshairAlert._visible ? this.CrosshairAlert : this.CrosshairInstance;\n      var center = {x:0,y:0};\n      nativeCrosshair.localToGlobal(center);\n      this.globalToLocal(center);\n      this.NordicDot._x = center.x;\n      this.NordicDot._y = center.y;\n      var alertState = this.CrosshairAlert._visible;\n      var phase = getTimer() / (alertState ? 70 : 360);\n      var pulse = (Math.sin(phase) + 1) / 2;\n      var scale = alertState ? 125 + pulse * 45 : 94 + pulse * 12;\n      this.NordicDot._xscale = scale;\n      this.NordicDot._yscale = scale;\n      this.NordicDot._alpha = alertState ? 78 + pulse * 22 : 84 + pulse * 16;\n      this.NordicDot._visible = this.bCrosshairEnabled && (this.CrosshairAlert._visible || this.CrosshairInstance._visible);\n      this.CrosshairInstance._alpha = 0;\n      this.CrosshairAlert._alpha = 0;\n   }\n   function RunMeterAnim(aMeter)\n   {''')
        replace_once(hud, "   function onEnterFrame()\n   {", "   function onEnterFrame()\n   {\n      this.UpdateNordicCrosshair();")
        marker = "   function RunMeterAnim(aMeter)\n   {"
        methods = '''   function SetNordicFadeDelay(seconds)\n   {\n      this.NordicFadeDelay = Math.max(1,Math.min(10,seconds));\n   }\n   function SetNordicBarsEnabled(enabled)\n   {\n      this.NordicBarsEnabled = enabled;\n      this.HealthMeterAnim._visible = enabled;\n      this.MagickaMeterAnim._visible = enabled;\n      this.StaminaMeterAnim._visible = enabled;\n      if(enabled) this.ScheduleNordicFade();\n   }\n   function SetNordicCompassEnabled(enabled)\n   {\n      this.NordicCompassEnabled = enabled;\n      this.CompassShoutMeterHolder._visible = enabled;\n   }\n   function SetNordicCombatActive(active)\n   {\n      this.NordicCombatActive = active;\n      if(active)\n      {\n         clearInterval(this.NordicFadeTimerID);\n         if(this.NordicBarsEnabled)\n         {\n            this.HealthMeterAnim._visible = true;\n            this.MagickaMeterAnim._visible = true;\n            this.StaminaMeterAnim._visible = true;\n         }\n      }\n      else this.ScheduleNordicFade();\n   }\n   function ScheduleNordicFade()\n   {\n      clearInterval(this.NordicFadeTimerID);\n      if(this.NordicBarsEnabled && !this.NordicCombatActive)\n         this.NordicFadeTimerID = setInterval(this,\"NordicFadeMeters\",this.NordicFadeDelay * 1000);\n   }\n   function NordicFadeMeters()\n   {\n      clearInterval(this.NordicFadeTimerID);\n      if(this.NordicBarsEnabled && !this.NordicCombatActive)\n      {\n         this.FadeOutMeter(this.HealthMeterAnim);\n         this.FadeOutMeter(this.MagickaMeterAnim);\n         this.FadeOutMeter(this.StaminaMeterAnim);\n      }\n   }\n   function CreateNordicHorsePanel()
   {
      if(this.NordicHorsePanel != undefined) return;
      this.NordicHorsePanel = this.createEmptyMovieClip("NordicHorseStatusPanel",10001);
      var panel = this.NordicHorsePanel;
      panel.lineStyle(1,0xD8CDA5,42);
      panel.beginFill(0x11130F,82);
      panel.moveTo(0,0);
      panel.lineTo(264,0);
      panel.lineTo(264,96);
      panel.lineTo(0,96);
      panel.lineTo(0,0);
      panel.endFill();
      panel.lineStyle(1,0xD8CDA5,72);
      panel.moveTo(13,1);
      panel.lineTo(251,1);
      panel.createTextField("HorseNameField",1,13,9,238,23);
      panel.createTextField("HorseHealthLabel",2,13,34,150,14);
      panel.createTextField("HorseHealthValue",3,211,34,40,14);
      panel.createTextField("HorseStaminaLabel",4,13,62,150,14);
      panel.createTextField("HorseStaminaValue",5,211,62,40,14);
      this.NordicHorseNameField = panel.HorseNameField;
      this.NordicHorseHealthLabel = panel.HorseHealthLabel;
      this.NordicHorseHealthValue = panel.HorseHealthValue;
      this.NordicHorseStaminaLabel = panel.HorseStaminaLabel;
      this.NordicHorseStaminaValue = panel.HorseStaminaValue;
      var titleFormat = new TextFormat("$EverywhereFont",18,0xF0EBDD,false,false,false,false,"","left",0,0,0,0);
      var labelFormat = new TextFormat("$EverywhereFont",11,0xD8CDA5,false,false,false,false,"","left",0,0,0,0);
      var valueFormat = new TextFormat("$EverywhereFont",11,0xF0EBDD,false,false,false,false,"","right",0,0,0,0);
      this.NordicHorseNameField.setNewTextFormat(titleFormat);
      this.NordicHorseNameField.setTextFormat(titleFormat);
      this.NordicHorseNameField.textAutoSize = "shrink";
      this.NordicHorseNameField.selectable = false;
      this.NordicHorseHealthLabel.setNewTextFormat(labelFormat);
      this.NordicHorseHealthLabel.setTextFormat(labelFormat);
      this.NordicHorseHealthLabel.selectable = false;
      this.NordicHorseHealthLabel.text = "ZDROWIE";
      this.NordicHorseHealthValue.setNewTextFormat(valueFormat);
      this.NordicHorseHealthValue.setTextFormat(valueFormat);
      this.NordicHorseHealthValue.selectable = false;
      this.NordicHorseStaminaLabel.setNewTextFormat(labelFormat);
      this.NordicHorseStaminaLabel.setTextFormat(labelFormat);
      this.NordicHorseStaminaLabel.selectable = false;
      this.NordicHorseStaminaLabel.text = "WYTRZYMAŁOŚĆ";
      this.NordicHorseStaminaValue.setNewTextFormat(valueFormat);
      this.NordicHorseStaminaValue.setTextFormat(valueFormat);
      this.NordicHorseStaminaValue.selectable = false;
      this.NordicHorseHealthBar = panel.createEmptyMovieClip("HorseHealthBar",6);
      this.NordicHorseHealthBar._x = 13;
      this.NordicHorseHealthBar._y = 51;
      this.NordicHorseStaminaBar = panel.createEmptyMovieClip("HorseStaminaBar",7);
      this.NordicHorseStaminaBar._x = 13;
      this.NordicHorseStaminaBar._y = 79;
      this.DrawNordicHorseBar(this.NordicHorseHealthBar,1,0xB66D61);
      this.DrawNordicHorseBar(this.NordicHorseStaminaBar,1,0xD8CDA5);
      panel._visible = false;
      // Lock preserves the authored offset; it does not move a new clip to BR.
      // Position in the same coordinate space as the native stamina meter first.
      panel._x = this.StaminaMeterAnim._x + this.StaminaMeterAnim._width - 264;
      panel._y = this.StaminaMeterAnim._y - 118;
      panel.Lock("BR");
   }
   function DrawNordicHorseBar(barClip,percent,color)
   {
      percent = Math.max(0,Math.min(1,percent));
      barClip.clear();
      barClip.beginFill(0x2B2B25,100);
      barClip.moveTo(0,0);
      barClip.lineTo(238,0);
      barClip.lineTo(238,5);
      barClip.lineTo(0,5);
      barClip.lineTo(0,0);
      barClip.endFill();
      if(percent > 0)
      {
         barClip.beginFill(color,100);
         barClip.moveTo(0,0);
         barClip.lineTo(238 * percent,0);
         barClip.lineTo(238 * percent,5);
         barClip.lineTo(0,5);
         barClip.lineTo(0,0);
         barClip.endFill();
      }
   }
   function SetNordicHorseName(name)
   {
      if(this.NordicHorsePanel == undefined) this.CreateNordicHorsePanel();
      this.NordicHorseNameField.text = name;
   }
   function SetNordicHorseHealth(percent)
   {
      if(this.NordicHorsePanel == undefined) this.CreateNordicHorsePanel();
      percent = Math.max(0,Math.min(1,percent));
      this.NordicHorseHealthValue.text = Math.round(percent * 100) + "%";
      this.DrawNordicHorseBar(this.NordicHorseHealthBar,percent,0xB66D61);
   }
   function SetNordicHorseStamina(percent)
   {
      if(this.NordicHorsePanel == undefined) this.CreateNordicHorsePanel();
      percent = Math.max(0,Math.min(1,percent));
      this.NordicHorseStaminaValue.text = Math.round(percent * 100) + "%";
      this.DrawNordicHorseBar(this.NordicHorseStaminaBar,percent,0xD8CDA5);
   }
   function SetNordicHorseVisible(visible)
   {
      if(this.NordicHorsePanel == undefined) this.CreateNordicHorsePanel();
      this.NordicHorsePanel._visible = visible;
   }'''
        replace_once(hud, marker, methods + marker)
        for meter in ("Health", "Magicka", "Stamina"):
            sig = f"   function Set{meter}MeterPercent(aPercent, abForce)\n   {{"
            replace_once(hud, sig, sig + f"\n      if(this.NordicBarsEnabled)\n      {{\n         this.{meter}MeterAnim._visible = true;\n         this.ScheduleNordicFade();\n      }}")
        dialogue = exports["dialogue"] / "__Packages/DialogueCenteredList.as"
        old = "         aEntryClip.textField.textColor = !(aEntryObject.topicIsNew == undefined || aEntryObject.topicIsNew) ? 6316128 : 16777215;"
        new = "         aEntryClip.textField.textColor = aEntryObject == this.selectedEntry || aEntryObject.topicIsNew == undefined || aEntryObject.topicIsNew ? 14209701 : 7829367;"
        replace_once(dialogue, old, new)
        dialogue_menu = exports["dialogue"] / "__Packages/DialogueMenu.as"
        replace_once(
            dialogue_menu,
            'this.ExitButton.addEventListener("click",this,"onCancelPress");',
            'this.ExitButton.addEventListener("click",this,"onCancelPress");\n      this.CreateNordicExitIcon();',
        )
        replace_once(
            dialogue_menu,
            "this.ExitButton._visible = !abHideExitButton;",
            "this.ExitButton._visible = !abHideExitButton;\n      this.SetNordicExitIconVisible(!abHideExitButton);",
        )
        replace_once(
            dialogue_menu,
            "this.ExitButton._visible = false;",
            "this.ExitButton._visible = false;\n      this.SetNordicExitIconVisible(false);",
        )
        replace_once(
            dialogue_menu,
            "function SetPlatform(",
            '''   function CreateNordicExitIcon()
   {
      if(this.NordicExitIcon != undefined) return;
      this.NordicExitIcon = this.createEmptyMovieClip("NordicDialogueExitIcon",10000);
      this.NordicExitIcon._x = this.ExitButton._x - 22;
      this.NordicExitIcon._y = this.ExitButton._y + 8;
      this.NordicExitIcon.lineStyle(2,0xD8CDA5,92);
      this.NordicExitIcon.moveTo(-5,-7);
      this.NordicExitIcon.lineTo(1,-7);
      this.NordicExitIcon.lineTo(1,7);
      this.NordicExitIcon.lineTo(-5,7);
      this.NordicExitIcon.lineTo(-5,-7);
      this.NordicExitIcon.moveTo(-2,0);
      this.NordicExitIcon.lineTo(8,0);
      this.NordicExitIcon.lineTo(4,-4);
      this.NordicExitIcon.moveTo(8,0);
      this.NordicExitIcon.lineTo(4,4);
      this.NordicExitIcon._visible = false;
   }
   function SetNordicExitIconVisible(visible)
   {
      if(this.NordicExitIcon == undefined) this.CreateNordicExitIcon();
      this.NordicExitIcon._visible = visible;
   }
   function SetPlatform(''',
        )
        sleepwait = exports["sleepwait"] / "__Packages/SleepWaitMenu.as"
        replace_once(
            sleepwait,
            "   var bDisableControls;",
            """   var bDisableControls;
   var NordicWaitDial;
   var NordicDialCenterX;
   var NordicDialCenterY;
   var NordicQuestionBaseY;
   var NordicCurrentTimeBaseY;
   var NordicDialRadius = 26;
   var NordicDialDragging = false;""",
        )
        replace_once(
            sleepwait,
            '      this.HoursSlider.addEventListener("change",this,"sliderChange");',
            '      this.HoursSlider.addEventListener("change",this,"sliderChange");\n      this.CreateNordicWaitDial();',
        )
        replace_once(
            sleepwait,
            "      this.CurrentTime.SetText(aTime);",
            "      this.CurrentTime.SetText(aTime);\n      this.ApplyNordicWaitLayout();",
        )
        replace_once(
            sleepwait,
            "      this.QuestionInstance.SetText(_loc2_);",
            "      this.QuestionInstance.SetText(_loc2_);\n      this.ApplyNordicWaitLayout();",
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
      this.NordicQuestionBaseY = this.QuestionInstance._y;
      this.NordicCurrentTimeBaseY = this.CurrentTime._y;
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
      this.ApplyNordicWaitLayout();
      this.HoursText.text = Math.floor(this.HoursSlider.value).toString();
      this.DrawNordicWaitDial();
   }
   function ApplyNordicWaitLayout()
   {
      if(this.QuestionInstance != undefined && this.NordicQuestionBaseY != undefined)
      {
         this.QuestionInstance._y = this.NordicQuestionBaseY - 22;
      }
      if(this.CurrentTime != undefined && this.NordicCurrentTimeBaseY != undefined)
      {
         this.CurrentTime._y = this.NordicCurrentTimeBaseY + 10;
         var timeFormat = this.CurrentTime.getTextFormat();
         timeFormat.align = "center";
         timeFormat.size = 22;
         timeFormat.color = 0xD8CDA5;
         this.CurrentTime.setNewTextFormat(timeFormat);
         this.CurrentTime.setTextFormat(timeFormat);
      }
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
      this.NordicWaitDial.lineStyle(3,0xD8CDA5,22);
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
         var tickInner = radius + (i % 6 == 0 ? 3 : 4);
         var tickOuter = radius + (i % 6 == 0 ? 8 : 6);
         this.NordicWaitDial.lineStyle(i % 6 == 0 ? 2 : 1,0xD8CDA5,i % 6 == 0 ? 88 : 52);
         this.NordicWaitDial.moveTo(Math.cos(angle) * tickInner,Math.sin(angle) * tickInner);
         this.NordicWaitDial.lineTo(Math.cos(angle) * tickOuter,Math.sin(angle) * tickOuter);
         i++;
      }
      this.NordicWaitDial.lineStyle(3,0xE4D7B1,100);
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
      this.NordicWaitDial.moveTo(markerX + 3,markerY);
      i = 1;
      while(i <= 16)
      {
         this.NordicWaitDial.lineTo(markerX + Math.cos(i * Math.PI / 8) * 3,markerY + Math.sin(i * Math.PI / 8) * 3);
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
