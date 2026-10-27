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
            if(entry.qdjLabel == undefined) entry.qdjLabel = "Ustalanie celu...";
         }
      }
      _root.QDJRequests = requests;
      _root.QDJCount = queue.length;
   }
   function QDJSetResult(formID, instanceID, label)
   {
      var lists = [this.TitleList.entryList,this.ObjectiveList.entryList];
      for(var l = 0; l < lists.length; l++)
      {
         for(var i = 0; i < lists[l].length; i++)
         {
            var entry = lists[l][i];
            if((entry.formID | 0) == Number(formID) && (entry.instance == undefined ? 0 : entry.instance) == Number(instanceID))
               entry.qdjLabel = label;
         }
      }
      this.TitleList.UpdateList();
      this.ObjectiveList.UpdateList();
   }
