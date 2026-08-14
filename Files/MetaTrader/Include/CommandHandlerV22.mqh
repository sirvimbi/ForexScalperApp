//+------------------------------------------------------------------+
//| CommandHandlerV22.mqh                                           |
//| Small V22 extension over the existing command handler.          |
//+------------------------------------------------------------------+
#ifndef COMMAND_HANDLER_V22_MQH
#define COMMAND_HANDLER_V22_MQH

#include <CommandHandler.mqh>

#define V22_TRAILING_ACTIVATION_GV "FSV22_TRAIL_ACTIVATION_PIPS"
#define V22_TRAILING_MIN_PIPS 1.0
#define V22_TRAILING_MAX_PIPS 100.0

class CCommandHandlerV22 : public CCommandHandler
{
public:
   void HandleCommand(ulong sock, const HttpRequest &req)
   {
      if(req.path == "/v1/settings/trailing" || req.path == "/settings/trailing")
      {
         string response = HandleTrailingSettings(req);
         SendSettingsResponse(sock, 200, response);
         return;
      }

      CCommandHandler::HandleCommand(sock, req);
   }

private:
   string HandleTrailingSettings(const HttpRequest &req)
   {
      double activation = 5.0;
      if(GlobalVariableCheck(V22_TRAILING_ACTIVATION_GV))
         activation = GlobalVariableGet(V22_TRAILING_ACTIVATION_GV);

      if(req.method == "POST" || req.method == "PUT")
      {
         CJAVal body;
         if(!body.Deserialize(req.body))
            return "{\"success\":false,\"error\":\"Invalid JSON body\"}";

         double requested = body["trailing_activation_pips"].ToDbl();
         if(requested <= 0.0)
            requested = body["activation_pips"].ToDbl();
         if(requested <= 0.0)
            return StringFormat("{\"success\":false,\"error\":\"trailing_activation_pips must be greater than zero\",\"current\":%.2f}", activation);

         activation = MathMax(V22_TRAILING_MIN_PIPS, MathMin(V22_TRAILING_MAX_PIPS, requested));
         if(GlobalVariableSet(V22_TRAILING_ACTIVATION_GV, activation) == 0)
            return StringFormat("{\"success\":false,\"error\":\"Failed to persist MT5 terminal setting\",\"current\":%.2f}", activation);
         GlobalVariablesFlush();

         PrintFormat("[EA V22] TRAILING SETTING | activation=%.1f pips | source=Swift", activation);
      }

      return StringFormat(
         "{\"success\":true,\"trailing_activation_pips\":%.2f,\"curve\":{\"5_10\":3.0,\"10_15\":4.5,\"15_25\":6.0,\"25_40\":8.0,\"40_80\":10.0,\"80_plus\":12.0},\"hard_sl_unchanged\":true,\"forward_only\":true,\"volatility_aware\":true}",
         activation
      );
   }

   void SendSettingsResponse(ulong sock, int statusCode, string body)
   {
      string status = statusCode == 200 ? "OK" : "Bad Request";
      string response =
         "HTTP/1.1 " + IntegerToString(statusCode) + " " + status + "\r\n" +
         "Content-Type: application/json; charset=utf-8\r\n" +
         "Access-Control-Allow-Origin: *\r\n" +
         "Access-Control-Allow-Methods: GET, POST, PUT, OPTIONS\r\n" +
         "Access-Control-Allow-Headers: Content-Type, Authorization\r\n" +
         "Cache-Control: no-cache\r\n" +
         "Connection: close\r\n" +
         "Content-Length: " + IntegerToString(StringLen(body)) + "\r\n\r\n" + body;

      char payload[];
      int length = StringToCharArray(response, payload, 0, StringLen(response));
      if(length > 0) send(sock, payload, length, 0);
   }
};

#endif
