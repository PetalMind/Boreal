   function QDJEntryLists()
   {
      var lists = [this.TitleList.entryList];
      if(this.IsViewingMiscObjectives()) lists.push(this.ObjectiveList.entryList);
      return lists;
   }
   function QDJStart()
   {
      _root.QDJPage = this;
      _root.QDJBridgeVersion = 130;
      _root.QDJConnected = false;
      if(this.qdjSortMode == undefined) this.qdjSortMode = 0;
      if(this.qdjTrackedFirst == undefined) this.qdjTrackedFirst = true;
      if(this.qdjShowDetails == undefined) this.qdjShowDetails = true;
      if(this.qdjTimer != undefined) clearInterval(this.qdjTimer);
      this.qdjTimer = setInterval(this,"QDJPulse",250);
      this.qdjLastSignal = -1000;
      this.qdjLastSort = -1000;
      this.qdjStartedAt = getTimer();
      this.qdjConnectionMessage = false;
      this.QDJPulse();
   }
   function QDJPulse()
   {
      this.QDJQueueEntries();
      this.QDJUpdateSortControl();
      if(!_root.QDJConnected && getTimer() - this.qdjLastSignal > 800)
      {
         this.qdjLastSignal = getTimer();
         _global.skse.SendModEvent("QDJ_Ready","",130,0);
      }
      if(!_root.QDJConnected && !this.qdjConnectionMessage && getTimer() - this.qdjStartedAt > 6000)
      {
         var lists = this.QDJEntryLists();
         for(var l = 0; l < lists.length; l++)
            for(var i = 0; lists[l] != undefined && i < lists[l].length; i++)
               if(lists[l][i].qdjLabel != undefined)
                  lists[l][i].qdjLabel = "Dane niedostępne — odśwież w MCM";
         this.TitleList.UpdateList();
         this.ObjectiveList.UpdateList();
         this.qdjConnectionMessage = true;
      }
      if(this.qdjSortPending && getTimer() - this.qdjLastSort > 600)
         this.QDJApplySort();
   }
   function QDJQueueEntries()
   {
      var queue = new Array();
      var seen = new Object();
      var lists = this.QDJEntryLists();
      var annotated = false;
      for(var l = 0; l < lists.length; l++)
      {
         if(lists[l] == undefined) continue;
         for(var i = 0; i < lists[l].length; i++)
         {
            var entry = lists[l][i];
            if(entry.formID == undefined || entry.formID == 0 || entry.completed || entry.divider) continue;
            var instance = entry.instance == undefined ? 0 : entry.instance;
            var key = String(entry.formID | 0) + ":" + String(instance);
            if(!seen[key])
            {
               seen[key] = true;
               queue.push({formID:entry.formID | 0,instance:instance,title:entry.text});
            }
            entry.qdjShowDetails = this.qdjShowDetails;
            if(entry.qdjLabel == undefined)
            {
               entry.qdjLabel = "Ustalanie lokalizacji i odległości...";
               entry.qdjDistance = -1;
               entry.qdjCity = "";
               annotated = true;
            }
         }
      }
      queue.sort(function(a,b)
      {
         if(a.formID != b.formID) return a.formID < b.formID ? -1 : 1;
         return a.instance - b.instance;
      });
      var signature = "";
      var requests = new Object();
      for(var q = 0; q < queue.length; q++)
      {
         signature += queue[q].formID + ":" + queue[q].instance + ";";
         requests["q" + q] = queue[q];
      }
      if(signature != this.qdjRequestSignature)
      {
         _root.QDJRequests = requests;
         _root.QDJCount = queue.length;
         _root.QDJRequestRevision = (_root.QDJRequestRevision == undefined ? 0 : _root.QDJRequestRevision) + 1;
         this.qdjRequestSignature = signature;
         this.qdjSortPending = true;
      }
      var selected = this.IsViewingMiscObjectives() ? this.ObjectiveList.selectedEntry : this.TitleList.selectedEntry;
      if(selected == undefined && !this.IsViewingMiscObjectives()) selected = this.TitleList.centeredEntry;
      _root.QDJSelectedFormID = selected.formID == undefined ? 0 : (selected.formID | 0);
      _root.QDJSelectedInstance = selected.instance == undefined ? 0 : selected.instance;
      if(annotated)
      {
         this.TitleList.UpdateList();
         this.ObjectiveList.UpdateList();
      }
   }
   function QDJSetResult(formID, instanceID, label, city, distance)
   {
      var changed = false;
      var lists = this.QDJEntryLists();
      for(var l = 0; l < lists.length; l++)
      {
         if(lists[l] == undefined) continue;
         for(var i = 0; i < lists[l].length; i++)
         {
            var entry = lists[l][i];
            if((entry.formID | 0) == Number(formID) && (entry.instance == undefined ? 0 : entry.instance) == Number(instanceID))
            {
               if(entry.qdjLabel != label || entry.qdjCity != city || entry.qdjDistance != Number(distance))
               {
                  entry.qdjLabel = label;
                  entry.qdjCity = city;
                  entry.qdjDistance = Number(distance);
                  entry.qdjShowDetails = this.qdjShowDetails;
                  changed = true;
               }
            }
         }
      }
      if(changed)
      {
         this.qdjSortPending = true;
         this.TitleList.UpdateList();
         this.ObjectiveList.UpdateList();
         if(this.TitleList.selectedEntry != undefined) this.SetDescriptionText();
      }
   }
   function QDJConfigure(sortMode, trackedFirst, showDetails)
   {
      this.qdjSortMode = Math.max(0,Math.min(3,Number(sortMode)));
      this.qdjTrackedFirst = String(trackedFirst).toLowerCase() == "true" || trackedFirst == "1";
      this.qdjShowDetails = String(showDetails).toLowerCase() == "true" || showDetails == "1";
      var lists = this.QDJEntryLists();
      for(var l = 0; l < lists.length; l++)
         for(var i = 0; lists[l] != undefined && i < lists[l].length; i++)
            lists[l][i].qdjShowDetails = this.qdjShowDetails;
      this.qdjSortPending = true;
      this.QDJQueueEntries();
      this.QDJApplySort();
   }
   function QDJDescription()
   {
      var entry = this.TitleList.selectedEntry;
      if(entry == undefined) return " ";
      var description = entry.description == undefined ? "" : entry.description;
      if(this.qdjShowDetails && !entry.completed && entry.formID != undefined && entry.formID != 0)
      {
         var label = entry.qdjLabel == undefined ? "Ustalanie lokalizacji i odległości..." : entry.qdjLabel;
         description += "\n\n" + label + "\n" + (entry.active ? "Śledzone zadanie" : "Zadanie nieśledzone");
         description += " · Najbliższy dostępny aktywny cel";
      }
      return description == "" ? " " : description;
   }
