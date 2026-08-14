//+------------------------------------------------------------------+
//| SocketBridgeEA.mq5                                               |
//| ForexScalperApp MT5 Execution Bridge V21.1                     |
//+------------------------------------------------------------------+
#property copyright "God Mode Scalper"
#property version   "21.1"
#property description "ForexScalperApp Swift/MT5 Execution Bridge V21.1"
#property strict

#include <CommandHandler.mqh>
#include <Data.mqh>
#include <WebSocketLib.mqh>
#include <SocketManager.mqh>
#include <Trade/Trade.mqh>
#include <JAson.mqh>

#define HTTP_PORT             8890
#define SOCKET_BUFFER_SIZE    65536
#define TIMER_INTERVAL_MS     20
#define MAGIC_NUMBER          888888
#define DEFAULT_DEVIATION     15
#define EA_INVALID_SOCKET     ((ulong)-1)

CSocketManager httpServer;
ulong httpClientSockets[];
ulong WebSocketClients[];
CCommandHandler *commandHandler = NULL;
CData *dataManager = NULL;
CTrade tradeControl;
datetime lastServerInitAttempt = 0;
datetime lastHeartbeat = 0;

string EscapeJsonString(const string value)
{
   string result = value;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\n", "\\n");
   return result;
}

double StopDistancePrice(const string symbol)
{
   const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   const long stops = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const long freeze = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(point, (double)MathMax(stops, freeze) * point);
}

double NormalizeStopPrice(const string symbol, const double price)
{
   if(price <= 0.0) return 0.0;
   return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
}

void BuildSafeStops(const string symbol, const ENUM_POSITION_TYPE positionType,
                    const double requestedSL, const double requestedTP,
                    double &safeSL, double &safeTP,
                    bool &changedSL, bool &changedTP)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) return;

   const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   const double distance = StopDistancePrice(symbol);
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   safeSL = NormalizeStopPrice(symbol, requestedSL);
   safeTP = NormalizeStopPrice(symbol, requestedTP);
   changedSL = false;
   changedTP = false;

   if(positionType == POSITION_TYPE_BUY)
   {
      if(safeSL > 0.0 && safeSL >= tick.bid - distance)
      {
         safeSL = NormalizeDouble(tick.bid - distance - point, digits);
         changedSL = true;
      }
      if(safeTP > 0.0 && safeTP <= tick.ask + distance)
      {
         safeTP = NormalizeDouble(tick.ask + distance + point, digits);
         changedTP = true;
      }
   }
   else if(positionType == POSITION_TYPE_SELL)
   {
      if(safeSL > 0.0 && safeSL <= tick.ask + distance)
      {
         safeSL = NormalizeDouble(tick.ask + distance + point, digits);
         changedSL = true;
      }
      if(safeTP > 0.0 && safeTP >= tick.bid - distance)
      {
         safeTP = NormalizeDouble(tick.bid - distance - point, digits);
         changedTP = true;
      }
   }
}

bool StopsAreValid(const string symbol, const ENUM_POSITION_TYPE positionType,
                   const double sl, const double tp, string &reason)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      reason = "Unable to read current market price";
      return false;
   }

   const double distance = StopDistancePrice(symbol);

   if(positionType == POSITION_TYPE_BUY)
   {
      if(sl > 0.0 && sl >= tick.bid - distance)
      {
         reason = StringFormat("BUY SL %.10f must be below Bid %.10f by at least %.10f", sl, tick.bid, distance);
         return false;
      }
      if(tp > 0.0 && tp <= tick.ask + distance)
      {
         reason = StringFormat("BUY TP %.10f must be above Ask %.10f by at least %.10f", tp, tick.ask, distance);
         return false;
      }
   }
   else if(positionType == POSITION_TYPE_SELL)
   {
      if(sl > 0.0 && sl <= tick.ask + distance)
      {
         reason = StringFormat("SELL SL %.10f must be above Ask %.10f by at least %.10f", sl, tick.ask, distance);
         return false;
      }
      if(tp > 0.0 && tp >= tick.bid - distance)
      {
         reason = StringFormat("SELL TP %.10f must be below Bid %.10f by at least %.10f", tp, tick.bid, distance);
         return false;
      }
   }

   reason = "";
   return true;
}

string HandleValidatedModifyRequest(const string body)
{
   CJAVal req;
   if(!req.Deserialize(body))
      return "{\"success\":false,\"retryable\":false,\"error\":\"Invalid JSON\"}";

   const long ticketValue = StringToInteger(req["ticket"].ToStr());
   if(ticketValue <= 0)
      return "{\"success\":false,\"retryable\":false,\"error\":\"A valid position ticket is required\"}";

   const ulong ticket = (ulong)ticketValue;
   if(!PositionSelectByTicket(ticket))
      return "{\"success\":false,\"retryable\":false,\"error\":\"Position not found\"}";

   const string symbol = PositionGetString(POSITION_SYMBOL);
   const ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   const double currentSL = PositionGetDouble(POSITION_SL);
   const double currentTP = PositionGetDouble(POSITION_TP);
   const double requestedSL = req["sl"].ToDbl();
   const double requestedTP = req["tp"].ToDbl();

   string keepSL = req["keep_sl"].ToStr();
   string keepTP = req["keep_tp"].ToStr();
   StringToLower(keepSL);
   StringToLower(keepTP);

   double targetSL = (keepSL == "true" || keepSL == "1") ? currentSL : requestedSL;
   double targetTP = (keepTP == "true" || keepTP == "1") ? currentTP : requestedTP;
   double safeSL = targetSL;
   double safeTP = targetTP;
   bool changedSL = false;
   bool changedTP = false;

   BuildSafeStops(symbol, positionType, targetSL, targetTP, safeSL, safeTP, changedSL, changedTP);

   string validationReason = "";
   if(!StopsAreValid(symbol, positionType, safeSL, safeTP, validationReason))
   {
      Print("[EA V21.1] MODIFY validation failed ticket=", ticket, " symbol=", symbol, " reason=", validationReason);
      return StringFormat(
         "{\"success\":false,\"retryable\":true,\"error\":\"Invalid stops\",\"reason\":\"%s\",\"ticket\":%I64d,\"symbol\":\"%s\",\"requested_sl\":%s,\"requested_tp\":%s,\"adjusted_sl\":%s,\"adjusted_tp\":%s}",
         EscapeJsonString(validationReason), (long)ticket, EscapeJsonString(symbol),
         DoubleToString(targetSL, 10), DoubleToString(targetTP, 10),
         DoubleToString(safeSL, 10), DoubleToString(safeTP, 10));
   }

   tradeControl.SetExpertMagicNumber(MAGIC_NUMBER);
   tradeControl.SetTypeFillingBySymbol(symbol);
   tradeControl.SetDeviationInPoints(DEFAULT_DEVIATION);

   bool modified = false;
   uint retcode = 0;

   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(!PositionSelectByTicket(ticket)) break;

      const ENUM_POSITION_TYPE liveType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const double liveSL = PositionGetDouble(POSITION_SL);
      const double liveTP = PositionGetDouble(POSITION_TP);
      if(keepSL == "true" || keepSL == "1") targetSL = liveSL;
      if(keepTP == "true" || keepTP == "1") targetTP = liveTP;

      BuildSafeStops(symbol, liveType, targetSL, targetTP, safeSL, safeTP, changedSL, changedTP);
      string liveReason = "";
      if(!StopsAreValid(symbol, liveType, safeSL, safeTP, liveReason))
      {
         Print("[EA V21.1] MODIFY retry ", attempt + 1, " validation: ", liveReason);
         Sleep(50);
         continue;
      }

      ResetLastError();
      modified = tradeControl.PositionModify(ticket, safeSL, safeTP);
      retcode = tradeControl.ResultRetcode();
      if(modified && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL))
      {
         Print("[EA V21.1] MODIFY accepted ticket=", ticket, " symbol=", symbol,
               " SL=", DoubleToString(safeSL, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
               " TP=", DoubleToString(safeTP, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
         break;
      }

      Print("[EA V21.1] MODIFY rejected attempt=", attempt + 1, " ticket=", ticket,
            " retcode=", retcode, " comment=", tradeControl.ResultComment());
      Sleep(50);
   }

   const bool success = modified && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL);
   CJAVal result;
   result["success"] = success;
   result["retryable"] = !success;
   result["operation"] = "modify";
   result["retcode"] = (long)retcode;
   result["retcode_description"] = tradeControl.ResultRetcodeDescription();
   result["ticket"] = (long)ticket;
   result["symbol"] = symbol;
   result["requested_sl"] = targetSL;
   result["requested_tp"] = targetTP;
   result["adjusted_sl"] = safeSL;
   result["adjusted_tp"] = safeTP;
   result["sl_adjusted"] = changedSL;
   result["tp_adjusted"] = changedTP;
   result["bid"] = SymbolInfoDouble(symbol, SYMBOL_BID);
   result["ask"] = SymbolInfoDouble(symbol, SYMBOL_ASK);
   result["point"] = SymbolInfoDouble(symbol, SYMBOL_POINT);
   result["stops_level"] = (long)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   result["freeze_level"] = (long)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   result["comment"] = tradeControl.ResultComment();
   if(!success) result["error"] = "MT5 rejected SL/TP modification after broker-aware validation/retries";
   return result.Serialize();
}

int OnInit()
{
   if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
   {
      Print("[EA V21.1] CRITICAL: DLL imports must be enabled.");
      return INIT_FAILED;
   }
   char wsaData[];
   ArrayResize(wsaData, 400);
   if(WSAStartup(0x0202, wsaData) != 0)
   {
      Print("[EA V21.1] CRITICAL: WSAStartup failed.");
      return INIT_FAILED;
   }
   tradeControl.SetExpertMagicNumber(MAGIC_NUMBER);
   tradeControl.SetDeviationInPoints(DEFAULT_DEVIATION);
   tradeControl.SetAsyncMode(false);
   if(!InitializeWebSocketServer())
   {
      Print("[EA V21.1] CRITICAL: bridge initialization failed on port ", HTTP_PORT);
      WSACleanup();
      return INIT_FAILED;
   }
   EventSetMillisecondTimer(TIMER_INTERVAL_MS);
   Print("==================================================");
   Print(" FOREXSCALPERAPP MT5 EXECUTION BRIDGE V21.1");
   Print(" Broker-aware SL/TP validation and retry enabled");
   Print(" Partial TP: 50% @ 1R | 30% @ 2R | 20% runner");
   Print(" Trailing: activates at 5 pips; dynamic distance");
   Print(" Runner: unlimited hold; no EA max-TP/time exit");
   Print(" Hard SL: retained as emergency protection");
   Print(" Bridge port: ", HTTP_PORT, " | Magic: ", MAGIC_NUMBER);
   Print(" Status: ONLINE");
   Print("==================================================");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   CleanupHandlers();
   CloseAllConnections();
   Print("FOREXSCALPERAPP EA V21.1 STOPPED. Reason=", reason);
}

void OnTick()
{
   if(dataManager == NULL) return;
   if(ArraySize(WebSocketClients) > 0) SendUpdateToClients();
   else dataManager.SendCurrentPrices(EA_INVALID_SOCKET);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(dataManager == NULL || !dataManager.isTrackingOrderEvent) return;
   for(int i = ArraySize(WebSocketClients) - 1; i >= 0; i--)
   {
      ulong socket = WebSocketClients[i];
      if(socket == EA_INVALID_SOCKET) continue;
      if(!IsSocketAlive(socket))
      {
         closesocket(socket);
         ArrayRemove(WebSocketClients, i);
         continue;
      }
      dataManager.HandleTradeTransaction(trans, request, result, socket);
   }
}

void OnTimer()
{
   datetime now = TimeCurrent();
   if(!httpServer.IsValid())
   {
      if((now - lastServerInitAttempt) >= 10) InitializeWebSocketServer();
      return;
   }
   AcceptNewClients();
   ProcessHttpClients();
   if((now - lastHeartbeat) >= 60)
   {
      Print("[EA V21.1] heartbeat | WebSocket clients=", ArraySize(WebSocketClients), " | MT5 positions=", PositionsTotal());
      lastHeartbeat = now;
   }
}

bool InitializeWebSocketServer()
{
   lastServerInitAttempt = TimeCurrent();
   if(!httpServer.CreateServer(HTTP_PORT))
   {
      Print("[EA V21.1] Failed to bind bridge port ", HTTP_PORT);
      return false;
   }
   CleanupHandlers();
   commandHandler = new CCommandHandler();
   dataManager = new CData();
   if(commandHandler == NULL || dataManager == NULL)
   {
      Print("[EA V21.1] CRITICAL: handler allocation failed.");
      CleanupHandlers();
      httpServer.Close();
      return false;
   }
   commandHandler.SetPriceSender(dataManager);
   Print("[EA V21.1] Bridge server listening on port ", HTTP_PORT);
   return true;
}

void AcceptNewClients()
{
   ulong newSocket = (ulong)httpServer.AcceptClient();
   if(newSocket == EA_INVALID_SOCKET) return;
   int count = ArraySize(httpClientSockets);
   ArrayResize(httpClientSockets, count + 1);
   httpClientSockets[count] = newSocket;
}

void ProcessHttpClients()
{
   for(int i = ArraySize(httpClientSockets) - 1; i >= 0; i--)
   {
      ulong socket = httpClientSockets[i];
      if(socket == EA_INVALID_SOCKET)
      {
         ArrayRemove(httpClientSockets, i);
         continue;
      }
      char buffer[SOCKET_BUFFER_SIZE];
      int received = recv(socket, buffer, ArraySize(buffer), 0);
      if(received > 0)
      {
         string message = CharArrayToString(buffer, 0, received);
         HttpRequest request = ParseHttpRequest(message);
         if(request.isWebSocket)
         {
            if(PerformWebSocketHandshake(socket, message))
            {
               int count = ArraySize(WebSocketClients);
               ArrayResize(WebSocketClients, count + 1);
               WebSocketClients[count] = socket;
               ArrayRemove(httpClientSockets, i);
               Print("[EA V21.1] WebSocket connected. Clients=", count + 1);
            }
            else
            {
               closesocket(socket);
               ArrayRemove(httpClientSockets, i);
            }
            continue;
         }

         if(request.path == "/v1/order/modify" || request.path == "/api/mt5/modify" || request.path == "/modify")
         {
            string response = HandleValidatedModifyRequest(request.body);
            string http = HttpResponse(200, response);
            char responseBytes[];
            int responseLength = StringToCharArray(http, responseBytes, 0, StringLen(http));
            if(responseLength > 0) send(socket, responseBytes, StringLen(http), 0);
            closesocket(socket);
            ArrayRemove(httpClientSockets, i);
            continue;
         }

         if(commandHandler != NULL) commandHandler.HandleCommand(socket, request);
         closesocket(socket);
         ArrayRemove(httpClientSockets, i);
         continue;
      }
      if(received == 0 || (received < 0 && WSAGetLastError() != 10035))
      {
         closesocket(socket);
         ArrayRemove(httpClientSockets, i);
      }
   }
}

HttpRequest ParseHttpRequest(string message)
{
   HttpRequest request;
   request.method = "";
   request.path = "";
   request.query = "";
   request.body = "";
   request.isWebSocket = false;
   string lowerMessage = message;
   StringToLower(lowerMessage);
   request.isWebSocket = (StringFind(lowerMessage, "upgrade: websocket") >= 0);
   int firstSpace = StringFind(message, " ");
   if(firstSpace >= 0)
   {
      request.method = StringSubstr(message, 0, firstSpace);
      int secondSpace = StringFind(message, " ", firstSpace + 1);
      if(secondSpace > firstSpace)
      {
         string fullPath = StringSubstr(message, firstSpace + 1, secondSpace - firstSpace - 1);
         int questionMark = StringFind(fullPath, "?");
         if(questionMark >= 0)
         {
            request.path = StringSubstr(fullPath, 0, questionMark);
            request.query = StringSubstr(fullPath, questionMark + 1);
         }
         else request.path = fullPath;
      }
   }
   int bodyStart = StringFind(message, "\r\n\r\n");
   if(bodyStart >= 0) request.body = StringSubstr(message, bodyStart + 4);
   return request;
}

string HttpResponse(int statusCode, string body)
{
   string statusText = "OK";
   if(statusCode == 204) statusText = "No Content";
   if(statusCode == 400) statusText = "Bad Request";
   if(statusCode == 404) statusText = "Not Found";
   if(statusCode == 500) statusText = "Internal Server Error";
   return "HTTP/1.1 " + IntegerToString(statusCode) + " " + statusText + "\r\n"
          "Content-Type: application/json; charset=utf-8\r\n"
          "Access-Control-Allow-Origin: *\r\n"
          "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
          "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
          "Cache-Control: no-cache\r\n"
          "Connection: close\r\n"
          "Content-Length: " + IntegerToString(StringLen(body)) + "\r\n\r\n" + body;
}

bool IsSocketAlive(ulong socket)
{
   if(socket == EA_INVALID_SOCKET) return false;
   return IsSocketConnected(socket);
}

void SendUpdateToClients()
{
   for(int i = ArraySize(WebSocketClients) - 1; i >= 0; i--)
   {
      ulong socket = WebSocketClients[i];
      if(!IsSocketAlive(socket))
      {
         closesocket(socket);
         ArrayRemove(WebSocketClients, i);
         continue;
      }
      if(dataManager == NULL) continue;
      if(dataManager.isTrackingPrice) dataManager.SendCurrentPrices(socket);
      if(dataManager.isTrackingOhlc) dataManager.SendCurrentOhlcs(socket);
      if(dataManager.isTrackingMbook) dataManager.SendCurrentMbook(socket);
   }
}

void CloseAllConnections()
{
   for(int i = 0; i < ArraySize(WebSocketClients); i++)
      if(WebSocketClients[i] != EA_INVALID_SOCKET) closesocket(WebSocketClients[i]);
   ArrayResize(WebSocketClients, 0);
   for(int i = 0; i < ArraySize(httpClientSockets); i++)
      if(httpClientSockets[i] != EA_INVALID_SOCKET) closesocket(httpClientSockets[i]);
   ArrayResize(httpClientSockets, 0);
   httpServer.Close();
   WSACleanup();
}

void CleanupHandlers()
{
   if(commandHandler != NULL)
   {
      commandHandler.Destroy();
      delete commandHandler;
      commandHandler = NULL;
   }
   if(dataManager != NULL)
   {
      delete dataManager;
      dataManager = NULL;
   }
}
