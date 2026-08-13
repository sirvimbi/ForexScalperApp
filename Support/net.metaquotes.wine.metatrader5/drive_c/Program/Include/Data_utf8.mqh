//+------------------------------------------------------------------+
//| Data.mqh - Updated with OHLC functionality                     |
//| Price data sending functionality for MT5 socket communication   |
//+------------------------------------------------------------------+
#ifndef DATA_MQH
#define DATA_MQH

#include <JAson.mqh>
#include <socketlib.mqh>
#include <WebSocketLib.mqh>

// Forward declaration
class CCommandHandler;

// Structure to hold symbol price data
struct SymbolPriceData {
    string symbol;
    double lastBid;
    double lastAsk;
    bool initialized;
};

struct OhlcRequest {
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   int depth;
};

// Structure to hold OHLC data for tracking
struct OhlcData {
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    int depth;
    datetime lastBarTime;
    bool initialized;
};

//+------------------------------------------------------------------+
//| Data Class                                                      |
//+------------------------------------------------------------------+
class CData {
private:
    SOCKET64 client_socket;
    string symbols[];
    SymbolPriceData symbolData[];     // Array to store last prices for each symbol

    string mbookSymbols[];            // Symbols for market book tracking
    ulong lastBookHashes[];           // Hash for each symbol
    bool firstRun;

    datetime lastSentTime;
    CCommandHandler *commandHandler;  // Reference to command handler
    OhlcData ohlcRequests[];          // Array to store OHLC tracking requests

    // Private methods
    ulong CalculateBookHash(MqlBookInfo &bookInfo[]);
    void SendSymbolPrice(string symbol);
    void SendSymbolPrice(string symbol, SOCKET64 sock);
    void SendSymbolOhlc(string symbol, ENUM_TIMEFRAMES timeframe, int depth);
    bool HasPriceChanged(string symbol, double currentBid, double currentAsk);
    bool HasNewBar(string symbol, ENUM_TIMEFRAMES timeframe);
    void UpdateStoredPrice(string symbol, double bid, double ask);
    void UpdateLastBarTime(string symbol, ENUM_TIMEFRAMES timeframe, datetime barTime);
    int FindSymbolIndex(string symbol);
    int FindOhlcIndex(string symbol, ENUM_TIMEFRAMES timeframe);
    double GetSymbolBid(string symbol);
    double GetSymbolAsk(string symbol);
    double GetSymbolSpread(string symbol);
    void SendPriceData(string jsonData);
    void SendOhlcData(string jsonData);
    void SendOrderEventData(string jsonData);
    string TimeframeToString(ENUM_TIMEFRAMES tf);

public:
    bool isTrackingPrice;
    bool isTrackingOhlc;
    bool isTrackingOrderEvent;
    bool isTrackingMbook;

    // Constructors
    CData();
    CData(SOCKET64 socket);
    CData(SOCKET64 socket, CCommandHandler *cmdHandler);

    // Public methods
    void setSymbols(const string &inputSymbols[]);
    void setMbookSymbols(const string &inputSymbols[]);
    void setOhlcs(const OhlcRequest &requests[]);
    void setOrderEvents(bool Enabled);
    void SendCurrentPrices(SOCKET64 sock);
    void SendCurrentOhlcs(SOCKET64 sock);
    bool ShouldSendUpdate(int intervalSeconds = 1);
    void SendCurrentMbook(SOCKET64 sock);
    void HandleTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result, SOCKET64 sock);
};

//+------------------------------------------------------------------+
//| Empty constructor                                                |
//+------------------------------------------------------------------+
CData::CData() {
    client_socket = INVALID_SOCKET64;
    lastSentTime = 0;
    commandHandler = NULL;
    isTrackingPrice = false;
    isTrackingOhlc = false;
    isTrackingOrderEvent = false;
    isTrackingMbook = false;
    firstRun = true;  // Add this line
    ArrayResize(symbols, 0);
    ArrayResize(mbookSymbols, 0);
    ArrayResize(symbolData, 0);
    ArrayResize(ohlcRequests, 0);
    ArrayResize(lastBookHashes, 0);  // Add this line
}

//+------------------------------------------------------------------+
//| Constructor with socket                                          |
//+------------------------------------------------------------------+
CData::CData(SOCKET64 socket) : client_socket(socket) {
    lastSentTime = 0;
    commandHandler = NULL;
    isTrackingPrice = false;
    isTrackingOhlc = false;
    isTrackingOrderEvent = false;
    isTrackingMbook = false;
    firstRun = true;  // Add this line
    ArrayResize(symbols, 0);
    ArrayResize(mbookSymbols, 0);  // Add this line
    ArrayResize(symbolData, 0);
    ArrayResize(ohlcRequests, 0);
    ArrayResize(lastBookHashes, 0);  // Add this line
}

//+------------------------------------------------------------------+
//| Constructor with socket and command handler                     |
//+------------------------------------------------------------------+
CData::CData(SOCKET64 socket, CCommandHandler *cmdHandler) : client_socket(socket), commandHandler(cmdHandler) {
    lastSentTime = 0;
    isTrackingPrice = false;
    isTrackingOhlc = false;
    isTrackingOrderEvent = false;
    isTrackingMbook = false;
    firstRun = true;  // Add this line
    ArrayResize(symbols, 0);
    ArrayResize(mbookSymbols, 0);  // Add this line
    ArrayResize(symbolData, 0);
    ArrayResize(ohlcRequests, 0);
    ArrayResize(lastBookHashes, 0);  // Add this line
}

//+------------------------------------------------------------------+
void CData::setSymbols(const string &inputSymbols[]) {
    ArrayResize(symbols, 0);
    ArrayResize(symbolData, 0);

    int count = ArraySize(inputSymbols);
    if(count > 0) {
        ArrayResize(symbols, count);
        ArrayResize(symbolData, count);

        for(int i = 0; i < count; i++) {      
            symbols[i] = inputSymbols[i];

            symbolData[i].symbol = inputSymbols[i];
            symbolData[i].lastBid = 0.0;
            symbolData[i].lastAsk = 0.0;
            symbolData[i].initialized = false;
        }
    }

    Print("Symbols set for price tracking: ", count, " symbols");
    for(int i = 0; i < count; i++) {
        Print("Symbol[", i, "]: ", symbols[i]);
    }

    isTrackingPrice = (ArraySize(symbols) > 0);
}

//+------------------------------------------------------------------+
//| Set OHLC tracking requests                                       |
//+------------------------------------------------------------------+
void CData::setOhlcs(const OhlcRequest &requests[]) {
    ArrayResize(ohlcRequests, 0);
    
    int count = ArraySize(requests);
    if(count > 0) {
        ArrayResize(ohlcRequests, count);
        
        for(int i = 0; i < count; i++) {
            ohlcRequests[i].symbol = requests[i].symbol;
            ohlcRequests[i].timeframe = requests[i].timeframe;
            ohlcRequests[i].depth = requests[i].depth;
            ohlcRequests[i].lastBarTime = 0;
            ohlcRequests[i].initialized = false;
        }
    }
    
    Print("OHLC requests set for tracking: ", count, " requests");
    for(int i = 0; i < count; i++) {
        Print("OHLC[", i, "]: ", ohlcRequests[i].symbol, " ", TimeframeToString(ohlcRequests[i].timeframe), " depth=", ohlcRequests[i].depth);
    }
    
    isTrackingOhlc = (ArraySize(ohlcRequests) > 0);
}

//+------------------------------------------------------------------+
//| Set Order EVENT tracking requests                                |
//+------------------------------------------------------------------+
void CData::setOrderEvents(bool Enabled) {
    isTrackingOrderEvent = Enabled;
}

void CData::HandleTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result, SOCKET64 sock)
{
    client_socket = sock;

    // We only care about executed deals (closed orders)
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD)
        return;

    long deal_ticket = (long)trans.deal;

    // Access deal details
    if (!HistoryDealSelect((ulong)deal_ticket))
        return;

    ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);

    // Only act on deal closures (exits)
    if (deal_entry != DEAL_ENTRY_OUT)
        return;

    string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
    double price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
    double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
    double swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
    double commission = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
    ulong order_ticket = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER);
    ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);

    // Get position ID to find the TP/SL levels
    ulong position_id = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
    Print(StringFormat("DEBUG: Position ID: %I64d", position_id));
    
    // Try to get TP/SL from the position history
    double sl = 0.0, tp = 0.0;
    ENUM_ORDER_TYPE order_type = ORDER_TYPE_BUY;
    
    // Method 1: Look for the opening deal
    if (HistorySelectByPosition(position_id))
    {
        int deals_total = HistoryDealsTotal();
        Print(StringFormat("DEBUG: Found %d deals for position", deals_total));
        
        for (int i = 0; i < deals_total; i++)
        {
            ulong deal = HistoryDealGetTicket(i);
            ENUM_DEAL_ENTRY entry_type = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
            
            if (entry_type == DEAL_ENTRY_IN) // Opening deal
            {
                ulong open_order = (ulong)HistoryDealGetInteger(deal, DEAL_ORDER);
                Print(StringFormat("DEBUG: Found opening order: %I64d", open_order));
                
                if (HistoryOrderSelect(open_order))
                {
                    sl = HistoryOrderGetDouble(open_order, ORDER_SL);
                    tp = HistoryOrderGetDouble(open_order, ORDER_TP);
                    order_type = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(open_order, ORDER_TYPE);
                    Print(StringFormat("DEBUG: From opening order - TP: %.5f, SL: %.5f", tp, sl));
                    break;
                }
            }
        }
    }

    // Get symbol point value for comparison tolerance
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tolerance = point * 10;

    string reason = "Unknown";

    Print(StringFormat("DEBUG: Final values - price=%.5f, tp=%.5f, sl=%.5f, tolerance=%.5f", 
                       price, tp, sl, tolerance));

    // Determine exit reason by comparing exit price to SL/TP levels
    if (tp > 0 && MathAbs(price - tp) <= tolerance)
    {
        reason = "TP";
        Print("DEBUG: Detected as TP hit!");
    }
    else if (sl > 0 && MathAbs(price - sl) <= tolerance)
    {
        reason = "SL";
        Print("DEBUG: Detected as SL hit!");
    }
    else
    {
        Print(StringFormat("DEBUG: No match - TP diff: %.5f, SL diff: %.5f", 
                          (tp > 0) ? MathAbs(price - tp) : -1,
                          (sl > 0) ? MathAbs(price - sl) : -1));
        
        // Fallback: Use deal reason if available
        ENUM_DEAL_REASON deal_reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal_ticket, DEAL_REASON);
        Print(StringFormat("DEBUG: Deal reason: %d", deal_reason));
        
        if (deal_reason == DEAL_REASON_TP)
            reason = "TP";
        else if (deal_reason == DEAL_REASON_SL)
            reason = "SL";
        else
            reason = "Manual";
    }

    // Determine original side from the ORDER TYPE (not deal type)
    string side = "";
    if (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT || order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_STOP_LIMIT)
        side = "BUY";
    else if (order_type == ORDER_TYPE_SELL || order_type == ORDER_TYPE_SELL_LIMIT || order_type == ORDER_TYPE_SELL_STOP || order_type == ORDER_TYPE_SELL_STOP_LIMIT)
        side = "SELL";
    else
        side = "UNKNOWN";

    // Calculate gross profit (before swap/commission) for additional info
    double gross_profit = profit + swap + commission;

    string json = StringFormat("{\"type\":\"trade_event\",\"symbol\":\"%s\",\"ticket\":%I64d,\"side\":\"%s\",\"reason\":\"%s\",\"profit\":%.2f,\"gross_profit\":%.2f,\"swap\":%.2f,\"commission\":%.2f}",
                               symbol, order_ticket, side, reason, profit, gross_profit, swap, commission);
    SendOrderEventData(json);
}

//+------------------------------------------------------------------+
//| Set Mbook tracking                                               |
//+------------------------------------------------------------------+
void CData::setMbookSymbols(const string &inputSymbols[]) {

    for (int i = 0; i < ArraySize(mbookSymbols); i++) {
        if (MarketBookRelease(mbookSymbols[i])) {
            Print("Unsubscribed from market book: ", mbookSymbols[i]);
        } else {
            Print("Failed to unsubscribe: ", mbookSymbols[i], " (", GetLastError(), ")");
        }
    }

    ArrayResize(mbookSymbols, 0);

    int count = ArraySize(inputSymbols);
    if(count > 0) {
        ArrayResize(mbookSymbols, count);

        for(int i = 0; i < count; i++) {      
            mbookSymbols[i] = inputSymbols[i];

            if (MarketBookAdd(mbookSymbols[i])) {
                Print("Subscribed to market book: ", mbookSymbols[i]);
            } else {
                Print("Failed to subscribe to: ", mbookSymbols[i], " (", GetLastError(), ")");
            }
        }
    }

    Print("Symbols set for mbook tracking: ", count, " symbols");
    for(int i = 0; i < count; i++) {
        Print("Symbol[", i, "]: ", mbookSymbols[i]);
    }

    isTrackingMbook = (ArraySize(mbookSymbols) > 0);
}


//+------------------------------------------------------------------+
//| Send current OHLC data for all tracked symbols/timeframes        |
//+------------------------------------------------------------------+
void CData::SendCurrentOhlcs(SOCKET64 sock) {
    client_socket = sock;
    
    for(int i = 0; i < ArraySize(ohlcRequests); i++) {
        string symbol = ohlcRequests[i].symbol;
        ENUM_TIMEFRAMES timeframe = ohlcRequests[i].timeframe;
        
        if(HasNewBar(symbol, timeframe) || !ohlcRequests[i].initialized) {
            SendSymbolOhlc(symbol, timeframe, ohlcRequests[i].depth);
            
            // Update last bar time
            MqlRates rates[];
            if(CopyRates(symbol, timeframe, 0, 1, rates) > 0) {
                UpdateLastBarTime(symbol, timeframe, rates[0].time);
                ohlcRequests[i].initialized = true;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Send current market book data (hash-based change detection)     |
//+------------------------------------------------------------------+
void CData::SendCurrentMbook(SOCKET64 sock) {
    client_socket = sock;

    for (int i = 0; i < ArraySize(mbookSymbols); i++) {
        string symbol = mbookSymbols[i];
        MqlBookInfo bookInfo[];

        if (!MarketBookGet(symbol, bookInfo)) {
            int err = GetLastError();
            Print("Failed to get market book for ", symbol, " error: ", (err));
            continue;
        }


        // Ensure hash array is large enough
        if (i >= ArraySize(lastBookHashes)) {
            ArrayResize(lastBookHashes, i + 1);
            lastBookHashes[i] = 0;
        }

        // Calculate current hash
        ulong currentHash = CalculateBookHash(bookInfo);

        // Skip if no change (except first run)
        if (currentHash == lastBookHashes[i] && !firstRun) {
            continue;
        }

        // Store new hash
        lastBookHashes[i] = currentHash;

        // Build and send JSON
        string jsonStr = "{";
        jsonStr += "\"type\":\"track_mbook\",";
        jsonStr += "\"symbol\":\"" + symbol + "\",";
        jsonStr += "\"market_book\":[";

        string timeStr = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS);
        for (int j = 0; j < ArraySize(bookInfo); j++) {
            if (j > 0) jsonStr += ",";

            string typeStr = (bookInfo[j].type == BOOK_TYPE_BUY) ? "BOOK_TYPE_BUY" : "BOOK_TYPE_SELL";

            jsonStr += StringFormat(
                "{\"time\":\"%s\",\"price\":%.5f,\"volume\":%.0f,\"volumereal\":%.2f,\"type\":\"%s\"}",
                timeStr,
                bookInfo[j].price,
                bookInfo[j].volume,
                bookInfo[j].volume_real,
                typeStr
            );
        }

        jsonStr += "]}";

        SendPriceData(jsonStr);
    }
    
    firstRun = false;
}


//+------------------------------------------------------------------+
//| Calculate hash for market book data                             |
//+------------------------------------------------------------------+
ulong CData::CalculateBookHash(MqlBookInfo &bookInfo[]) {
    ulong hash = 0;
    int size = ArraySize(bookInfo);
    
    for (int i = 0; i < size; i++) {
        ulong priceHash = (ulong)(bookInfo[i].price * 100000);
        ulong volumeHash = (ulong)bookInfo[i].volume;
        ulong volumeRealHash = (ulong)(bookInfo[i].volume_real * 100);
        ulong typeHash = (ulong)bookInfo[i].type;
        
        hash ^= priceHash + 0x9e3779b9 + (hash << 6) + (hash >> 2);
        hash ^= volumeHash + 0x9e3779b9 + (hash << 6) + (hash >> 2);
        hash ^= volumeRealHash + 0x9e3779b9 + (hash << 6) + (hash >> 2);
        hash ^= typeHash + 0x9e3779b9 + (hash << 6) + (hash >> 2);
    }
    
    return hash;
}


//+------------------------------------------------------------------+
//| Send OHLC data for specific symbol and timeframe                 |
//+------------------------------------------------------------------+
void CData::SendSymbolOhlc(string symbol, ENUM_TIMEFRAMES timeframe, int depth) {
    MqlRates rates[];
    
    int copied = CopyRates(symbol, timeframe, 0, depth, rates);
    if(copied <= 0) {
        Print("Failed to copy rates for ", symbol, " ", TimeframeToString(timeframe));
        return;
    }
    
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    Print("OHLC update for ", symbol, " ", TimeframeToString(timeframe), " - ", copied, " bars");
    
    string jsonStr = "{";
    jsonStr += "\"type\":\"ohlc_update\",";
    jsonStr += "\"symbol\":\"" + symbol + "\",";
    jsonStr += "\"timeframe\":\"" + TimeframeToString(timeframe) + "\",";
    jsonStr += "\"bars\":[";
    
    for(int i = 0; i < copied; i++) {
        if(i > 0) jsonStr += ",";
        
        jsonStr += "{";
        jsonStr += "\"time\":\"" + TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\",";
        jsonStr += "\"open\":" + DoubleToString(rates[i].open, digits) + ",";
        jsonStr += "\"high\":" + DoubleToString(rates[i].high, digits) + ",";
        jsonStr += "\"low\":" + DoubleToString(rates[i].low, digits) + ",";
        jsonStr += "\"close\":" + DoubleToString(rates[i].close, digits) + ",";
        jsonStr += "\"volume\":" + IntegerToString(rates[i].tick_volume);
        jsonStr += "}";
    }
    
    jsonStr += "]";
    jsonStr += "}";
    
    SendOhlcData(jsonStr);
}


//+------------------------------------------------------------------+
//| Check if there's a new bar for the symbol/timeframe             |
//+------------------------------------------------------------------+
bool CData::HasNewBar(string symbol, ENUM_TIMEFRAMES timeframe) {
    int index = FindOhlcIndex(symbol, timeframe);
    if(index < 0) return false;
    
    if(!ohlcRequests[index].initialized) {
        return true;
    }
    
    MqlRates rates[];
    if(CopyRates(symbol, timeframe, 0, 1, rates) <= 0) {
        return false;
    }
    
    return (rates[0].time > ohlcRequests[index].lastBarTime);
}

//+------------------------------------------------------------------+
//| Update last bar time for symbol/timeframe                       |
//+------------------------------------------------------------------+
void CData::UpdateLastBarTime(string symbol, ENUM_TIMEFRAMES timeframe, datetime barTime) {
    int index = FindOhlcIndex(symbol, timeframe);
    if(index >= 0) {
        ohlcRequests[index].lastBarTime = barTime;
    }
}

//+------------------------------------------------------------------+
//| Find OHLC index for symbol/timeframe combination                |
//+------------------------------------------------------------------+
int CData::FindOhlcIndex(string symbol, ENUM_TIMEFRAMES timeframe) {
    for(int i = 0; i < ArraySize(ohlcRequests); i++) {
        if(ohlcRequests[i].symbol == symbol && ohlcRequests[i].timeframe == timeframe) {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Convert timeframe enum to string                                |
//+------------------------------------------------------------------+
string CData::TimeframeToString(ENUM_TIMEFRAMES tf) {
    switch(tf) {
        case PERIOD_M1:  return "M1";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN1";
        default: return "UNKNOWN";
    }
}

void CData::SendCurrentPrices(SOCKET64 sock) {
    client_socket = sock;
    for (int i = 0; i < ArraySize(symbols); i++) {
        string symbol = symbols[i];
        double currentBid = GetSymbolBid(symbol);
        double currentAsk = GetSymbolAsk(symbol);

        if (HasPriceChanged(symbol, currentBid, currentAsk)) {
            SendSymbolPrice(symbol);
            UpdateStoredPrice(symbol, currentBid, currentAsk);
        }
    }
}

void CData::SendSymbolPrice(string symbol) {
    double bid = GetSymbolBid(symbol);
    double ask = GetSymbolAsk(symbol);
    double spread = GetSymbolSpread(symbol);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    datetime ts = TimeTradeServer();
    long tickVolume = SymbolInfoInteger(symbol, SYMBOL_VOLUME);
    MqlTick tick;
    long realVolume = 0;
    if(SymbolInfoTick(symbol, tick)) {
        if (tick.volume_real > 0) realVolume = (long)tick.volume_real;
        else realVolume = tick.volume;
    }

    string jsonStr = "{";
    jsonStr += "\"type\":\"price_update\",";
    jsonStr += "\"timestamp\":" + IntegerToString((long)ts) + ",";
    jsonStr += "\"symbol\":\"" + symbol + "\",";
    jsonStr += "\"volume\":" + IntegerToString(realVolume) + ",";
    jsonStr += "\"bid\":" + DoubleToString(bid, digits) + ",";
    jsonStr += "\"ask\":" + DoubleToString(ask, digits) + ",";
    jsonStr += "\"spread\":" + DoubleToString(spread, digits) + ",";
    jsonStr += "\"digits\":" + IntegerToString(digits);
    jsonStr += "}";

    SendPriceData(jsonStr);
}

bool CData::HasPriceChanged(string symbol, double currentBid, double currentAsk) {
    int index = FindSymbolIndex(symbol);
    if(index < 0) return false;

    if(!symbolData[index].initialized) {
        Print("Price not initialized for symbol: ", symbol);
        return true;
    }

    if(symbolData[index].lastBid != currentBid || symbolData[index].lastAsk != currentAsk) {
        return true;
    }

    return false;
}

void CData::UpdateStoredPrice(string symbol, double bid, double ask) {
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        symbolData[index].lastBid = bid;
        symbolData[index].lastAsk = ask;
        symbolData[index].initialized = true;
    }
}

int CData::FindSymbolIndex(string symbol) {
    for(int i = 0; i < ArraySize(symbolData); i++) {
        if(symbolData[i].symbol == symbol) {
            return i;
        }
    }
    return -1;
}

double CData::GetSymbolBid(string symbol) {
    return SymbolInfoDouble(symbol, SYMBOL_BID);
}

double CData::GetSymbolAsk(string symbol) {
    return SymbolInfoDouble(symbol, SYMBOL_ASK);
}

double CData::GetSymbolSpread(string symbol) {
    return SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
}

void CData::SendPriceData(string jsonData) {
    if (client_socket == INVALID_SOCKET64) {
        Print("Socket not connected - cannot send price data");
        return;
    }
    SendWebSocketTextFrame(client_socket, jsonData + "}");
}

void CData::SendOhlcData(string jsonData) {
    if (client_socket == INVALID_SOCKET64) {
        Print("Socket not connected - cannot send OHLC data");
        return;
    }
    SendWebSocketTextFrame(client_socket, jsonData + "}");
}

void CData::SendOrderEventData(string jsonData) {
    if (client_socket == INVALID_SOCKET64) {
        Print("Socket not connected - cannot send Order Event data");
        return;
    }
    SendWebSocketTextFrame(client_socket, jsonData + "}");
}

#endif // DATA_MQH