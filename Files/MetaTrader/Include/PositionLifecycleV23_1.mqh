//+------------------------------------------------------------------+
//| PositionLifecycleV23_1.mqh                                      |
//| Production lifecycle: settings-driven TP1/TP2/TP3, BE, trail.  |
//+------------------------------------------------------------------+
#ifndef POSITION_LIFECYCLE_V23_1_MQH
#define POSITION_LIFECYCLE_V23_1_MQH

#property strict
#include <Trade/Trade.mqh>

#define V23_1_MAGIC 888888
#define V23_1_TP1_PERCENT_GV "FSV23_TP1_PERCENT"
#define V23_1_TP1_PIPS_GV "FSV23_TP1_PIPS"
#define V23_1_TP2_PERCENT_GV "FSV23_TP2_PERCENT"
#define V23_1_TP2_PIPS_GV "FSV23_TP2_PIPS"
#define V23_1_TP3_PERCENT_GV "FSV23_TP3_PERCENT"
#define V23_1_TP3_PIPS_GV "FSV23_TP3_PIPS"
#define V23_1_TRAIL_GV "FSV23_TRAIL_ACTIVATION_PIPS"
#define V23_1_MIN_TRAIL_STEP 1.0
#define V23_1_BE_LOCK 0.5

class CPositionLifecycleV23_1
{
private:
   CTrade trade;

   string StateKey(ulong ticket,string name){return "FSV23_1_"+IntegerToString((long)ticket)+"_"+name;}
   double Setting(string name,double fallback){return GlobalVariableCheck(name)?GlobalVariableGet(name):fallback;}
   double Pip(string symbol){double p=SymbolInfoDouble(symbol,SYMBOL_POINT);int d=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);return (d==3||d==5)?p*10.0:p;}
   int VolDigits(string symbol){double s=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);int d=0;while(d<8&&MathAbs(s*MathPow(10.0,d)-MathRound(s*MathPow(10.0,d)))>1e-9)d++;return d;}

   double NormalizeDown(string symbol,double requested)
   {
      double min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN), max=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX), step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0) step=min;
      if(step<=0.0) return 0.0;
      double v=MathFloor((MathMin(requested,max)+1e-12)/step)*step;
      v=NormalizeDouble(v,VolDigits(symbol));
      return v>=min?v:0.0;
   }

   bool RetcodeOK(uint rc){return rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL||rc==TRADE_RETCODE_PLACED;}

   ENUM_ORDER_TYPE_FILLING FillingMode(string symbol)
   {
      int flags=(int)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      ENUM_SYMBOL_TRADE_EXECUTION execution=(ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
      if(execution==SYMBOL_TRADE_EXECUTION_MARKET)
      {
         if((flags&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
         return ORDER_FILLING_FOK;
      }
      if((flags&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
      if((flags&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
      return ORDER_FILLING_RETURN;
   }

   double StopDistance(string symbol)
   {
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      long stops=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL), freeze=SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      return MathMax(point,(double)MathMax(stops,freeze)*point);
   }

   double ClampSL(string symbol,ENUM_POSITION_TYPE type,double desired)
   {
      MqlTick t;if(!SymbolInfoTick(symbol,t))return 0.0;
      double d=StopDistance(symbol);int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      return NormalizeDouble(type==POSITION_TYPE_BUY?MathMin(desired,t.bid-d):MathMax(desired,t.ask+d),digits);
   }

   bool ValidSL(string symbol,ENUM_POSITION_TYPE type,double sl)
   {
      MqlTick t;if(sl<=0.0||!SymbolInfoTick(symbol,t))return false;double d=StopDistance(symbol);
      return type==POSITION_TYPE_BUY?sl<t.bid-d:sl>t.ask+d;
   }

   bool ModifySL(ulong ticket,string symbol,ENUM_POSITION_TYPE type,double requested,double keepTP,string action)
   {
      requested=ClampSL(symbol,type,requested);
      if(!ValidSL(symbol,type,requested)) return false;
      MqlTradeRequest req={};MqlTradeResult res={};
      req.action=TRADE_ACTION_SLTP;req.position=ticket;req.symbol=symbol;req.sl=requested;req.tp=keepTP;
      ResetLastError();bool sent=OrderSend(req,res);
      PrintFormat("[V23.1] %s | ticket=%I64u | requestedSL=%.*f | keepTP=%.*f | retcode=%u | comment=%s | error=%d",action,ticket,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),requested,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),keepTP,res.retcode,res.comment,GetLastError());
      if(!sent||!RetcodeOK(res.retcode)||!PositionSelectByTicket(ticket))return false;
      double actual=PositionGetDouble(POSITION_SL);
      return MathAbs(actual-requested)<=SymbolInfoDouble(symbol,SYMBOL_POINT)*2.0;
   }

   bool Close(ulong ticket,string symbol,ENUM_POSITION_TYPE type,double requested,string stage,bool finalClose)
   {
      if(!PositionSelectByTicket(ticket))return false;
      double before=PositionGetDouble(POSITION_VOLUME), min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double volume=NormalizeDown(symbol,requested);
      if(volume<=0.0)return false;
      if(!finalClose && before-volume<min-1e-9)
      {
         PrintFormat("[V23.1] %s SKIP | ticket=%I64u | requested=%.4f | normalized=%.4f | current=%.4f | min=%.4f",stage,ticket,requested,volume,before,min);
         return false;
      }
      if(finalClose) volume=NormalizeDown(symbol,before);
      if(volume<=0.0)return false;

      trade.SetExpertMagicNumber(V23_1_MAGIC);trade.SetDeviationInPoints(15);trade.SetTypeFillingBySymbol(symbol);trade.SetAsyncMode(false);
      bool sent=false;uint rc=0;string comment="";
      ENUM_ACCOUNT_MARGIN_MODE mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         sent=trade.PositionClosePartial(ticket,volume,15);rc=trade.ResultRetcode();comment=trade.ResultComment();
      }
      else
      {
         MqlTradeRequest req={};MqlTradeResult res={};
         req.action=TRADE_ACTION_DEAL;req.position=ticket;req.symbol=symbol;req.volume=volume;req.magic=V23_1_MAGIC;req.deviation=15;
         req.type_filling=FillingMode(symbol);req.type=type==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
         req.price=type==POSITION_TYPE_BUY?SymbolInfoDouble(symbol,SYMBOL_BID):SymbolInfoDouble(symbol,SYMBOL_ASK);req.comment="FS V23.1 "+stage;
         ResetLastError();sent=OrderSend(req,res);rc=res.retcode;comment=res.comment;
      }
      double after=before;if(PositionSelectByTicket(ticket))after=PositionGetDouble(POSITION_VOLUME);else after=0.0;
      double executed=MathMax(0.0,before-after);
      PrintFormat("[V23.1] %s RESULT | ticket=%I64u | requested=%.4f | executed=%.4f | remaining=%.4f | retcode=%u | comment=%s | error=%d",stage,ticket,volume,executed,after,rc,comment,GetLastError());
      return sent&&RetcodeOK(rc)&&executed>0.0;
   }

   double InitialVolume(ulong ticket,long identifier,double fallback)
   {
      string key=StateKey(ticket,"INITIAL_VOLUME");if(GlobalVariableCheck(key))return GlobalVariableGet(key);
      double initial=fallback;
      if(identifier>0&&HistorySelectByPosition((ulong)identifier))
      {
         for(int i=0;i<HistoryDealsTotal();i++)
         {
            ulong deal=HistoryDealGetTicket(i);if(deal==0)continue;
            ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
            if(entry==DEAL_ENTRY_IN){initial=HistoryDealGetDouble(deal,DEAL_VOLUME);break;}
         }
      }
      GlobalVariableSet(key,initial);GlobalVariablesFlush();return initial;
   }

   double ClosedVolume(long identifier)
   {
      if(identifier<=0||!HistorySelectByPosition((ulong)identifier))return 0.0;
      double total=0.0;
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);if(deal==0)continue;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_OUT||entry==DEAL_ENTRY_OUT_BY)total+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      }
      return total;
   }

   double ReconstructStage(ulong ticket,long identifier,double initial,double current)
   {
      string key=StateKey(ticket,"STAGE");
      if(GlobalVariableCheck(key))return GlobalVariableGet(key);
      double closed=ClosedVolume(identifier);
      if(initial>0.0&&closed>0.0)
      {
         double fraction=closed/initial,p1=Setting(V23_1_TP1_PERCENT_GV,0.50),p2=Setting(V23_1_TP2_PERCENT_GV,0.30);
         if(fraction>=0.999)return 3.0;
         if(fraction+1e-6>=p1+p2)return 2.0;
         if(fraction+1e-6>=p1)return 1.0;
      }
      return 0.0;
   }

   void Persist(ulong ticket,string name,double value){GlobalVariableSet(StateKey(ticket,name),value);GlobalVariablesFlush();}

   void ClaimLegacy(ulong ticket){GlobalVariableSet("FSV22_"+IntegerToString((long)ticket)+"_STAGE",2.0);GlobalVariablesFlush();}

   void ManageOne(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))return;
      if(PositionGetInteger(POSITION_MAGIC)!=V23_1_MAGIC)return;
      string symbol=PositionGetString(POSITION_SYMBOL);ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      long identifier=PositionGetInteger(POSITION_IDENTIFIER);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),volume=PositionGetDouble(POSITION_VOLUME),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      if(symbol==""||entry<=0.0||volume<=0.0||sl<=0.0){PrintFormat("[V23.1] HALT | ticket=%I64u | symbol=%s | volume=%.4f | hardSL=%.*f",ticket,symbol,volume,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),sl);return;}
      ClaimLegacy(ticket);

      double initial=InitialVolume(ticket,identifier,volume),stage=ReconstructStage(ticket,identifier,initial,volume),pip=Pip(symbol);if(pip<=0.0)return;
      MqlTick tick;if(!SymbolInfoTick(symbol,tick))return;
      double favorable=type==POSITION_TYPE_BUY?tick.bid-entry:entry-tick.ask;
      double profitPips=favorable/pip;

      if(tp>0.0&&GlobalVariableCheck(StateKey(ticket,"TP_REMOVED"))==false)
      {
         if(ModifySL(ticket,symbol,type,sl,0.0,"REMOVE_BROKER_TP"))Persist(ticket,"TP_REMOVED",1.0);
      }

      double p1=MathMax(0.0,MathMin(1.0,Setting(V23_1_TP1_PERCENT_GV,0.50))),d1=MathMax(0.0,Setting(V23_1_TP1_PIPS_GV,10.0));
      double p2=MathMax(0.0,MathMin(1.0,Setting(V23_1_TP2_PERCENT_GV,0.30))),d2=MathMax(d1,Setting(V23_1_TP2_PIPS_GV,15.0));
      double p3=MathMax(0.0,MathMin(1.0,Setting(V23_1_TP3_PERCENT_GV,0.20))),d3=MathMax(d2,Setting(V23_1_TP3_PIPS_GV,20.0));
      double total=p1+p2+p3;if(total>1.0+1e-9){PrintFormat("[V23.1] INVALID SETTINGS | ticket=%I64u | TP percentages total=%.4f",ticket,total);return;}
      bool hit1=type==POSITION_TYPE_BUY?tick.bid>=entry+d1*pip:tick.ask<=entry-d1*pip;
      bool hit2=type==POSITION_TYPE_BUY?tick.bid>=entry+d2*pip:tick.ask<=entry-d2*pip;
      bool hit3=type==POSITION_TYPE_BUY?tick.bid>=entry+d3*pip:tick.ask<=entry-d3*pip;

      if(stage<1.0&&hit1)
      {
         if(Close(ticket,symbol,type,initial*p1,"TP1_PARTIAL",false))
         {
            Persist(ticket,"STAGE",1.0);stage=1.0;
            if(PositionSelectByTicket(ticket))
            {
               double liveSL=PositionGetDouble(POSITION_SL),be=type==POSITION_TYPE_BUY?entry+V23_1_BE_LOCK*pip:entry-V23_1_BE_LOCK*pip;
               bool improve=type==POSITION_TYPE_BUY?be>liveSL:(liveSL<=0.0||be<liveSL);
               if(improve&&ModifySL(ticket,symbol,type,be,PositionGetDouble(POSITION_TP),"BREAKEVEN_AFTER_TP1"))Persist(ticket,"BE_CONFIRMED",1.0);
            }
         }
      }

      if(!PositionSelectByTicket(ticket))return;volume=PositionGetDouble(POSITION_VOLUME);stage=ReconstructStage(ticket,identifier,initial,volume);
      if(stage>=1.0&&stage<2.0&&hit2)
      {
         if(Close(ticket,symbol,type,initial*p2,"TP2_PARTIAL",false)){Persist(ticket,"STAGE",2.0);stage=2.0;}
      }

      if(!PositionSelectByTicket(ticket))return;volume=PositionGetDouble(POSITION_VOLUME);stage=ReconstructStage(ticket,identifier,initial,volume);
      if(stage>=2.0&&stage<3.0&&hit3)
      {
         if(Close(ticket,symbol,type,volume,"TP3_FINAL",true)){Persist(ticket,"STAGE",3.0);return;}
      }

      if(!PositionSelectByTicket(ticket))return;volume=PositionGetDouble(POSITION_VOLUME);if(volume<=0.0)return;
      double activation=MathMax(1.0,Setting(V23_1_TRAIL_GV,5.0));if(profitPips<activation)return;
      double trail=profitPips>=80.0?12.0:profitPips>=40.0?10.0:profitPips>=25.0?8.0:profitPips>=15.0?6.0:profitPips>=10.0?4.5:3.0;
      double desired=type==POSITION_TYPE_BUY?tick.bid-trail*pip:tick.ask+trail*pip;desired=ClampSL(symbol,type,desired);double currentSL=PositionGetDouble(POSITION_SL);
      bool improve=type==POSITION_TYPE_BUY?(currentSL<=0.0||desired>currentSL+V23_1_MIN_TRAIL_STEP*pip):(currentSL<=0.0||desired<currentSL-V23_1_MIN_TRAIL_STEP*pip);
      if(improve)ModifySL(ticket,symbol,type,desired,PositionGetDouble(POSITION_TP),"TRAIL_FORWARD_ONLY");
   }

public:
   CPositionLifecycleV23_1(){trade.SetExpertMagicNumber(V23_1_MAGIC);trade.SetDeviationInPoints(15);trade.SetAsyncMode(false);}
   void ManageAll(){for(int i=PositionsTotal()-1;i>=0;i--){ulong ticket=PositionGetTicket(i);if(ticket>0)ManageOne(ticket);}}
};

#endif
