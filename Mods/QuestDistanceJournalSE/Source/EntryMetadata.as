      // This branch only affects entries explicitly annotated by QuestsPage.
      if(aEntryObject.qdjLabel == undefined || aEntryObject.completed || aEntryClip.textField == undefined)
      {
         if(aEntryClip.qdjMetadata != undefined) aEntryClip.qdjMetadata.removeTextField();
      }
      if(aEntryObject.qdjLabel != undefined && !aEntryObject.completed && aEntryClip.textField != undefined)
      {
         var title = aEntryClip.textField;
         if(aEntryClip.qdjMetadata == undefined)
            aEntryClip.createTextField("qdjMetadata",700,title._x,title._y + title._height,title._width,20);
         var field = aEntryClip.qdjMetadata;
         field._y = title._y + title._height;
         field._width = title._width;
         field._visible = true;
         field.selectable = false;
         field.textAutoSize = "shrink";
         var format = title.getTextFormat();
         format.size = 13;
         format.color = 0xD8CDA5;
         field.setNewTextFormat(format);
         field.text = aEntryObject.qdjLabel;
         field.setTextFormat(format);
      }
