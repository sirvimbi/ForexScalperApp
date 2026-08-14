//+------------------------------------------------------------------+
//| Data.mqh                                                         |
//| GOD MODE V21.0 - SWIFT BROADCAST + BROKER-SIDE TRADE PROTECTION |
//+------------------------------------------------------------------+
#ifndef DATA_MQH
#define DATA_MQH

#property strict

#include <EA_V21_BUILD.mqh>
#include <socketlib.mqh>
#include <JAson.mqh>
#include <Trade/Trade.mqh>

#define DATA_INVALID_SOCKET ((ulong)-1)
#define DATA_PROTOCOL_VERSION FOREX_SCALPER_EA_VERSION
#define EA_V21_VERSION FOREX_SCALPER_EA_VERSION
#define EA_V21_MAGIC FOREX_SCALPER_EA_MAGIC
#define V21_MIN_PROFIT_PIPS 5.0
#define V21_STAGE1_R        1.0
#define V21_STAGE2_R        2.0

class CData
{
public:
   bool isTrackingPrice;
   bool isTrackingOhlc;
   bool isTrackingMbook;
   bool isTrackingOrderEvent;

private:
   CTrade m_trade;
   bool   m_versionLogged;

public:
   CData()
   {
      isTrackingPrice      = true;
      isTrackingOhlc       = false;
      isTrackingMbook      = false;
      isTrackingOrderEvent = true;
      m_versionLogged      = false;

      m_trade.SetExpertMagicNumber(EA_V21_MAGIC);
      m_trade.SetDeviationInPoints(15);
      m_trade.SetAsyncMode(false);
   }

   void SendCurrentPrices(ulong socket)
   {
      // Protection is deliberately before the socket guard. This lets the
      // standalone EA keep trailing/partial protection active even when the
      // Swift WebSocket is disconnected.
      ManageProtectedPositions();

      if(socket == DATA_INVALID_SOCKET) return;

      if(!m_versionLogged)
      {
         Print("==================================================");
         Print(" SWIFT/MT5 EXECUTION BRIDGE EA V21.0");
         Print(" Partial TP: 50% @ 1R | 30% @ 2R | 20% runner");
         Print(" Trailing: active >= 5 pips, dynamic distance");
         Print(" Runner: no EA time exit / no runner TP cap");
         Print(" Hard SL: retained as emergency protection");
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

   void HandleTradeTransaction(
      const MqlTradeTransaction &trans,
      const MqlTradeRequest &request,
      const MqlTradeResult &result,
      ulong socket
   )
   {
      request;
      result;
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
      else
      {
         json["ticket"] = (long)trans.position;
      }

      SendWebSocketMessage(socket, json.Serialize());
   }

private:
   string StateKey(ulong ticket, string suffix)
   {
      return "FSV21_" + IntegerToString((long)ticket) + "_" + suffix;
   }

   double PipSize(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(digits == 3 || digits == 5) return point * 10.0;
      return point;
   }

   double NormalizePrice(string symbol, double price)
   {
      return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
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
      normalized = NormalizeDouble(normalized, 8);
      if(normalized < minVolume) return 0.0;
      return normalized;
   }

   ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol)
   {
      long flags = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      long execution = SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);

      if(execution != SYMBOL_TRADE_EXECUTION_MARKET)
         return ORDER_FILLING_RETURN;
      if((flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;
      if((flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;
      return ORDER_FILLING_IOC;
   }

   bool ModifyProtection(ulong ticket, string symbol, double newSL, double newTP)
   {
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
         PrintFormat("[EA V21] SLTP modify failed | %s #%I64u | error=%d | retcode=%u | %s",
                     symbol, ticket, GetLastError(), result.retcode, result.comment);
         return false;
      }

      if(result.retcode != TRADE_RETCODE_DONE &&
         result.retcode != TRADE_RETCODE_DONE_PARTIAL &&
         result.retcode != TRADE_RETCODE_PLACED)
      {
         PrintFormat("[EA V21] SLTP rejected | %s #%I64u | retcode=%u | %s",
                     symbol, ticket, result.retcode, result.comment);
         return false;
      }
      return true;
   }

   bool ClosePartial(ulong ticket, string symbol, ENUM_POSITION_TYPE positionType, double volume)
   {
      volume = NormalizeVolumeDown(symbol, volume);
      if(volume <= 0.0) return false;

      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol = symbol;
      request.volume = volume;
      request.magic = EA_V21_MAGIC;
      request.deviation = 15;
      request.type_filling = GetFillingMode(symbol);

      if(positionType == POSITION_TYPE_BUY)
      {
         request.type = ORDER_TYPE_SELL;
         request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
      }
      else
      {
         request.type = ORDER_TYPE_BUY;
         request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      }
      request.comment = "FS V21 PARTIAL";

      ResetLastError();
      if(!OrderSend(request, result))
      {
         PrintFormat("[EA V21] Partial close failed | %s #%I64u | volume=%.2f | error=%d | retcode=%u | %s",
                     symbol, ticket, volume, GetLastError(), result.retcode, result.comment);
         return false;
      }

      if(result.retcode != TRADE_RETCODE_DONE &&
         result.retcode != TRADE_RETCODE_DONE_PARTIAL &&
         result.retcode != TRADE_RETCODE_PLACED)
      {
         PrintFormat("[EA V21] Partial close rejected | %s #%I64u | volume=%.2f | retcode=%u | %s",
                     symbol, ticket, volume, result.retcode, result.comment);
         return false;
      }
      return true;
   }

   void ManageProtectedPositions()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != EA_V21_MAGIC) continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);

         // Never operate without a broker-side hard SL.
         if(symbol == "" || sl <= 0.0 || entry <= 0.0 || volume <= 0.0) continue;

         string entryKey = StateKey(ticket, "ENTRY");
         string riskKey = StateKey(ticket, "RISK");
         string initVolKey = StateKey(ticket, "INITVOL");
         string stageKey = StateKey(ticket, "STAGE");

         if(!GlobalVariableCheck(entryKey)) GlobalVariableSet(entryKey, entry);
         if(!GlobalVariableCheck(riskKey)) GlobalVariableSet(riskKey, MathAbs(entry - sl));
         if(!GlobalVariableCheck(initVolKey)) GlobalVariableSet(initVolKey, volume);
         if(!GlobalVariableCheck(stageKey)) GlobalVariableSet(stageKey, 0.0);

         double initialEntry = GlobalVariableGet(entryKey);
         double riskDistance = GlobalVariableGet(riskKey);
         double initialVolume = GlobalVariableGet(initVolKey);
         double stageValue = GlobalVariableGet(stageKey);
         if(initialEntry <= 0.0 || riskDistance <= 0.0 || initialVolume <= 0.0) continue;

         MqlTick tick;
         if(!SymbolInfoTick(symbol, tick)) continue;

         double pip = PipSize(symbol);
         if(pip <= 0.0) continue;

         double favorableDistance = (type == POSITION_TYPE_BUY)
                                    ? (tick.bid - initialEntry)
                                    : (initialEntry - tick.ask);
         double profitPips = favorableDistance / pip;
         double rMultiple = favorableDistance / riskDistance;

         // The original maximum TP is removed so the 20% runner cannot be
         // capped. The hard SL remains in force as emergency protection.
         if(tp != 0.0 && ModifyProtection(ticket, symbol, sl, 0.0))
         {
            PrintFormat("[EA V21] RUNNER UNCAP | %s #%I64u | originalTP=%.*f removed; hardSL=%.*f retained",
                        symbol, ticket,
                        (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), tp,
                        (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), sl);
         }

         // 50% partial at 1R.
         if(stageValue < 1.0 && rMultiple >= V21_STAGE1_R)
         {
            double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double closeable = MathMax(0.0, volume - minVolume);
            double closeVolume = NormalizeVolumeDown(symbol, MathMin(initialVolume * 0.50, closeable));

            if(closeVolume > 0.0 && ClosePartial(ticket, symbol, type, closeVolume))
            {
               GlobalVariableSet(stageKey, 1.0);
               stageValue = 1.0;
               PrintFormat("[EA V21] PARTIAL TP1 | %s #%I64u | R=%.2f | profit=%.1f pips | closed=%.2f | remaining=50%%",
                           symbol, ticket, rMultiple, profitPips, closeVolume);
            }
         }

         // 30% partial at 2R; the remaining 20% is the unlimited runner.
         if(stageValue < 2.0 && rMultiple >= V21_STAGE2_R)
         {
            if(PositionSelectByTicket(ticket)) volume = PositionGetDouble(POSITION_VOLUME);
            double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double closeable = MathMax(0.0, volume - minVolume);
            double closeVolume = NormalizeVolumeDown(symbol, MathMin(initialVolume * 0.30, closeable));

            if(closeVolume > 0.0 && ClosePartial(ticket, symbol, type, closeVolume))
            {
               GlobalVariableSet(stageKey, 2.0);
               stageValue = 2.0;
               PrintFormat("[EA V21] PARTIAL TP2 | %s #%I64u | R=%.2f | profit=%.1f pips | closed=%.2f | runner=20%%",
                           symbol, ticket, rMultiple, profitPips, closeVolume);
            }
         }

         // Runner has no time exit and no maximum TP. Only trailing protects it.
         if(profitPips >= V21_MIN_PROFIT_PIPS)
         {
            double trailPips = DynamicTrailingPips(profitPips);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double stopLevelPoints = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double trailDistance = MathMax(trailPips * pip, stopLevelPoints * point);
            double desiredSL;

            if(type == POSITION_TYPE_BUY)
            {
               desiredSL = NormalizePrice(symbol, tick.bid - trailDistance);
               if(desiredSL > 0.0 && desiredSL < tick.bid && (sl <= 0.0 || desiredSL > sl))
               {
                  if(ModifyProtection(ticket, symbol, desiredSL, 0.0))
                     PrintFormat("[EA V21] TRAIL | %s #%I64u | profit=%.1f pips | trail=%.1f pips | SL=%.*f",
                                 symbol, ticket, profitPips, trailPips,
                                 (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), desiredSL);
               }
            }
            else
            {
               desiredSL = NormalizePrice(symbol, tick.ask + trailDistance);
               if(desiredSL > tick.ask && (sl <= 0.0 || desiredSL < sl))
               {
                  if(ModifyProtection(ticket, symbol, desiredSL, 0.0))
                     PrintFormat("[EA V21] TRAIL | %s #%I64u | profit=%.1f pips | trail=%.1f pips | SL=%.*f",
                                 symbol, ticket, profitPips, trailPips,
                                 (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), desiredSL);
               }
            }
         }
      }
   }

   double DynamicTrailingPips(double profitPips)
   {
      if(profitPips >= 80.0) return 12.0;
      if(profitPips >= 40.0) return 10.0;
      if(profitPips >= 25.0) return 8.0;
      if(profitPips >= 15.0) return 6.0;
      if(profitPips >= 10.0) return 4.5;
      return 3.0;
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
         ArrayResize(frame, 2 + payloadLength);
         frame[0] = (char)0x81;
         frame[1] = (char)payloadLength;
      }
      else if(payloadLength <= 65535)
      {
         ArrayResize(frame, 4 + payloadLength);
         frame[0] = (char)0x81;
         frame[1] = (char)126;
         frame[2] = (char)((payloadLength >> 8) & 0xFF);
         frame[3] = (char)(payloadLength & 0xFF);
         headerLength = 4;
      }
      else
      {
         ArrayResize(frame, 10 + payloadLength);
         frame[0] = (char)0x81;
         frame[1] = (char)127;
         ulong length = (ulong)payloadLength;
         for(int i = 0; i < 8; i++)
         {
            int shift = 56 - (i * 8);
            frame[2 + i] = (char)((length >> shift) & 0xFF);
         }
         headerLength = 10;
      }

      for(int i = 0; i < payloadLength; i++) frame[headerLength + i] = (char)payload[i];

      int totalLength = ArraySize(frame);
      int sent = 0;
      while(sent < totalLength)
      {
         int result = send(socket, frame, totalLength - sent, 0);
         if(result <= 0) break;
         sent += result;
      }
   }
};

#endif
