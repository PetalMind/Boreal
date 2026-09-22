#!/usr/bin/env python3
"""Apply the small AS2 patch to FFDec's decompiled quickbar class."""

from __future__ import annotations

import sys
from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"Expected one {label} block, found {count}")
    return source.replace(old, new, 1)


def patch(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    source = replace_once(
        source,
        '   var m_CooldownFinishController;\n   var m_DisableMovie;',
        '   var m_CooldownFinishController;\n'
        '   var m_CooldownNumberFormat;\n'
        '   var m_CooldownNumberTxt;\n'
        '   var m_CooldownNumberTimer = 0;\n'
        '   var m_DisableMovie;',
        "cooldown fields",
    )
    source = replace_once(
        source,
        '      this.SetTokens(this.AbilityToken,this.QuickItemToken);\n'
        '      this.StackCount_mc_init = function()',
        '      this.SetTokens(this.AbilityToken,this.QuickItemToken);\n'
        '      this.InitializeCooldownNumber();\n'
        '      this.m_CooldownNumberTimer = setInterval(this,"UpdateCooldownNumber",100);\n'
        '      this.StackCount_mc_init = function()',
        "cooldown setup",
    )
    source = replace_once(
        source,
        '   function OnRemoved()\n'
        '   {\n'
        '      super.OnRemoved();\n'
        '   }',
        '   function OnRemoved()\n'
        '   {\n'
        '      if(this.m_CooldownNumberTimer != 0)\n'
        '      {\n'
        '         clearInterval(this.m_CooldownNumberTimer);\n'
        '         this.m_CooldownNumberTimer = 0;\n'
        '      }\n'
        '      super.OnRemoved();\n'
        '   }',
        "cooldown cleanup",
    )
    source = replace_once(
        source,
        '   function OnCooldownEnd()\n'
        '   {\n'
        '      if(ExternalCommands.GetBool(this.AbilityToken + ".IsWarning") == false && ExternalCommands.GetBool(this.AbilityToken + ".IsError") == false)\n'
        '      {\n'
        '         this.m_CooldownFinishController.PlayForward();\n'
        '      }\n'
        '   }\n',
        '   function OnCooldownEnd()\n'
        '   {\n'
        '      if(ExternalCommands.GetBool(this.AbilityToken + ".IsWarning") == false && ExternalCommands.GetBool(this.AbilityToken + ".IsError") == false)\n'
        '      {\n'
        '         this.m_CooldownFinishController.PlayForward();\n'
        '      }\n'
        '   }\n'
        '   function InitializeCooldownNumber()\n'
        '   {\n'
        '      this.createTextField("CooldownNumbers_txt",this.getNextHighestDepth(),0,10,42,22);\n'
        '      this.m_CooldownNumberTxt = this.CooldownNumbers_txt;\n'
        '      this.m_CooldownNumberTxt.selectable = false;\n'
        '      this.m_CooldownNumberTxt.multiline = false;\n'
        '      this.m_CooldownNumberTxt.wordWrap = false;\n'
        '      this.m_CooldownNumberTxt.autoSize = "center";\n'
        '      this.m_CooldownNumberTxt.textColor = 16777215;\n'
        '      this.m_CooldownNumberTxt.html = false;\n'
        '      this.m_CooldownNumberTxt.shadowStyle = "s{0,1}{1,1}{1,0}";\n'
        '      this.m_CooldownNumberTxt.shadowColor = 0;\n'
        '      this.m_CooldownNumberFormat = new TextFormat();\n'
        '      this.m_CooldownNumberFormat.font = "BodyFont";\n'
        '      this.m_CooldownNumberFormat.size = 16;\n'
        '      this.m_CooldownNumberFormat.bold = true;\n'
        '      this.m_CooldownNumberFormat.align = "center";\n'
        '      this.m_CooldownNumberFormat.color = 16777215;\n'
        '      this.m_CooldownNumberTxt.setNewTextFormat(this.m_CooldownNumberFormat);\n'
        '      this.m_CooldownNumberTxt.text = "";\n'
        '      this.m_CooldownNumberTxt._visible = false;\n'
        '   }\n'
        '   function UpdateCooldownNumber()\n'
        '   {\n'
        '      if(this.m_CooldownNumberTxt == null)\n'
        '      {\n'
        '         return undefined;\n'
        '      }\n'
        '      var _loc4_ = Number(ExternalCommands.GetValue(this.m_sAbilityInstanceToken + ".CooldownPercentage"));\n'
        '      var _loc3_ = Number(ExternalCommands.GetValue(this.m_sAbilityInstanceToken + ".AbilityTemplate.Cooldown"));\n'
        '      if(!this.m_bValidAbilityToken || isNaN(_loc4_) || isNaN(_loc3_) || _loc4_ <= 0 || _loc3_ <= 0)\n'
        '      {\n'
        '         this.m_CooldownNumberTxt.text = "";\n'
        '         this.m_CooldownNumberTxt._visible = false;\n'
        '         return undefined;\n'
        '      }\n'
        '      var _loc2_ = _loc4_ * _loc3_;\n'
        '      var _loc1_ = "";\n'
        '      if(_loc2_ >= 10)\n'
        '      {\n'
        '         _loc1_ = String(Math.ceil(_loc2_));\n'
        '      }\n'
        '      else if(_loc2_ > 0.05)\n'
        '      {\n'
        '         _loc1_ = _loc2_.toFixed(1);\n'
        '      }\n'
        '      if(_loc1_.length == 0)\n'
        '      {\n'
        '         this.m_CooldownNumberTxt.text = "";\n'
        '         this.m_CooldownNumberTxt._visible = false;\n'
        '      }\n'
        '      else\n'
        '      {\n'
        '         this.m_CooldownNumberTxt.text = _loc1_;\n'
        '         this.m_CooldownNumberTxt.setTextFormat(this.m_CooldownNumberFormat);\n'
        '         this.m_CooldownNumberTxt._visible = true;\n'
        '      }\n'
        '   }\n',
        "cooldown rendering methods",
    )
    path.write_text(source, encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: patch_quickbar.py DECOMPILED_QUICKBAR_CLASS")
    patch(Path(sys.argv[1]))
