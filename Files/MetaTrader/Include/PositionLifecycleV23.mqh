//+------------------------------------------------------------------+
//| PositionLifecycleV23.mqh                                        |
//| Production position lifecycle: TP1/TP2/TP3 + BE + trailing.     |
//+------------------------------------------------------------------+
#ifndef POSITION_LIFECYCLE_V23_MQH
#define POSITION_LIFECYCLE_V23_MQH

#property strict

#include <Trade/Trade.mqh>

#define V23_MAGIC 888888
#define V23_TP1_PERCENT_GV "FSV23_TP1_PERCENT"
#define V23_TP1_PIPS_GV    "FSV23_TP1_PIPS"
#define V23_TP2_PERCENT_GV "FSV23_TP2_PERCENT"
#define V23_TP2_PIPS_GV    "FSV23_TP2_PIPS"
#define V23_TP3_PERCENT_GV "FSV23_TP3_PERCENT"
#define V23_TP3_PIPS_GV    "FSV23_TP3_PIPS"
#define V23_TRAIL_ACTIVATION_GV "FSV23_TRAIL_ACTIVATION_PIPS"
#define V23_BROKER_SUFFIX_GV "FSV23_BROKER_SUFFIX"
#define V23_MIN_TRAIL_STEP_PIPS 1.0
#define V23_BE_LOCK_PIPS 0.5
#define V23_DEFAULT_TP1_PERCENT 0.50
#define V23_DEFAULT_TP1_PIPS 10.0
#define V23_DEFAULT_TP2_PERCENT 0.30
#define V23_DEFAULT_TP2_PIPS 15.0
#define V23_DEFAULT_TP3_PERCENT 0.20
#define V23_DEFAULT_TP3_PIPS 20.0
#define V23_DEFAULT_TRAIL_ACTIVATION 5.0

class CPositionLifecycleV23
{
private:
   CTrade m_trade;

   string Key(ulong ticket,string suffix)
   {
      return "FSV23_" + IntegerToString((long)ticket) + "_" + suffix;
   }

   double GV(string name,double fallback)
   {
      if(!GlobalVariableCheck(name)) return fallback;
      return GlobalVariableGet(name);
   }

   double PipSize(string symbol)
   {
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      return (digits==3 || digits==5) ? point*10.0 : point;
   }

   int VolumeDigits(string symbol)
   {
      double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      int digits=0;
      while(digits<8 && MathAbs(step*MathPow(10.0,digits)-MathRound(step*MathPow(10.0,digits)))>1e-9) digits++;
      return digits;
   }

   double NormalizeVolumeDown(string symbol,double volume)
   {
      double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double maxVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0) step=minVolume;
      if(step<=0.0) return 0.0;
      volume=MathMin(volume,maxVolume);
      double normalized=MathFloor((volume+1e-12)/step)*step;
      normalized=NormalizeDouble(normalized,VolumeDigits(symbol));
      return normalized>=minVolume ? normalized : 0.0;
   }

   bool Success(uint retcode)
   {
      return retcode==TRADE_RETCODE_DONE || retcode==TRADE_RETCODE_DONE_PARTIAL || retcode==TRADE_RETCODE_PLACED;
   }

   double StopDistance(string symbol)
   {
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      long stops=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      long freeze=SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      return MathMax(point,(double)MathMax(stops,freeze)*point);
   }

   bool ValidSL(string symbol,ENUM_POSITION_TYPE type,double sl)
   {
      MqlTick tick;
      if(sl<=0.0 || !SymbolInfoTick(symbol,tick)) return false;
      double distance=StopDistance(symbol);
      if(type==POSITION_TYPE_BUY) return sl<tick.bid-distance;
      return sl>tick.ask+distance;
   }

   double ClampSL(string symbol,ENUM_POSITION_TYPE type,double sl)
   {
      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick)) return 0.0;
      double distance=StopDistance(symbol);
      if(type==POSITION_TYPE_BUY) return NormalizeDouble(MathMin(sl,tick.bid-distance),(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
      return NormalizeDouble(MathMax(sl,tick.ask+distance),(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
   }

   bool ModifySL(ulong ticket,string symbol,ENUM_POSITION_TYPE type,double requestedSL,double currentTP)
   {
      if(requestedSL<=0.0 || !ValidSL(symbol,type,requestedSL)) return false;
      double oldSL=PositionGetDouble(POSITION_SL);
      double tp=currentTP;
      MqlTradeRequest request={};
      MqlTradeResult result={};
      request.action=TRADE_ACTION_SLTP;
      request.position=ticket;
      request.symbol=symbol;
      request.sl=requestedSL;
      request.tp=tp;
      ResetLastError();
      bool sent=OrderSend(request,result);
      PrintFormat("[V23] SL MODIFY | ticket=%I64u | requestedSL=%.*f | currentTP=%.*f | retcode=%u | comment=%s | oldSL=%.*f",ticket,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),requestedSL,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),tp,result.retcode,result.comment,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),oldSL);
      if(!sent || !Success(result.retcode)) return false;
      if(!PositionSelectByTicket(ticket)) return false;
      double actual=PositionGetDouble(POSITION_SL);
      return MathAbs(actual-requestedSL)<=SymbolInfoDouble(symbol,SYMBOL_POINT)*2.0;
   }

   bool CloseVolume(ulong ticket,string symbol,ENUM_POSITION_TYPE type,double requestedVolume,string stage)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double before=PositionGetDouble(POSITION_VOLUME);
      double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double volume=NormalizeVolumeDown(symbol,requestedVolume);
      if(volume<=0.0 || before-volume<minVolume-1e-9)
      {
         PrintFormat("[V23] %s SKIP | ticket=%I64u | requested=%.4f | normalized=%.4f | current=%.4f | min=%.4f",stage,ticket,requestedVolume,volume,before,minVolume);
         return false;
      }

      m_trade.SetExpertMagicNumber(V23_MAGIC);
      m_trade.SetDeviationInPoints(15);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetAsyncMode(false);
      bool sent=false;
      uint retcode=0;
      string comment="";
      ENUM_ACCOUNT_MARGIN_MODE mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         sent=m_trade.PositionClosePartial(ticket,volume,15);
         retcode=m_trade.ResultRetcode();
         comment=m_trade.ResultComment();
      }
      else
      {
         MqlTradeRequest request={};
         MqlTradeResult result={};
         request.action=TRADE_ACTION_DEAL;
         request.position=ticket;
         request.symbol=symbol;
         request.volume=volume;
         request.magic=V23_MAGIC;
         request.deviation=15;
         request.type_filling=ORDER_FILLING_IOC;
         request.type=(type==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
         request.price=(type==POSITION_TYPE_BUY)?SymbolInfoDouble(symbol,SYMBOL_BID):SymbolInfoDouble(symbol,SYMBOL_ASK);
         request.comment="FS V23 "+stage;
         ResetLastError();
         sent=OrderSend(request,result);
         retcode=result.retcode;
         comment=result.comment;
      }

      if(!sent || !Success(retcode))
      {
         PrintFormat("[V23] %s FAILED | ticket=%I64u | requested=%.4f | executed=0.0000 | retcode=%u | comment=%s | error=%d",stage,ticket,volume,retcode,comment,GetLastError());
         return false;
      }

      double after=0.0;
      if(PositionSelectByTicket(ticket)) after=PositionGetDouble(POSITION_VOLUME);
      double executed=MathMax(0.0,before-after);
      PrintFormat("[V23] %s RESULT | ticket=%I64u | requested=%.4f | executed=%.4f | remaining=%.4f | retcode=%u | comment=%s",stage,ticket,volume,executed,after,retcode,comment);
      return executed>0.0;
   }

   double InitialVolume(ulong ticket,double fallback)
   {
      string key=Key(ticket,"INITIAL_VOLUME");
      if(GlobalVariableCheck(key)) return GlobalVariableGet(key);
      double value=fallback;
      if(HistorySelectByPosition(ticket))
      {
         int total=HistoryDealsTotal();
         for(int i=0;i<total;i++)
         {
            ulong deal=HistoryDealGetTicket(i);
            if(deal==0) continue;
            ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
            if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
            {
               value=HistoryDealGetDouble(deal,DEAL_VOLUME);
               break;
            }
         }
      }
      GlobalVariableSet(key,value);
      return value;
   }

   double ClosedVolumeFromHistory(ulong ticket)
   {
      double total=0.0;
      if(!HistorySelectByPosition(ticket)) return total;
      int deals=HistoryDealsTotal();
      for(int i=0;i<deals;i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(deal==0) continue;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
            total+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      }
      return total;
   }

   double Stage(ulong ticket,double initial,double current)
   {
      double closed=ClosedVolumeFromHistory(ticket);
      if(closed>0.0 && initial>0.0)
      {
         double fraction=closed/initial;
         if(fraction>=0.999) return 3.0;
         double p1=GV(V23_TP1_PERCENT_GV,V23_DEFAULT_TP1_PERCENT);
         double p2=GV(V23_TP2_PERCENT_GV,V23_DEFAULT_TP2_PERCENT);
         if(fraction+1e-6>=p1+p2) return 2.0;
         if(fraction+1e-6>=p1) return 1.0;
      }
      string key=Key(ticket,"STAGE");
      return GlobalVariableCheck(key)?GlobalVariableGet(key):0.0;
   }

   void PersistStage(ulong ticket,double stage)
   {
      GlobalVariableSet(Key(ticket,"STAGE"),stage);
      GlobalVariablesFlush();
   }

   void DisableLegacyManager(ulong ticket)
   {
      // The existing V22 manager uses this state key. Setting it to TP2 complete
      // makes this V23 lifecycle the sole owner of partial TP decisions.
      GlobalVariableSet("FSV22_"+IntegerToString((long)ticket)+"_STAGE",2.0);
      GlobalVariablesFlush();
   }

   void RemoveBrokerTP(ulong ticket,string symbol,ENUM_POSITION_TYPE type,double sl)
   {
      string key=Key(ticket,"TP_REMOVED");
      if(GV(key,0.0)>=1.0) return;
      double tp=PositionGetDouble(POSITION_TP);
      if(tp<=0.0) { GlobalVariableSet(key,1.0); return; }
      if(ModifySL(ticket,symbol,type,sl,0.0))
      {
         GlobalVariableSet(key,1.0);
         PrintFormat("[V23] MANAGEMENT CLAIMED | ticket=%I64u | originalTP=%.*f removed | SL preserved",ticket,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),tp);
      }
   }

   void ManageOne(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return;
      if(PositionGetInteger(POSITION_MAGIC)!=V23_MAGIC) return;
      string symbol=PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double volume=PositionGetDouble(POSITION_VOLUME);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      if(symbol=="" || entry<=0.0 || volume<=0.0 || sl<=0.0)
      {
         PrintFormat("[V23] MANAGEMENT HALT | ticket=%I64u | symbol=%s | volume=%.4f | SL=%.*f",ticket,symbol,volume,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),sl);
         return;
      }

      DisableLegacyManager(ticket);
      double initial=InitialVolume(ticket,volume);
      double stage=Stage(ticket,initial,volume);
      double pip=PipSize(symbol);
      if(pip<=0.0) return;
      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick)) return;
      double favorable=(type==POSITION_TYPE_BUY)?tick.bid-entry:entry-tick.ask;
      double profitPips=favorable/pip;

      RemoveBrokerTP(ticket,symbol,type,sl);

      double tp1Percent=MathMax(0.0,MathMin(1.0,GV(V23_TP1_PERCENT_GV,V23_DEFAULT_TP1_PERCENT)));
      double tp1Pips=MathMax(0.0,GV(V23_TP1_PIPS_GV,V23_DEFAULT_TP1_PIPS));
      double tp2Percent=MathMax(0.0,MathMin(1.0,GV(V23_TP2_PERCENT_GV,V23_DEFAULT_TP2_PERCENT)));
      double tp2Pips=MathMax(tp1Pips,GV(V23_TP2_PIPS_GV,V23_DEFAULT_TP2_PIPS));
      double tp3Pips=MathMax(tp2Pips,GV(V23_TP3_PIPS_GV,V23_DEFAULT_TP3_PIPS));
      double tp3Percent=MathMax(0.0,MathMin(1.0,GV(V23_TP3_PERCENT_GV,V23_DEFAULT_TP3_PERCENT)));
      double target1=(type==POSITION_TYPE_BUY)?entry+tp1Pips*pip:entry-tp1Pips*pip;
      double target2=(type==POSITION_TYPE_BUY)?entry+tp2Pips*pip:entry-tp2Pips*pip;
      double target3=(type==POSITION_TYPE_BUY)?entry+tp3Pips*pip:entry-tp3Pips*pip;
      bool hit1=(type==POSITION_TYPE_BUY)?tick.bid>=target1:tick.ask<=target1;
      bool hit2=(type==POSITION_TYPE_BUY)?tick.bid>=target2:tick.ask<=target2;
      bool hit3=(type==POSITION_TYPE_BUY)?tick.bid>=target3:tick.ask<=target3;

      if(stage<1.0 && hit1)
      {
         double closeVolume=initial*tp1Percent;
         if(CloseVolume(ticket,symbol,type,closeVolume,"TP1_PARTIAL"))
         {
            PersistStage(ticket,1.0);
            if(PositionSelectByTicket(ticket))
            {
               double liveSL=PositionGetDouble(POSITION_SL);
               double be=(type==POSITION_TYPE_BUY)?entry+V23_BE_LOCK_PIPS*pip:entry-V23_BE_LOCK_PIPS*pip;
               bool improve=(type==POSITION_TYPE_BUY)?(be>liveSL):(liveSL<=0.0 || be<liveSL);
               if(improve && ModifySL(ticket,symbol,type,be,PositionGetDouble(POSITION_TP)))
                  GlobalVariableSet(Key(ticket,"BE_CONFIRMED"),1.0);
            }
         }
      }

      if(PositionSelectByTicket(ticket)) volume=PositionGetDouble(POSITION_VOLUME);
      stage=Stage(ticket,initial,volume);
      if(stage>=1.0 && stage<2.0 && hit2)
      {
         double closeVolume=initial*tp2Percent;
         if(CloseVolume(ticket,symbol,type,closeVolume,"TP2_PARTIAL")) PersistStage(ticket,2.0);
      }

      if(!PositionSelectByTicket(ticket)) return;
      volume=PositionGetDouble(POSITION_VOLUME);
      stage=Stage(ticket,initial,volume);
      if(stage>=2.0 && stage<3.0 && hit3)
      {
         // TP3 is the final configured target: close all remaining valid volume.
         double finalVolume=volume;
         if(CloseVolume(ticket,symbol,type,finalVolume,"TP3_FINAL")) PersistStage(ticket,3.0);
      }

      if(!PositionSelectByTicket(ticket)) return;
      volume=PositionGetDouble(POSITION_VOLUME);
      if(volume<=0.0) return;
      double activation=MathMax(1.0,GV(V23_TRAIL_ACTIVATION_GV,V23_DEFAULT_TRAIL_ACTIVATION));
      if(profitPips<activation) return;
      double trailPips=profitPips>=80.0?12.0:profitPips>=40.0?10.0:profitPips>=25.0?8.0:profitPips>=15.0?6.0:profitPips>=10.0?4.5:3.0;
      double desired=(type==POSITION_TYPE_BUY)?tick.bid-trailPips*pip:tick.ask+trailPips*pip;
      desired=ClampSL(symbol,type,desired);
      double currentSL=PositionGetDouble(POSITION_SL);
      bool improve=(type==POSITION_TYPE_BUY)?(currentSL<=0.0 || desired>currentSL+V23_MIN_TRAIL_STEP_PIPS*pip):(currentSL<=0.0 || desired<currentSL-V23_MIN_TRAIL_STEP_PIPS*pip);
      if(improve) ModifySL(ticket,symbol,type,desired,PositionGetDouble(POSITION_TP));
   }

public:
   CPositionLifecycleV23()
   {
      m_trade.SetExpertMagicNumber(V23_MAGIC);
      m_trade.SetDeviationInPoints(15);
      m_trade.SetAsyncMode(false);
   }

   void ManageAll()
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket>0) ManageOne(ticket);
      }
   }
};

#endif
