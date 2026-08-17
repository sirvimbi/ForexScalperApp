//+------------------------------------------------------------------+
//| SocketBridgeEA.mq5                                               |
//| ForexScalperApp MT5 Execution Bridge V23.0                     |
//+------------------------------------------------------------------+
#property copyright "God Mode Scalper"
#property version   "23.0"
#property description "ForexScalperApp Swift/MT5 Execution Bridge V23.0"
#property strict

#include <CommandHandlerV22.mqh>
#include <PositionManagerV23.mqh>
#include <Data.mqh>
#include <WebSocketLib.mqh>
#include <SocketManager.mqh>
#include <Trade/Trade.mqh>

#define HTTP_PORT             8890
#define SOCKET_BUFFER_SIZE    65536
#define TIMER_INTERVAL_MS     20
#define MAGIC_NUMBER          888888
#define DEFAULT_DEVIATION     15
#define EA_INVALID_SOCKET     ((ulong)-1)

CSocketManager httpServer;
ulong httpClientSockets[];
ulong WebSocketClients[];
CCommandHandlerV22 *commandHandler = NULL;
CData *dataManager = NULL;
CTrade tradeControl;
CPositionManagerV23 positionManager;
datetime lastServerInitAttempt = 0;
datetime lastHeartbeat = 0;

int OnInit()
{
   if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
   {
      Print("[EA V23.0] CRITICAL: DLL imports must be enabled.");
      return INIT_FAILED;
   }
   char wsaData[];
   ArrayResize(wsaData, 400);
   if(WSAStartup(0x0202, wsaData) != 0)
   {
      Print("[EA V23.0] CRITICAL: WSAStartup failed.");
      return INIT_FAILED;
   }
   tradeControl.SetExpertMagicNumber(MAGIC_NUMBER);
   tradeControl.SetDeviationInPoints(DEFAULT_DEVIATION);
   tradeControl.SetAsyncMode(false);
   if(!InitializeWebSocketServer())
   {
      Print("[EA V23.0] CRITICAL: bridge initialization failed on port ", HTTP_PORT);
      WSACleanup();
      return INIT_FAILED;
   }
   EventSetMillisecondTimer(TIMER_INTERVAL_MS);
   Print("==================================================");
   Print(" FOREXSCALPERAPP MT5 EXECUTION BRIDGE V23.0");
   Print(" Strategy authority: SWIFT | Protection authority: EA V23");
   Print(" Position lifecycle: TP1/TP2/TP3 + breakeven + forward-only trailing");
   Print(" Close/modify success requires broker retcode AND resulting-state verification");
   Print(" Runner: TP3 closes the remaining broker position exactly once");
   Print(" Hard SL: mandatory emergency protection");
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
   Print("FOREXSCALPERAPP EA V23.0 STOPPED. Reason=", reason);
}

void OnTick()
{
   // Position management is broker-side and continues independently of Swift/WebSocket availability.
   positionManager.ManageAll();

   if(dataManager == NULL) return;
   if(ArraySize(WebSocketClients) > 0) SendUpdateToClients();
   else dataManager.SendCurrentPrices(EA_INVALID_SOCKET);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
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
      Print("[EA V23.0] heartbeat | WebSocket clients=", ArraySize(WebSocketClients),
            " | MT5 positions=", PositionsTotal());
      lastHeartbeat = now;
   }
}

bool InitializeWebSocketServer()
{
   lastServerInitAttempt = TimeCurrent();
   if(!httpServer.CreateServer(HTTP_PORT))
   {
      Print("[EA V23.0] Failed to bind bridge port ", HTTP_PORT);
      return false;
   }
   CleanupHandlers();
   commandHandler = new CCommandHandlerV22();
   dataManager = new CData();
   if(commandHandler == NULL || dataManager == NULL)
   {
      Print("[EA V23.0] CRITICAL: handler allocation failed.");
      CleanupHandlers();
      httpServer.Close();
      return false;
   }
   commandHandler.SetPriceSender(dataManager);
   Print("[EA V23.0] Bridge server listening on port ", HTTP_PORT);
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
               Print("[EA V23.0] WebSocket connected. Clients=", count + 1);
            }
            else
            {
               closesocket(socket);
               ArrayRemove(httpClientSockets, i);
            }
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
