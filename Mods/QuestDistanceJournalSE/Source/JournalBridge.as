   function QDJQueueEntries()
   {
      var queue = new Array();
      var requests = new Object();
      var seen = new Object();
      var lists = [this.TitleList.entryList,this.ObjectiveList.entryList];
      for(var l = 0; l < lists.length; l++)
      {
         for(var i = 0; i < lists[l].length; i++)
         {
            var entry = lists[l][i];
            if(entry.formID == undefined || entry.formID == 0 || entry.completed || entry.divider) continue;
            var key = String(entry.formID) + ":" + String(entry.instance);
            if(seen[key]) continue;
            seen[key] = true;
            requests["q" + queue.length] = {formID:entry.formID,instance:entry.instance == undefined ? 0 : entry.instance};
            queue.push(entry.formID);
            if(entry.qdjLabel == undefined) entry.qdjLabel = "";
         }
      }
      _root.QDJRequests = requests;
      _root.QDJCount = queue.length;
      var selected = this.IsViewingMiscObjectives() ? this.ObjectiveList.selectedEntry : this.TitleList.selectedEntry;
      _root.QDJSelectedFormID = selected.formID == undefined ? 0 : selected.formID;
      _root.QDJSelectedInstance = selected.instance == undefined ? 0 : selected.instance;
   }
   function QDJSetResult(formID, instanceID, label)
   {
      var changed = false;
      var lists = [this.TitleList.entryList,this.ObjectiveList.entryList];
      for(var l = 0; l < lists.length; l++)
      {
         for(var i = 0; i < lists[l].length; i++)
         {
            var entry = lists[l][i];
            if((entry.formID | 0) == Number(formID) && (entry.instance == undefined ? 0 : entry.instance) == Number(instanceID))
            {
               if(entry.qdjLabel != label)
               {
                  entry.qdjLabel = label;
                  changed = true;
               }
            }
         }
      }
      if(changed)
      {
         this.TitleList.UpdateList();
         this.ObjectiveList.UpdateList();
      }
   }
