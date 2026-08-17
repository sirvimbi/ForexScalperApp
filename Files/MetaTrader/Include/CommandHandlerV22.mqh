//+------------------------------------------------------------------+
//| CommandHandlerV22.mqh                                           |
//| V22 extension over the existing command handler.                |
//+------------------------------------------------------------------+
#ifndef COMMAND_HANDLER_V22_MQH
#define COMMAND_HANDLER_V22_MQH

#include <CommandHandler.mqh>

#define V22_TRAILING_ACTIVATION_GV "FSV22_TRAIL_ACTIVATION_PIPS"
#define V22_TRAILING_MIN_PIPS 1.0
#define V22_TRAILING_MAX_PIPS 100.0
#define V22_TP1_PIPS_GV "FSV22_TP1_PIPS"
#define V22_TP1_PCT_GV "FSV22_TP1_PCT"
#define V22_TP2_PIPS_GV "FSV22_TP2_PIPS"
#define V22_TP2_PCT_GV "FSV22_TP2_PCT"
#define V22_TP3_PIPS_GV "FSV22_TP3_PIPS"
#define V22_TP3_PCT_GV "FSV22_TP3_PCT"

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
      if(req.path == "/v1/settings/protection" || req.path == "/settings/protection")
      {
         string response = HandleProtectionSettings(req);
         SendSettingsResponse(sock, 200, response);
         return;
      }
      CCommandHandler::HandleCommand(sock, req);
   }

private:
   double GetSetting(const string key,const double fallback){return GlobalVariableCheck(key)?GlobalVariableGet(key):fallback;}

   string HandleTrailingSettings(const HttpRequest &req)
   {
      double activation = GetSetting(V22_TRAILING_ACTIVATION_GV, 5.0);
      if(req.method == "POST" || req.method == "PUT")
      {
         CJAVal body;
         if(!body.Deserialize(req.body)) return "{\"success\":false,\"error\":\"Invalid JSON body\"}";
         double requested = body["trailing_activation_pips"].ToDbl();
         if(requested <= 0.0) requested = body["activation_pips"].ToDbl();
         if(requested <= 0.0) return StringFormat("{\"success\":false,\"error\":\"trailing_activation_pips must be greater than zero\",\"current\":%.2f}", activation);
         activation = MathMax(V22_TRAILING_MIN_PIPS, MathMin(V22_TRAILING_MAX_PIPS, requested));
         if(GlobalVariableSet(V22_TRAILING_ACTIVATION_GV, activation) == 0) return StringFormat("{\"success\":false,\"error\":\"Failed to persist MT5 terminal setting\",\"current\":%.2f}", activation);
         GlobalVariablesFlush();
         PrintFormat("[EA V22] TRAILING SETTING | activation=%.1f pips | source=Swift", activation);
      }
      return StringFormat("{\"success\":true,\"trailing_activation_pips\":%.2f,\"curve\":{\"5_10\":3.0,\"10_15\":4.5,\"15_25\":6.0,\"25_40\":8.0,\"40_80\":10.0,\"80_plus\":12.0},\"hard_sl_unchanged\":true,\"forward_only\":true,\"volatility_aware\":true}", activation);
   }

   string HandleProtectionSettings(const HttpRequest &req)
   {
      if(req.method == "POST" || req.method == "PUT")
      {
         CJAVal body;
         if(!body.Deserialize(req.body)) return "{\"success\":false,\"error\":\"Invalid JSON body\"}";
         double tp1Pips=body["tp1_pips"].ToDbl(),tp1Pct=body["tp1_percent"].ToDbl(),tp2Pips=body["tp2_pips"].ToDbl(),tp2Pct=body["tp2_percent"].ToDbl(),tp3Pips=body["tp3_pips"].ToDbl(),tp3Pct=body["tp3_percent"].ToDbl(),activation=body["trailing_activation_pips"].ToDbl();
         if(tp1Pips>0.0)GlobalVariableSet(V22_TP1_PIPS_GV,tp1Pips);
         if(tp1Pct>=0.0)GlobalVariableSet(V22_TP1_PCT_GV,MathMax(0.0,MathMin(1.0,tp1Pct)));
         if(tp2Pips>0.0)GlobalVariableSet(V22_TP2_PIPS_GV,tp2Pips);
         if(tp2Pct>=0.0)GlobalVariableSet(V22_TP2_PCT_GV,MathMax(0.0,MathMin(1.0,tp2Pct)));
         if(tp3Pips>0.0)GlobalVariableSet(V22_TP3_PIPS_GV,tp3Pips);
         if(tp3Pct>=0.0)GlobalVariableSet(V22_TP3_PCT_GV,MathMax(0.0,MathMin(1.0,tp3Pct)));
         if(activation>0.0)GlobalVariableSet(V22_TRAILING_ACTIVATION_GV,MathMax(V22_TRAILING_MIN_PIPS,MathMin(V22_TRAILING_MAX_PIPS,activation)));
         GlobalVariablesFlush();
         PrintFormat("[EA V22] PROTECTION SETTINGS SYNC | TP1=%.2fp/%.2f%% | TP2=%.2fp/%.2f%% | TP3=%.2fp/%.2f%% | trail=%.2fp",GetSetting(V22_TP1_PIPS_GV,10.0),GetSetting(V22_TP1_PCT_GV,0.50)*100.0,GetSetting(V22_TP2_PIPS_GV,15.0),GetSetting(V22_TP2_PCT_GV,0.30)*100.0,GetSetting(V22_TP3_PIPS_GV,20.0),GetSetting(V22_TP3_PCT_GV,0.20)*100.0,GetSetting(V22_TRAILING_ACTIVATION_GV,5.0));
      }
      return StringFormat("{\"success\":true,\"tp1_pips\":%.4f,\"tp1_percent\":%.4f,\"tp2_pips\":%.4f,\"tp2_percent\":%.4f,\"tp3_pips\":%.4f,\"tp3_percent\":%.4f,\"trailing_activation_pips\":%.4f}",GetSetting(V22_TP1_PIPS_GV,10.0),GetSetting(V22_TP1_PCT_GV,0.50),GetSetting(V22_TP2_PIPS_GV,15.0),GetSetting(V22_TP2_PCT_GV,0.30),GetSetting(V22_TP3_PIPS_GV,20.0),GetSetting(V22_TP3_PCT_GV,0.20),GetSetting(V22_TRAILING_ACTIVATION_GV,5.0));
   }

   void SendSettingsResponse(ulong sock,int statusCode,string body)
   {
      string status=statusCode==200?"OK":"Bad Request";
      string response="HTTP/1.1 "+IntegerToString(statusCode)+" "+status+"\r\n"+"Content-Type: application/json; charset=utf-8\r\n"+"Access-Control-Allow-Origin: *\r\n"+"Access-Control-Allow-Methods: GET, POST, PUT, OPTIONS\r\n"+"Access-Control-Allow-Headers: Content-Type, Authorization\r\n"+"Cache-Control: no-cache\r\n"+"Connection: close\r\n"+"Content-Length: "+IntegerToString(StringLen(body))+"\r\n\r\n"+body;
      char payload[]; int length=StringToCharArray(response,payload,0,StringLen(response)); if(length>0)send(sock,payload,length,0);
   }
};

#endif