//+------------------------------------------------------------------+
//| CommandHandlerV22.mqh                                           |
//| V23 settings extension over the existing command handler.       |
//+------------------------------------------------------------------+
#ifndef COMMAND_HANDLER_V22_MQH
#define COMMAND_HANDLER_V22_MQH

#include <CommandHandler.mqh>

#define V23_SETTING_PREFIX "FSV23_PM_"
#define V23_TRAILING_ACTIVATION_GV "FSV23_PM_TRAIL_ACTIVATION_PIPS"
#define V23_MIN_ACTIVATION 0.0
#define V23_MAX_ACTIVATION 1000.0

class CCommandHandlerV22 : public CCommandHandler
{
public:
   void HandleCommand(ulong sock, const HttpRequest &req)
   {
      if(req.path == "/v1/settings/trailing" || req.path == "/settings/trailing")
      {
         SendSettingsResponse(sock, 200, HandleTrailingSettings(req));
         return;
      }
      if(req.path == "/v1/settings/position-management" || req.path == "/settings/position-management")
      {
         SendSettingsResponse(sock, 200, HandlePositionManagementSettings(req));
         return;
      }
      CCommandHandler::HandleCommand(sock, req);
   }

private:
   double ReadSetting(string name, double fallback)
   {
      string key = V23_SETTING_PREFIX + name;
      return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback;
   }

   double Clamp(double value, double minimum, double maximum)
   {
      return MathMax(minimum, MathMin(maximum, value));
   }

   void WriteSetting(string name, double value)
   {
      GlobalVariableSet(V23_SETTING_PREFIX + name, value);
   }

   string HandleTrailingSettings(const HttpRequest &req)
   {
      if(req.method == "POST" || req.method == "PUT")
      {
         CJAVal body;
         if(!body.Deserialize(req.body)) return "{\"success\":false,\"error\":\"Invalid JSON body\"}";
         double requested = body["trailing_activation_pips"].ToDbl();
         if(requested <= 0.0) requested = body["activation_pips"].ToDbl();
         if(requested <= 0.0) return "{\"success\":false,\"error\":\"Activation must be greater than zero\"}";
         requested = Clamp(requested, 1.0, 1000.0);
         WriteSetting("TRAIL_ACTIVATION_PIPS", requested);
         GlobalVariablesFlush();
         PrintFormat("[EA V23] TRAILING SETTING | activation=%.2f pips | source=Swift", requested);
      }
      return StringFormat("{\"success\":true,\"trailing_activation_pips\":%.2f}", ReadSetting("TRAIL_ACTIVATION_PIPS", 5.0));
   }

   string HandlePositionManagementSettings(const HttpRequest &req)
   {
      if(req.method == "OPTIONS") return "";
      if(req.method == "POST" || req.method == "PUT")
      {
         CJAVal body;
         if(!body.Deserialize(req.body)) return "{\"success\":false,\"error\":\"Invalid JSON body\"}";

         WriteSetting("TP1_PIPS", Clamp(body["tp1_pips"].ToDbl(), 0.0, 10000.0));
         WriteSetting("TP1_PERCENT", Clamp(body["tp1_percent"].ToDbl(), 0.0, 1.0));
         WriteSetting("TP2_PIPS", Clamp(body["tp2_pips"].ToDbl(), 0.0, 10000.0));
         WriteSetting("TP2_PERCENT", Clamp(body["tp2_percent"].ToDbl(), 0.0, 1.0));
         WriteSetting("TP3_PIPS", Clamp(body["tp3_pips"].ToDbl(), 0.0, 10000.0));
         WriteSetting("TP3_PERCENT", Clamp(body["tp3_percent"].ToDbl(), 0.0, 1.0));
         WriteSetting("TRAIL_ACTIVATION_PIPS", Clamp(body["trailing_activation_pips"].ToDbl(), 0.0, 1000.0));
         WriteSetting("BE_LOCK_PIPS", Clamp(body["breakeven_lock_pips"].ToDbl(), 0.0, 100.0));
         WriteSetting("MIN_TRAIL_STEP_PIPS", Clamp(body["minimum_trail_step_pips"].ToDbl(), 0.0, 100.0));
         WriteSetting("ATR_PERIOD", Clamp(body["atr_period"].ToDbl(), 2.0, 200.0));
         WriteSetting("ATR_BASELINE_PIPS", Clamp(body["atr_baseline_pips"].ToDbl(), 0.1, 100.0));
         WriteSetting("ATR_MAX_MULTIPLIER", Clamp(body["atr_max_multiplier"].ToDbl(), 1.0, 5.0));
         WriteSetting("TRAIL_5_10", Clamp(body["trail_5_10_pips"].ToDbl(), 0.1, 100.0));
         WriteSetting("TRAIL_10_15", Clamp(body["trail_10_15_pips"].ToDbl(), 0.1, 100.0));
         WriteSetting("TRAIL_15_25", Clamp(body["trail_15_25_pips"].ToDbl(), 0.1, 100.0));
         WriteSetting("TRAIL_25_40", Clamp(body["trail_25_40_pips"].ToDbl(), 0.1, 150.0));
         WriteSetting("TRAIL_40_80", Clamp(body["trail_40_80_pips"].ToDbl(), 0.1, 200.0));
         WriteSetting("TRAIL_80_PLUS", Clamp(body["trail_80_plus_pips"].ToDbl(), 0.1, 300.0));
         WriteSetting("DEVIATION_POINTS", Clamp(body["deviation_points"].ToDbl(), 0.0, 500.0));
         GlobalVariablesFlush();
         Print("[EA V23] POSITION SETTINGS | synchronized from Swift");
      }

      return StringFormat(
         "{\"success\":true,\"tp1_pips\":%.2f,\"tp1_percent\":%.4f,\"tp2_pips\":%.2f,\"tp2_percent\":%.4f,\"tp3_pips\":%.2f,\"tp3_percent\":%.4f,\"trailing_activation_pips\":%.2f,\"breakeven_lock_pips\":%.2f,\"minimum_trail_step_pips\":%.2f,\"atr_period\":%.0f,\"atr_baseline_pips\":%.2f,\"atr_max_multiplier\":%.3f,\"trail_5_10_pips\":%.2f,\"trail_10_15_pips\":%.2f,\"trail_15_25_pips\":%.2f,\"trail_25_40_pips\":%.2f,\"trail_40_80_pips\":%.2f,\"trail_80_plus_pips\":%.2f,\"deviation_points\":%.0f}",
         ReadSetting("TP1_PIPS", 10.0), ReadSetting("TP1_PERCENT", 0.50),
         ReadSetting("TP2_PIPS", 15.0), ReadSetting("TP2_PERCENT", 0.30),
         ReadSetting("TP3_PIPS", 20.0), ReadSetting("TP3_PERCENT", 0.20),
         ReadSetting("TRAIL_ACTIVATION_PIPS", 5.0), ReadSetting("BE_LOCK_PIPS", 0.5),
         ReadSetting("MIN_TRAIL_STEP_PIPS", 1.0), ReadSetting("ATR_PERIOD", 14.0),
         ReadSetting("ATR_BASELINE_PIPS", 5.0), ReadSetting("ATR_MAX_MULTIPLIER", 1.5),
         ReadSetting("TRAIL_5_10", 3.0), ReadSetting("TRAIL_10_15", 4.5),
         ReadSetting("TRAIL_15_25", 6.0), ReadSetting("TRAIL_25_40", 8.0),
         ReadSetting("TRAIL_40_80", 10.0), ReadSetting("TRAIL_80_PLUS", 12.0),
         ReadSetting("DEVIATION_POINTS", 15.0)
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
