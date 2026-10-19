//+------------------------------------------------------------------+
//|                                            CopyTradeFollower.mq5 |
//| Syncs with the local Fastify API: copies the Master snapshot,    |
//| applies settings and runs commands sent from the web dashboard.  |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "Copy-trade Follower EA"

#include <Trade\Trade.mqh>

#define COPY_COMMENT_PREFIX "Copy AiO_"
#define LEGACY_COPY_COMMENT_PREFIX "COPY_MASTER_"
#define MAX_REMEMBERED_COMMANDS 100

// The comments are the names shown in the MT5 inputs dropdown
enum ENUM_COPY_LOT_MODE
{
   SAME_AS_MASTER = 0, // Same as master
   FIXED          = 1, // Fixed lot
   MULTIPLIER     = 2, // Master lot x multiplier
   STEP_LOT       = 3  // Step lot
};

// Fixed for every follower. Lot size is set in the inputs below; the other
// copy and risk settings come from the API and are edited in the web dashboard.
// Add API_BASE_URL to MT5's WebRequest allowlist.
#define API_BASE_URL      "https://copy-trade-api.salatrades.com"
#define SYNC_INTERVAL_MS  100
// Long polling: the API may hold a sync this long, answering the moment the
// master's trades, the settings or a command change. The HTTP timeout must
// stay above it.
#define SYNC_WAIT_MS      1500
#define HTTP_TIMEOUT_MS   5000
// Marks the trades this EA copied. Keep it unchanged so positions copied
// before an update are still recognised.
#define COPY_MAGIC_NUMBER 26090201

// The comment after each input is the label shown in MT5.
input group "Connection"
// The server's EA_API_KEY, sent in the X-EA-Key header
input string ApiKey = ""; // API key (EA_API_KEY from the server)

input group "Copy"
// false keeps reporting to the dashboard but never trades
input bool Enabled = true; // Enable copy trading on this terminal

input group "Lot size"
input ENUM_COPY_LOT_MODE LotMode = SAME_AS_MASTER; // Lot mode
input double FixedLot            = 0.01; // Fixed lot (Fixed lot mode)
input double LotMultiplier       = 1.0;  // Multiplier (Master lot x multiplier mode)
input double StepStartMultiplier = 1.0;  // Step lot: multiplier for the 1st trade
input double StepMultiplier      = 0.5;  // Step lot: added for each next trade
input double StepMinMultiplier   = 0.1;  // Step lot: lowest multiplier
input double StepMaxMultiplier   = 10.0; // Step lot: highest multiplier
input double MaxLot              = 10.0; // Max lot per copied trade

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

struct CopySettings
{
   bool               copyBuy;
   bool               copySell;
   bool               copyStopLoss;
   bool               copyTakeProfit;
   bool               copyModify;
   bool               copyClosedPositions;
   int                maxOpenPositions;
   double             maxDailyLossPercent;
   bool               closeAllOnDailyLoss;
};

CTrade g_trade;

string g_mappedMasterTickets[];
ulong  g_mappedFollowerTickets[];
bool     g_apiOnline             = false;
int      g_lastHttpStatus        = 0;
datetime g_lastSuccessfulSync    = 0;
string   g_masterAccountNumber   = "N/A";
int      g_masterPositionCount   = 0;
string   g_lastFollowerError     = "WAITING FOR API";
string   g_followerDashboardState = "";

// State received from the API.
CopySettings g_settings;
bool     g_haveSettings      = false;
long     g_settingsVersion   = 0;
bool     g_copyEnabled       = false;
string   g_stopReason        = "";
bool     g_masterOnline      = false;
// Master state version received last; the API waits while it is still current
long     g_masterVersion     = 0;
bool     g_haveMasterState   = false;
string   g_pairingCode       = "";
datetime g_pairingExpiresAt  = 0;

// Symbol problems repeat on every sync; log each distinct message once.
// The list is cleared when new settings arrive, so problems are reported again.
string g_loggedMessages[];

// Set when this EA stops copying by itself; sent to the API until it records it.
string   g_autoStopReason    = "";

// Results of commands already run, so a repeated command is acked, not re-run.
string g_doneCommandIds[];
string g_doneCommandStatuses[];
string g_doneCommandErrors[];

#define FOLLOWER_DASHBOARD_PREFIX "CTF_DASH_"

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

string AccountLogin()
{
   return (string)AccountInfoInteger(ACCOUNT_LOGIN);
}

void SetFollowerDashboardError(const string message)
{
   g_lastFollowerError = message;
}

string FollowerDashboardTime(const datetime value)
{
   return value > 0 ? TimeToString(value, TIME_SECONDS) : "NEVER";
}

string FollowerDashboardClip(const string value, const int maximumLength)
{
   if(StringLen(value) <= maximumLength)
      return value;
   return StringSubstr(value, 0, maximumLength - 3) + "...";
}

void FollowerDashboardSetLabel(const string key,
                               const int y,
                               const string text,
                               const color textColor,
                               const int fontSize)
{
   string name = FOLLOWER_DASHBOARD_PREFIX + key;
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 18);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }

   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateFollowerDashboard()
{
   string background = FOLLOWER_DASHBOARD_PREFIX + "BACKGROUND";
   if(ObjectFind(0, background) < 0)
   {
      if(!ObjectCreate(0, background, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, background, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, background, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, background, OBJPROP_YDISTANCE, 15);
      ObjectSetInteger(0, background, OBJPROP_BGCOLOR, C'20,24,32');
      ObjectSetInteger(0, background, OBJPROP_COLOR, C'65,75,92');
      ObjectSetInteger(0, background, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, background, OBJPROP_BACK, false);
      ObjectSetInteger(0, background, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, background, OBJPROP_HIDDEN, true);
   }

   // Sized on every call so a panel left from an older version grows to fit
   ObjectSetInteger(0, background, OBJPROP_XSIZE, 360);
   ObjectSetInteger(0, background, OBJPROP_YSIZE, 354);
}

bool IsCopying()
{
   return Enabled && g_haveSettings && g_copyEnabled &&
      StringLen(g_autoStopReason) == 0;
}

string CopyStatusText()
{
   if(!Enabled)
      return "DISABLED ON TERMINAL";
   if(!g_haveSettings)
      return "WAITING FOR SETTINGS";
   if(IsCopying())
      return "ON";

   string reason = StringLen(g_autoStopReason) > 0 ? g_autoStopReason : g_stopReason;
   return StringLen(reason) > 0 ? "OFF (" + reason + ")" : "OFF";
}

string PairingText()
{
   if(StringLen(g_pairingCode) == 0)
      return "WAITING";

   long secondsLeft = (long)(g_pairingExpiresAt - TimeGMT());
   if(secondsLeft <= 0)
      return "REFRESHING...";

   return StringFormat("%s  (%d:%02d)", g_pairingCode,
      (int)(secondsLeft / 60), (int)(secondsLeft % 60));
}

//--- Risk settings shown on the panel ------------------------------------

string OnOff(const bool value)
{
   return value ? "on" : "off";
}

string LotSettingsText()
{
   string maxLot = StringFormat("max %.2f", MaxLot);

   if(LotMode == FIXED)
      return StringFormat("Fixed %.2f, %s", FixedLot, maxLot);
   if(LotMode == MULTIPLIER)
      return StringFormat("Master x%.2f, %s", LotMultiplier, maxLot);
   if(LotMode == STEP_LOT)
      return StringFormat("Step x%.1f%+.1f [%.1f-%.1f], %s",
         StepStartMultiplier, StepMultiplier,
         StepMinMultiplier, StepMaxMultiplier, maxLot);
   return "Same as master, " + maxLot;
}

string TradesSettingsText()
{
   return "BUY " + OnOff(g_settings.copyBuy) +
      "  SELL " + OnOff(g_settings.copySell) +
      "  SL " + OnOff(g_settings.copyStopLoss) +
      "  TP " + OnOff(g_settings.copyTakeProfit);
}

string MaxPositionsText()
{
   if(g_settings.maxOpenPositions <= 0)
      return "unlimited";
   return StringFormat("%d / %d open", ArraySize(g_mappedMasterTickets),
      g_settings.maxOpenPositions);
}

// Today's loss against the limit, e.g. "1.25% of 5.00%, then close all"
string DailyLossText()
{
   if(g_settings.maxDailyLossPercent <= 0.0)
      return "off";

   return StringFormat("%.2f%% of %.2f%%%s",
      MathMax(0.0, DailyLossPercent()), g_settings.maxDailyLossPercent,
      g_settings.closeAllOnDailyLoss ? ", then close all" : "");
}

void UpdateFollowerDashboard()
{
   string apiStatus = g_apiOnline ? "ONLINE" : "ERROR";
   string broker = FollowerDashboardClip(AccountInfoString(ACCOUNT_COMPANY), 37);
   string master = g_masterAccountNumber +
      (g_masterOnline ? " (online)" : " (offline)");
   string copyStatus = FollowerDashboardClip(CopyStatusText(), 38);
   string settingsText = g_haveSettings
      ? "v" + IntegerToString(g_settingsVersion)
      : "WAITING";
   string pairing = PairingText();
   string lastError = FollowerDashboardClip(g_lastFollowerError, 39);
   int copiedPositions = ArraySize(g_mappedMasterTickets);
   string waiting = "WAITING";
   string lots = FollowerDashboardClip(LotSettingsText(), 34);
   string trades = g_haveSettings ? TradesSettingsText() : waiting;
   string maxPositions = g_haveSettings ? MaxPositionsText() : waiting;
   string dailyLoss = g_haveSettings ? FollowerDashboardClip(DailyLossText(), 27) : waiting;
   string displayState = lots + "|" + trades + "|" + maxPositions + "|" + dailyLoss + "|" + StringFormat(
      "%s|%s|%s|%s|%d|%d|%s|%s|%s|%s|%s",
      apiStatus,
      AccountLogin(),
      broker,
      master,
      g_masterPositionCount,
      copiedPositions,
      copyStatus,
      settingsText,
      pairing,
      FollowerDashboardTime(g_lastSuccessfulSync),
      lastError);

   if(displayState == g_followerDashboardState)
      return;
   g_followerDashboardState = displayState;

   CreateFollowerDashboard();
   FollowerDashboardSetLabel("TITLE", 23, "COPY TRADE FOLLOWER", C'80,200,255', 10);
   FollowerDashboardSetLabel("API", 45, "API: " + apiStatus,
      g_apiOnline ? C'70,220,130' : C'255,100,100', 9);
   FollowerDashboardSetLabel("ACCOUNT", 63, "Account: " + AccountLogin(), clrWhite, 9);
   FollowerDashboardSetLabel("BROKER", 81, "Broker: " + broker, clrWhite, 9);
   FollowerDashboardSetLabel("MASTER", 99, "Master: " + master,
      g_masterOnline ? clrWhite : C'255,180,90', 9);
   FollowerDashboardSetLabel("MASTER_POSITIONS", 117,
      "Master Positions: " + IntegerToString(g_masterPositionCount), clrWhite, 9);
   FollowerDashboardSetLabel("COPIED_POSITIONS", 135,
      "Copied Positions: " + IntegerToString(copiedPositions), clrWhite, 9);
   FollowerDashboardSetLabel("COPY", 153, "Copy: " + copyStatus,
      IsCopying() ? C'70,220,130' : C'255,180,90', 9);
   FollowerDashboardSetLabel("SETTINGS", 171, "Settings: " + settingsText,
      clrWhite, 9);

   color riskColor = C'200,205,215';
   FollowerDashboardSetLabel("RISK_TITLE", 193, "RISK SETTINGS", C'80,200,255', 9);
   FollowerDashboardSetLabel("RISK_LOT", 211, "Lot: " + lots, riskColor, 9);
   FollowerDashboardSetLabel("RISK_TRADES", 229, "Trades: " + trades, riskColor, 9);
   FollowerDashboardSetLabel("RISK_MAX_POS", 247, "Max Positions: " + maxPositions,
      riskColor, 9);
   FollowerDashboardSetLabel("RISK_DAILY", 265, "Daily Loss: " + dailyLoss,
      StringLen(g_autoStopReason) > 0 ? C'255,100,100' : riskColor, 9);

   FollowerDashboardSetLabel("PAIRING", 289, "Dashboard Code: " + pairing,
      C'80,200,255', 10);
   FollowerDashboardSetLabel("SYMBOL", 309, "Symbol: " + _Symbol + " (chart)", clrWhite, 9);
   FollowerDashboardSetLabel("SYNC", 327,
      "Last Sync: " + FollowerDashboardTime(g_lastSuccessfulSync), clrWhite, 9);
   FollowerDashboardSetLabel("ERROR", 345, "Last Error: " + lastError,
      g_lastFollowerError == "NONE" ? clrWhite : C'255,180,90', 9);
   ChartRedraw();
}

void DeleteFollowerDashboard()
{
   ObjectsDeleteAll(0, FOLLOWER_DASHBOARD_PREFIX);
   g_followerDashboardState = "";
}

bool StartsWith(const string value, const string prefix)
{
   return StringLen(value) >= StringLen(prefix) &&
      StringSubstr(value, 0, StringLen(prefix)) == prefix;
}

//--- JSON reading -------------------------------------------------------

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

// Returns the index of the closing quote of the string starting at start.
int SkipJsonString(const string json, const int start)
{
   bool escaped = false;

   for(int index = start + 1; index < StringLen(json); index++)
   {
      ushort character = StringGetCharacter(json, index);
      if(escaped)
         escaped = false;
      else if(character == 92)
         escaped = true;
      else if(character == 34)
         return index;
   }

   return -1;
}

int SkipJsonWhitespace(const string json, int index)
{
   while(index < StringLen(json))
   {
      ushort character = StringGetCharacter(json, index);
      if(character != 32 && character != 9 && character != 10 && character != 13)
         break;
      index++;
   }

   return index;
}

// Only matches keys of the outermost object, so a nested object with the same
// key name (for example "master" inside symbolMappings) is never picked up.
int FindJsonValueStart(const string json, const string key)
{
   int depth = 0;
   int length = StringLen(json);

   for(int index = 0; index < length; index++)
   {
      ushort character = StringGetCharacter(json, index);

      if(character == 34)
      {
         int end = SkipJsonString(json, index);
         if(end < 0)
            return -1;

         if(depth == 1 && StringSubstr(json, index + 1, end - index - 1) == key)
         {
            int colon = SkipJsonWhitespace(json, end + 1);
            if(colon < length && StringGetCharacter(json, colon) == 58)
               return SkipJsonWhitespace(json, colon + 1);
         }

         index = end;
         continue;
      }

      if(character == 123 || character == 91)
         depth++;
      else if(character == 125 || character == 93)
         depth--;
   }

   return -1;
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
      if(character == 44 || character == 125 || character == 93 ||
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

bool ExtractJsonBool(const string json, const string key, bool &value)
{
   string raw;
   if(!ExtractJsonScalar(json, key, raw))
      return false;

   if(raw == "true")
      value = true;
   else if(raw == "false")
      value = false;
   else
      return false;

   return true;
}

// A JSON null becomes an empty string.
bool ExtractJsonNullableString(const string json, const string key, string &value)
{
   int start = FindJsonValueStart(json, key);
   if(start < 0)
      return false;

   if(StringSubstr(json, start, 4) == "null")
   {
      value = "";
      return true;
   }

   return ReadJsonString(json, start, value);
}

bool ExtractJsonContainer(const string json,
                          const string key,
                          const ushort openToken,
                          const ushort closeToken,
                          string &value)
{
   int start = FindJsonValueStart(json, key);
   if(start < 0 || StringGetCharacter(json, start) != openToken)
      return false;

   int end = FindMatchingJsonToken(json, start, openToken, closeToken);
   if(end < 0)
      return false;

   value = StringSubstr(json, start, end - start + 1);
   return true;
}

bool ExtractJsonObject(const string json, const string key, string &value)
{
   return ExtractJsonContainer(json, key, 123, 125, value);
}

bool ExtractJsonArray(const string json, const string key, string &value)
{
   return ExtractJsonContainer(json, key, 91, 93, value);
}

// Splits a JSON array of objects. Returns the count, or -1 if malformed.
int SplitJsonObjects(const string arrayJson, string &objects[])
{
   ArrayResize(objects, 0);

   int arrayEnd = FindMatchingJsonToken(arrayJson, 0, 91, 93);
   if(StringGetCharacter(arrayJson, 0) != 91 || arrayEnd < 0)
      return -1;

   int cursor = 1;
   while(cursor < arrayEnd)
   {
      int objectStart = StringFind(arrayJson, "{", cursor);
      if(objectStart < 0 || objectStart >= arrayEnd)
         break;

      int objectEnd = FindMatchingJsonToken(arrayJson, objectStart, 123, 125);
      if(objectEnd < 0 || objectEnd > arrayEnd)
         return -1;

      int size = ArraySize(objects);
      ArrayResize(objects, size + 1);
      objects[size] = StringSubstr(arrayJson, objectStart, objectEnd - objectStart + 1);
      cursor = objectEnd + 1;
   }

   return ArraySize(objects);
}

//--- JSON writing -------------------------------------------------------

string JsonString(const string value)
{
   string result = "\"";

   for(int index = 0; index < StringLen(value); index++)
   {
      ushort character = StringGetCharacter(value, index);
      if(character == 34)
         result += "\\\"";
      else if(character == 92)
         result += "\\\\";
      else if(character < 32)
         result += StringFormat("\\u%04X", character);
      else
         result += ShortToString(character);
   }

   return result + "\"";
}

string JsonNullableString(const string value)
{
   return StringLen(value) > 0 ? JsonString(value) : "null";
}

string IsoUtc(const datetime value)
{
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
      parts.year, parts.mon, parts.day, parts.hour, parts.min, parts.sec);
}

// "2026-10-16T12:05:00.000Z" -> datetime (UTC).
datetime ParseIsoUtc(const string iso)
{
   if(StringLen(iso) < 19)
      return 0;

   string value = StringSubstr(iso, 0, 19);
   StringReplace(value, "-", ".");
   StringReplace(value, "T", " ");
   return StringToTime(value);
}

// Broker server time minus UTC, rounded to the nearest half hour.
int ServerUtcOffsetSeconds()
{
   double difference = (double)(TimeTradeServer() - TimeGMT());
   return (int)MathRound(difference / 1800.0) * 1800;
}

//--- API ------------------------------------------------------------------

bool HttpPostJson(const string path, const string body, int &status, string &response)
{
   char request[];
   char result[];
   string resultHeaders;
   string url = API_BASE_URL + path;
   string headers = "Content-Type: application/json\r\nAccept: application/json\r\n" +
      "X-EA-Key: " + ApiKey + "\r\n";

   int length = StringToCharArray(body, request, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(request, MathMax(length - 1, 0)); // drop the trailing null

   ResetLastError();
   status = WebRequest("POST", url, headers, HTTP_TIMEOUT_MS, request, result, resultHeaders);

   if(status < 0)
   {
      int errorCode = GetLastError();
      SetFollowerDashboardError("WebRequest error " + IntegerToString(errorCode));
      if(g_lastHttpStatus != -1)
      {
         PrintFormat("CopyTradeFollower: WebRequest failed. error=%d url=%s",
            errorCode, url);
         if(errorCode == 4014 || errorCode == 4060)
            PrintFormat("CopyTradeFollower: add %s to the MT5 WebRequest allowlist.",
               API_BASE_URL);
      }
      g_lastHttpStatus = -1;
      return false;
   }

   response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
}

string LotModeName()
{
   if(LotMode == FIXED)
      return "FIXED";
   if(LotMode == MULTIPLIER)
      return "MULTIPLIER";
   if(LotMode == STEP_LOT)
      return "STEP_LOT";
   return "SAME_AS_MASTER";
}

string LotSettingsJson()
{
   return "{" +
      "\"lotMode\":\"" + LotModeName() + "\"," +
      "\"fixedLot\":" + DoubleToString(FixedLot, 8) + "," +
      "\"lotMultiplier\":" + DoubleToString(LotMultiplier, 8) + "," +
      "\"maxLot\":" + DoubleToString(MaxLot, 8) + "," +
      "\"stepStartMultiplier\":" + DoubleToString(StepStartMultiplier, 8) + "," +
      "\"stepMultiplier\":" + DoubleToString(StepMultiplier, 8) + "," +
      "\"stepMinMultiplier\":" + DoubleToString(StepMinMultiplier, 8) + "," +
      "\"stepMaxMultiplier\":" + DoubleToString(StepMaxMultiplier, 8) +
      "}";
}

string ReportableError()
{
   if(g_lastFollowerError == "NONE" || g_lastFollowerError == "WAITING FOR API")
      return "";
   return g_lastFollowerError;
}

string BuildSyncRequest()
{
   string positions = "";
   int offset = ServerUtcOffsetSeconds();
   int total = PositionsTotal();

   for(int index = 0; index < total; index++)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;

      string masterTicket = "";
      IsOwnedPosition(ticket, masterTicket);

      string symbol = PositionGetString(POSITION_SYMBOL);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME) - offset;

      if(StringLen(positions) > 0)
         positions += ",";

      positions += "{" +
         "\"ticket\":\"" + (string)ticket + "\"," +
         "\"symbol\":" + JsonString(symbol) + "," +
         "\"type\":\"" + (type == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\"," +
         "\"volume\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 8) + "," +
         "\"openPrice\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), digits) + "," +
         "\"currentPrice\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_CURRENT), digits) + "," +
         "\"stopLoss\":" + DoubleToString(PositionGetDouble(POSITION_SL), digits) + "," +
         "\"takeProfit\":" + DoubleToString(PositionGetDouble(POSITION_TP), digits) + "," +
         "\"profit\":" + DoubleToString(profit, 2) + "," +
         "\"masterTicket\":" + JsonNullableString(masterTicket) + "," +
         "\"openTime\":\"" + IsoUtc(openTime) + "\"" +
         "}";
   }

   return "{" +
      "\"accountNumber\":\"" + AccountLogin() + "\"," +
      "\"broker\":" + JsonString(AccountInfoString(ACCOUNT_COMPANY)) + "," +
      "\"server\":" + JsonString(AccountInfoString(ACCOUNT_SERVER)) + "," +
      "\"name\":" + JsonString(AccountInfoString(ACCOUNT_NAME)) + "," +
      "\"currency\":" + JsonString(AccountInfoString(ACCOUNT_CURRENCY)) + "," +
      "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "," +
      "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "," +
      "\"positions\":[" + positions + "]," +
      "\"lotSettings\":" + LotSettingsJson() + "," +
      "\"appliedSettingsVersion\":" + IntegerToString(g_settingsVersion) + "," +
      "\"knownMasterVersion\":" + IntegerToString(g_masterVersion) + "," +
      "\"waitMs\":" + IntegerToString(SYNC_WAIT_MS) + "," +
      "\"autoStopReason\":" + JsonNullableString(g_autoStopReason) + "," +
      "\"lastError\":" + JsonNullableString(ReportableError()) + "," +
      "\"timestamp\":\"" + IsoUtc(TimeGMT()) + "\"" +
      "}";
}

bool ParseMasterPositions(const string stateJson, MasterPosition &positions[])
{
   ArrayResize(positions, 0);

   string positionsJson;
   string objects[];
   if(!ExtractJsonArray(stateJson, "positions", positionsJson) ||
      SplitJsonObjects(positionsJson, objects) < 0)
      return false;

   for(int index = 0; index < ArraySize(objects); index++)
   {
      MasterPosition position;
      string type;

      if(!ExtractJsonScalar(objects[index], "ticket", position.ticket) ||
         !ExtractJsonScalar(objects[index], "symbol", position.symbol) ||
         !ExtractJsonScalar(objects[index], "type", type) ||
         !ExtractJsonNumber(objects[index], "volume", position.volume) ||
         !ExtractJsonNumber(objects[index], "openPrice", position.openPrice) ||
         !ExtractJsonNumber(objects[index], "stopLoss", position.stopLoss) ||
         !ExtractJsonNumber(objects[index], "takeProfit", position.takeProfit))
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
   }

   return true;
}

bool ApplySettings(const string json, const long version)
{
   if(g_haveSettings && version == g_settingsVersion)
      return true;

   CopySettings settings;
   ZeroMemory(settings);
   double maxOpenPositions = 0.0;

   if(!ExtractJsonBool(json, "copyBuy", settings.copyBuy) ||
      !ExtractJsonBool(json, "copySell", settings.copySell) ||
      !ExtractJsonBool(json, "copyStopLoss", settings.copyStopLoss) ||
      !ExtractJsonBool(json, "copyTakeProfit", settings.copyTakeProfit) ||
      !ExtractJsonBool(json, "copyModify", settings.copyModify) ||
      !ExtractJsonBool(json, "copyClosedPositions", settings.copyClosedPositions) ||
      !ExtractJsonNumber(json, "maxOpenPositions", maxOpenPositions) ||
      !ExtractJsonNumber(json, "maxDailyLossPercent", settings.maxDailyLossPercent) ||
      !ExtractJsonBool(json, "closeAllOnDailyLoss", settings.closeAllOnDailyLoss))
      return false;

   settings.maxOpenPositions = (int)maxOpenPositions;

   if(settings.maxOpenPositions < 0 || settings.maxDailyLossPercent < 0.0)
      return false;

   g_settings = settings;
   ArrayResize(g_loggedMessages, 0);

   g_settingsVersion = version;
   g_haveSettings = true;
   PrintFormat("CopyTradeFollower: settings v%I64d applied. maxOpen=%d dailyLoss=%.2f%%",
      version, settings.maxOpenPositions, settings.maxDailyLossPercent);
   return true;
}

bool ApplySyncResponse(const string data,
                       MasterPosition &positions[],
                       string &commands[])
{
   string master;
   string settings;
   string commandsJson;
   string pairing;
   string stopReason;
   bool masterOnline = false;
   bool copyEnabled = false;
   double settingsVersion = 0.0;

   if(!ExtractJsonObject(data, "master", master) ||
      !ExtractJsonBool(master, "online", masterOnline) ||
      !ExtractJsonBool(data, "copyEnabled", copyEnabled) ||
      !ExtractJsonNullableString(data, "stopReason", stopReason) ||
      !ExtractJsonNumber(data, "settingsVersion", settingsVersion) ||
      !ExtractJsonObject(data, "settings", settings) ||
      !ExtractJsonArray(data, "commands", commandsJson) ||
      !ExtractJsonObject(data, "pairing", pairing))
      return false;

   // The master state is null until the Master EA has posted once.
   string state;
   g_haveMasterState = ExtractJsonObject(master, "state", state);
   ArrayResize(positions, 0);
   if(g_haveMasterState)
   {
      if(!ParseMasterPositions(state, positions))
         return false;

      string masterAccount;
      if(ExtractJsonScalar(state, "accountNumber", masterAccount))
         g_masterAccountNumber = masterAccount;
   }

   if(!ApplySettings(settings, (long)settingsVersion) ||
      SplitJsonObjects(commandsJson, commands) < 0)
      return false;

   string code;
   string expiresAt;
   if(ExtractJsonScalar(pairing, "code", code) &&
      ExtractJsonScalar(pairing, "expiresAt", expiresAt))
   {
      g_pairingCode = code;
      g_pairingExpiresAt = ParseIsoUtc(expiresAt);
   }

   g_masterOnline = masterOnline;

   double masterVersion;
   if(ExtractJsonNumber(master, "version", masterVersion))
      g_masterVersion = (long)masterVersion;
   g_masterPositionCount = ArraySize(positions);
   g_copyEnabled = copyEnabled;
   g_stopReason = stopReason;

   // The API has recorded our auto-stop once it reports copying as off.
   if(!copyEnabled)
      g_autoStopReason = "";

   return true;
}

bool SyncWithApi(MasterPosition &positions[], string &commands[])
{
   int status;
   string response;

   if(!HttpPostJson("/api/follower/sync", BuildSyncRequest(), status, response))
   {
      g_apiOnline = false;
      return false;
   }

   if(status != 200)
   {
      g_apiOnline = false;
      SetFollowerDashboardError("HTTP " + IntegerToString(status));
      if(status != g_lastHttpStatus)
         PrintFormat("CopyTradeFollower: API returned HTTP %d. response=%s",
            status, response);
      g_lastHttpStatus = status;
      return false;
   }

   g_lastHttpStatus = status;

   string data;
   if(!ExtractJsonObject(response, "data", data) ||
      !ApplySyncResponse(data, positions, commands))
   {
      g_apiOnline = false;
      SetFollowerDashboardError("Invalid API JSON");
      Print("CopyTradeFollower: invalid sync response; no trades were changed.");
      return false;
   }

   g_apiOnline = true;
   g_lastSuccessfulSync = TimeLocal();
   SetFollowerDashboardError("NONE");
   return true;
}

//--- Copied positions ---------------------------------------------------

string MasterTicketFromComment(const string comment)
{
   if(StartsWith(comment, COPY_COMMENT_PREFIX))
      return Trim(StringSubstr(comment, StringLen(COPY_COMMENT_PREFIX)));

   // Keep tracking positions opened before the trade label was renamed.
   if(StartsWith(comment, LEGACY_COPY_COMMENT_PREFIX))
      return Trim(StringSubstr(comment, StringLen(LEGACY_COPY_COMMENT_PREFIX)));

   return "";
}

bool IsOwnedPosition(const ulong positionTicket, string &masterTicket)
{
   if(!PositionSelectByTicket(positionTicket))
      return false;

   if((ulong)PositionGetInteger(POSITION_MAGIC) != COPY_MAGIC_NUMBER)
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
      if(followerTicket == 0 || !IsOwnedPosition(followerTicket, masterTicket) ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
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

// Master tickets whose copy was closed from the dashboard. They are not copied
// again while the master position stays open. Kept in terminal global
// variables so an EA restart does not reopen them.
string SkipKey(const string masterTicket)
{
   return "CAIO_SKIP_" + IntegerToString(COPY_MAGIC_NUMBER) + "_" + masterTicket;
}

bool IsSkippedMasterTicket(const string masterTicket)
{
   return GlobalVariableCheck(SkipKey(masterTicket));
}

void SkipMasterTicket(const string masterTicket)
{
   GlobalVariableSet(SkipKey(masterTicket), 1.0);
}

void PruneSkippedMasterTickets(const MasterPosition &positions[])
{
   string prefix = SkipKey("");

   for(int index = GlobalVariablesTotal() - 1; index >= 0; index--)
   {
      string name = GlobalVariableName(index);
      if(!StartsWith(name, prefix))
         continue;

      if(!MasterPositionExists(positions, StringSubstr(name, StringLen(prefix))))
         GlobalVariableDel(name);
   }
}

bool EndsWith(const string value, const string suffix)
{
   int valueLength = StringLen(value);
   int suffixLength = StringLen(suffix);
   return suffixLength <= valueLength &&
      StringSubstr(value, valueLength - suffixLength) == suffix;
}

bool IsKnownQuoteCurrency(const string value)
{
   return value == "USD" || value == "EUR" || value == "GBP" ||
      value == "JPY" || value == "AUD" || value == "NZD" ||
      value == "CAD" || value == "CHF" || value == "CNH" ||
      value == "HKD" || value == "SGD";
}

bool IsLettersOnly(const string value)
{
   for(int index = 0; index < StringLen(value); index++)
   {
      ushort character = StringGetCharacter(value, index);
      if(character < 65 || character > 90)
         return false;
   }

   return true;
}

string NormalizeSymbolBase(const string symbol)
{
   string upperSymbol = Upper(Trim(symbol));
   string compact = "";

   // Remove separators first. This turns XAUUSD.std into XAUUSDSTD while
   // preserving attached broker affixes such as the trailing 'm'.
   for(int index = 0; index < StringLen(upperSymbol); index++)
   {
      ushort character = StringGetCharacter(upperSymbol, index);
      if((character >= 65 && character <= 90) ||
         (character >= 48 && character <= 57))
         compact += ShortToString(character);
   }

   // Currency, metal and crypto pairs have a six-letter base ending in a
   // quote currency. Searching for that base handles both attached prefixes
   // and suffixes: mXAUUSD, XAUUSDm, XAUUSD.std and XAUUSD.pro -> XAUUSD.
   for(int index = 0; index + 6 <= StringLen(compact); index++)
   {
      string possibleBase = StringSubstr(compact, index, 6);
      if(IsLettersOnly(possibleBase) &&
         IsKnownQuoteCurrency(StringSubstr(possibleBase, 3, 3)))
         return possibleBase;
   }

   // Fallback for indices and other non-six-letter instruments.
   string affixes[] = {"MICRO", "MINI", "CENT", "STD", "PRO",
      "RAW", "ECN", "VIP", "M"};
   bool removed = true;
   while(removed && StringLen(compact) > 3)
   {
      removed = false;
      for(int index = 0; index < ArraySize(affixes); index++)
      {
         string affix = affixes[index];
         int remaining = StringLen(compact) - StringLen(affix);
         if(remaining < 3)
            continue;

         if(StartsWith(compact, affix))
         {
            compact = StringSubstr(compact, StringLen(affix));
            removed = true;
            break;
         }

         if(EndsWith(compact, affix))
         {
            compact = StringSubstr(compact, 0, remaining);
            removed = true;
            break;
         }
      }
   }

   return compact;
}

// "XAUUSD" on the master and "XAUUSDs" on this chart are the same instrument
bool IsSameInstrument(const string masterSymbol)
{
   return NormalizeSymbolBase(masterSymbol) == NormalizeSymbolBase(_Symbol);
}

void PrintOnce(const string message)
{
   for(int index = 0; index < ArraySize(g_loggedMessages); index++)
   {
      if(g_loggedMessages[index] == message)
         return;
   }

   int size = ArraySize(g_loggedMessages);
   ArrayResize(g_loggedMessages, size + 1);
   g_loggedMessages[size] = message;
   Print(message);
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

double StepLotMultiplier(const int sequenceNumber)
{
   double multiplier = StepStartMultiplier +
      (sequenceNumber - 1) * StepMultiplier;
   return MathMax(StepMinMultiplier,
      MathMin(multiplier, StepMaxMultiplier));
}

double NormalizeFollowerVolume(const string symbol,
                               const double masterVolume,
                               const int sequenceNumber)
{
   double requested = masterVolume;
   if(LotMode == FIXED)
      requested = FixedLot;
   else if(LotMode == MULTIPLIER)
      requested = masterVolume * LotMultiplier;
   else if(LotMode == STEP_LOT)
      requested = masterVolume * StepLotMultiplier(sequenceNumber);

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

   if(g_settings.copyStopLoss &&
      IsValidStop(symbol, master.type, true, master.stopLoss, tick))
      stopLoss = NormalizePrice(symbol, master.stopLoss);

   if(g_settings.copyTakeProfit &&
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
      SetFollowerDashboardError("Margin check failed: " + symbol);
      PrintFormat("CopyTradeFollower: margin calculation failed for %s. error=%d",
         symbol, GetLastError());
      return false;
   }

   if(requiredMargin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      SetFollowerDashboardError("Insufficient margin: " + symbol);
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
   SetFollowerDashboardError(action + " failed: " + symbol);
   PrintFormat(
      "CopyTradeFollower: %s failed. master=%s symbol=%s retcode=%u message=%s",
      action,
      masterTicket,
      symbol,
      g_trade.ResultRetcode(),
      g_trade.ResultRetcodeDescription());
}

bool OpenCopiedPosition(const MasterPosition &master,
                        const int sequenceNumber)
{
   if((master.type == POSITION_TYPE_BUY && !g_settings.copyBuy) ||
      (master.type == POSITION_TYPE_SELL && !g_settings.copySell))
      return false;

   if(FindFollowerTicket(master.ticket) != 0)
      return true;

   if(IsSkippedMasterTicket(master.ticket))
      return false;

   if(g_settings.maxOpenPositions > 0 &&
      ArraySize(g_mappedMasterTickets) >= g_settings.maxOpenPositions)
   {
      SetFollowerDashboardError("Max open positions reached");
      return false;
   }

   // Copies open on this chart's symbol (e.g. master XAUUSD -> XAUUSDs here)
   string symbol = _Symbol;
   if(!IsSameInstrument(master.symbol))
   {
      PrintOnce(StringFormat("CopyTradeFollower: ignoring master %s trades; this EA copies %s only.",
         master.symbol, symbol));
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      SetFollowerDashboardError("No market price: " + symbol);
      PrintFormat("CopyTradeFollower: no valid market price for %s", symbol);
      return false;
   }

   long tradeMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED ||
      tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY ||
      (master.type == POSITION_TYPE_BUY && tradeMode == SYMBOL_TRADE_MODE_SHORTONLY) ||
      (master.type == POSITION_TYPE_SELL && tradeMode == SYMBOL_TRADE_MODE_LONGONLY))
   {
      SetFollowerDashboardError("Trading unavailable: " + symbol);
      PrintFormat("CopyTradeFollower: market is not open for new trades on %s",
         symbol);
      return false;
   }

   double volume = NormalizeFollowerVolume(symbol, master.volume, sequenceNumber);
   if(volume <= 0.0)
   {
      SetFollowerDashboardError("Invalid volume: " + symbol);
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

   if(LotMode == STEP_LOT)
      PrintFormat("Copy AiO: step lot master=%s sequence=%d masterLot=%.8f multiplier=%.8f followerLot=%.8f",
         master.ticket, sequenceNumber, master.volume,
         StepLotMultiplier(sequenceNumber), volume);

   RebuildMasterTicketMapping();
   return true;
}

void ModifyCopiedPosition(const MasterPosition &master,
                          const ulong followerTicket)
{
   if(!g_settings.copyModify || !PositionSelectByTicket(followerTicket))
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

   if(g_settings.copyStopLoss)
   {
      if(master.stopLoss == 0.0)
         desiredStopLoss = 0.0;
      else if(IsValidStop(symbol, localType, true, master.stopLoss, tick))
         desiredStopLoss = NormalizePrice(symbol, master.stopLoss);
   }

   if(g_settings.copyTakeProfit)
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
   if(!g_settings.copyClosedPositions)
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

// When copying is off, no new trades are opened, but positions that are
// already copied keep following the master's closes and SL/TP changes.
void SynchronizeFollower(const MasterPosition &masterPositions[], const bool allowOpen)
{
   RebuildMasterTicketMapping();
   CloseMissingCopiedPositions(masterPositions);

   for(int index = 0; index < ArraySize(masterPositions); index++)
   {
      ulong followerTicket = FindFollowerTicket(masterPositions[index].ticket);
      if(followerTicket == 0 && allowOpen)
      {
         // The Master publishes active positions in ascending ticket order.
         // Include every Master position, even if an earlier copy failed.
         OpenCopiedPosition(masterPositions[index], index + 1);
         followerTicket = FindFollowerTicket(masterPositions[index].ticket);
      }

      if(followerTicket != 0)
         ModifyCopiedPosition(masterPositions[index], followerTicket);
   }
}

//--- Risk -------------------------------------------------------------------

// Loss since the start of the broker's trading day, as a percent of the
// equity at that time. The day's starting equity survives EA restarts.
double DailyLossPercent()
{
   string dayKey = "CAIO_DAY_" + AccountLogin();
   string equityKey = "CAIO_DAYEQ_" + AccountLogin();
   long now = (long)TimeTradeServer();
   double today = (double)(now - now % 86400);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!GlobalVariableCheck(dayKey) || !GlobalVariableCheck(equityKey) ||
      GlobalVariableGet(dayKey) != today)
   {
      GlobalVariableSet(dayKey, today);
      GlobalVariableSet(equityKey, equity);
      return 0.0;
   }

   double startEquity = GlobalVariableGet(equityKey);
   if(startEquity <= 0.0)
      return 0.0;

   return (startEquity - equity) / startEquity * 100.0;
}

void CheckDailyLoss()
{
   // Always called so the day's starting equity rolls over on time.
   double loss = DailyLossPercent();

   if(g_settings.maxDailyLossPercent <= 0.0 || !IsCopying() ||
      loss < g_settings.maxDailyLossPercent)
      return;

   g_autoStopReason = StringFormat("Daily loss limit reached (%.2f%%)", loss);
   PrintFormat("CopyTradeFollower: %s. Copying stopped.", g_autoStopReason);

   if(g_settings.closeAllOnDailyLoss)
   {
      string error;
      CloseAllCopiedPositions(error);
   }
}

//--- Dashboard commands -------------------------------------------------

bool ClosePositionByCommand(const string ticketText, string &error)
{
   ulong ticket = (ulong)StringToInteger(ticketText);
   if(ticket == 0 || !PositionSelectByTicket(ticket))
   {
      error = "Position not found";
      return false;
   }

   string symbol = PositionGetString(POSITION_SYMBOL);
   string masterTicket = "";
   if(IsOwnedPosition(ticket, masterTicket))
      SkipMasterTicket(masterTicket);

   if(!TradeRequestSucceeded(g_trade.PositionClose(ticket)))
   {
      error = g_trade.ResultRetcodeDescription();
      LogTradeFailure("close", masterTicket, symbol);
      return false;
   }

   RebuildMasterTicketMapping();
   return true;
}

// Closes every position this EA copied. Manual trades are left alone.
bool CloseAllCopiedPositions(string &error)
{
   RebuildMasterTicketMapping();
   int total = ArraySize(g_mappedFollowerTickets);
   int failed = 0;

   for(int index = 0; index < total; index++)
   {
      ulong ticket = g_mappedFollowerTickets[index];
      SkipMasterTicket(g_mappedMasterTickets[index]);

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!TradeRequestSucceeded(g_trade.PositionClose(ticket)))
      {
         failed++;
         LogTradeFailure("close", g_mappedMasterTickets[index], symbol);
      }
   }

   RebuildMasterTicketMapping();

   if(failed > 0)
   {
      error = StringFormat("%d of %d positions failed to close", failed, total);
      return false;
   }

   return true;
}

int FindDoneCommand(const string id)
{
   for(int index = 0; index < ArraySize(g_doneCommandIds); index++)
   {
      if(g_doneCommandIds[index] == id)
         return index;
   }

   return -1;
}

int RememberCommand(const string id, const string status, const string error)
{
   if(ArraySize(g_doneCommandIds) >= MAX_REMEMBERED_COMMANDS)
   {
      ArrayRemove(g_doneCommandIds, 0, 1);
      ArrayRemove(g_doneCommandStatuses, 0, 1);
      ArrayRemove(g_doneCommandErrors, 0, 1);
   }

   int size = ArraySize(g_doneCommandIds);
   ArrayResize(g_doneCommandIds, size + 1);
   ArrayResize(g_doneCommandStatuses, size + 1);
   ArrayResize(g_doneCommandErrors, size + 1);
   g_doneCommandIds[size] = id;
   g_doneCommandStatuses[size] = status;
   g_doneCommandErrors[size] = error;
   return size;
}

// A failed ack is retried on the next sync, because the API keeps sending the
// command until it is acked.
void AckCommand(const string id, const string status, const string error)
{
   string body = "{" +
      "\"accountNumber\":\"" + AccountLogin() + "\"," +
      "\"status\":\"" + status + "\"," +
      "\"error\":" + JsonNullableString(error) +
      "}";
   int httpStatus;
   string response;

   if(HttpPostJson("/api/follower/commands/" + id + "/ack", body, httpStatus, response) &&
      httpStatus != 200)
      PrintFormat("CopyTradeFollower: command ack returned HTTP %d. id=%s response=%s",
         httpStatus, id, response);
}

void ProcessCommands(const string &commands[])
{
   for(int index = 0; index < ArraySize(commands); index++)
   {
      string id;
      string type;
      string ticket = "";

      if(!ExtractJsonScalar(commands[index], "id", id) ||
         !ExtractJsonScalar(commands[index], "type", type))
         continue;
      ExtractJsonNullableString(commands[index], "ticket", ticket);

      int done = FindDoneCommand(id);
      if(done < 0)
      {
         string error = "";
         bool succeeded = false;

         if(!Enabled)
            error = "EA is disabled on the terminal";
         else if(type == "CLOSE_POSITION")
            succeeded = ClosePositionByCommand(ticket, error);
         else if(type == "CLOSE_ALL")
            succeeded = CloseAllCopiedPositions(error);
         else
            error = "Unknown command: " + type;

         done = RememberCommand(id, succeeded ? "done" : "failed", error);
         PrintFormat("CopyTradeFollower: command %s %s -> %s %s",
            type, ticket, g_doneCommandStatuses[done], error);
      }

      AckCommand(id, g_doneCommandStatuses[done], g_doneCommandErrors[done]);
   }
}

//--- Events -------------------------------------------------------------

int OnInit()
{
   if(!MathIsValidNumber(FixedLot) || FixedLot <= 0.0 ||
      !MathIsValidNumber(LotMultiplier) || LotMultiplier <= 0.0 ||
      !MathIsValidNumber(MaxLot) || MaxLot <= 0.0 ||
      !MathIsValidNumber(StepStartMultiplier) || StepStartMultiplier <= 0.0 ||
      !MathIsValidNumber(StepMultiplier) ||
      !MathIsValidNumber(StepMinMultiplier) || StepMinMultiplier <= 0.0 ||
      !MathIsValidNumber(StepMaxMultiplier) || StepMaxMultiplier <= 0.0 ||
      StepMinMultiplier > StepMaxMultiplier)
   {
      Print("CopyTradeFollower: invalid lot size inputs. Lots and multipliers must be above 0, and the step lowest multiplier must not exceed the highest.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(LotMode == FIXED && FixedLot > MaxLot)
   {
      Print("CopyTradeFollower: Fixed lot must not be greater than Max lot per copied trade.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(StringLen(ApiKey) == 0)
   {
      Print("CopyTradeFollower: set the API key input (EA_API_KEY from the server).");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_trade.SetExpertMagicNumber(COPY_MAGIC_NUMBER);
   g_trade.SetAsyncMode(false);
   RebuildMasterTicketMapping();

   ResetLastError();
   if(!EventSetMillisecondTimer(SYNC_INTERVAL_MS))
   {
      PrintFormat("CopyTradeFollower: failed to start timer. interval=%d error=%d",
         SYNC_INTERVAL_MS, GetLastError());
      return INIT_FAILED;
   }

   PrintFormat("CopyTradeFollower started. enabled=%s api=%s interval=%dms mapped=%d",
      Enabled ? "true" : "false",
      API_BASE_URL,
      SYNC_INTERVAL_MS,
      ArraySize(g_mappedMasterTickets));
   CreateFollowerDashboard();
   UpdateFollowerDashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteFollowerDashboard();
   PrintFormat("CopyTradeFollower stopped. reason=%d", reason);
}

void OnTimer()
{
   MasterPosition positions[];
   string commands[];

   // Synced even when disabled, so the web dashboard still shows the account.
   if(!SyncWithApi(positions, commands))
   {
      UpdateFollowerDashboard();
      return;
   }

   ProcessCommands(commands);

   if(Enabled && g_haveSettings)
   {
      CheckDailyLoss();

      // Never trade from a stale snapshot of an offline master.
      if(g_haveMasterState && g_masterOnline)
      {
         PruneSkippedMasterTickets(positions);
         SynchronizeFollower(positions, IsCopying());
      }
   }

   UpdateFollowerDashboard();
}
//+------------------------------------------------------------------+
