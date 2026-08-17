//+------------------------------------------------------------------+
//| PositionManagerV23.mqh                                          |
//| Production position protection: configurable TP/BE/trailing.   |
//+------------------------------------------------------------------+
#ifndef POSITION_MANAGER_V23_MQH
#define POSITION_MANAGER_V23_MQH

#include <Trade/Trade.mqh>

#define PM23_MAGIC 888888
#define PM23_DEFAULT_DEVIATION 15
#define PM23_DEFAULT_TP1_PIPS 10.0
#define PM23_DEFAULT_TP1_PERCENT 0.50
#define PM23_DEFAULT_TP2_PIPS 15.0
#define PM23_DEFAULT_TP2_PERCENT 0.30
#define PM23_DEFAULT_TP3_PIPS 20.0
#define PM23_DEFAULT_TP3_PERCENT 0.20
#define PM23_DEFAULT_TRAIL_ACTIVATION 5.0
#define PM23_DEFAULT_BE_LOCK 0.5
#define PM23_DEFAULT_MIN_STEP 1.0
#define PM23_DEFAULT_ATR_PERIOD 14
#define PM23_DEFAULT_ATR_BASELINE 5.0
#define PM23_DEFAULT_ATR_MAX_MULT 1.50
#define PM23_DEFAULT_TRAIL_5_10 3.0
#define PM23_DEFAULT_TRAIL_10_15 4.5
#define PM23_DEFAULT_TRAIL_15_25 6.0
#define PM23_DEFAULT_TRAIL_25_40 8.0
#define PM23_DEFAULT_TRAIL_40_80 10.0
#define PM23_DEFAULT_TRAIL_80_PLUS 12.0

class CPositionManagerV23
{
private:
   CTrade m_trade;
   string Prefix(ulong ticket, string name) { return "FSV23_" + IntegerToString((long)ticket) + "_" + name; }
   double Read(string key, double fallback) { return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback; }
   void Write(string key, double value) { GlobalVariableSet(key, value); }
   double Config(string name, double fallback, double minimum, double maximum)
   {
      string key = "FSV23_PM_" + name;
      double value = Read(key, fallback);
      return MathMax(minimum, MathMin(maximum, value));
   }
   int ConfigInt(string name, int fallback, int minimum, int maximum)
   {
      return (int)MathRound(Config(name, (double)fallback, (double)minimum, (double)maximum));
   }
   double PipSize(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      return (digits == 3 || digits == 5) ? point * 10.0 : point;
   }
   int VolumeDigits(string symbol)
   {
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      int digits = 0;
      while(digits < 8 && MathAbs(step * MathPow(10.0, digits) - MathRound(step * MathPow(10.0, digits))) > 1e-9) digits++;
      return digits;
   }
   double NormalizeVolumeDown(string symbol, double volume)
   {
      double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = minVolume;
      if(step <= 0.0) return 0.0;
      volume = MathMin(volume, maxVolume);
      return NormalizeDouble(MathFloor((volume + 1e-12) / step) * step, VolumeDigits(symbol));
   }
   bool Successful(uint retcode)
   {
      return retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL || retcode == TRADE_RETCODE_PLACED;
   }
   double StopDistance(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      long stops = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long freeze = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      return MathMax(point, (double)MathMax(stops, freeze) * point);
   }
   double ClampSL(string symbol, ENUM_POSITION_TYPE type, double desired)
   {
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick)) return 0.0;
      double distance = StopDistance(symbol);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(type == POSITION_TYPE_BUY) return NormalizeDouble(MathMin(desired, tick.bid - distance), digits);
      return NormalizeDouble(MathMax(desired, tick.ask + distance), digits);
   }
   bool ValidSL(string symbol, ENUM_POSITION_TYPE type, double sl)
   {
      if(sl <= 0.0) return false;
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick)) return false;
      double distance = StopDistance(symbol);
      if(type == POSITION_TYPE_BUY) return sl < tick.bid - distance;
      return sl > tick.ask + distance;
   }
   bool ModifySL(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double sl, double tp)
   {
      if(!ValidSL(symbol, type, sl)) return false;
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = symbol;
      request.sl = sl;
      request.tp = tp;
      ResetLastError();
      if(!OrderSend(request, result) || !Successful(result.retcode))
      {
         PrintFormat("[EA V23] SL MODIFY FAILED | %s #%I64u | sl=%.10f | retcode=%u | %s", symbol, ticket, sl, result.retcode, result.comment);
         return false;
      }
      return true;
   }
   ENUM_ORDER_TYPE_FILLING FillingMode(string symbol)
   {
      long flags = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      if((flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
      if((flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
      return ORDER_FILLING_RETURN;
   }
   bool PartialClose(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double requested)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double current = PositionGetDouble(POSITION_VOLUME);
      double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double closeVolume = NormalizeVolumeDown(symbol, requested);
      if(closeVolume <= 0.0 || closeVolume >= current || current - closeVolume < minVolume - 1e-9)
      {
         PrintFormat("[EA V23] PARTIAL NOT POSSIBLE | %s #%I64u | current=%.8f requested=%.8f normalized=%.8f min=%.8f", symbol, ticket, current, requested, closeVolume, minVolume);
         return false;
      }

      m_trade.SetExpertMagicNumber(PM23_MAGIC);
      m_trade.SetDeviationInPoints(ConfigInt("DEVIATION_POINTS", PM23_DEFAULT_DEVIATION, 0, 500));
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetAsyncMode(false);

      bool sent = false;
      uint retcode = 0;
      ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         sent = m_trade.PositionClosePartial(ticket, closeVolume);
         retcode = m_trade.ResultRetcode();
      }
      else
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = symbol;
         request.volume = closeVolume;
         request.magic = PM23_MAGIC;
         request.deviation = ConfigInt("DEVIATION_POINTS", PM23_DEFAULT_DEVIATION, 0, 500);
         request.type_filling = FillingMode(symbol);
         request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
         request.comment = "FS V23 PARTIAL";
         ResetLastError();
         sent = OrderSend(request, result);
         retcode = result.retcode;
         if(!sent || !Successful(retcode))
            PrintFormat("[EA V23] PARTIAL REJECTED | %s #%I64u | volume=%.8f | retcode=%u | %s", symbol, ticket, closeVolume, retcode, result.comment);
      }
      if(!sent || !Successful(retcode))
      {
         PrintFormat("[EA V23] PARTIAL FAILED | %s #%I64u | volume=%.8f | retcode=%u | %s", symbol, ticket, closeVolume, retcode, m_trade.ResultComment());
         return false;
      }
      PrintFormat("[EA V23] PARTIAL EXECUTED | %s #%I64u | volume=%.8f | retcode=%u", symbol, ticket, closeVolume, retcode);
      return true;
   }
   double TrailDistance(double profitPips)
   {
      if(profitPips < 0.0) return 0.0;
      double v;
      if(profitPips < 10.0) v = Config("TRAIL_5_10", PM23_DEFAULT_TRAIL_5_10, 0.1, 100.0);
      else if(profitPips < 15.0) v = Config("TRAIL_10_15", PM23_DEFAULT_TRAIL_10_15, 0.1, 100.0);
      else if(profitPips < 25.0) v = Config("TRAIL_15_25", PM23_DEFAULT_TRAIL_15_25, 0.1, 100.0);
      else if(profitPips < 40.0) v = Config("TRAIL_25_40", PM23_DEFAULT_TRAIL_25_40, 0.1, 100.0);
      else if(profitPips < 80.0) v = Config("TRAIL_40_80", PM23_DEFAULT_TRAIL_40_80, 0.1, 150.0);
      else v = Config("TRAIL_80_PLUS", PM23_DEFAULT_TRAIL_80_PLUS, 0.1, 200.0);
      return v;
   }
   double VolatilityAdjustedTrail(string symbol, double basePips)
   {
      if(basePips <= 0.0) return 0.0;
      double pip = PipSize(symbol);
      if(pip <= 0.0) return basePips;
      int period = ConfigInt("ATR_PERIOD", PM23_DEFAULT_ATR_PERIOD, 2, 200);
      double baseline = Config("ATR_BASELINE_PIPS", PM23_DEFAULT_ATR_BASELINE, 0.1, 100.0);
      double maxMultiplier = Config("ATR_MAX_MULTIPLIER", PM23_DEFAULT_ATR_MAX_MULT, 1.0, 5.0);
      int handle = iATR(symbol, PERIOD_M5, period);
      if(handle == INVALID_HANDLE) return basePips;
      double values[];
      ArraySetAsSeries(values, true);
      double result = basePips;
      if(CopyBuffer(handle, 0, 0, 1, values) == 1 && values[0] > 0.0)
      {
         double multiplier = MathMax(1.0, MathMin(maxMultiplier, (values[0] / pip) / baseline));
         result = basePips * multiplier;
      }
      IndicatorRelease(handle);
      return result;
   }
   void ReconstructStage(ulong ticket, double initialVolume, double currentVolume, double p1, double p2, double p3)
   {
      string key = Prefix(ticket, "STAGE");
      if(GlobalVariableCheck(key)) return;
      double tolerance = MathMax(SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_VOLUME_STEP), 1e-8) * 0.5;
      double remainingAfter1 = initialVolume * (1.0 - p1);
      double remainingAfter2 = remainingAfter1 - initialVolume * p2;
      double remainingAfter3 = MathMax(0.0, remainingAfter2 - initialVolume * p3);
      if(p3 > 0.0 && currentVolume <= remainingAfter3 + tolerance) Write(key, 3.0);
      else if(p2 > 0.0 && currentVolume <= remainingAfter2 + tolerance) Write(key, 2.0);
      else if(p1 > 0.0 && currentVolume <= remainingAfter1 + tolerance) Write(key, 1.0);
      else Write(key, 0.0);
   }

public:
   void Manage()
   {
      for(int index = PositionsTotal() - 1; index >= 0; index--)
      {
         ulong ticket = PositionGetTicket(index);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != PM23_MAGIC) continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double hardSL = PositionGetDouble(POSITION_SL);
         double brokerTP = PositionGetDouble(POSITION_TP);
         if(symbol == "" || entry <= 0.0 || volume <= 0.0) continue;
         if(hardSL <= 0.0)
         {
            PrintFormat("[EA V23] PROTECTION HALT | %s #%I64u | hard SL missing", symbol, ticket);
            continue;
         }

         double pip = PipSize(symbol);
         if(pip <= 0.0) continue;
         double initialVolume = Read(Prefix(ticket, "INITIAL_VOLUME"), 0.0);
         double initialSL = Read(Prefix(ticket, "INITIAL_SL"), 0.0);
         if(initialVolume <= 0.0) { initialVolume = volume; Write(Prefix(ticket, "INITIAL_VOLUME"), initialVolume); }
         if(initialSL <= 0.0) { initialSL = hardSL; Write(Prefix(ticket, "INITIAL_SL"), initialSL); }

         double tp1Pips = Config("TP1_PIPS", PM23_DEFAULT_TP1_PIPS, 0.0, 10000.0);
         double tp1Pct = Config("TP1_PERCENT", PM23_DEFAULT_TP1_PERCENT, 0.0, 1.0);
         double tp2Pips = Config("TP2_PIPS", PM23_DEFAULT_TP2_PIPS, 0.0, 10000.0);
         double tp2Pct = Config("TP2_PERCENT", PM23_DEFAULT_TP2_PERCENT, 0.0, 1.0);
         double tp3Pips = Config("TP3_PIPS", PM23_DEFAULT_TP3_PIPS, 0.0, 10000.0);
         double tp3Pct = Config("TP3_PERCENT", PM23_DEFAULT_TP3_PERCENT, 0.0, 1.0);
         if(tp2Pips > 0.0 && tp1Pips > 0.0 && tp2Pips < tp1Pips) tp2Pips = tp1Pips;
         if(tp3Pips > 0.0 && tp2Pips > 0.0 && tp3Pips < tp2Pips) tp3Pips = tp2Pips;

         ReconstructStage(ticket, initialVolume, volume, tp1Pct, tp2Pct, tp3Pct);
         double stage = Read(Prefix(ticket, "STAGE"), 0.0);
         MqlTick tick;
         if(!SymbolInfoTick(symbol, tick)) continue;
         double favorable = (type == POSITION_TYPE_BUY) ? tick.bid - entry : entry - tick.ask;
         double profitPips = favorable / pip;

         // The EA removes an initial TP once it claims the position, but never removes the hard SL.
         if(brokerTP > 0.0 && Read(Prefix(ticket, "TP_REMOVED"), 0.0) < 1.0)
         {
            if(ModifySL(ticket, symbol, type, hardSL, 0.0))
            {
               Write(Prefix(ticket, "TP_REMOVED"), 1.0);
               PrintFormat("[EA V23] TP HANDOFF | %s #%I64u | brokerTP=%.10f removed; hardSL retained", symbol, ticket, brokerTP);
            }
         }

         if(stage < 1.0 && tp1Pips > 0.0 && tp1Pct > 0.0 && profitPips >= tp1Pips)
         {
            double closeVolume = initialVolume * tp1Pct;
            if(PartialClose(ticket, symbol, type, closeVolume))
            {
               Write(Prefix(ticket, "STAGE"), 1.0); stage = 1.0;
               PrintFormat("[EA V23] TP1 | %s #%I64u | target=%.2f pips | closed=%.8f", symbol, ticket, tp1Pips, closeVolume);
               if(PositionSelectByTicket(ticket))
               {
                  double liveSL = PositionGetDouble(POSITION_SL);
                  double beLock = Config("BE_LOCK_PIPS", PM23_DEFAULT_BE_LOCK, 0.0, 100.0);
                  double be = (type == POSITION_TYPE_BUY) ? entry + beLock * pip : entry - beLock * pip;
                  be = ClampSL(symbol, type, be);
                  bool improve = type == POSITION_TYPE_BUY ? (liveSL <= 0.0 || be > liveSL) : (liveSL <= 0.0 || be < liveSL);
                  if(improve) ModifySL(ticket, symbol, type, be, PositionGetDouble(POSITION_TP));
               }
            }
         }

         if(PositionSelectByTicket(ticket)) volume = PositionGetDouble(POSITION_VOLUME);
         if(stage < 2.0 && tp2Pips > 0.0 && tp2Pct > 0.0 && profitPips >= tp2Pips)
         {
            double closeVolume = initialVolume * tp2Pct;
            if(PartialClose(ticket, symbol, type, closeVolume))
            {
               Write(Prefix(ticket, "STAGE"), 2.0); stage = 2.0;
               PrintFormat("[EA V23] TP2 | %s #%I64u | target=%.2f pips | closed=%.8f", symbol, ticket, tp2Pips, closeVolume);
            }
         }

         if(PositionSelectByTicket(ticket)) volume = PositionGetDouble(POSITION_VOLUME);
         if(stage < 3.0 && tp3Pips > 0.0 && tp3Pct > 0.0 && profitPips >= tp3Pips)
         {
            double closeVolume = initialVolume * tp3Pct;
            double remaining = volume - NormalizeVolumeDown(symbol, closeVolume);
            double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            if(remaining > 0.0 && remaining < minVolume) closeVolume = volume;
            if(closeVolume >= volume - 1e-9)
            {
               m_trade.SetExpertMagicNumber(PM23_MAGIC);
               m_trade.SetDeviationInPoints(ConfigInt("DEVIATION_POINTS", PM23_DEFAULT_DEVIATION, 0, 500));
               m_trade.SetTypeFillingBySymbol(symbol);
               if(m_trade.PositionClose(ticket))
               {
                  Write(Prefix(ticket, "STAGE"), 3.0);
                  PrintFormat("[EA V23] TP3 FINAL | %s #%I64u | target=%.2f pips | full remaining volume closed", symbol, ticket, tp3Pips);
                  continue;
               }
            }
            else if(PartialClose(ticket, symbol, type, closeVolume))
            {
               Write(Prefix(ticket, "STAGE"), 3.0);
               PrintFormat("[EA V23] TP3 | %s #%I64u | target=%.2f pips | closed=%.8f", symbol, ticket, tp3Pips, closeVolume);
            }
         }

         if(!PositionSelectByTicket(ticket)) continue;
         volume = PositionGetDouble(POSITION_VOLUME);
         double activation = Config("TRAIL_ACTIVATION_PIPS", PM23_DEFAULT_TRAIL_ACTIVATION, 0.0, 1000.0);
         if(profitPips >= activation)
         {
            double baseTrail = TrailDistance(profitPips);
            double trailPips = VolatilityAdjustedTrail(symbol, baseTrail);
            double desired = (type == POSITION_TYPE_BUY) ? tick.bid - trailPips * pip : tick.ask + trailPips * pip;
            desired = ClampSL(symbol, type, desired);
            double currentSL = PositionGetDouble(POSITION_SL);
            double minStep = Config("MIN_TRAIL_STEP_PIPS", PM23_DEFAULT_MIN_STEP, 0.0, 100.0) * pip;
            bool improve = type == POSITION_TYPE_BUY ? (currentSL <= 0.0 || desired > currentSL + minStep) : (currentSL <= 0.0 || desired < currentSL - minStep);
            if(improve && ModifySL(ticket, symbol, type, desired, PositionGetDouble(POSITION_TP)))
               PrintFormat("[EA V23] TRAIL | %s #%I64u | activation=%.2f | profit=%.2f | distance=%.2f | SL=%.10f", symbol, ticket, activation, profitPips, trailPips, desired);
         }
      }
   }
};

#endif
