//+------------------------------------------------------------------+
//| Data.mqh                                                         |
//| ForexScalperApp MT5 bridge V23 - market/event transport          |
//+------------------------------------------------------------------+
#ifndef DATA_MQH
#define DATA_MQH

#property strict

#include <EA_V22_BUILD.mqh>
#include <socketlib.mqh>
#include <JAson.mqh>
#include <Trade/Trade.mqh>
#include <PositionManagerV23.mqh>

#define DATA_INVALID_SOCKET ((ulong)-1)
#define DATA_PROTOCOL_VERSION FOREX_SCALPER_EA_VERSION
#define EA_V23_MAGIC 888888

class CData
{
public:
   bool isTrackingPrice;
   bool isTrackingOhlc;
   bool isTrackingMbook;
   bool isTrackingOrderEvent;

private:
   CPositionManagerV23 m_positionManager;
   bool m_versionLogged;

public:
   CData()
   {
      isTrackingPrice = true;
      isTrackingOhlc = false;
      isTrackingMbook = false;
      isTrackingOrderEvent = true;
      m_versionLogged = false;
   }

   void SendCurrentPrices(ulong socket)
   {
      // Protection runs independently of WebSocket connectivity.
      m_positionManager.Manage();
      if(socket == DATA_INVALID_SOCKET) return;

      if(!m_versionLogged)
      {
         Print("==================================================");
         Print(" FOREXSCALPERAPP MT5 EXECUTION BRIDGE V23.0");
         Print(" Strategy authority: SWIFT | Protection authority: EA V23");
         Print(" TP1/TP2/TP3, breakeven and trailing are settings-driven");
         Print(" Broker stop/freeze and volume-step validation enabled");
         Print(" Position-management state persists across EA restarts");
         Print(" Swift trade monitor: observation / unprofitable exits only");
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

   void SendCurrentOhlcs(ulong socket)
   {
      // OHLC subscription remains supported by the command contract.
      // Candle history is served by CommandHandler; no duplicate polling is needed here.
      socket;
   }

   void SendCurrentMbook(ulong socket)
   {
      // Market-book subscription remains intentionally disabled unless enabled by the bridge.
      socket;
   }

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
