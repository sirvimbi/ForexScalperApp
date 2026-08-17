//+------------------------------------------------------------------+
//| PositionManagerV22.mqh                                           |
//| Production MT5 position lifecycle authority.                    |
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
      if(requested <= 0.0 || current <= 0.0 || step <= 0.0) return 0.0;
      requested = MathMin(requested, current);
      if(maxVolume > 0.0) requested = MathMin(requested, maxVolume);
      requested = MathFloor((requested + step * 0.000001) / step) * step;
      requested = NormalizeDouble(requested, VolumeDigits(step));
      if(requested < minVolume) return 0.0;
      return requested;
   }

   string StateKey(ulong ticket, string suffix)
   {
      return PM_PREFIX + IntegerToString((long)ticket) + "_" + suffix;
   }

   double ClosedVolumeFromHistory(ulong ticket)
   {
      datetime from = TimeCurrent() - 90 * 24 * 60 * 60;
      datetime to = TimeCurrent() + 60;
      if(!HistorySelect(from, to)) return 0.0;

      double closed = 0.0;
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         if(positionId != ticket) continue;
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
            closed += HistoryDealGetDouble(deal, DEAL_VOLUME);
      }
      return closed;
   }

   double OriginalVolume(ulong ticket, double current, double tp1Pct, double tp2Pct, double tp3Pct)
   {
      string key = StateKey(ticket, "ORIGINAL");
      if(GlobalVariableCheck(key))
      {
         double saved = GlobalVariableGet(key);
         if(saved > 0.0) return saved;
      }

      double reconstructed = current + ClosedVolumeFromHistory(ticket);
      if(reconstructed < current) reconstructed = current;
      GlobalVariableSet(key, reconstructed);
      GlobalVariablesFlush();

      double closed = MathMax(0.0, reconstructed - current);
      double fraction = reconstructed > 0.0 ? closed / reconstructed : 0.0;
      int inferredStage = 0;
      double tolerance = 0.5 * MathMax(SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_VOLUME_STEP), 0.00000001) / reconstructed;
      if(tp1Pct > 0.0 && fraction + tolerance >= tp1Pct) inferredStage = PM_STAGE_TP1;
      if(tp2Pct > 0.0 && fraction + tolerance >= tp1Pct + tp2Pct) inferredStage = PM_STAGE_TP2;
      if(tp3Pct > 0.0 && fraction + tolerance >= tp1Pct + tp2Pct + tp3Pct - 0.000001) inferredStage = PM_STAGE_TP3;
      if(inferredStage > 0) SetTPStage(ticket, inferredStage);
      return reconstructed;
   }

   int TPStage(ulong ticket)
   {
      string key = StateKey(ticket, "TP_STAGE");
      return GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
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
      return retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL;
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
      return type == POSITION_TYPE_BUY ? newSL > oldSL : newSL < oldSL;
   }

   bool VerifySL(ulong ticket, double expected, int digits, double tolerance)
   {
      for(int attempt = 0; attempt < 6; attempt++)
      {
         if(PositionSelectByTicket(ticket))
         {
            double actual = PositionGetDouble(POSITION_SL);
            if(MathAbs(actual - expected) <= tolerance) return true;
         }
         Sleep(100);
      }
      return false;
   }

   bool ModifySL(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double newSL, string reason)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double oldSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      newSL = NormalizeDouble(newSL, digits);
      if(!ImproveOnly(type, oldSL, newSL)) return true;
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
      bool brokerAccepted = callOK && (SuccessfulRetcode(retcode) || retcode == TRADE_RETCODE_PLACED);
      bool verified = brokerAccepted && VerifySL(ticket, newSL, digits, MathMax(point * 2.0, 0.00000001));
      PrintFormat("[EA V22 PM] SL MODIFY | ticket=%I64d | reason=%s | requestedSL=%s | preservedTP=%s | retcode=%u | accepted=%s | verified=%s | resultingSL=%s | %s",
                  ticket, reason, DoubleToString(newSL, digits), DoubleToString(currentTP, digits), retcode,
                  brokerAccepted ? "true" : "false", verified ? "true" : "false",
                  PositionSelectByTicket(ticket) ? DoubleToString(PositionGetDouble(POSITION_SL), digits) : "closed",
                  m_trade.ResultRetcodeDescription());
      return verified;
   }

   bool VerifyClose(ulong ticket, double beforeVolume, double requestedVolume, string symbol, string reason, double *executedOut)
   {
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double tolerance = MathMax(step * 0.51, 0.00000001);
      for(int attempt = 0; attempt < 8; attempt++)
      {
         if(!PositionSelectByTicket(ticket))
         {
            if(executedOut != NULL) *executedOut = beforeVolume;
            PrintFormat("[EA V22 PM] CLOSE VERIFY | ticket=%I64d | reason=%s | requested=%.8f | executed=%.8f | resultingPosition=closed | verified=true", ticket, reason, requestedVolume, beforeVolume);
            return true;
         }
         double afterVolume = PositionGetDouble(POSITION_VOLUME);
         double executed = MathMax(0.0, beforeVolume - afterVolume);
         if(executed + tolerance >= requestedVolume)
         {
            if(executedOut != NULL) *executedOut = executed;
            PrintFormat("[EA V22 PM] CLOSE VERIFY | ticket=%I64d | reason=%s | requested=%.8f | executed=%.8f | remaining=%.8f | verified=true", ticket, reason, requestedVolume, executed, afterVolume);
            return true;
         }
         Sleep(100);
      }
      if(executedOut != NULL) *executedOut = 0.0;
      double remaining = PositionSelectByTicket(ticket) ? PositionGetDouble(POSITION_VOLUME) : 0.0;
      PrintFormat("[EA V22 PM] CLOSE VERIFY | ticket=%I64d | reason=%s | requested=%.8f | executed=%.8f | remaining=%.8f | verified=false", ticket, reason, requestedVolume, MathMax(0.0, beforeVolume - remaining), remaining);
      return false;
   }

   bool CloseVolume(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double volume, string reason)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double beforeVolume = PositionGetDouble(POSITION_VOLUME);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(step <= 0.0 || minVolume <= 0.0 || beforeVolume <= 0.0) return false;

      double closeVolume = NormalizeCloseVolume(symbol, volume, beforeVolume);
      if(closeVolume <= 0.0) return false;
      double remainder = beforeVolume - closeVolume;
      if(remainder > 0.0 && remainder < minVolume) closeVolume = beforeVolume;
      closeVolume = NormalizeDouble(closeVolume, VolumeDigits(step));

      m_trade.SetExpertMagicNumber(PM_MAGIC_NUMBER);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetAsyncMode(false);

      bool callOK = false;
      ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(closeVolume >= beforeVolume - step * 0.25)
      {
         callOK = m_trade.PositionClose(ticket);
      }
      else if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         callOK = m_trade.PositionClosePartial(ticket, closeVolume);
      }
      else
      {
         if(type == POSITION_TYPE_BUY) callOK = m_trade.Sell(closeVolume, symbol, 0.0, 0.0, 0.0, "GOD_MODE_V22_TP");
         else callOK = m_trade.Buy(closeVolume, symbol, 0.0, 0.0, 0.0, "GOD_MODE_V22_TP");
      }

      uint retcode = m_trade.ResultRetcode();
      bool brokerAccepted = callOK && (SuccessfulRetcode(retcode) || retcode == TRADE_RETCODE_PLACED);
      double executed = 0.0;
      bool verified = brokerAccepted && VerifyClose(ticket, beforeVolume, closeVolume, symbol, reason, &executed);
      PrintFormat("[EA V22 PM] CLOSE | ticket=%I64d | reason=%s | requested=%.8f | brokerVolume=%.8f | retcode=%u | accepted=%s | verified=%s | resultingPosition=%s | %s",
                  ticket, reason, closeVolume, m_trade.ResultVolume(), retcode,
                  brokerAccepted ? "true" : "false", verified ? "true" : "false",
                  PositionSelectByTicket(ticket) ? DoubleToString(PositionGetDouble(POSITION_VOLUME), VolumeDigits(step)) : "closed",
                  m_trade.ResultRetcodeDescription());
      return verified;
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
      double pip = PipSize(symbol);
      if(currentVolume <= 0.0 || entry <= 0.0 || current <= 0.0 || pip <= 0.0) return;

      double tp1Pips = MathMax(0.0, ReadSetting("TP1_PIPS", 10.0));
      double tp2Pips = MathMax(tp1Pips, ReadSetting("TP2_PIPS", 15.0));
      double tp3Pips = MathMax(tp2Pips, ReadSetting("TP3_PIPS", 20.0));
      double tp1Pct = Clamp(ReadSetting("TP1_PCT", 0.50), 0.0, 1.0);
      double tp2Pct = Clamp(ReadSetting("TP2_PCT", 0.30), 0.0, 1.0);
      double tp3Pct = Clamp(ReadSetting("TP3_PCT", 0.20), 0.0, 1.0);

      double original = OriginalVolume(ticket, currentVolume, tp1Pct, tp2Pct, tp3Pct);
      int stage = TPStage(ticket);
      double profitPips = type == POSITION_TYPE_BUY ? (current - entry) / pip : (entry - current) / pip;

      if(profitPips > 0.0 && stage < PM_STAGE_TP1 && tp1Pct > 0.0 && tp1Pips > 0.0 && profitPips >= tp1Pips)
      {
         if(CloseVolume(ticket, symbol, type, original * tp1Pct, "TP1"))
         {
            SetTPStage(ticket, PM_STAGE_TP1);
            stage = PM_STAGE_TP1;
            PrintFormat("[EA V22 PM] TP1 COMPLETE | ticket=%I64d | original=%.8f | configuredClose=%.2f%% | trigger=%.2f pips", ticket, original, tp1Pct * 100.0, tp1Pips);
         }
      }

      if(!PositionSelectByTicket(ticket)) return;
      current = PositionGetDouble(POSITION_PRICE_CURRENT);
      profitPips = type == POSITION_TYPE_BUY ? (current - entry) / pip : (entry - current) / pip;
      stage = TPStage(ticket);

      if(profitPips > 0.0 && stage < PM_STAGE_TP2 && tp2Pct > 0.0 && tp2Pips > 0.0 && profitPips >= tp2Pips)
      {
         if(CloseVolume(ticket, symbol, type, original * tp2Pct, "TP2"))
         {
            SetTPStage(ticket, PM_STAGE_TP2);
            stage = PM_STAGE_TP2;
            PrintFormat("[EA V22 PM] TP2 COMPLETE | ticket=%I64d | original=%.8f | configuredClose=%.2f%% | trigger=%.2f pips", ticket, original, tp2Pct * 100.0, tp2Pips);
         }
      }

      if(!PositionSelectByTicket(ticket)) return;
      current = PositionGetDouble(POSITION_PRICE_CURRENT);
      profitPips = type == POSITION_TYPE_BUY ? (current - entry) / pip : (entry - current) / pip;
      stage = TPStage(ticket);

      if(profitPips > 0.0 && stage < PM_STAGE_TP3 && tp3Pips > 0.0 && profitPips >= tp3Pips)
      {
         double remaining = PositionGetDouble(POSITION_VOLUME);
         if(remaining > 0.0 && CloseVolume(ticket, symbol, type, remaining, "TP3_FINAL"))
         {
            SetTPStage(ticket, PM_STAGE_TP3);
            PrintFormat("[EA V22 PM] TP3 COMPLETE | ticket=%I64d | finalRemaining=%.8f | configuredTarget=%.2f%% | trigger=%.2f pips", ticket, remaining, tp3Pct * 100.0, tp3Pips);
            return;
         }
      }

      if(!PositionSelectByTicket(ticket)) return;
      current = PositionGetDouble(POSITION_PRICE_CURRENT);
      profitPips = type == POSITION_TYPE_BUY ? (current - entry) / pip : (entry - current) / pip;

      bool breakevenEnabled = ReadBool("BE_ENABLED", true);
      double beTrigger = MathMax(0.0, ReadSetting("BE_TRIGGER_PIPS", tp1Pips));
      double beOffset = ReadSetting("BE_OFFSET_PIPS", 0.0);
      if(breakevenEnabled && beTrigger > 0.0 && profitPips >= beTrigger && !BreakevenDone(ticket))
      {
         double beSL = type == POSITION_TYPE_BUY ? entry + beOffset * pip : entry - beOffset * pip;
         if(ModifySL(ticket, symbol, type, beSL, "BREAKEVEN"))
         {
            SetBreakevenDone(ticket);
            PrintFormat("[EA V22 PM] BREAKEVEN COMPLETE | ticket=%I64d | entry=%s | offset=%.2f pips", ticket, DoubleToString(entry, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)), beOffset);
         }
      }

      if(!PositionSelectByTicket(ticket)) return;
      current = PositionGetDouble(POSITION_PRICE_CURRENT);
      double existingSL = PositionGetDouble(POSITION_SL);
      profitPips = type == POSITION_TYPE_BUY ? (current - entry) / pip : (entry - current) / pip;
      bool trailingEnabled = ReadBool("TRAIL_ENABLED", true);
      double activation = MathMax(0.0, ReadSetting("TRAIL_ACTIVATION_PIPS", 5.0));
      double distance = MathMax(0.0, ReadSetting("TRAIL_DISTANCE_PIPS", 6.0));
      double step = MathMax(0.0, ReadSetting("TRAIL_STEP_PIPS", 1.0));
      if(trailingEnabled && activation > 0.0 && distance > 0.0 && profitPips >= activation)
      {
         double desired = type == POSITION_TYPE_BUY ? current - distance * pip : current + distance * pip;
         desired = NormalizeDouble(desired, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
         bool improves = ImproveOnly(type, existingSL, desired);
         double movement = existingSL > 0.0 ? MathAbs(desired - existingSL) / pip : step;
         if(improves && (existingSL <= 0.0 || movement >= step))
            ModifySL(ticket, symbol, type, desired, "TRAILING");
      }
   }

   void EnsureDefaultConfiguration()
   {
      if(GlobalVariableCheck(PM_PREFIX + "CONFIG_READY") && GlobalVariableGet(PM_PREFIX + "CONFIG_READY") > 0.5) return;
      // Fail-safe defaults mirror the existing ScalpingConfig TP settings and
      // the production position-management defaults. Swift sync overwrites these
      // values whenever the app saves/refreshes its settings.
      GlobalVariableSet(PM_PREFIX + "TP1_PCT", 0.50);
      GlobalVariableSet(PM_PREFIX + "TP1_PIPS", 10.0);
      GlobalVariableSet(PM_PREFIX + "TP2_PCT", 0.30);
      GlobalVariableSet(PM_PREFIX + "TP2_PIPS", 15.0);
      GlobalVariableSet(PM_PREFIX + "TP3_PCT", 0.20);
      GlobalVariableSet(PM_PREFIX + "TP3_PIPS", 20.0);
      GlobalVariableSet(PM_PREFIX + "BE_ENABLED", 1.0);
      GlobalVariableSet(PM_PREFIX + "BE_TRIGGER_PIPS", 10.0);
      GlobalVariableSet(PM_PREFIX + "BE_OFFSET_PIPS", 0.0);
      GlobalVariableSet(PM_PREFIX + "TRAIL_ENABLED", 1.0);
      GlobalVariableSet(PM_PREFIX + "TRAIL_ACTIVATION_PIPS", 5.0);
      GlobalVariableSet(PM_PREFIX + "TRAIL_DISTANCE_PIPS", 6.0);
      GlobalVariableSet(PM_PREFIX + "TRAIL_STEP_PIPS", 1.0);
      GlobalVariableSet(PM_PREFIX + "CONFIG_READY", 1.0);
      GlobalVariablesFlush();
      Print("[EA V22 PM] DEFAULT CONFIGURATION INITIALIZED | awaiting Swift settings sync");
   }

public:
   CPositionManagerV22()
   {
      m_trade.SetExpertMagicNumber(PM_MAGIC_NUMBER);
      m_trade.SetAsyncMode(false);
   }

   void ManageAll()
   {
      EnsureDefaultConfiguration();
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         ManagePosition(ticket);
      }
   }
};

#endif
