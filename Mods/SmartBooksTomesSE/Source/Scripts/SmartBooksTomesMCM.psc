Scriptname SmartBooksTomesMCM extends SKI_ConfigBase

Int Property PageSize = 32 AutoReadOnly
Int Property BookFormType = 27 AutoReadOnly

FormList BookInventory
String[] filterLabels
String[] pageLabels
Int filterIndex
Int pageIndex
Int filterOption
Int pageOption

Event OnConfigInit()
    ModName = "Smart Books & Tomes SE"
    Pages = new String[1]
    Pages[0] = "Księgi"
    filterLabels = new String[7]
    filterLabels[0] = "Wszystkie"
    filterLabels[1] = "Nieprzeczytane"
    filterLabels[2] = "Przeczytane"
    filterLabels[3] = "Książki umiejętności"
    filterLabels[4] = "Tomy zaklęć"
    filterLabels[5] = "Nowe zaklęcia"
    filterLabels[6] = "Znane zaklęcia"
    filterIndex = 0
    pageIndex = 0
EndEvent

Event OnPageReset(String page)
    If page != "Księgi"
        Return
    EndIf

    RefreshInventory()
    SetCursorFillMode(TOP_TO_BOTTOM)
    filterOption = AddMenuOption("Filtr", filterLabels[filterIndex])

    Int resultCount = CountFilteredBooks()
    Int pageCount = (resultCount + PageSize - 1) / PageSize
    If pageCount < 1
        pageCount = 1
    EndIf
    If pageIndex >= pageCount
        pageIndex = pageCount - 1
    EndIf
    BuildPageLabels(pageCount)
    pageOption = AddMenuOption("Strona", pageLabels[pageIndex])
    AddTextOption("Pozycje", resultCount + "", OPTION_FLAG_DISABLED)
    AddHeaderOption("Książki i tomy")

    If resultCount == 0
        AddTextOption("Brak pozycji dla tego filtra", "", OPTION_FLAG_DISABLED)
        Return
    EndIf

    Actor player = Game.GetPlayer()
    Int matchingIndex = 0
    Int visibleCount = 0
    Int listIndex = 0
    Int firstIndex = pageIndex * PageSize
    While listIndex < BookInventory.GetSize() && visibleCount < PageSize
        Book item = BookInventory.GetAt(listIndex) as Book
        If item != None && MatchesFilter(item, player)
            If matchingIndex >= firstIndex
                AddTextOption(item.GetName(), GetStatus(item, player), OPTION_FLAG_DISABLED)
                visibleCount += 1
            EndIf
            matchingIndex += 1
        EndIf
        listIndex += 1
    EndWhile
EndEvent

Event OnOptionMenuOpen(Int option)
    If option == filterOption
        SetMenuDialogStartIndex(filterIndex)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(filterLabels)
    ElseIf option == pageOption
        SetMenuDialogStartIndex(pageIndex)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(pageLabels)
    EndIf
EndEvent

Event OnOptionMenuAccept(Int option, Int selectedIndex)
    If option == filterOption
        filterIndex = selectedIndex
        pageIndex = 0
        ForcePageReset()
    ElseIf option == pageOption
        pageIndex = selectedIndex
        ForcePageReset()
    EndIf
EndEvent

Function RefreshInventory()
    BookInventory = Game.GetFormFromFile(0x801, "SmartBooksTomesSE.esp") as FormList
    If BookInventory == None
        Return
    EndIf
    BookInventory.Revert()
    PO3_SKSEFunctions.AddItemsOfTypeToList(Game.GetPlayer(), BookInventory, BookFormType, False, False, False)
EndFunction

Int Function CountFilteredBooks()
    If BookInventory == None
        Return 0
    EndIf
    Actor player = Game.GetPlayer()
    Int count = 0
    Int index = 0
    While index < BookInventory.GetSize()
        Book item = BookInventory.GetAt(index) as Book
        If item != None && MatchesFilter(item, player)
            count += 1
        EndIf
        index += 1
    EndWhile
    Return count
EndFunction

Bool Function MatchesFilter(Book item, Actor player)
    Spell taughtSpell = item.GetSpell()
    Bool isTome = taughtSpell != None
    Bool isRead = item.IsRead()
    If filterIndex == 0
        Return True
    ElseIf filterIndex == 1
        Return !isTome && !isRead
    ElseIf filterIndex == 2
        Return !isTome && isRead
    ElseIf filterIndex == 3
        Return !isTome && item.GetSkill() >= 0
    ElseIf filterIndex == 4
        Return isTome
    ElseIf filterIndex == 5
        Return isTome && !player.HasSpell(taughtSpell)
    ElseIf filterIndex == 6
        Return isTome && player.HasSpell(taughtSpell)
    EndIf
    Return True
EndFunction

String Function GetStatus(Book item, Actor player)
    Spell taughtSpell = item.GetSpell()
    If taughtSpell != None
        If player.HasSpell(taughtSpell)
            Return "✓ Znane zaklęcie"
        EndIf
        Return "+ Nowe zaklęcie"
    EndIf

    If item.GetSkill() >= 0
        If item.IsRead()
            Return "✓ Książka umiejętności"
        EndIf
        Return "★ Nieprzeczytana umiejętności"
    EndIf

    If item.IsRead()
        Return "✓ Przeczytana"
    EndIf
    Return "○ Nieprzeczytana"
EndFunction

Function BuildPageLabels(Int pageCount)
    pageLabels = new String[pageCount]
    Int index = 0
    While index < pageCount
        pageLabels[index] = (index + 1) + ""
        index += 1
    EndWhile
EndFunction
