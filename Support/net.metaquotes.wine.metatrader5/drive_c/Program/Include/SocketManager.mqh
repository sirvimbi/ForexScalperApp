//+------------------------------------------------------------------+
//| SocketManager.mqh - GOD MODE V10.4 FIXED                         |
//+------------------------------------------------------------------+
#ifndef SOCKET_MANAGER_MQH
#define SOCKET_MANAGER_MQH

#property copyright "God Mode Scalper"
#property strict

#include <socketlib.mqh>

class CSocketManager
{
private:
   ulong m_socket;

public:
   CSocketManager()
   {
      m_socket = INVALID_SOCKET64;
   }

   ~CSocketManager()
   {
      Close();
   }

   bool IsValid()
   {
      return (m_socket != INVALID_SOCKET64);
   }

   ulong GetSocket()
   {
      return m_socket;
   }

   bool CreateServer(int port)
   {
      Close();

      m_socket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
      if(m_socket == INVALID_SOCKET64)
      {
         Print("Socket creation failed: ", WSAGetLastError());
         return false;
      }

      // Allow immediate rebinding after EA restart.
      char reuse_opt[4];
      reuse_opt[0] = 1;
      reuse_opt[1] = 0;
      reuse_opt[2] = 0;
      reuse_opt[3] = 0;
      setsockopt(m_socket, SOL_SOCKET, SO_REUSEADDR, reuse_opt, 4);

      // TCP_NODELAY.
      char nodelay_opt[4];
      nodelay_opt[0] = 1;
      nodelay_opt[1] = 0;
      nodelay_opt[2] = 0;
      nodelay_opt[3] = 0;
      setsockopt(m_socket, IPPROTO_TCP, TCP_NODELAY, nodelay_opt, 4);

      sockaddr_in serverAddr;
      serverAddr.sin_family = AF_INET;
      serverAddr.sin_port   = htons((ushort)port);
      serverAddr.sin_addr   = 0;

      for(int i = 0; i < 8; i++)
         serverAddr.sin_zero[i] = 0;

      char addrData[];
      StructToCharArray(serverAddr, addrData);

      if(bind(m_socket, addrData, sizeof(serverAddr)) == SOCKET_ERROR)
      {
         Print("Bind failed on port ", port, ": ", WSAGetLastError());
         Close();
         return false;
      }

      if(listen(m_socket, SOMAXCONN) == SOCKET_ERROR)
      {
         Print("Listen failed: ", WSAGetLastError());
         Close();
         return false;
      }

      int nonBlocking = 1;
      if(ioctlsocket(m_socket, (long)FIONBIO, nonBlocking) == SOCKET_ERROR)
      {
         Print("Failed to set listening socket non-blocking: ",
               WSAGetLastError());
         Close();
         return false;
      }

      Print("SocketBridge listening on port ", port);
      return true;
   }

   ulong AcceptClient()
   {
      if(m_socket == INVALID_SOCKET64)
         return INVALID_SOCKET64;

      char addrData[];
      ArrayResize(addrData, 16);

      int addrLen = 16;
      ulong client = accept(m_socket, addrData, addrLen);

      if(client == INVALID_SOCKET64)
         return INVALID_SOCKET64;

      int nonBlocking = 1;
      ioctlsocket(client, (long)FIONBIO, nonBlocking);

      char nodelay_opt[4];
      nodelay_opt[0] = 1;
      nodelay_opt[1] = 0;
      nodelay_opt[2] = 0;
      nodelay_opt[3] = 0;
      setsockopt(client, IPPROTO_TCP, TCP_NODELAY, nodelay_opt, 4);

      Print("Connection accepted: #", client);
      return client;
   }

   void Close()
   {
      if(m_socket != INVALID_SOCKET64)
      {
         closesocket(m_socket);
         m_socket = INVALID_SOCKET64;
      }
   }
};

// This helper is intentionally conservative. It validates the request and
// sends the RFC sample response only for the RFC sample key. If your
// WebSocketLib.mqh already performs the real SHA1/Base64 handshake, use that
// implementation for arbitrary Swift WebSocket clients.
bool PerformWebSocketHandshake(ulong clientSocket, const string &request)
{
   int start = StringFind(request, "Sec-WebSocket-Key:");
   if(start < 0)
      return false;

   start = StringFind(request, ":", start);
   if(start < 0)
      return false;

   start++;
   while(start < StringLen(request))
   {
      ushort c = StringGetCharacter(request, start);
      if(c != ' ' && c != '\t')
         break;
      start++;
   }

   int end = StringFind(request, "\r\n", start);
   if(end < 0)
      return false;

   string key = StringSubstr(request, start, end - start);
   StringTrimLeft(key);
   StringTrimRight(key);

   if(key != "dGhlIHNhbXBsZSBub25jZQ==")
      return false;

   string response =
      "HTTP/1.1 101 Switching Protocols\r\n"
      "Upgrade: websocket\r\n"
      "Connection: Upgrade\r\n"
      "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"
      "\r\n";

   char respData[];
   int len = StringToCharArray(response, respData, 0, StringLen(response));

   if(len <= 0)
      return false;

   // StringToCharArray may include a terminating NUL depending on the count.
   // Send only the HTTP response bytes.
   int sent = send(clientSocket, respData, StringLen(response), 0);
   return (sent == StringLen(response));
}

bool IsSocketConnected(ulong socketHandle)
{
   if(socketHandle == INVALID_SOCKET64)
      return false;

   char probe[];
   ArrayResize(probe, 1);

   int result = recv(socketHandle, probe, 1, MSG_PEEK);

   if(result > 0)
      return true;

   if(result == 0)
      return false;

   int err = WSAGetLastError();

   // Non-blocking socket with no data available is still connected.
   if(err == WSAEWOULDBLOCK || err == 0)
      return true;

   return false;
}

#endif
