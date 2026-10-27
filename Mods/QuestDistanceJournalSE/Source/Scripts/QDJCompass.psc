Scriptname QDJCompass extends Quest

String Property CompassPath = "_root.HUDMovieBaseInstance.CompassShoutMeterHolder.Compass" AutoReadOnly
Bool Property CompassEnabled = True Auto

Function SetEnabled(Bool enabled)
    CompassEnabled = enabled
    If !enabled
        Show("")
    EndIf
EndFunction

Function Show(String label)
    If !CompassEnabled
        label = ""
    EndIf
    If !UI.IsMenuOpen("HUD Menu")
        Return
    EndIf
    String path = CompassPath + ".QDJDistance"
    If UI.GetFloat("HUD Menu", path + "._width") <= 0.0
        Float width = UI.GetFloat("HUD Menu", CompassPath + ".CompassMask_mc._width")
        If width <= 0.0
            Return
        EndIf
        String[] args = new String[6]
        args[0] = "QDJDistance"
        args[1] = "5000"
        args[2] = UI.GetFloat("HUD Menu", CompassPath + ".CompassMask_mc._x") as String
        args[3] = (UI.GetFloat("HUD Menu", CompassPath + ".CompassMask_mc._y") + UI.GetFloat("HUD Menu", CompassPath + ".CompassMask_mc._height") + 8.0) as String
        args[4] = width as String
        args[5] = "28"
        UI.InvokeStringA("HUD Menu", CompassPath + ".createTextField", args)
        UI.SetBool("HUD Menu", path + ".selectable", False)
        UI.SetBool("HUD Menu", path + ".multiline", False)
        UI.SetBool("HUD Menu", path + ".html", True)
        UI.SetString("HUD Menu", path + ".textAutoSize", "shrink")
    EndIf
    UI.SetString("HUD Menu", path + ".htmlText", "<p align='center'><font face='$EverywhereFont' size='14' color='#FFFFFF'>" + Escape(label) + "</font></p>")
    UI.SetBool("HUD Menu", path + "._visible", label != "")
EndFunction

String Function Escape(String value)
    String result = ""
    Int i = 0
    While i < StringUtil.GetLength(value)
        String letter = StringUtil.GetNthChar(value, i)
        If letter == "&"
            result += "&amp;"
        ElseIf letter == "<"
            result += "&lt;"
        ElseIf letter == ">"
            result += "&gt;"
        Else
            result += letter
        EndIf
        i += 1
    EndWhile
    Return result
EndFunction
