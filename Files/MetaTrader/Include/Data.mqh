//+------------------------------------------------------------------+
//| Data.mqh                                                         |
//| ForexScalperApp MT5 bridge V22.0 - authoritative trade manager  |
//+------------------------------------------------------------------+
#ifndef DATA_MQH
#define DATA_MQH

#property strict

#include <EA_V22_BUILD.mqh>
#include <socketlib.mqh>
#include <JAson.mqh>
#include <Trade/Trade.mqh>

#define DATA_INVALID_SOCKET ((ulong)-1)
#define DATA_PROTOCOL_VERSION FOREX_SCALPER_EA_VERSION
#define EA_V22_MAGIC FOREX_SCALPER_EA_MAGIC
#define V22_TRAIL_ACTIVATION_PIPS 5.0
#define V22_STAGE1_R 1.0
#define V22_STAGE2_R 2.0
#define V22_MIN_TRAIL_STEP_PIPS 1.0
#define V22_BE_LOCK_PIPS 0.5

class CData
{
public:
   bool isTrackingPrice;
   bool isTrackingOhlc;
   bool isTrackingMbook;
   bool isTrackingOrderEvent;

private:
   CTrade m_trade;
   bool m_versionLogged;

public:
   CData()
   {
      isTrackingPrice = true;
      isTrackingOhlc = false;
      isTrackingMbook = false;
      isTrackingOrderEvent = true;
      m_versionLogged = false;
      m_trade.SetExpertMagicNumber(EA_V22_MAGIC);
      m_trade.SetDeviationInPoints(15);
      m_trade.SetAsyncMode(false);
   }

   void SendCurrentPrices(ulong socket)
   {
      ManageProtectedPositions();
      if(socket == DATA_INVALID_SOCKET) return;
      if(!m_versionLogged)
      {
         Print("==================================================");
         Print(" FOREXSCALPERAPP MT5 EXECUTION BRIDGE V22.0");
         Print(" EA-authoritative trade management: ENABLED");
         Print(" Partial TP: 50% @ 1R | 30% @ 2R | remainder runner");
         Print(" Trailing: activates at 5 pips; profit-adaptive distance");
         Print(" Runner: unlimited hold; no fixed TP/time exit");
         Print(" Hard SL: mandatory emergency protection");
         Print(" Swift trade monitor: OBSERVATION / UNPROFITABLE EXITS ONLY");
         Print("==================================================");
         m_versionLogged = true;
      }
      CJAVal root;
      root["type"] = "price_update";
      root["version"] = DATA_PROTOCOL_VERSION;
      root["event_id"] = IntegerToString((long)GetTickCount64());
      root["timestamp"] = (long)TimeCurrent();
      CJAVal prices;
      prices.Clear(jtARRAY);
      int total = SymbolsTotal(true);
      for(int i = 0; i < total; i++)
      {
         string symbol = SymbolName(i, true);
         if(symbol == "") continue;
         MqlTick tick;
         if(!SymbolInfoTick(symbol, tick)) continue;
         CJAVal item;
         item["symbol"] = symbol;
         item["bid"] = tick.bid;
         item["ask"] = tick.ask;
         item["last"] = tick.last;
         item["time"] = (long)tick.time;
         item["time_msc"] = (long)tick.time_msc;
         prices.Add(item);
      }
      root["data"] = prices;
      SendWebSocketMessage(socket, root.Serialize());
   }

   void SendCurrentOhlcs(ulong socket) { }
   void SendCurrentMbook(ulong socket) { }

   void HandleTradeTransaction(const MqlTradeTransaction &trans,
                               const MqlTradeRequest &request,
                               const MqlTradeResult &result,
                               ulong socket)
   {
      request; result;
      if(!isTrackingOrderEvent || socket == DATA_INVALID_SOCKET) return;
      CJAVal json;
      json["type"] = "trade_event";
      json["version"] = DATA_PROTOCOL_VERSION;
      json["event_id"] = IntegerToString((long)GetTickCount64()) + "-" + IntegerToString((long)trans.deal) + "-" + IntegerToString((long)trans.order);
      json["timestamp"] = (long)TimeCurrent();
      json["trans_type"] = (long)trans.type;
      json["symbol"] = trans.symbol;
      json["deal"] = (long)trans.deal;
      json["order"] = (long)trans.order;
      json["position"] = (long)trans.position;
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0 && HistoryDealSelect(trans.deal))
      {
         long positionId = (long)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         json["ticket"] = positionId > 0 ? positionId : (long)trans.position;
         json["position_id"] = positionId;
         json["profit"] = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         json["volume"] = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         json["price"] = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         json["entry"] = (long)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         json["deal_type"] = (long)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         json["commission"] = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
         json["swap"] = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
         json["magic"] = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         json["comment"] = HistoryDealGetString(trans.deal, DEAL_COMMENT);
         json["time"] = (long)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      }
      else json["ticket"] = (long)trans.position;
      SendWebSocketMessage(socket, json.Serialize());
   }

private:
   string StateKey(ulong ticket, string suffix) { return "FSV22_" + IntegerToString((long)ticket) + "_" + suffix; }
   string LegacyStateKey(ulong ticket, string suffix) { return "FSV21_" + IntegerToString((long)ticket) + "_" + suffix; }
   double PipSize(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      return (digits == 3 || digits == 5) ? point * 10.0 : point;
   }
   double NormalizePrice(string symbol, double price) { return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)); }
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
      double normalized = MathFloor((volume + 1e-12) / step) * step;
      normalized = NormalizeDouble(normalized, VolumeDigits(symbol));
      return normalized >= minVolume ? normalized : 0.0;
   }
   bool IsTradeRetcodeSuccess(uint retcode)
   {
      return retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL || retcode == TRADE_RETCODE_PLACED;
   }
   double MinimumStopDistance(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      long stops = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long freeze = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      return MathMax(point, (double)MathMax(stops, freeze) * point);
   }
   bool IsStopValid(string symbol, ENUM_POSITION_TYPE type, double sl)
   {
      if(sl <= 0.0) return false;
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick)) return false;
      double distance = MinimumStopDistance(symbol);
      if(type == POSITION_TYPE_BUY) return sl < tick.bid - distance;
      return sl > tick.ask + distance;
   }
   double ClampTrailingStop(string symbol, ENUM_POSITION_TYPE type, double desired)
   {
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick)) return 0.0;
      double distance = MinimumStopDistance(symbol);
      if(type == POSITION_TYPE_BUY) return NormalizePrice(symbol, MathMin(desired, tick.bid - distance));
      return NormalizePrice(symbol, MathMax(desired, tick.ask + distance));
   }
   bool ModifyProtection(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double newSL, double newTP)
   {
      if(newSL > 0.0 && !IsStopValid(symbol, type, newSL))
      {
         PrintFormat("[EA V22] MODIFY SKIP | %s #%I64u | invalid SL=%.*f for current market", symbol, ticket, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), newSL);
         return false;
      }
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = symbol;
      request.sl = newSL;
      request.tp = newTP;
      ResetLastError();
      if(!OrderSend(request, result))
      {
         PrintFormat("[EA V22] SLTP modify failed | %s #%I64u | error=%d | retcode=%u | %s", symbol, ticket, GetLastError(), result.retcode, result.comment);
         return false;
      }
      if(!IsTradeRetcodeSuccess(result.retcode))
      {
         PrintFormat("[EA V22] SLTP rejected | %s #%I64u | retcode=%u | %s", symbol, ticket, result.retcode, result.comment);
         return false;
      }
      return true;
   }
   bool ClosePartial(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double volume)
   {
      volume = NormalizeVolumeDown(symbol, volume);
      double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      if(volume <= 0.0 || currentVolume - volume < minVolume - 1e-9)
      {
         PrintFormat("[EA V22] PARTIAL SKIP | %s #%I64u | requested=%.4f | current=%.4f | brokerMin=%.4f", symbol, ticket, volume, currentVolume, minVolume);
         return false;
      }
      m_trade.SetExpertMagicNumber(EA_V22_MAGIC);
      m_trade.SetDeviationInPoints(15);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetAsyncMode(false);
      bool ok = false;
      ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) ok = m_trade.PositionClosePartial(ticket, volume, 15);
      else
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = symbol;
         request.volume = volume;
         request.magic = EA_V22_MAGIC;
         request.deviation = 15;
         request.type_filling = ORDER_FILLING_IOC;
         request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
         request.comment = "FS V22 PARTIAL";
         ResetLastError();
         ok = OrderSend(request, result) && IsTradeRetcodeSuccess(result.retcode);
         if(!ok) PrintFormat("[EA V22] PARTIAL REJECTED | %s #%I64u | volume=%.4f | error=%d | retcode=%u | %s", symbol, ticket, volume, GetLastError(), result.retcode, result.comment);
      }
      if(!ok)
      {
         PrintFormat("[EA V22] PARTIAL FAILED | %s #%I64u | volume=%.4f | retcode=%u | %s", symbol, ticket, volume, m_trade.ResultRetcode(), m_trade.ResultComment());
         return false;
      }
      return true;
   }
   void SetState(string key, double value) { GlobalVariableSet(key, value); }
   double ReadState(string key, double fallback) { return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback; }
   double DynamicTrailingPips(double profitPips)
   {
      if(profitPips >= 100.0) return 18.0;
      if(profitPips >= 60.0) return 15.0;
      if(profitPips >= 40.0) return 12.0;
      if(profitPips >= 25.0) return 10.0;
      if(profitPips >= 15.0) return 8.0;
      if(profitPips >= 10.0) return 6.0;
      return 5.0;
   }
   bool ImproveStop(ulong ticket, string symbol, ENUM_POSITION_TYPE type, double currentSL, double desiredSL)
   {
      if(desiredSL <= 0.0) return false;
      desiredSL = ClampTrailingStop(symbol, type, desiredSL);
      if(desiredSL <= 0.0) return false;
      double pip = PipSize(symbol);
      if(pip <= 0.0) return false;
      if(type == POSITION_TYPE_BUY)
      {
         if(currentSL > 0.0 && desiredSL <= currentSL + V22_MIN_TRAIL_STEP_PIPS * pip) return false;
      }
      else if(currentSL > 0.0 && desiredSL >= currentSL - V22_MIN_TRAIL_STEP_PIPS * pip) return false;
      return ModifyProtection(ticket, symbol, type, desiredSL, 0.0);
   }
   void ManageProtectedPositions()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != EA_V22_MAGIC) continue;
         string symbol = PositionGetString(POSITION_SYMBOL);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         if(symbol == "" || entry <= 0.0 || volume <= 0.0) continue;
         if(sl <= 0.0)
         {
            PrintFormat("[EA V22] MANAGEMENT HALT | %s #%I64u | no hard SL; protection not claimed", symbol, ticket);
            continue;
         }
         string entryKey = StateKey(ticket, "ENTRY");
         string riskKey = StateKey(ticket, "RISK");
         string initVolKey = StateKey(ticket, "INITVOL");
         string stageKey = StateKey(ticket, "STAGE");
         string tpRemovedKey = StateKey(ticket, "TPREMOVED");
         if(!GlobalVariableCheck(entryKey) && GlobalVariableCheck(LegacyStateKey(ticket, "ENTRY"))) GlobalVariableSet(entryKey, GlobalVariableGet(LegacyStateKey(ticket, "ENTRY")));
         if(!GlobalVariableCheck(riskKey) && GlobalVariableCheck(LegacyStateKey(ticket, "RISK"))) GlobalVariableSet(riskKey, GlobalVariableGet(LegacyStateKey(ticket, "RISK")));
         if(!GlobalVariableCheck(initVolKey) && GlobalVariableCheck(LegacyStateKey(ticket, "INITVOL"))) GlobalVariableSet(initVolKey, GlobalVariableGet(LegacyStateKey(ticket, "INITVOL")));
         if(!GlobalVariableCheck(stageKey) && GlobalVariableCheck(LegacyStateKey(ticket, "STAGE"))) GlobalVariableSet(stageKey, GlobalVariableGet(LegacyStateKey(ticket, "STAGE")));
         if(!GlobalVariableCheck(entryKey)) SetState(entryKey, entry);
         if(!GlobalVariableCheck(riskKey)) SetState(riskKey, MathAbs(entry - sl));
         if(!GlobalVariableCheck(initVolKey)) SetState(initVolKey, volume);
         if(!GlobalVariableCheck(stageKey)) SetState(stageKey, 0.0);
         if(!GlobalVariableCheck(tpRemovedKey)) SetState(tpRemovedKey, 0.0);
         double initialEntry = ReadState(entryKey, entry);
         double riskDistance = ReadState(riskKey, MathAbs(entry - sl));
         double initialVolume = ReadState(initVolKey, volume);
         double stage = ReadState(stageKey, 0.0);
         if(initialEntry <= 0.0 || riskDistance <= 0.0 || initialVolume <= 0.0) continue;
         MqlTick tick;
         if(!SymbolInfoTick(symbol, tick)) continue;
         double pip = PipSize(symbol);
         if(pip <= 0.0) continue;
         double favorableDistance = (type == POSITION_TYPE_BUY) ? tick.bid - initialEntry : initialEntry - tick.ask;
         double profitPips = favorableDistance / pip;
         double rMultiple = favorableDistance / riskDistance;
         if(tp > 0.0 && ReadState(tpRemovedKey, 0.0) < 1.0)
         {
            if(ModifyProtection(ticket, symbol, type, sl, 0.0))
            {
               SetState(tpRemovedKey, 1.0);
               PrintFormat("[EA V22] MANAGEMENT CLAIMED | %s #%I64u | originalTP=%.*f removed | hardSL=%.*f retained", symbol, ticket, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), sl);
            }
         }
         if(stage < 1.0 && rMultiple >= V22_STAGE1_R)
         {
            double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double closeable = MathMax(0.0, volume - minVolume);
            double closeVolume = NormalizeVolumeDown(symbol, MathMin(initialVolume * 0.50, closeable));
            if(closeVolume > 0.0 && ClosePartial(ticket, symbol, type, closeVolume))
            {
               SetState(stageKey, 1.0); stage = 1.0;
               PrintFormat("[EA V22] PARTIAL TP1 | %s #%I64u | R=%.2f | profit=%.1f pips | closed=%.4f | target=50%%", symbol, ticket, rMultiple, profitPips, closeVolume);
               if(PositionSelectByTicket(ticket))
               {
                  double liveSL = PositionGetDouble(POSITION_SL);
                  double lock = (type == POSITION_TYPE_BUY) ? initialEntry + V22_BE_LOCK_PIPS * pip : initialEntry - V22_BE_LOCK_PIPS * pip;
                  if((type == POSITION_TYPE_BUY && lock > liveSL) || (type == POSITION_TYPE_SELL && (liveSL <= 0.0 || lock < liveSL))) ImproveStop(ticket, symbol, type, liveSL, lock);
               }
            }
            else if(closeVolume <= 0.0)
            {
               SetState(stageKey, 0.5); stage = 0.5;
               PrintFormat("[EA V22] PARTIAL TP1 UNAVAILABLE | %s #%I64u | initial=%.4f | brokerMin=%.4f | position remains protected", symbol, ticket, initialVolume, minVolume);
            }
         }
         if(stage >= 1.0 && stage < 2.0 && rMultiple >= V22_STAGE2_R)
         {
            if(PositionSelectByTicket(ticket)) volume = PositionGetDouble(POSITION_VOLUME);
            double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double closeable = MathMax(0.0, volume - minVolume);
            double closeVolume = NormalizeVolumeDown(symbol, MathMin(initialVolume * 0.30, closeable));
            if(closeVolume > 0.0 && ClosePartial(ticket, symbol, type, closeVolume))
            {
               SetState(stageKey, 2.0); stage = 2.0;
               PrintFormat("[EA V22] PARTIAL TP2 | %s #%I64u | R=%.2f | profit=%.1f pips | closed=%.4f | runner=remaining volume", symbol, ticket, rMultiple, profitPips, closeVolume);
            }
            else if(closeVolume <= 0.0)
            {
               SetState(stageKey, 1.5); stage = 1.5;
               PrintFormat("[EA V22] PARTIAL TP2 UNAVAILABLE | %s #%I64u | current=%.4f | brokerMin=%.4f | runner remains protected", symbol, ticket, volume, minVolume);
            }
         }
         if(profitPips >= V22_TRAIL_ACTIVATION_PIPS)
         {
            double trailPips = DynamicTrailingPips(profitPips);
            double desiredSL = (type == POSITION_TYPE_BUY) ? tick.bid - trailPips * pip : tick.ask + trailPips * pip;
            desiredSL = ClampTrailingStop(symbol, type, desiredSL);
            double currentSL = PositionGetDouble(POSITION_SL);
            if(ImproveStop(ticket, symbol, type, currentSL, desiredSL))
               PrintFormat("[EA V22] TRAIL | %s #%I64u | profit=%.1f pips | distance=%.1f pips | SL=%.*f", symbol, ticket, profitPips, trailPips, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), desiredSL);
         }
      }
   }
   void SendWebSocketMessage(ulong socket, string message)
   {
      if(socket == DATA_INVALID_SOCKET) return;
      uchar payload[];
      int payloadLength = StringToCharArray(message, payload, 0, StringLen(message));
      if(payloadLength <= 0) return;
      char frame[];
      int headerLength = 2;
      if(payloadLength <= 125)
      {
         ArrayResize(frame, 2 + payloadLength); frame[0] = (char)0x81; frame[1] = (char)payloadLength;
      }
      else if(payloadLength <= 65535)
      {
         ArrayResize(frame, 4 + payloadLength); frame[0] = (char)0x81; frame[1] = (char)126;
         frame[2] = (char)((payloadLength >> 8) & 0xFF); frame[3] = (char)(payloadLength & 0xFF); headerLength = 4;
      }
      else
      {
         ArrayResize(frame, 10 + payloadLength); frame[0] = (char)0x81; frame[1] = (char)127;
         ulong length = (ulong)payloadLength;
         for(int i = 0; i < 8; i++) { int shift = 56 - (i * 8); frame[2 + i] = (char)((length >> shift) & 0xFF); }
         headerLength = 10;
      }
      for(int i = 0; i < payloadLength; i++) frame[headerLength + i] = (char)payload[i];
      int totalLength = ArraySize(frame), sent = 0;
      while(sent < totalLength)
      {
         int result = send(socket, frame, totalLength - sent, 0);
         if(result <= 0) break;
         sent += result;
      }
   }
};

#endif
