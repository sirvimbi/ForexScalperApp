//+------------------------------------------------------------------+
//| CommandHandlerV22.mqh                                           |
//| V22/V23 settings extension.                                     |
//+------------------------------------------------------------------+
#ifndef COMMAND_HANDLER_V22_MQH
#define COMMAND_HANDLER_V22_MQH

#include <CommandHandler.mqh>

#define V22_TRAILING_ACTIVATION_GV "FSV22_TRAIL_ACTIVATION_PIPS"
#define V22_TRAILING_MIN_PIPS 1.0
#define V22_TRAILING_MAX_PIPS 100.0

#define V23_TP1_PERCENT_GV "FSV23_TP1_PERCENT"
#define V23_TP1_PIPS_GV    "FSV23_TP1_PIPS"
#define V23_TP2_PERCENT_GV "FSV23_TP2_PERCENT"
#define V23_TP2_PIPS_GV    "FSV23_TP2_PIPS"
#define V23_TP3_PERCENT_GV "FSV23_TP3_PERCENT"
#define V23_TP3_PIPS_GV    "FSV23_TP3_PIPS"
#define V23_TRAIL_ACTIVATION_GV "FSV23_TRAIL_ACTIVATION_PIPS"

class CCommandHandlerV22 : public CCommandHandler
{
public:
   void HandleCommand(ulong sock,const HttpRequest &req)
   {
      if(req.path=="/v1/settings/trailing" || req.path=="/settings/trailing")
      {
         string response=HandleTrailingSettings(req);
         SendSettingsResponse(sock,200,response);
         return;
      }
      if(req.path=="/v1/settings/position-management" || req.path=="/settings/position-management")
      {
         string response=HandlePositionManagementSettings(req);
         SendSettingsResponse(sock,200,response);
         return;
      }
      CCommandHandler::HandleCommand(sock,req);
   }

private:
   double ReadGV(string name,double fallback)
   {
      return GlobalVariableCheck(name) ? GlobalVariableGet(name) : fallback;
   }

   double ClampPercent(double value,double fallback)
   {
      if(value<0.0 || value>1.0) return fallback;
      return value;
   }

   double ClampPositive(double value,double fallback)
   {
      return value>0.0 ? value : fallback;
   }

   string HandlePositionManagementSettings(const HttpRequest &req)
   {
      double tp1Percent=ReadGV(V23_TP1_PERCENT_GV,0.50);
      double tp1Pips=ReadGV(V23_TP1_PIPS_GV,10.0);
      double tp2Percent=ReadGV(V23_TP2_PERCENT_GV,0.30);
      double tp2Pips=ReadGV(V23_TP2_PIPS_GV,15.0);
      double tp3Percent=ReadGV(V23_TP3_PERCENT_GV,0.20);
      double tp3Pips=ReadGV(V23_TP3_PIPS_GV,20.0);
      double activation=ReadGV(V23_TRAIL_ACTIVATION_GV,5.0);
      string suffix="";

      if(req.method=="POST" || req.method=="PUT")
      {
         CJAVal body;
         if(!body.Deserialize(req.body))
            return "{\"success\":false,\"error\":\"Invalid JSON body\"}";

         tp1Percent=ClampPercent(body["tp1_percent"].ToDbl(),tp1Percent);
         tp1Pips=ClampPositive(body["tp1_pips"].ToDbl(),tp1Pips);
         tp2Percent=ClampPercent(body["tp2_percent"].ToDbl(),tp2Percent);
         tp2Pips=ClampPositive(body["tp2_pips"].ToDbl(),tp2Pips);
         tp3Percent=ClampPercent(body["tp3_percent"].ToDbl(),tp3Percent);
         tp3Pips=ClampPositive(body["tp3_pips"].ToDbl(),tp3Pips);
         activation=ClampPositive(body["trailing_activation_pips"].ToDbl(),activation);
         activation=MathMax(V22_TRAILING_MIN_PIPS,MathMin(V22_TRAILING_MAX_PIPS,activation));
         if(tp2Pips<tp1Pips || tp3Pips<tp2Pips)
            return "{\"success\":false,\"error\":\"TP distances must be non-decreasing\"}";
         double total=tp1Percent+tp2Percent+tp3Percent;
         if(total<=0.0 || total>1.0+1e-9)
            return "{\"success\":false,\"error\":\"TP percentages must be positive and sum to no more than 100%\"}";
         suffix=body["broker_suffix"].ToStr();

         GlobalVariableSet(V23_TP1_PERCENT_GV,tp1Percent);
         GlobalVariableSet(V23_TP1_PIPS_GV,tp1Pips);
         GlobalVariableSet(V23_TP2_PERCENT_GV,tp2Percent);
         GlobalVariableSet(V23_TP2_PIPS_GV,tp2Pips);
         GlobalVariableSet(V23_TP3_PERCENT_GV,tp3Percent);
         GlobalVariableSet(V23_TP3_PIPS_GV,tp3Pips);
         GlobalVariableSet(V23_TRAIL_ACTIVATION_GV,activation);
         GlobalVariableSet(V22_TRAILING_ACTIVATION_GV,activation);
         GlobalVariablesFlush();
         PrintFormat("[EA V23] SETTINGS APPLIED | TP1 %.1f%%/%.1fp | TP2 %.1f%%/%.1fp | TP3 %.1f%%/%.1fp | trail %.1fp | suffix=%s",tp1Percent*100.0,tp1Pips,tp2Percent*100.0,tp2Pips,tp3Percent*100.0,tp3Pips,activation,suffix);
      }

      return StringFormat("{\"success\":true,\"tp1_percent\":%.4f,\"tp1_pips\":%.4f,\"tp2_percent\":%.4f,\"tp2_pips\":%.4f,\"tp3_percent\":%.4f,\"tp3_pips\":%.4f,\"trailing_activation_pips\":%.4f,\"broker_suffix\":\"%s\"}",tp1Percent,tp1Pips,tp2Percent,tp2Pips,tp3Percent,tp3Pips,activation,suffix);
   }

   string HandleTrailingSettings(const HttpRequest &req)
   {
      double activation=ReadGV(V22_TRAILING_ACTIVATION_GV,5.0);
      if(req.method=="POST" || req.method=="PUT")
      {
         CJAVal body;
         if(!body.Deserialize(req.body))
            return "{\"success\":false,\"error\":\"Invalid JSON body\"}";
         double requested=body["trailing_activation_pips"].ToDbl();
         if(requested<=0.0) requested=body["activation_pips"].ToDbl();
         if(requested<=0.0)
            return StringFormat("{\"success\":false,\"error\":\"trailing_activation_pips must be greater than zero\",\"current\":%.2f}",activation);
         activation=MathMax(V22_TRAILING_MIN_PIPS,MathMin(V22_TRAILING_MAX_PIPS,requested));
         GlobalVariableSet(V22_TRAILING_ACTIVATION_GV,activation);
         GlobalVariableSet(V23_TRAIL_ACTIVATION_GV,activation);
         GlobalVariablesFlush();
         PrintFormat("[EA V22/V23] TRAILING SETTING | activation=%.1f pips | source=Swift",activation);
      }
      return StringFormat("{\"success\":true,\"trailing_activation_pips\":%.2f,\"hard_sl_unchanged\":true,\"forward_only\":true}",activation);
   }

   void SendSettingsResponse(ulong sock,int statusCode,string body)
   {
      string status=statusCode==200 ? "OK" : "Bad Request";
      string response="HTTP/1.1 "+IntegerToString(statusCode)+" "+status+"\r\n"+
         "Content-Type: application/json; charset=utf-8\r\n"+
         "Access-Control-Allow-Origin: *\r\n"+
         "Access-Control-Allow-Methods: GET, POST, PUT, OPTIONS\r\n"+
         "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"+
         "Cache-Control: no-cache\r\n"+
         "Connection: close\r\n"+
         "Content-Length: "+IntegerToString(StringLen(body))+"\r\n\r\n"+body;
      char payload[];
      int length=StringToCharArray(response,payload,0,StringLen(response));
      if(length>0) send(sock,payload,length,0);
   }
};

#endif
