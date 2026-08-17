//+------------------------------------------------------------------+
//| PositionProtectionManager.mqh                                    |
//| Broker-side TP1/TP2/TP3, breakeven and forward-only trailing.    |
//+------------------------------------------------------------------+
#ifndef POSITION_PROTECTION_MANAGER_MQH
#define POSITION_PROTECTION_MANAGER_MQH

#include <Trade/Trade.mqh>

#define PM_GV_PREFIX "FS_PM_"
#define PM_CONFIG_VERSION 1

class CPositionProtectionManager
{
private:
   CTrade m_trade;
   datetime m_lastRun;

   string Key(ulong ticket, string name)
   {
      return PM_GV_PREFIX + IntegerToString((long)ticket) + "_" + name;
   }

   double GetConfig(string name, double fallback)
   {
      string key = PM_GV_PREFIX + name;
      if(GlobalVariableCheck(key)) return GlobalVariableGet(key);
      return fallback;
   }

   bool GetBoolConfig(string name, bool fallback)
   {
      return GetConfig(name, fallback ? 1.0 : 0.0) > 0.5;
   }

   double PipSize(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(point <= 0.0) return 0.0;
      return (digits == 3 || digits == 5) ? point * 10.0 : point;
   }

   double NormalizeVolume(string symbol, double volume)
   {
      double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0 || volume <= 0.0) return 0.0;
      if(volume < minVolume) return 0.0;
      volume = MathMin(volume, maxVolume);
      double normalized = MathFloor((volume + step * 0.000001) / step) * step;
      if(normalized < minVolume) return 0.0;
      int digits = VolumeDigits(step);
      return NormalizeDouble(normalized, digits);
   }

   int VolumeDigits(double step)
   {
      int digits = 0;
      double value = step;
      while(digits < 8 && MathAbs(value - MathRound(value)) > 0.000000001)
      {
         value *= 10.0;
         digits++;
      }
      return digits;
   }

   double PriceNormalize(string symbol, double price)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      return NormalizeDouble(price, digits);
   }

   bool IsSuccessful(uint retcode)
   {
      return retcode == TRADE_RETCODE_DONE ||
             retcode == TRADE_RETCODE_PLACED ||
             retcode == TRADE_RETCODE_DONE_PARTIAL;
   }

   bool IsBetterSL(ENUM_POSITION_TYPE type, double currentSL, double candidate)
   {
      if(candidate <= 0.0) return false;
      if(currentSL <= 0.0) return true;
      return type == POSITION_TYPE_BUY ? candidate > currentSL : candidate < currentSL;
   }

   bool IsPastTarget(ENUM_POSITION_TYPE type, double price, double target)
   {
      return type == POSITION_TYPE_BUY ? price >= target : price <= target;
   }

   double ProfitPips(ENUM_POSITION_TYPE type, string symbol, double openPrice, double currentPrice)
   {
      double pip = PipSize(symbol);
      if(pip <= 0.0) return 0.0;
      double delta = type == POSITION_TYPE_BUY ? currentPrice - openPrice : openPrice - currentPrice;
      return delta / pip;
   }

   bool CloseStage(ulong ticket, string symbol, double requestedVolume, string stage)
   {
      if(requestedVolume <= 0.0) return true;
      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double volume = NormalizeVolume(symbol, MathMin(requestedVolume, currentVolume));
      if(volume <= 0.0)
      {
         // If the requested stage is smaller than broker minimum, defer it;
         // the final stage may close the remaining broker-valid volume.
         PrintFormat("[PM] %s deferred | ticket=%I64u | requested=%.8f | current=%.8f | min=%.8f",
                     stage, ticket, requestedVolume, currentVolume, minVolume);
         return false;
      }

      m_trade.SetAsyncMode(false);
      bool callOK = m_trade.PositionClosePartial(ticket, volume);
      uint retcode = m_trade.ResultRetcode();
      bool success = callOK && IsSuccessful(retcode);
      PrintFormat("[PM] %s | ticket=%I64u | requested=%.8f | executed=%.8f | retcode=%u | success=%s | comment=%s",
                  stage, ticket, requestedVolume, m_trade.ResultVolume(), retcode,
                  success ? "true" : "false", m_trade.ResultComment());
      if(success)
      {
         GlobalVariableSet(Key(ticket, stage), 1.0);
         GlobalVariablesFlush();
      }
      return success;
   }

   bool ModifySL(ulong ticket, string symbol, double candidateSL, string reason)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(!IsBetterSL(type, currentSL, candidateSL)) return true;

      candidateSL = PriceNormalize(symbol, candidateSL);
      m_trade.SetAsyncMode(false);
      bool callOK = m_trade.PositionModify(ticket, candidateSL, currentTP);
      uint retcode = m_trade.ResultRetcode();
      bool success = callOK && IsSuccessful(retcode);
      PrintFormat("[PM] %s | ticket=%I64u | oldSL=%.10f | newSL=%.10f | retcode=%u | success=%s | comment=%s",
                  reason, ticket, currentSL, candidateSL, retcode,
                  success ? "true" : "false", m_trade.ResultComment());
      return success;
   }

   void ProcessPosition(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return;
      string symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double initialVolumeKey = GetConfig(IntegerToString((long)ticket) + "_INITIAL_VOLUME", 0.0);
      if(initialVolumeKey <= 0.0)
      {
         initialVolumeKey = volume;
         GlobalVariableSet(Key(ticket, "INITIAL_VOLUME"), initialVolumeKey);
         GlobalVariablesFlush();
      }

      double profitPips = ProfitPips(type, symbol, openPrice, currentPrice);
      if(profitPips <= 0.0) return;

      double tp1Percent = GetConfig("TP1_PERCENT", 0.50);
      double tp1Pips = GetConfig("TP1_PIPS", 10.0);
      double tp2Percent = GetConfig("TP2_PERCENT", 0.30);
      double tp2Pips = GetConfig("TP2_PIPS", 15.0);
      double tp3Percent = GetConfig("TP3_PERCENT", 0.20);
      double tp3Pips = GetConfig("TP3_PIPS", 20.0);

      bool tp1Done = GetConfig(IntegerToString((long)ticket) + "_TP1", 0.0) > 0.5;
      bool tp2Done = GetConfig(IntegerToString((long)ticket) + "_TP2", 0.0) > 0.5;
      bool tp3Done = GetConfig(IntegerToString((long)ticket) + "_TP3", 0.0) > 0.5;

      if(!tp1Done && tp1Percent > 0.0 && tp1Pips > 0.0 && profitPips >= tp1Pips)
      {
         if(CloseStage(ticket, symbol, initialVolumeKey * tp1Percent, "TP1")) tp1Done = true;
      }

      if(PositionSelectByTicket(ticket) && !tp2Done && tp2Percent > 0.0 && tp2Pips > 0.0 && profitPips >= tp2Pips)
      {
         if(CloseStage(ticket, symbol, initialVolumeKey * tp2Percent, "TP2")) tp2Done = true;
      }

      if(PositionSelectByTicket(ticket) && !tp3Done && tp3Pips > 0.0 && profitPips >= tp3Pips)
      {
         // TP3 is the final configured allocation. If broker rounding leaves
         // a small residual, close only a broker-valid residual volume.
         double requested = initialVolumeKey * tp3Percent;
         double current = PositionGetDouble(POSITION_VOLUME);
         if(requested > current) requested = current;
         if(CloseStage(ticket, symbol, requested, "TP3")) tp3Done = true;
      }

      if(!PositionSelectByTicket(ticket)) return;
      double currentSL = PositionGetDouble(POSITION_SL);

      bool breakevenEnabled = GetBoolConfig("BREAKEVEN_ENABLED", true);
      double breakevenTrigger = GetConfig("BREAKEVEN_TRIGGER_PIPS", 10.0);
      double breakevenOffset = GetConfig("BREAKEVEN_OFFSET_PIPS", 0.0);
      if(breakevenEnabled && profitPips >= breakevenTrigger)
      {
         double pip = PipSize(symbol);
         double beSL = type == POSITION_TYPE_BUY ? openPrice + breakevenOffset * pip : openPrice - breakevenOffset * pip;
         if(IsBetterSL(type, currentSL, beSL)) ModifySL(ticket, symbol, beSL, "BREAKEVEN");
      }

      bool trailingEnabled = GetBoolConfig("TRAILING_ENABLED", true);
      double activation = GetConfig("TRAILING_ACTIVATION_PIPS", 5.0);
      double distance = GetConfig("TRAILING_DISTANCE_PIPS", 6.0);
      double step = GetConfig("TRAILING_STEP_PIPS", 1.0);
      if(trailingEnabled && activation > 0.0 && distance > 0.0 && profitPips >= activation)
      {
         double pip = PipSize(symbol);
         double candidate = type == POSITION_TYPE_BUY ? currentPrice - distance * pip : currentPrice + distance * pip;
         candidate = PriceNormalize(symbol, candidate);
         double movementPips = currentSL > 0.0 ? MathAbs(candidate - currentSL) / pip : step;
         if(currentSL <= 0.0 || movementPips >= step)
         {
            ModifySL(ticket, symbol, candidate, "TRAILING");
         }
      }
   }

public:
   CPositionProtectionManager()
   {
      m_lastRun = 0;
      m_trade.SetAsyncMode(false);
   }

   void Run()
   {
      datetime now = TimeCurrent();
      if(now == m_lastRun) return;
      m_lastRun = now;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         ProcessPosition(ticket);
      }
   }
};

#endif
