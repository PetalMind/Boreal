   function SetNordicDotSize(value)
   {
      if(isNaN(value)) return;
      this.NordicDotSize = Math.max(50,Math.min(200,value));
   }
   function SetNordicDotOpacity(value)
   {
      if(isNaN(value)) return;
      this.NordicDotOpacity = Math.max(25,Math.min(100,value));
   }
   function SetNordicDotMotion(enabled)
   {
      this.NordicDotMotion = enabled == true;
   }
   function CreateNordicDot()
   {
      this.NordicDot = this.createEmptyMovieClip("NordicMinimalUIDot",10000);
      this.NordicDot._visible = false;
      this.NordicDotStyle = "";
   }
   function DrawNordicDot(state,alertState)
   {
      var dot = this.NordicDot;
      var color = alertState ? 0xEEA18C : 0xF0EBDD;
      dot.clear();
      dot.lineStyle(1,0x171917,100);
      dot.beginFill(color,100);
      dot.moveTo(2.25,0);
      for(var i = 1; i <= 24; i++)
         dot.lineTo(Math.cos(i * Math.PI / 12) * 2.25,Math.sin(i * Math.PI / 12) * 2.25);
      dot.endFill();
      // Shape conveys the state even without distinguishing the warning color.
      if(state == "Target")
      {
         dot.lineStyle(3,0x171917,100);
         this.DrawNordicTargetRing(dot);
         dot.lineStyle(1,color,100);
         this.DrawNordicTargetRing(dot);
      }
      else if(state == "Favor")
      {
         dot.lineStyle(3,0x171917,100);
         this.DrawNordicFavorDiamond(dot);
         dot.lineStyle(1,color,100);
         this.DrawNordicFavorDiamond(dot);
      }
      if(alertState)
      {
         dot.lineStyle(3,0x171917,100);
         dot.moveTo(-4,9);
         dot.lineTo(4,9);
         dot.lineStyle(1,color,100);
         dot.moveTo(-4,9);
         dot.lineTo(4,9);
      }
   }
   function DrawNordicTargetRing(dot)
   {
      dot.moveTo(6,0);
      for(var i = 1; i <= 32; i++)
         dot.lineTo(Math.cos(i * Math.PI / 16) * 6,Math.sin(i * Math.PI / 16) * 6);
   }
   function DrawNordicFavorDiamond(dot)
   {
      dot.moveTo(0,-7);
      dot.lineTo(7,0);
      dot.lineTo(0,7);
      dot.lineTo(-7,0);
      dot.lineTo(0,-7);
   }
   function UpdateNordicCrosshair()
   {
      if(this.NordicDot == undefined) this.CreateNordicDot();
      // Timeline frame numbers also change for pickup animations. The active
      // Crosshair timeline instance identifies Normal/Alert without guessing.
      var nativeCrosshair = this.Crosshair;
      var alertState = nativeCrosshair == this.CrosshairAlert;
      var state = nativeCrosshair.NordicState;
      if(state == undefined) state = "NoTarget";
      var style = state + (alertState ? "Alert" : "Normal");
      if(style != this.NordicDotStyle)
      {
         this.DrawNordicDot(state,alertState);
         this.NordicDotStyle = style;
      }
      var center = {x:0,y:0};
      nativeCrosshair.localToGlobal(center);
      this.globalToLocal(center);
      this.NordicDot._x = center.x;
      this.NordicDot._y = center.y;
      var size = this.NordicDotSize == undefined ? 100 : this.NordicDotSize;
      var pulse = this.NordicDotMotion == true ? 1 + Math.sin(getTimer() / 600) * 0.04 : 1;
      this.NordicDot._xscale = size * pulse;
      this.NordicDot._yscale = size * pulse;
      this.NordicDot._alpha = this.NordicDotOpacity == undefined ? 100 : this.NordicDotOpacity;
      // Preserve the native HUD mode, explicit suppression and game setting.
      // In StealthMode the unmodified native eye remains the aiming reference.
      this.NordicDot._visible = this.bCrosshairEnabled && nativeCrosshair._visible && this.CheckAgainstHudMode(nativeCrosshair);
      this.CrosshairInstance._alpha = 0;
      this.CrosshairAlert._alpha = 0;
   }
