//+------------------------------------------------------------------+
//| PositionManagerV22.mqh                                           |
//| Production position-management authority for ForexScalperApp.   |
//+------------------------------------------------------------------+
#ifndef POSITION_MANAGER_V22_MQH
#define POSITION_MANAGER_V22_MQH

#include <Trade/Trade.mqh>

#define PM_MAGIC_NUMBER 888888
#define PM_PREFIX "FSV22_PM_"
#define PM_STAGE_TP1 1
#define PM_STAGE_TP2 2
#define PM_STAGE_TP3 3

class CPositionManagerV22
{
private:
   CTrade m_trade;

   double ReadSetting(string name, double fallback)
   {
      string key = PM_PREFIX + name;
      if(!GlobalVariableCheck(key)) return fallback;
      return GlobalVariableGet(key);
   }

   bool ReadBool(string name, bool fallback)
   {
      return ReadSetting(name, fallback ? 1.0 : 0.0) > 0.5;
   }

   double Clamp(double value, double low, double high)
   {
      return MathMax(low, MathMin(high, value));
   }

   double PipSize(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(point <= 0.0) return 0.0;
      return (digits == 3 || digits == 5) ? point * 10.0 : point;
   }

   int VolumeDigits(double step)
   {
      if(step <= 0.0) return 2;
      int digits = 0;
      double value = step;
      while(digits < 8 && MathAbs(value - MathRound(value)) > 0.000000001)
      {
         value *= 10.0;
         digits++;
      }
      return digits;
   }

   double NormalizeCloseVolume(string symbol, double requested, double current)
   {
      double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(requested <= 0.0 || current <= 0.0) return 0.0;
      requested = MathMin(requested, current);
      if(maxVolume > 0.0) requested = MathMin(requested, maxVolume);
      if(step > 0.0) requested = MathFloor((requested + step * 0.000001) / step) * step;
      requested = NormalizeDouble(requested, VolumeDigits(step));
      if(requested < minVolume) return 0.0;
      return requested;
   }

   string StateKey(ulong ticket, string suffix)
   {
      return PM_PREFIX + IntegerToString((int)ticket) + "_" + suffix;
   }

   double OriginalVolume(ulong ticket, double current)
   {
      string key = StateKey(ticket, "ORIGINAL");
      if(GlobalVariableCheck(key))
      {
         double saved = GlobalVariableGet(key);
         if(saved > 0.0) return saved;
      }
      GlobalVariableSet(key, current);
      GlobalVariablesFlush();
      return current;
   }

   int TPStage(ulong ticket)
   {
      string key = StateKey(ticket, "TP_STAGE");
      if(!GlobalVariableCheck(key)) return 0;
      return (int)GlobalVariableGet(key);
   }

   void SetTPStage(ulong ticket, int stage)
   {
      GlobalVariableSet(StateKey(ticket, "TP_STAGE"), stage);
      GlobalVariablesFlush();
   }

   bool BreakevenDone(ulong ticket)
   {
      return GlobalVariableCheck(StateKey(ticket, "BE_DONE")) && GlobalVariableGet(StateKey(ticket, "BE_DONE")) > 0.5;
   }

   void SetBreakevenDone(ulong ticket)
   {
      GlobalVariableSet(StateKey(ticket, "BE_DONE"), 1.0);
      GlobalVariablesFlush();
   }

   bool SuccessfulRetcode(uint retcode)
   {
      return retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL || retcode == TRADE_RETCODE_PLACED;
   }

   bool IsStopDistanceValid(string symbol, ENUM_POSITION_TYPE type, double sl)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(point <= 0.0) return false;

      long stopsLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double minimumDistance = MathMax((double)stopsLevel, (double)freezeLevel) * point;

      if(type == POSITION_TYPE_BUY) return sl < bid && (minimumDistance <= 0.0 || (bid - sl) >= minimumDistance);
      return sl > ask && (minimumDistance <= 0.0 || (sl - ask) >= minimumDistance);
   }

   bool ImproveOnly(ENUM_POSITION_TYPE type, double oldSL, double newSL)
   {
      if(oldSL <= 0.0) return true;
      if(type == POSITION_TYPE_BUY) return newSL > oldSL;
      return newSL < oldSL;
   }

   bool ModifySL(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double newSL, string reason)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double oldSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      newSL = NormalizeDouble(newSL, digits);

      if(!ImproveOnly(type, oldSL, newSL)) return false;
      if(!IsStopDistanceValid(symbol, type, newSL))
      {
         PrintFormat("[EA V22 PM] SL SKIP | ticket=%I64d | reason=%s | requested=%s | broker stop/freeze distance not satisfied", ticket, reason, DoubleToString(newSL, digits));
         return false;
      }

      m_trade.SetExpertMagicNumber(PM_MAGIC_NUMBER);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetAsyncMode(false);

      bool callOK = m_trade.PositionModify(ticket, newSL, currentTP);
      uint retcode = m_trade.ResultRetcode();
      bool serverOK = SuccessfulRetcode(retcode);
      PrintFormat("[EA V22 PM] SL MODIFY | ticket=%I64d | reason=%s | old=%s | new=%s | retcode=%u | %s",
                  ticket, reason, DoubleToString(oldSL, digits), DoubleToString(newSL, digits), retcode,
                  m_trade.ResultRetcodeDescription());
      return callOK && serverOK;
   }

   bool CloseVolume(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double volume, string reason)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      double closeVolume = NormalizeCloseVolume(symbol, volume, currentVolume);
      if(closeVolume <= 0.0) return false;

      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      int digits = VolumeDigits(step);
      m_trade.SetExpertMagicNumber(PM_MAGIC_NUMBER);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetAsyncMode(false);

      bool callOK = false;
      ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      double remainder = currentVolume - closeVolume;
      if(remainder > 0.0 && minVolume > 0.0 && remainder < minVolume) closeVolume = currentVolume;

      if(closeVolume >= currentVolume - (step > 0.0 ? step * 0.25 : 0.00000001))
         callOK = m_trade.PositionClose(ticket);
      else if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         callOK = m_trade.PositionClosePartial(ticket, closeVolume);
      else if(type == POSITION_TYPE_BUY)
         callOK = m_trade.Sell(closeVolume, symbol, 0.0, 0.0, 0.0, "GOD_MODE_V22_TP");
      else
         callOK = m_trade.Buy(closeVolume, symbol, 0.0, 0.0, 0.0, "GOD_MODE_V22_TP");

      uint retcode = m_trade.ResultRetcode();
      bool serverOK = SuccessfulRetcode(retcode);
      PrintFormat("[EA V22 PM] CLOSE | ticket=%I64d | reason=%s | requested=%s | retcode=%u | %s",
                  ticket, reason, DoubleToString(closeVolume, digits), retcode, m_trade.ResultRetcodeDescription());
      return callOK && serverOK;
   }

   void ManagePosition(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return;
      if((long)PositionGetInteger(POSITION_MAGIC) != PM_MAGIC_NUMBER) return;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double current = PositionGetDouble(POSITION_PRICE_CURRENT);
      double existingSL = PositionGetDouble(POSITION_SL);
      double pip = PipSize(symbol);
      if(currentVolume <= 0.0 || entry <= 0.0 || current <= 0.0 || pip <= 0.0) return;

      double profitPips = type == POSITION_TYPE_BUY ? (current - entry) / pip : (entry - current) / pip;
      if(profitPips <= 0.0) return;

      double original = OriginalVolume(ticket, currentVolume);
      int stage = TPStage(ticket);

      double tp1Pips = MathMax(0.0, ReadSetting("TP1_PIPS", 10.0));
      double tp2Pips = MathMax(tp1Pips, ReadSetting("TP2_PIPS", 15.0));
      double tp3Pips = MathMax(tp2Pips, ReadSetting("TP3_PIPS", 20.0));
      double tp1Pct = Clamp(ReadSetting("TP1_PCT", 0.50), 0.0, 1.0);
      double tp2Pct = Clamp(ReadSetting("TP2_PCT", 0.30), 0.0, 1.0);
      double tp3Pct = Clamp(ReadSetting("TP3_PCT", 0.20), 0.0, 1.0);

      if(stage < PM_STAGE_TP1 && tp1Pips > 0.0 && profitPips >= tp1Pips)
      {
         if(CloseVolume(ticket, symbol, type, original * tp1Pct, "TP1"))
         {
            SetTPStage(ticket, PM_STAGE_TP1);
            stage = PM_STAGE_TP1;
         }
      }

      if(stage >= PM_STAGE_TP1 && stage < PM_STAGE_TP2 && tp2Pips > 0.0 && profitPips >= tp2Pips && PositionSelectByTicket(ticket))
      {
         currentVolume = PositionGetDouble(POSITION_VOLUME);
         if(CloseVolume(ticket, symbol, type, MathMin(currentVolume, original * tp2Pct), "TP2"))
         {
            SetTPStage(ticket, PM_STAGE_TP2);
            stage = PM_STAGE_TP2;
         }
      }

      if(stage >= PM_STAGE_TP2 && stage < PM_STAGE_TP3 && tp3Pips > 0.0 && profitPips >= tp3Pips && PositionSelectByTicket(ticket))
      {
         currentVolume = PositionGetDouble(POSITION_VOLUME);
         if(CloseVolume(ticket, symbol, type, MathMin(currentVolume, original * tp3Pct), "TP3"))
         {
            SetTPStage(ticket, PM_STAGE_TP3);
            stage = PM_STAGE_TP3;
         }
      }

      bool breakevenEnabled = ReadBool("BE_ENABLED", true);
      double beTrigger = MathMax(0.0, ReadSetting("BE_TRIGGER_PIPS", tp1Pips));
      double beOffset = ReadSetting("BE_OFFSET_PIPS", 0.0);
      if(breakevenEnabled && beTrigger > 0.0 && profitPips >= beTrigger && !BreakevenDone(ticket))
      {
         double beSL = type == POSITION_TYPE_BUY ? entry + beOffset * pip : entry - beOffset * pip;
         if(ModifySL(ticket, symbol, type, beSL, "BREAKEVEN")) SetBreakevenDone(ticket);
      }

      bool trailingEnabled = ReadBool("TRAIL_ENABLED", true);
      double activation = MathMax(0.0, ReadSetting("TRAIL_ACTIVATION_PIPS", 5.0));
      double distance = MathMax(0.0, ReadSetting("TRAIL_DISTANCE_PIPS", 6.0));
      double step = MathMax(0.0, ReadSetting("TRAIL_STEP_PIPS", 1.0));

      if(trailingEnabled && activation > 0.0 && distance > 0.0 && profitPips >= activation)
      {
         double desired = type == POSITION_TYPE_BUY ? current - distance * pip : current + distance * pip;
         if(existingSL <= 0.0 || MathAbs(desired - existingSL) >= step * pip)
            ModifySL(ticket, symbol, type, desired, "TRAILING");
      }
   }

public:
   CPositionManagerV22()
   {
      m_trade.SetExpertMagicNumber(PM_MAGIC_NUMBER);
      m_trade.SetAsyncMode(false);
   }

   void ManageAll()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         ManagePosition(ticket);
      }
   }

   void ClearClosedState() {}
};

#endif
