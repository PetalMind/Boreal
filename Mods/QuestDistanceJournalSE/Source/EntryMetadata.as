      // Reuse the native text field and font; separate dynamic fields can be
      // clipped by the journal's row movie clips and font mapping.
      if(aEntryClip.textField != undefined && (aEntryObject.qdjLabel != undefined || aEntryClip.textField.qdjOriginalHeight != undefined))
      {
         var title = aEntryClip.textField;
         if(title.qdjOriginalHeight == undefined)
         {
            title.qdjOriginalHeight = title._height;
            title.qdjOriginalMultiline = title.multiline;
            title.qdjOriginalWordWrap = title.wordWrap;
            title.qdjOriginalFormat = title.getTextFormat();
         }
         title._height = title.qdjOriginalHeight;
         title.multiline = title.qdjOriginalMultiline;
         title.wordWrap = title.qdjOriginalWordWrap;
         title.setTextFormat(title.qdjOriginalFormat);
         if(aEntryObject.qdjLabel != undefined && aEntryObject.qdjShowDetails != false && !aEntryObject.completed && !aEntryObject.divider)
         {
            var primary = aEntryObject.text == undefined ? "" : aEntryObject.text;
            var baseFormat = title.qdjOriginalFormat;
            title.multiline = true;
            title.wordWrap = false;
            title._height = title.qdjOriginalHeight + 21;
            title.SetText(primary + "\n" + aEntryObject.qdjLabel);
            title.setTextFormat(0,primary.length,baseFormat);
            var detailFormat = new TextFormat(baseFormat.font,13,0xE6DDC8);
            detailFormat.align = baseFormat.align;
            title.setTextFormat(primary.length + 1,title.text.length,detailFormat);
         }
      }
