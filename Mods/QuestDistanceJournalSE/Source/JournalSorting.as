   function QDJCompare(a, b)
   {
      if(Boolean(a.completed) != Boolean(b.completed)) return a.completed ? 1 : -1;
      if(a.completed && b.completed) return a.timeIndex - b.timeIndex;
      if((a.formID == 0) != (b.formID == 0)) return a.formID == 0 ? 1 : -1;
      if(this.qdjTrackedFirst && Boolean(a.active) != Boolean(b.active)) return a.active ? -1 : 1;
      var mode = this.qdjSortMode;
      if(mode == 0)
      {
         var cityA = a.qdjCity == undefined ? "" : a.qdjCity.toLowerCase();
         var cityB = b.qdjCity == undefined ? "" : b.qdjCity.toLowerCase();
         if((cityA == "") != (cityB == "")) return cityA == "" ? 1 : -1;
         if(cityA != cityB) return cityA < cityB ? -1 : 1;
      }
      if(mode == 0 || mode == 1)
      {
         var distanceA = a.qdjDistance == undefined || a.qdjDistance < 0 ? 1.7976931348623157e+308 : a.qdjDistance;
         var distanceB = b.qdjDistance == undefined || b.qdjDistance < 0 ? 1.7976931348623157e+308 : b.qdjDistance;
         if(distanceA != distanceB) return distanceA < distanceB ? -1 : 1;
      }
      if(mode != 3)
      {
         var titleA = a.text == undefined ? "" : a.text.toLowerCase();
         var titleB = b.text == undefined ? "" : b.text.toLowerCase();
         if(titleA != titleB) return titleA < titleB ? -1 : 1;
      }
      var originalA = a.timeIndex == undefined ? 0 : a.timeIndex;
      var originalB = b.timeIndex == undefined ? 0 : b.timeIndex;
      return originalA - originalB;
   }
   function QDJApplySort()
   {
      this.qdjSortPending = false;
      this.qdjLastSort = getTimer();
      if(this.TitleList.entryList.length == 0) return;
      var selected = this.TitleList.selectedEntry;
      if(selected == undefined) selected = this.TitleList.centeredEntry;
      var selectedObjective = this.ObjectiveList.selectedEntry;
      var page = this;
      this.TitleList.entryList.sort(function(a,b) { return page.QDJCompare(a,b); });
      var selectedIndex = 0;
      for(var i = 0; i < this.TitleList.entryList.length; i++)
         if(this.TitleList.entryList[i] == selected) selectedIndex = i;
      this.TitleList.RestoreScrollPosition(selectedIndex,true);
      this.TitleList.InvalidateData();
      this.onQuestHighlight();
      if(this.IsViewingMiscObjectives())
      {
         this.ObjectiveList.entryList.sort(function(a,b) { return page.QDJCompare(a,b); });
         this.ObjectiveList.InvalidateData();
         for(var j = 0; j < this.ObjectiveList.entryList.length; j++)
            if(this.ObjectiveList.entryList[j] == selectedObjective) this.ObjectiveList.selectedIndex = j;
      }
      this.QDJUpdateSortControl();
   }
   function QDJSortName()
   {
      var names = ["Miejscowość","Odległość","Nazwa","Kolejność gry"];
      return names[this.qdjSortMode == undefined ? 0 : this.qdjSortMode];
   }
   function QDJCycleSort()
   {
      this.qdjSortMode = (this.qdjSortMode + 1) % 4;
      _global.skse.SendModEvent("QDJ_SortChanged","",this.qdjSortMode,0);
      this.QDJApplySort();
   }
   function QDJUpdateSortControl()
   {
      if(this.qdjSortControl == undefined)
      {
         var control = this.createEmptyMovieClip("qdjSortControl",1800);
         control._x = this.TitleList_mc._x;
         control._y = Math.max(4,this.TitleList_mc._y - 30);
         control.beginFill(0x000000,25);
         control.moveTo(0,0);
         control.lineTo(340,0);
         control.lineTo(340,26);
         control.lineTo(0,26);
         control.lineTo(0,0);
         control.endFill();
         control.createTextField("label",1,4,2,332,24);
         control.label.selectable = false;
         control.label.textAutoSize = "shrink";
         var format = new TextFormat("$EverywhereFont",15,0xFFFFFF);
         control.label.setNewTextFormat(format);
         control.onRelease = function() { this._parent.QDJCycleSort(); };
      }
      this.qdjSortControl.label.text = "Sortowanie: " + this.QDJSortName() + (this.iPlatform == 0 ? "  [S]" : "  · Zmień w MCM");
   }
