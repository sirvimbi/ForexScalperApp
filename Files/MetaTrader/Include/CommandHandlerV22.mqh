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
#define PM_GV_PREFIX "FSV22_PM_"

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

      if(req.path == "/v1/settings/position-management" || req.path == "/settings/position-management")
      {
         string response = HandlePositionManagementSettings(req);
         SendSettingsResponse(sock, 200, response);
         return;
      }

      CCommandHandler::HandleCommand(sock, req);
   }

private:
   double Setting(string name, double fallback)
   {
      string key = PM_GV_PREFIX + name;
      if(!GlobalVariableCheck(key)) return fallback;
      return GlobalVariableGet(key);
   }

   double Clamp(double value, double low, double high)
   {
      return MathMax(low, MathMin(high, value));
   }

   string HandleTrailingSettings(const HttpRequest &req)
   {
      double activation = 5.0;
      if(GlobalVariableCheck(V22_TRAILING_ACTIVATION_GV)) activation = GlobalVariableGet(V22_TRAILING_ACTIVATION_GV);

      if(req.method == "POST" || req.method == "PUT")
      {
         CJAVal body;
         if(!body.Deserialize(req.body)) return "{\"success\":false,\"error\":\"Invalid JSON body\"}";
         double requested = body["trailing_activation_pips"].ToDbl();
         if(requested <= 0.0) requested = body["activation_pips"].ToDbl();
         if(requested <= 0.0) return StringFormat("{\"success\":false,\"error\":\"trailing_activation_pips must be greater than zero\",\"current\":%.2f}", activation);

         activation = Clamp(requested, V22_TRAILING_MIN_PIPS, V22_TRAILING_MAX_PIPS);
         if(GlobalVariableSet(V22_TRAILING_ACTIVATION_GV, activation) == 0) return StringFormat("{\"success\":false,\"error\":\"Failed to persist MT5 terminal setting\",\"current\":%.2f}", activation);
         GlobalVariableSet(PM_GV_PREFIX + "TRAIL_ACTIVATION_PIPS", activation);
         GlobalVariablesFlush();
         PrintFormat("[EA V22] TRAILING SETTING | activation=%.1f pips | source=Swift", activation);
      }

      return StringFormat(
         "{\"success\":true,\"trailing_activation_pips\":%.2f,\"hard_sl_unchanged\":true,\"forward_only\":true}",
         activation
      );
   }

   string HandlePositionManagementSettings(const HttpRequest &req)
   {
      if(req.method == "GET") return BuildPositionManagementSettingsResponse();
      if(req.method != "POST" && req.method != "PUT") return "{\"success\":false,\"error\":\"Unsupported method\"}";

      CJAVal body;
      if(!body.Deserialize(req.body)) return "{\"success\":false,\"error\":\"Invalid JSON body\"}";

      double tp1Pct = Clamp(body["tp1_percent"].ToDbl(), 0.0, 1.0);
      double tp2Pct = Clamp(body["tp2_percent"].ToDbl(), 0.0, 1.0);
      double tp3Pct = Clamp(body["tp3_percent"].ToDbl(), 0.0, 1.0);
      double tp1Pips = MathMax(0.0, body["tp1_pips"].ToDbl());
      double tp2Pips = MathMax(0.0, body["tp2_pips"].ToDbl());
      double tp3Pips = MathMax(0.0, body["tp3_pips"].ToDbl());
      double beTrigger = MathMax(0.0, body["breakeven_trigger_pips"].ToDbl());
      double beOffset = body["breakeven_offset_pips"].ToDbl();
      double trailActivation = MathMax(0.0, body["trailing_activation_pips"].ToDbl());
      double trailDistance = MathMax(0.0, body["trailing_distance_pips"].ToDbl());
      double trailStep = MathMax(0.0, body["trailing_step_pips"].ToDbl());
      bool beEnabled = body["breakeven_enabled"].ToDbl() > 0.5;
      bool trailEnabled = body["trailing_enabled"].ToDbl() > 0.5;

      if(tp1Pips > 0.0 && tp2Pips > 0.0 && tp2Pips < tp1Pips) return "{\"success\":false,\"error\":\"TP2 must be >= TP1\"}";
      if(tp2Pips > 0.0 && tp3Pips > 0.0 && tp3Pips < tp2Pips) return "{\"success\":false,\"error\":\"TP3 must be >= TP2\"}";
      if(tp1Pct + tp2Pct + tp3Pct > 1.000001) return "{\"success\":false,\"error\":\"TP percentages must total no more than 100%\"}";
      if(beOffset < -10.0 || beOffset > 10.0) return "{\"success\":false,\"error\":\"Breakeven offset is outside the supported range\"}";
      if(trailEnabled && (trailActivation <= 0.0 || trailDistance <= 0.0 || trailStep < 0.0)) return "{\"success\":false,\"error\":\"Trailing settings must be positive when trailing is enabled\"}";

      GlobalVariableSet(PM_GV_PREFIX + "TP1_PCT", tp1Pct);
      GlobalVariableSet(PM_GV_PREFIX + "TP1_PIPS", tp1Pips);
      GlobalVariableSet(PM_GV_PREFIX + "TP2_PCT", tp2Pct);
      GlobalVariableSet(PM_GV_PREFIX + "TP2_PIPS", tp2Pips);
      GlobalVariableSet(PM_GV_PREFIX + "TP3_PCT", tp3Pct);
      GlobalVariableSet(PM_GV_PREFIX + "TP3_PIPS", tp3Pips);
      GlobalVariableSet(PM_GV_PREFIX + "BE_ENABLED", beEnabled ? 1.0 : 0.0);
      GlobalVariableSet(PM_GV_PREFIX + "BE_TRIGGER_PIPS", beTrigger);
      GlobalVariableSet(PM_GV_PREFIX + "BE_OFFSET_PIPS", beOffset);
      GlobalVariableSet(PM_GV_PREFIX + "TRAIL_ENABLED", trailEnabled ? 1.0 : 0.0);
      GlobalVariableSet(PM_GV_PREFIX + "TRAIL_ACTIVATION_PIPS", trailActivation);
      GlobalVariableSet(PM_GV_PREFIX + "TRAIL_DISTANCE_PIPS", trailDistance);
      GlobalVariableSet(PM_GV_PREFIX + "TRAIL_STEP_PIPS", trailStep);
      GlobalVariableSet(PM_GV_PREFIX + "CONFIG_READY", 1.0);
      GlobalVariablesFlush();

      PrintFormat("[EA V22 PM] SETTINGS SYNC | TP=%.1f%%/%.1f%%/%.1f%% @ %.2f/%.2f/%.2f pips | BE=%s @ %.2f + %.2f | TRAIL=%s activation=%.2f distance=%.2f step=%.2f",
                  tp1Pct * 100.0, tp2Pct * 100.0, tp3Pct * 100.0, tp1Pips, tp2Pips, tp3Pips,
                  beEnabled ? "ON" : "OFF", beTrigger, beOffset,
                  trailEnabled ? "ON" : "OFF", trailActivation, trailDistance, trailStep);

      return BuildPositionManagementSettingsResponse();
   }

   string BuildPositionManagementSettingsResponse()
   {
      return StringFormat(
         "{\"success\":true,\"config_ready\":%s,\"tp1_percent\":%.6f,\"tp1_pips\":%.6f,\"tp2_percent\":%.6f,\"tp2_pips\":%.6f,\"tp3_percent\":%.6f,\"tp3_pips\":%.6f,\"breakeven_enabled\":%s,\"breakeven_trigger_pips\":%.6f,\"breakeven_offset_pips\":%.6f,\"trailing_enabled\":%s,\"trailing_activation_pips\":%.6f,\"trailing_distance_pips\":%.6f,\"trailing_step_pips\":%.6f}",
         Setting("CONFIG_READY", 0.0) > 0.5 ? "true" : "false",
         Setting("TP1_PCT", 0.50), Setting("TP1_PIPS", 10.0),
         Setting("TP2_PCT", 0.30), Setting("TP2_PIPS", 15.0),
         Setting("TP3_PCT", 0.20), Setting("TP3_PIPS", 20.0),
         Setting("BE_ENABLED", 1.0) > 0.5 ? "true" : "false", Setting("BE_TRIGGER_PIPS", 10.0), Setting("BE_OFFSET_PIPS", 0.0),
         Setting("TRAIL_ENABLED", 1.0) > 0.5 ? "true" : "false", Setting("TRAIL_ACTIVATION_PIPS", 5.0), Setting("TRAIL_DISTANCE_PIPS", 6.0), Setting("TRAIL_STEP_PIPS", 1.0)
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
