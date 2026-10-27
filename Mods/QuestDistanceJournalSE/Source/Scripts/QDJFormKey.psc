Scriptname QDJFormKey Hidden

String Function FromForm(Form value) Global
    If value == None
        Return ""
    EndIf
    Int raw = value.GetFormID()
    Int index = Math.RightShift(raw, 24)
    Int localID = Math.LogicalAnd(raw, 0x00FFFFFF)
    String plugin
    If index == 254
        plugin = Game.GetLightModName(Math.RightShift(Math.LogicalAnd(raw, 0x00FFF000), 12))
        localID = Math.LogicalAnd(raw, 0x00000FFF)
    ElseIf index < 254
        plugin = Game.GetModName(index)
    Else
        Return ""
    EndIf
    Return plugin + "|" + localID
EndFunction

Form Function ToForm(String key) Global
    String[] parts = StringUtil.Split(key, "|")
    If parts.Length != 2
        Return None
    EndIf
    Return Game.GetFormFromFile(parts[1] as Int, parts[0])
EndFunction
