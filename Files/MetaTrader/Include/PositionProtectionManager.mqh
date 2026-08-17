// PositionProtectionManager.mqh - V22 broker-side protection authority
#ifndef POSITION_PROTECTION_MANAGER_MQH
#define POSITION_PROTECTION_MANAGER_MQH

#include <Trade/Trade.mqh>

#define FS_PROTECT_PREFIX "FSV22_PROTECT_"
#define FS_TRAIL_ACTIVATION "FSV22_TRAIL_ACTIVATION_PIPS"
#define FS_TP1_PIPS "FSV22_TP1_PIPS"
#define FS_TP1_PCT "FSV22_TP1_PCT"
#define FS_TP2_PIPS "FSV22_TP2_PIPS"
#define FS_TP2_PCT "FSV22_TP2_PCT"
#define FS_TP3_PIPS "FSV22_TP3_PIPS"
#define FS_TP3_PCT "FSV22_TP3_PCT"

class CPositionProtectionManager
{
private:
   CTrade m_trade;
   ulong m_magic;
   double Setting(const string name,const double fallback){return GlobalVariableCheck(name)?GlobalVariableGet(name):fallback;}
   double PipSize(const string symbol){const double p=SymbolInfoDouble(symbol,SYMBOL_POINT);const int d=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);return(d==3||d==5)?p*10.0:p;}
   double NormalizePrice(const string symbol,const double price){return NormalizeDouble(price,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));}
   double NormalizeVolume(const string symbol,double volume){const double minV=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),maxV=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);if(step<=0.0)return MathMin(maxV,MathMax(0.0,volume));volume=MathMin(maxV,MathMax(0.0,volume));return NormalizeDouble(MathFloor((volume+1e-12)/step)*step,8);}
   string Key(const ulong ticket,const string suffix){return FS_PROTECT_PREFIX+IntegerToString((long)ticket)+"_"+suffix;}
   bool Done(const ulong ticket,const string stage){return GlobalVariableCheck(Key(ticket,stage))&&GlobalVariableGet(Key(ticket,stage))>0.5;}
   void MarkDone(const ulong ticket,const string stage){GlobalVariableSet(Key(ticket,stage),1.0);GlobalVariablesFlush();}
   double OriginalVolume(const ulong ticket,const double currentVolume){const string k=Key(ticket,"ORIG");if(GlobalVariableCheck(k))return GlobalVariableGet(k);GlobalVariableSet(k,currentVolume);GlobalVariablesFlush();PrintFormat("[EA V22] PROTECTION INIT | ticket=%I64u | original_volume=%.8f",ticket,currentVolume);return currentVolume;}
   double ProfitPips(const string symbol,const ENUM_POSITION_TYPE type,const double openPrice){MqlTick tick;if(!SymbolInfoTick(symbol,tick))return 0.0;const double cur=type==POSITION_TYPE_BUY?tick.bid:tick.ask,pip=PipSize(symbol);if(pip<=0.0)return 0.0;return type==POSITION_TYPE_BUY?(cur-openPrice)/pip:(openPrice-cur)/pip;}
   bool ClosePartial(const ulong ticket,const string symbol,const double requestedVolume){const double current=PositionGetDouble(POSITION_VOLUME),minV=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);double volume=NormalizeVolume(symbol,requestedVolume);if(volume<minV-1e-9){PrintFormat("[EA V22] PARTIAL SKIP | ticket=%I64u | requested=%.8f below broker minimum=%.8f",ticket,requestedVolume,minV);return false;}if(current-volume>0.0&&current-volume<minV-1e-9)volume=NormalizeVolume(symbol,current);if(volume<=0.0||volume>current+1e-9)return false;const bool ok=m_trade.PositionClosePartial(ticket,volume);const uint rc=m_trade.ResultRetcode();PrintFormat("[EA V22] PARTIAL CLOSE | ticket=%I64u | requested=%.8f | executed=%.8f | ok=%s | retcode=%u | comment=%s",ticket,requestedVolume,volume,ok?"true":"false",rc,m_trade.ResultRetcodeDescription());return ok&&(rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL||rc==TRADE_RETCODE_PLACED);}
   bool ModifyStopForwardOnly(const ulong ticket,const string symbol,const ENUM_POSITION_TYPE type,const double proposedSL){const double oldSL=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP),point=SymbolInfoDouble(symbol,SYMBOL_POINT),target=NormalizePrice(symbol,proposedSL);if(target<=0.0)return false;if(type==POSITION_TYPE_BUY&&oldSL>0.0&&target<=oldSL+point*0.5)return false;if(type==POSITION_TYPE_SELL&&oldSL>0.0&&target>=oldSL-point*0.5)return false;const bool ok=m_trade.PositionModify(ticket,target,tp);const uint rc=m_trade.ResultRetcode();PrintFormat("[EA V22] SL MODIFY | ticket=%I64u | oldSL=%.5f | newSL=%.5f | ok=%s | retcode=%u | comment=%s",ticket,oldSL,target,ok?"true":"false",rc,m_trade.ResultRetcodeDescription());return ok&&(rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL||rc==TRADE_RETCODE_PLACED);}
   double TrailDistancePips(const double profitPips){if(profitPips>=80.0)return 12.0;if(profitPips>=40.0)return 10.0;if(profitPips>=25.0)return 8.0;if(profitPips>=15.0)return 6.0;if(profitPips>=10.0)return 4.5;return 3.0;}
   void ManagePosition(const ulong ticket){
      if(!PositionSelectByTicket(ticket)||((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic))return;
      const string symbol=PositionGetString(POSITION_SYMBOL);const ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);const double open=PositionGetDouble(POSITION_PRICE_OPEN),current=PositionGetDouble(POSITION_VOLUME),original=OriginalVolume(ticket,current);if(original<=0.0||current<=0.0)return;
      const double profit=ProfitPips(symbol,type,open),tp1=MathMax(0.0,Setting(FS_TP1_PIPS,10.0)),tp2=MathMax(tp1,Setting(FS_TP2_PIPS,15.0)),tp3=MathMax(tp2,Setting(FS_TP3_PIPS,20.0)),p1=MathMax(0.0,MathMin(1.0,Setting(FS_TP1_PCT,0.50))),p2=MathMax(0.0,MathMin(1.0,Setting(FS_TP2_PCT,0.30))),p3=MathMax(0.0,MathMin(1.0,Setting(FS_TP3_PCT,0.20)));
      if(profit>=tp1&&!Done(ticket,"TP1")){if(ClosePartial(ticket,symbol,original*p1))MarkDone(ticket,"TP1");}
      if(!PositionSelectByTicket(ticket))return;
      if(profit>=tp1&&!Done(ticket,"BE")){if(ModifyStopForwardOnly(ticket,symbol,type,open))MarkDone(ticket,"BE");}
      if(!PositionSelectByTicket(ticket))return;
      if(profit>=tp2&&!Done(ticket,"TP2")){if(ClosePartial(ticket,symbol,original*p2))MarkDone(ticket,"TP2");}
      if(!PositionSelectByTicket(ticket))return;
      if(profit>=tp3&&!Done(ticket,"TP3")){if(ClosePartial(ticket,symbol,MathMin(original*p3,PositionGetDouble(POSITION_VOLUME))))MarkDone(ticket,"TP3");}
      if(!PositionSelectByTicket(ticket))return;
      const double activation=MathMax(1.0,Setting(FS_TRAIL_ACTIVATION,5.0));if(profit<activation)return;const double pip=PipSize(symbol);if(pip<=0.0)return;MqlTick tick;if(!SymbolInfoTick(symbol,tick))return;const double dist=TrailDistancePips(profit),ref=type==POSITION_TYPE_BUY?tick.bid:tick.ask,target=type==POSITION_TYPE_BUY?ref-dist*pip:ref+dist*pip;ModifyStopForwardOnly(ticket,symbol,type,target);
   }
public:
   CPositionProtectionManager(const ulong magic=888888){m_magic=magic;m_trade.SetExpertMagicNumber(magic);m_trade.SetAsyncMode(false);}
   void ManageAll(){for(int i=PositionsTotal()-1;i>=0;i--){const ulong ticket=PositionGetTicket(i);if(ticket>0)ManagePosition(ticket);}}
};

#endif