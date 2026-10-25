Scriptname QuestTrackerController extends Quest

Float Property PollSeconds = 1.0 AutoReadOnly
String Property HUDMenu = "HUD Menu" AutoReadOnly
String Property PanelPath = "_root.QuestTrackerPanel" AutoReadOnly
String Property TextPath = "_root.QuestTrackerPanel.QuestTrackerText" AutoReadOnly

GlobalVariable EnabledSetting
GlobalVariable HorizontalPosition
GlobalVariable VerticalPosition
GlobalVariable PanelWidth
GlobalVariable PanelOpacity
GlobalVariable MaximumQuests
Bool widgetReady
String lastHTML

Event OnInit()
    LoadSettings()
    RegisterForSingleUpdate(PollSeconds)
EndEvent

Event OnUpdate()
    RefreshHUD()
    RegisterForSingleUpdate(PollSeconds)
EndEvent

Function ApplySettings()
    LoadSettings()
    widgetReady = False
    RefreshHUD()
EndFunction

Function RefreshHUD()
    If !UI.IsMenuOpen(HUDMenu)
        widgetReady = False
        lastHTML = ""
        Return
    EndIf

    EnsureWidget()

    String html = ""
    If IsEnabled()
        html = QuestTrackerNative.GetTrackedQuestHTML(GetValue(MaximumQuests, 6.0) as Int)
    EndIf

    If html != lastHTML
        UI.SetString(HUDMenu, TextPath + ".htmlText", html)
        lastHTML = html
    EndIf

    ApplyWidgetSettings()
    Bool showWidget = IsEnabled() && html != "" && !IsOverlayBlocked()
    UI.SetBool(HUDMenu, TextPath + "._visible", showWidget)
EndFunction

Function EnsureWidget()
    If widgetReady && UI.GetFloat(HUDMenu, TextPath + "._width") > 0.0
        Return
    EndIf

    String[] panelArguments = new String[2]
    panelArguments[0] = "QuestTrackerPanel"
    panelArguments[1] = "50000"
    UI.InvokeStringA(HUDMenu, "_root.createEmptyMovieClip", panelArguments)

    String[] textArguments = new String[6]
    textArguments[0] = "QuestTrackerText"
    textArguments[1] = "1"
    textArguments[2] = "0"
    textArguments[3] = "0"
    textArguments[4] = "640"
    textArguments[5] = "720"
    UI.InvokeStringA(HUDMenu, PanelPath + ".createTextField", textArguments)

    lastHTML = ""
    UI.SetBool(HUDMenu, TextPath + ".multiline", True)
    UI.SetBool(HUDMenu, TextPath + ".wordWrap", True)
    UI.SetBool(HUDMenu, TextPath + ".selectable", False)
    UI.SetBool(HUDMenu, TextPath + ".border", False)
    UI.SetBool(HUDMenu, TextPath + ".background", True)
    UI.SetInt(HUDMenu, TextPath + ".backgroundColor", 0x16130F)
    UI.SetFloat(HUDMenu, TextPath + "._height", 720.0)
    widgetReady = True
EndFunction

Function ApplyWidgetSettings()
    Float width = GetValue(PanelWidth, 360.0)
    Float x = GetValue(HorizontalPosition, 850.0)
    Float y = GetValue(VerticalPosition, 220.0)
    Float height = UI.GetFloat(HUDMenu, TextPath + ".textHeight") + 16.0
    If width < 240.0
        width = 240.0
    ElseIf width > 640.0
        width = 640.0
    EndIf
    If height < 40.0
        height = 40.0
    ElseIf height > 704.0
        height = 704.0
    EndIf
    If x + width > 1280.0
        x = 1280.0 - width
    EndIf
    If y + height > 720.0
        y = 720.0 - height
    EndIf

    UI.SetFloat(HUDMenu, TextPath + "._x", x)
    UI.SetFloat(HUDMenu, TextPath + "._y", y)
    UI.SetFloat(HUDMenu, TextPath + "._width", width)
    UI.SetFloat(HUDMenu, TextPath + "._height", height)
    UI.SetFloat(HUDMenu, TextPath + "._alpha", GetValue(PanelOpacity, 88.0))
EndFunction

Bool Function IsOverlayBlocked()
    Return UI.IsMenuOpen("InventoryMenu") || UI.IsMenuOpen("MagicMenu") || UI.IsMenuOpen("Journal Menu") || UI.IsMenuOpen("MapMenu") || UI.IsMenuOpen("ContainerMenu") || UI.IsMenuOpen("BarterMenu") || UI.IsMenuOpen("GiftMenu") || UI.IsMenuOpen("Dialogue Menu") || UI.IsMenuOpen("Sleep/Wait Menu") || UI.IsMenuOpen("Book Menu") || UI.IsMenuOpen("FavoritesMenu") || UI.IsMenuOpen("Crafting Menu") || UI.IsMenuOpen("Training Menu") || UI.IsMenuOpen("Lockpicking Menu") || UI.IsMenuOpen("StatsMenu") || UI.IsMenuOpen("LevelUp Menu") || UI.IsMenuOpen("MessageBoxMenu") || UI.IsMenuOpen("Console")
EndFunction

Function LoadSettings()
    EnabledSetting = Game.GetFormFromFile(0x801, "QuestTrackerHUDSE.esp") as GlobalVariable
    HorizontalPosition = Game.GetFormFromFile(0x802, "QuestTrackerHUDSE.esp") as GlobalVariable
    VerticalPosition = Game.GetFormFromFile(0x803, "QuestTrackerHUDSE.esp") as GlobalVariable
    PanelWidth = Game.GetFormFromFile(0x804, "QuestTrackerHUDSE.esp") as GlobalVariable
    PanelOpacity = Game.GetFormFromFile(0x805, "QuestTrackerHUDSE.esp") as GlobalVariable
    MaximumQuests = Game.GetFormFromFile(0x806, "QuestTrackerHUDSE.esp") as GlobalVariable
EndFunction

Bool Function IsEnabled()
    Return EnabledSetting == None || EnabledSetting.GetValue() >= 0.5
EndFunction

Float Function GetValue(GlobalVariable setting, Float fallback)
    If setting == None
        Return fallback
    EndIf
    Return setting.GetValue()
EndFunction
