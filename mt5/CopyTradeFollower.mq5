//+------------------------------------------------------------------+
//|                                            CopyTradeFollower.mq5 |
//| Copies the current Master snapshot from the local Fastify API.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Copy-trade Follower EA"

#include <Trade\Trade.mqh>

#define COPY_COMMENT_PREFIX "COPY_MASTER_"

enum ENUM_COPY_LOT_MODE
{
   SAME_AS_MASTER = 0,
   FIXED          = 1,
   MULTIPLIER     = 2
};

input group "Connection"
input string ApiUrl        = "http://127.0.0.1:4000/api/master/state";
input int    SyncIntervalMs = 250;
input bool   Enabled        = true;

input group "Copy Settings"
input ulong MagicNumber   = 26090201;
input bool  CopyBuy       = true;
input bool  CopySell      = true;
input bool  CopyStopLoss  = true;
input bool  CopyTakeProfit = true;
input bool  CopyModify    = true;
input bool  CopyClosedPositions = true;

input group "Volume"
input ENUM_COPY_LOT_MODE LotMode      = SAME_AS_MASTER;
input double             FixedLot     = 0.01;
input double             LotMultiplier = 1.0;
input double             MaxLot       = 10.0;

input group "Symbols"
input bool   AutoDetectSymbol   = true;
input string ManualSymbolMapping = ""; // MASTER=FOLLOWER;XAUUSD=XAUUSD.pro

struct MasterPosition
{
   string ticket;
   string symbol;
   ENUM_POSITION_TYPE type;
   double volume;
   double openPrice;
   double stopLoss;
   double takeProfit;
};

CTrade g_trade;
int    g_syncIntervalMs = 250;

string g_mappedMasterTickets[];
ulong  g_mappedFollowerTickets[];
string g_cachedMasterSymbols[];
string g_cachedFollowerSymbols[];

string Trim(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

string Upper(string value)
{
   StringToUpper(value);
   return value;
}

bool StartsWith(const string value, const string prefix)
{
   return StringLen(value) >= StringLen(prefix) &&
      StringSubstr(value, 0, StringLen(prefix)) == prefix;
}

int FindMatchingJsonToken(const string json,
                          const int start,
                          const ushort openToken,
                          const ushort closeToken)
{
   int depth = 0;
   bool inString = false;
   bool escaped = false;

   for(int index = start; index < StringLen(json); index++)
   {
      ushort character = StringGetCharacter(json, index);

      if(inString)
      {
         if(escaped)
            escaped = false;
         else if(character == 92)
            escaped = true;
         else if(character == 34)
            inString = false;
         continue;
      }

      if(character == 34)
      {
         inString = true;
         continue;
      }

      if(character == openToken)
         depth++;
      else if(character == closeToken)
      {
         depth--;
         if(depth == 0)
            return index;
      }
   }

   return -1;
}

int FindJsonValueStart(const string json, const string key)
{
   string quotedKey = "\"" + key + "\"";
   int keyPosition = StringFind(json, quotedKey);
   if(keyPosition < 0)
      return -1;

   int colonPosition = StringFind(json, ":", keyPosition + StringLen(quotedKey));
   if(colonPosition < 0)
      return -1;

   int valuePosition = colonPosition + 1;
   while(valuePosition < StringLen(json))
   {
      ushort character = StringGetCharacter(json, valuePosition);
      if(character != 32 && character != 9 && character != 10 && character != 13)
         break;
      valuePosition++;
   }

   return valuePosition;
}

bool ReadJsonString(const string json, const int start, string &value)
{
   if(start < 0 || start >= StringLen(json) ||
      StringGetCharacter(json, start) != 34)
      return false;

   value = "";
   bool escaped = false;

   for(int index = start + 1; index < StringLen(json); index++)
   {
      ushort character = StringGetCharacter(json, index);

      if(escaped)
      {
         if(character == 34 || character == 92 || character == 47)
            value += ShortToString(character);
         else if(character == 98)
            value += ShortToString(8);
         else if(character == 102)
            value += ShortToString(12);
         else if(character == 110)
            value += ShortToString(10);
         else if(character == 114)
            value += ShortToString(13);
         else if(character == 116)
            value += ShortToString(9);
         else
            value += ShortToString(character);

         escaped = false;
         continue;
      }

      if(character == 92)
      {
         escaped = true;
         continue;
      }

      if(character == 34)
         return true;

      value += ShortToString(character);
   }

   return false;
}

bool ExtractJsonScalar(const string json, const string key, string &value)
{
   int start = FindJsonValueStart(json, key);
   if(start < 0)
      return false;

   if(StringGetCharacter(json, start) == 34)
      return ReadJsonString(json, start, value);

   int end = start;
   while(end < StringLen(json))
   {
      ushort character = StringGetCharacter(json, end);
      if(character == 44 || character == 125 ||
         character == 32 || character == 9 ||
         character == 10 || character == 13)
         break;
      end++;
   }

   if(end <= start)
      return false;

   value = StringSubstr(json, start, end - start);
   return true;
}

bool ExtractJsonNumber(const string json, const string key, double &value)
{
   string raw;
   if(!ExtractJsonScalar(json, key, raw))
      return false;

   value = StringToDouble(raw);
   return true;
}

bool ParseMasterPositions(const string json, MasterPosition &positions[])
{
   ArrayResize(positions, 0);

   int positionsKey = StringFind(json, "\"positions\"");
   if(positionsKey < 0)
      return false;

   int arrayStart = StringFind(json, "[", positionsKey);
   if(arrayStart < 0)
      return false;

   int arrayEnd = FindMatchingJsonToken(json, arrayStart, 91, 93);
   if(arrayEnd < 0)
      return false;

   int cursor = arrayStart + 1;
   while(cursor < arrayEnd)
   {
      int objectStart = StringFind(json, "{", cursor);
      if(objectStart < 0 || objectStart >= arrayEnd)
         break;

      int objectEnd = FindMatchingJsonToken(json, objectStart, 123, 125);
      if(objectEnd < 0 || objectEnd > arrayEnd)
         return false;

      string objectJson =
         StringSubstr(json, objectStart, objectEnd - objectStart + 1);
      MasterPosition position;
      string type;

      if(!ExtractJsonScalar(objectJson, "ticket", position.ticket) ||
         !ExtractJsonScalar(objectJson, "symbol", position.symbol) ||
         !ExtractJsonScalar(objectJson, "type", type) ||
         !ExtractJsonNumber(objectJson, "volume", position.volume) ||
         !ExtractJsonNumber(objectJson, "openPrice", position.openPrice) ||
         !ExtractJsonNumber(objectJson, "stopLoss", position.stopLoss) ||
         !ExtractJsonNumber(objectJson, "takeProfit", position.takeProfit))
         return false;

      position.ticket = Trim(position.ticket);
      position.symbol = Trim(position.symbol);
      type = Upper(Trim(type));

      if(StringLen(position.ticket) == 0 || StringLen(position.symbol) == 0 ||
         position.volume <= 0.0 || position.openPrice <= 0.0 ||
         position.stopLoss < 0.0 || position.takeProfit < 0.0)
         return false;

      if(type == "BUY")
         position.type = POSITION_TYPE_BUY;
      else if(type == "SELL")
         position.type = POSITION_TYPE_SELL;
      else
         return false;

      int size = ArraySize(positions);
      ArrayResize(positions, size + 1);
      positions[size] = position;
      cursor = objectEnd + 1;
   }

   return true;
}

bool FetchMasterPositions(MasterPosition &positions[])
{
   char requestBody[];
   char responseBody[];
   string responseHeaders;
   string headers = "Accept: application/json\r\n";

   ResetLastError();
   int status = WebRequest(
      "GET",
      ApiUrl,
      headers,
      2000,
      requestBody,
      responseBody,
      responseHeaders);

   if(status < 0)
   {
      int errorCode = GetLastError();
      PrintFormat("CopyTradeFollower: WebRequest failed. error=%d url=%s",
         errorCode, ApiUrl);
      if(errorCode == 4060)
         Print("CopyTradeFollower: add http://127.0.0.1:4000 to the MT5 WebRequest allowlist.");
      return false;
   }

   string response =
      CharArrayToString(responseBody, 0, WHOLE_ARRAY, CP_UTF8);

   if(status != 200)
   {
      PrintFormat("CopyTradeFollower: API returned HTTP %d. response=%s",
         status, response);
      return false;
   }

   if(!ParseMasterPositions(response, positions))
   {
      Print("CopyTradeFollower: invalid master-state JSON; no trades were changed.");
      return false;
   }

   return true;
}

string MasterTicketFromComment(const string comment)
{
   if(!StartsWith(comment, COPY_COMMENT_PREFIX))
      return "";

   return Trim(StringSubstr(comment, StringLen(COPY_COMMENT_PREFIX)));
}

bool IsOwnedPosition(const ulong positionTicket, string &masterTicket)
{
   if(!PositionSelectByTicket(positionTicket))
      return false;

   if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return false;

   masterTicket = MasterTicketFromComment(PositionGetString(POSITION_COMMENT));
   return StringLen(masterTicket) > 0;
}

void RebuildMasterTicketMapping()
{
   ArrayResize(g_mappedMasterTickets, 0);
   ArrayResize(g_mappedFollowerTickets, 0);

   int total = PositionsTotal();
   for(int index = 0; index < total; index++)
   {
      ulong followerTicket = PositionGetTicket(index);
      string masterTicket;
      if(followerTicket == 0 || !IsOwnedPosition(followerTicket, masterTicket))
         continue;

      int size = ArraySize(g_mappedMasterTickets);
      ArrayResize(g_mappedMasterTickets, size + 1);
      ArrayResize(g_mappedFollowerTickets, size + 1);
      g_mappedMasterTickets[size] = masterTicket;
      g_mappedFollowerTickets[size] = followerTicket;
   }
}

ulong FindFollowerTicket(const string masterTicket)
{
   for(int index = 0; index < ArraySize(g_mappedMasterTickets); index++)
   {
      if(g_mappedMasterTickets[index] == masterTicket)
         return g_mappedFollowerTickets[index];
   }

   return 0;
}

bool MasterPositionExists(const MasterPosition &positions[],
                          const string masterTicket)
{
   for(int index = 0; index < ArraySize(positions); index++)
   {
      if(positions[index].ticket == masterTicket)
         return true;
   }

   return false;
}

string ManualMappedSymbol(const string masterSymbol)
{
   string mappings[];
   ushort separator = StringGetCharacter(";", 0);
   int count = StringSplit(ManualSymbolMapping, separator, mappings);

   for(int index = 0; index < count; index++)
   {
      string pair = Trim(mappings[index]);
      int equals = StringFind(pair, "=");
      if(equals <= 0)
         continue;

      string source = Trim(StringSubstr(pair, 0, equals));
      string target = Trim(StringSubstr(pair, equals + 1));
      if(Upper(source) == Upper(masterSymbol) && StringLen(target) > 0)
         return target;
   }

   return "";
}

string CachedFollowerSymbol(const string masterSymbol)
{
   for(int index = 0; index < ArraySize(g_cachedMasterSymbols); index++)
   {
      if(g_cachedMasterSymbols[index] == masterSymbol)
         return g_cachedFollowerSymbols[index];
   }

   return "";
}

void CacheFollowerSymbol(const string masterSymbol, const string followerSymbol)
{
   int size = ArraySize(g_cachedMasterSymbols);
   ArrayResize(g_cachedMasterSymbols, size + 1);
   ArrayResize(g_cachedFollowerSymbols, size + 1);
   g_cachedMasterSymbols[size] = masterSymbol;
   g_cachedFollowerSymbols[size] = followerSymbol;
}

int SymbolMatchScore(const string masterSymbol, const string candidateSymbol)
{
   string master = Upper(masterSymbol);
   string candidate = Upper(candidateSymbol);

   if(master == candidate)
      return 10000;

   int masterLength = StringLen(master);
   int candidateLength = StringLen(candidate);
   int shorterLength = (int)MathMin(masterLength, candidateLength);
   if(shorterLength < 3)
      return -1;

   if(StringSubstr(master, 0, shorterLength) !=
      StringSubstr(candidate, 0, shorterLength))
      return -1;

   return 1000 - (int)MathAbs(masterLength - candidateLength);
}

string ResolveFollowerSymbol(const string masterSymbol)
{
   string cached = CachedFollowerSymbol(masterSymbol);
   if(StringLen(cached) > 0 && SymbolSelect(cached, true))
      return cached;

   string manual = ManualMappedSymbol(masterSymbol);
   if(StringLen(manual) > 0)
   {
      if(SymbolSelect(manual, true))
      {
         CacheFollowerSymbol(masterSymbol, manual);
         return manual;
      }

      PrintFormat("CopyTradeFollower: manual symbol mapping unavailable: %s -> %s",
         masterSymbol, manual);
      return "";
   }

   if(SymbolSelect(masterSymbol, true))
   {
      CacheFollowerSymbol(masterSymbol, masterSymbol);
      return masterSymbol;
   }

   if(!AutoDetectSymbol)
   {
      PrintFormat("CopyTradeFollower: follower symbol not found: %s", masterSymbol);
      return "";
   }

   string bestSymbol = "";
   int bestScore = -1;
   int total = SymbolsTotal(false);

   for(int index = 0; index < total; index++)
   {
      string candidate = SymbolName(index, false);
      int score = SymbolMatchScore(masterSymbol, candidate);
      if(score > bestScore)
      {
         bestScore = score;
         bestSymbol = candidate;
      }
   }

   if(bestScore < 0 || StringLen(bestSymbol) == 0 ||
      !SymbolSelect(bestSymbol, true))
   {
      PrintFormat("CopyTradeFollower: unable to auto-map master symbol %s",
         masterSymbol);
      return "";
   }

   CacheFollowerSymbol(masterSymbol, bestSymbol);
   PrintFormat("CopyTradeFollower: auto-mapped %s -> %s",
      masterSymbol, bestSymbol);
   return bestSymbol;
}

int VolumeDigits(const double step)
{
   for(int digits = 0; digits <= 8; digits++)
   {
      if(MathAbs(NormalizeDouble(step, digits) - step) < 0.000000001)
         return digits;
   }

   return 8;
}

double NormalizeFollowerVolume(const string symbol, const double masterVolume)
{
   double requested = masterVolume;
   if(LotMode == FIXED)
      requested = FixedLot;
   else if(LotMode == MULTIPLIER)
      requested = masterVolume * LotMultiplier;

   double minimum = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(minimum <= 0.0 || maximum <= 0.0 || step <= 0.0 || requested <= 0.0)
      return 0.0;

   double allowedMaximum = maximum;
   if(MaxLot > 0.0)
      allowedMaximum = MathMin(allowedMaximum, MaxLot);
   if(allowedMaximum < minimum)
      return 0.0;

   requested = MathMax(minimum, MathMin(requested, allowedMaximum));
   double normalized = minimum +
      MathFloor((requested - minimum) / step + 0.000000001) * step;
   normalized = MathMin(normalized, allowedMaximum);

   return NormalizeDouble(normalized, VolumeDigits(step));
}

double NormalizePrice(const string symbol, const double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

bool IsValidStop(const string symbol,
                 const ENUM_POSITION_TYPE type,
                 const bool isStopLoss,
                 const double price,
                 const MqlTick &tick)
{
   if(price == 0.0)
      return true;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minimumDistance = stopLevel * point;

   if(type == POSITION_TYPE_BUY)
      return isStopLoss
         ? price < tick.bid - minimumDistance
         : price > tick.ask + minimumDistance;

   return isStopLoss
      ? price > tick.ask + minimumDistance
      : price < tick.bid - minimumDistance;
}

void PrepareOpenStops(const MasterPosition &master,
                      const string symbol,
                      const MqlTick &tick,
                      double &stopLoss,
                      double &takeProfit)
{
   stopLoss = 0.0;
   takeProfit = 0.0;

   if(CopyStopLoss &&
      IsValidStop(symbol, master.type, true, master.stopLoss, tick))
      stopLoss = NormalizePrice(symbol, master.stopLoss);

   if(CopyTakeProfit &&
      IsValidStop(symbol, master.type, false, master.takeProfit, tick))
      takeProfit = NormalizePrice(symbol, master.takeProfit);
}

bool HasEnoughMargin(const string symbol,
                     const ENUM_POSITION_TYPE type,
                     const double volume,
                     const MqlTick &tick)
{
   ENUM_ORDER_TYPE orderType = type == POSITION_TYPE_BUY
      ? ORDER_TYPE_BUY
      : ORDER_TYPE_SELL;
   double price = type == POSITION_TYPE_BUY ? tick.ask : tick.bid;
   double requiredMargin = 0.0;

   if(!OrderCalcMargin(orderType, symbol, volume, price, requiredMargin))
   {
      PrintFormat("CopyTradeFollower: margin calculation failed for %s. error=%d",
         symbol, GetLastError());
      return false;
   }

   if(requiredMargin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      PrintFormat("CopyTradeFollower: insufficient margin for %s %.8f lots",
         symbol, volume);
      return false;
   }

   return true;
}

bool TradeRequestSucceeded(const bool requestAccepted)
{
   if(!requestAccepted)
      return false;

   uint code = g_trade.ResultRetcode();
   return code == TRADE_RETCODE_DONE ||
      code == TRADE_RETCODE_DONE_PARTIAL ||
      code == TRADE_RETCODE_PLACED;
}

void LogTradeFailure(const string action,
                     const string masterTicket,
                     const string symbol)
{
   PrintFormat(
      "CopyTradeFollower: %s failed. master=%s symbol=%s retcode=%u message=%s",
      action,
      masterTicket,
      symbol,
      g_trade.ResultRetcode(),
      g_trade.ResultRetcodeDescription());
}

bool OpenCopiedPosition(const MasterPosition &master)
{
   if((master.type == POSITION_TYPE_BUY && !CopyBuy) ||
      (master.type == POSITION_TYPE_SELL && !CopySell))
      return false;

   if(FindFollowerTicket(master.ticket) != 0)
      return true;

   string symbol = ResolveFollowerSymbol(master.symbol);
   if(StringLen(symbol) == 0)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      PrintFormat("CopyTradeFollower: no valid market price for %s", symbol);
      return false;
   }

   long tradeMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED ||
      tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY ||
      (master.type == POSITION_TYPE_BUY && tradeMode == SYMBOL_TRADE_MODE_SHORTONLY) ||
      (master.type == POSITION_TYPE_SELL && tradeMode == SYMBOL_TRADE_MODE_LONGONLY))
   {
      PrintFormat("CopyTradeFollower: market is not open for new trades on %s",
         symbol);
      return false;
   }

   double volume = NormalizeFollowerVolume(symbol, master.volume);
   if(volume <= 0.0)
   {
      PrintFormat("CopyTradeFollower: invalid normalized volume for %s", symbol);
      return false;
   }

   if(!HasEnoughMargin(symbol, master.type, volume, tick))
      return false;

   double stopLoss;
   double takeProfit;
   PrepareOpenStops(master, symbol, tick, stopLoss, takeProfit);

   string comment = COPY_COMMENT_PREFIX + master.ticket;
   g_trade.SetTypeFillingBySymbol(symbol);

   bool accepted = master.type == POSITION_TYPE_BUY
      ? g_trade.Buy(volume, symbol, 0.0, stopLoss, takeProfit, comment)
      : g_trade.Sell(volume, symbol, 0.0, stopLoss, takeProfit, comment);

   if(!TradeRequestSucceeded(accepted))
   {
      LogTradeFailure("open", master.ticket, symbol);
      return false;
   }

   RebuildMasterTicketMapping();
   return true;
}

void ModifyCopiedPosition(const MasterPosition &master,
                          const ulong followerTicket)
{
   if(!CopyModify || !PositionSelectByTicket(followerTicket))
      return;

   string ownedMasterTicket;
   if(!IsOwnedPosition(followerTicket, ownedMasterTicket) ||
      ownedMasterTicket != master.ticket)
      return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE localType =
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(localType != master.type)
   {
      PrintFormat("CopyTradeFollower: direction mismatch for master %s; position left unchanged.",
         master.ticket);
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return;

   double currentStopLoss = PositionGetDouble(POSITION_SL);
   double currentTakeProfit = PositionGetDouble(POSITION_TP);
   double desiredStopLoss = currentStopLoss;
   double desiredTakeProfit = currentTakeProfit;

   if(CopyStopLoss)
   {
      if(master.stopLoss == 0.0)
         desiredStopLoss = 0.0;
      else if(IsValidStop(symbol, localType, true, master.stopLoss, tick))
         desiredStopLoss = NormalizePrice(symbol, master.stopLoss);
   }

   if(CopyTakeProfit)
   {
      if(master.takeProfit == 0.0)
         desiredTakeProfit = 0.0;
      else if(IsValidStop(symbol, localType, false, master.takeProfit, tick))
         desiredTakeProfit = NormalizePrice(symbol, master.takeProfit);
   }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(MathAbs(currentStopLoss - desiredStopLoss) < point * 0.5 &&
      MathAbs(currentTakeProfit - desiredTakeProfit) < point * 0.5)
      return;

   bool accepted =
      g_trade.PositionModify(followerTicket, desiredStopLoss, desiredTakeProfit);
   if(!TradeRequestSucceeded(accepted))
      LogTradeFailure("modify", master.ticket, symbol);
}

void CloseMissingCopiedPositions(const MasterPosition &masterPositions[])
{
   if(!CopyClosedPositions)
      return;

   for(int index = ArraySize(g_mappedFollowerTickets) - 1; index >= 0; index--)
   {
      string masterTicket = g_mappedMasterTickets[index];
      ulong followerTicket = g_mappedFollowerTickets[index];
      if(MasterPositionExists(masterPositions, masterTicket))
         continue;

      string ownedMasterTicket;
      if(!IsOwnedPosition(followerTicket, ownedMasterTicket) ||
         ownedMasterTicket != masterTicket)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      bool accepted = g_trade.PositionClose(followerTicket);
      if(!TradeRequestSucceeded(accepted))
         LogTradeFailure("close", masterTicket, symbol);
   }

   RebuildMasterTicketMapping();
}

void SynchronizeFollower(const MasterPosition &masterPositions[])
{
   RebuildMasterTicketMapping();
   CloseMissingCopiedPositions(masterPositions);

   for(int index = 0; index < ArraySize(masterPositions); index++)
   {
      ulong followerTicket = FindFollowerTicket(masterPositions[index].ticket);
      if(followerTicket == 0)
      {
         OpenCopiedPosition(masterPositions[index]);
         followerTicket = FindFollowerTicket(masterPositions[index].ticket);
      }

      if(followerTicket != 0)
         ModifyCopiedPosition(masterPositions[index], followerTicket);
   }
}

int OnInit()
{
   if(StringLen(Trim(ApiUrl)) == 0)
   {
      Print("CopyTradeFollower: ApiUrl cannot be empty.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(MagicNumber == 0)
   {
      Print("CopyTradeFollower: MagicNumber must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_syncIntervalMs = SyncIntervalMs > 0 ? SyncIntervalMs : 250;
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetAsyncMode(false);
   RebuildMasterTicketMapping();

   ResetLastError();
   if(!EventSetMillisecondTimer(g_syncIntervalMs))
   {
      PrintFormat("CopyTradeFollower: failed to start timer. interval=%d error=%d",
         g_syncIntervalMs, GetLastError());
      return INIT_FAILED;
   }

   PrintFormat("CopyTradeFollower started. enabled=%s url=%s interval=%dms mapped=%d",
      Enabled ? "true" : "false",
      ApiUrl,
      g_syncIntervalMs,
      ArraySize(g_mappedMasterTickets));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   PrintFormat("CopyTradeFollower stopped. reason=%d", reason);
}

void OnTimer()
{
   if(!Enabled)
      return;

   MasterPosition positions[];
   if(!FetchMasterPositions(positions))
      return;

   SynchronizeFollower(positions);
}
//+------------------------------------------------------------------+
