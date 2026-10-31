   function CreateNordicHorsePanel()
   {
      if(this.NordicHorsePanel != undefined) return;
      this.NordicHorsePanel = this.createEmptyMovieClip("NordicHorseStatusPanel",10001);
      var panel = this.NordicHorsePanel;
      panel.createTextField("HorseNameField",1,0,0,264,24);
      panel.createTextField("HorseHealthLabel",2,0,28,216,16);
      panel.createTextField("HorseHealthValue",3,220,28,44,16);
      panel.createTextField("HorseStaminaLabel",4,0,60,216,16);
      panel.createTextField("HorseStaminaValue",5,220,60,44,16);
      this.NordicHorseNameField = panel.HorseNameField;
      this.NordicHorseHealthLabel = panel.HorseHealthLabel;
      this.NordicHorseHealthValue = panel.HorseHealthValue;
      this.NordicHorseStaminaLabel = panel.HorseStaminaLabel;
      this.NordicHorseStaminaValue = panel.HorseStaminaValue;
      var titleFormat = new TextFormat("$EverywhereFont",18,0xFFFFFF,false,false,false,false,"","center",0,0,0,0);
      var labelFormat = new TextFormat("$EverywhereFont",11,0xFFFFFF,false,false,false,false,"","left",0,0,0,0);
      var valueFormat = new TextFormat("$EverywhereFont",11,0xFFFFFF,false,false,false,false,"","right",0,0,0,0);
      this.NordicHorseNameField.setNewTextFormat(titleFormat);
      this.NordicHorseNameField.setTextFormat(titleFormat);
      this.NordicHorseNameField.textAutoSize = "shrink";
      var labels = [this.NordicHorseHealthLabel,this.NordicHorseStaminaLabel];
      var values = [this.NordicHorseHealthValue,this.NordicHorseStaminaValue];
      var fields = [this.NordicHorseNameField];
      for(var i = 0; i < labels.length; i++)
      {
         labels[i].setNewTextFormat(labelFormat);
         labels[i].setTextFormat(labelFormat);
         values[i].setNewTextFormat(valueFormat);
         values[i].setTextFormat(valueFormat);
         fields.push(labels[i],values[i]);
      }
      for(var field = 0; field < fields.length; field++)
      {
         fields[field].selectable = false;
         fields[field].filters = this.EnemyHealth_mc.BracketsInstance.RolloverNameInstance.filters;
      }
      this.NordicHorseHealthLabel.text = "ZDROWIE";
      this.NordicHorseStaminaLabel.text = "WYTRZYMAŁOŚĆ";
      // Independent copies retain Skyrim's authored ornaments and fill colors.
      // Keep them beside the panel so player-meter fading cannot hide them.
      this.NordicHorseHealthBar = this.HealthMeterAnim.duplicateMovieClip("NordicHorseHealth",10002);
      this.NordicHorseStaminaBar = this.StaminaMeterAnim.duplicateMovieClip("NordicHorseStamina",10003);
      this.NordicHorseHealthBar.gotoAndStop(this.METER_PAUSE_FRAME);
      this.NordicHorseStaminaBar.gotoAndStop(this.METER_PAUSE_FRAME);
      this.NordicHorseHealthBar.HealthPenaltyMeter_mc._visible = false;
      this.NordicHorseStaminaBar.StaminaPenaltyMeter_mc._visible = false;
      this.NordicHorseStaminaBar.StaminaFlashInstance._visible = false;
      this.NordicHorseHealthBar.NordicMeterArt = this.NordicHorseHealthBar.HealthMeter_mc;
      this.NordicHorseStaminaBar.NordicMeterArt = this.NordicHorseStaminaBar.StaminaMeter_mc;
      this.NordicHorseHealthMeter = new Components.Meter(this.NordicHorseHealthBar.HealthMeter_mc.HealthLeft);
      this.NordicHorseStaminaMeter = new Components.Meter(this.NordicHorseStaminaBar.StaminaMeter_mc);
      this.NordicHorseHealthMeter.SetPercent(100);
      this.NordicHorseStaminaMeter.SetPercent(100);
      var bars = [this.NordicHorseHealthBar,this.NordicHorseStaminaBar];
      for(var bar = 0; bar < bars.length; bar++)
      {
         var bounds = bars[bar].NordicMeterArt.getBounds(this);
         var scale = 264 / Math.max(1,bounds.xMax - bounds.xMin);
         bars[bar]._xscale *= scale;
         bars[bar]._yscale *= scale;
         bars[bar]._alpha = 100;
         bars[bar]._visible = false;
      }
      panel._visible = false;
      this.PositionNordicHorsePanel();
   }
   function PositionNordicHorsePanel()
   {
      if(this.NordicHorsePanel == undefined) return;
      var anchor = {x:Stage.visibleRect.x + Stage.visibleRect.width / 2,y:Stage.visibleRect.y + Stage.visibleRect.height - Stage.safeRect.y};
      this.globalToLocal(anchor);
      this.NordicHorsePanel._x = anchor.x - 132;
      this.NordicHorsePanel._y = anchor.y - 96 - 48;
      this.PositionNordicHorseMeter(this.NordicHorseHealthBar,44);
      this.PositionNordicHorseMeter(this.NordicHorseStaminaBar,76);
   }
   function PositionNordicHorseMeter(bar,top)
   {
      var bounds = bar.NordicMeterArt.getBounds(this);
      bar._x += this.NordicHorsePanel._x - bounds.xMin;
      bar._y += this.NordicHorsePanel._y + top - bounds.yMin;
   }
   function SetNordicHorseName(name)
   {
      if(this.NordicHorsePanel == undefined) this.CreateNordicHorsePanel();
      this.NordicHorseNameField.text = name;
   }
   function SetNordicHorseHealth(percent)
   {
      if(this.NordicHorsePanel == undefined) this.CreateNordicHorsePanel();
      percent = Math.max(0,Math.min(1,percent));
      this.NordicHorseHealthValue.text = Math.round(percent * 100) + "%";
      this.NordicHorseHealthMeter.SetPercent(percent * 100);
   }
   function SetNordicHorseStamina(percent)
   {
      if(this.NordicHorsePanel == undefined) this.CreateNordicHorsePanel();
      percent = Math.max(0,Math.min(1,percent));
      this.NordicHorseStaminaValue.text = Math.round(percent * 100) + "%";
      this.NordicHorseStaminaMeter.SetPercent(percent * 100);
   }
   function SetNordicHorseVisible(visible)
   {
      if(this.NordicHorsePanel == undefined) this.CreateNordicHorsePanel();
      if(visible) this.PositionNordicHorsePanel();
      this.NordicHorsePanel._visible = visible;
      this.NordicHorseHealthBar._visible = visible;
      this.NordicHorseStaminaBar._visible = visible;
   }
