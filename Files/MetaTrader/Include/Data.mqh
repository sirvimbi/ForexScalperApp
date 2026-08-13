//+------------------------------------------------------------------+
//| Data.mqh                                                         |
//| GOD MODE V10.6 SWIFT BROADCAST ENGINE                            |
//+------------------------------------------------------------------+
#ifndef DATA_MQH
#define DATA_MQH

#property strict

#include <socketlib.mqh>
#include <JAson.mqh>

#define DATA_INVALID_SOCKET ((ulong)-1)
#define DATA_PROTOCOL_VERSION "10.6"

class CData
{
public:
   bool isTrackingPrice;
   bool isTrackingOhlc;
   bool isTrackingMbook;
   bool isTrackingOrderEvent;

   CData()
   {
      isTrackingPrice      = true;
      isTrackingOhlc       = false;
      isTrackingMbook      = false;
      isTrackingOrderEvent = true;
   }

   void SendCurrentPrices(ulong socket)
   {
      if(socket == DATA_INVALID_SOCKET)
         return;

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
         if(symbol == "")
            continue;

         MqlTick tick;
         if(!SymbolInfoTick(symbol, tick))
            continue;

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
      // Reserved for future live OHLC broadcasting.
   }

   void SendCurrentMbook(ulong socket)
   {
      // Reserved for future market-depth broadcasting.
   }

   void HandleTradeTransaction(
      const MqlTradeTransaction &trans,
      const MqlTradeRequest &request,
      const MqlTradeResult &result,
      ulong socket
   )
   {
      request;
      result;

      if(!isTrackingOrderEvent || socket == DATA_INVALID_SOCKET)
         return;

      CJAVal json;
      json["type"] = "trade_event";
      json["version"] = DATA_PROTOCOL_VERSION;
      json["event_id"] = IntegerToString((long)GetTickCount64());
      json["timestamp"] = (long)TimeCurrent();
      json["trans_type"] = (long)trans.type;
      json["symbol"] = trans.symbol;
      json["deal"] = (long)trans.deal;
      json["order"] = (long)trans.order;
      json["position"] = (long)trans.position;

      if(trans.type == TRADE_TRANSACTION_DEAL_ADD &&
         trans.deal > 0 &&
         HistoryDealSelect(trans.deal))
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
   void SendWebSocketMessage(ulong socket, string message)
   {
      if(socket == DATA_INVALID_SOCKET)
         return;

      uchar payload[];
      int payloadLength = StringToCharArray(message, payload, 0, StringLen(message));
      if(payloadLength <= 0)
         return;

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

      for(int i = 0; i < payloadLength; i++)
         frame[headerLength + i] = (char)payload[i];

      int totalLength = ArraySize(frame);
      int sent = 0;

      while(sent < totalLength)
      {
         char chunk[];
         int remaining = totalLength - sent;
         ArrayResize(chunk, remaining);
         for(int i = 0; i < remaining; i++)
            chunk[i] = frame[sent + i];

         int result = send(socket, chunk, remaining, 0);
         if(result <= 0)
            break;
         sent += result;
      }
   }
};

#endif