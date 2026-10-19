//+------------------------------------------------------------------+
//|                                              CopyTradeMaster.mq5 |
//| Publishes the current MT5 account state to the copy-trade API.   |
//| This EA never opens, modifies, or closes trades.                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Read-only Master account state publisher"

input group "Copy Trade Master"
input string ApiUrl                   = "https://copy-trade-api.salatrades.com/api/master/state";
// The server's EA_API_KEY; needed when the API is on another machine
input string ApiKey                   = ""; // API key (EA_API_KEY from the server)
input int    SyncIntervalMs           = 250;
input int    HeartbeatIntervalSeconds = 5;

input group "Dashboard"
input bool ShowDashboard = true;

string g_lastSuccessfulSnapshot = "";
uint   g_lastSuccessfulSendMs   = 0;
int    g_syncIntervalMs         = 250;
uint   g_heartbeatIntervalMs    = 5000;
bool     g_apiOnline            = false;
int      g_lastHttpStatus       = 0;
datetime g_lastSuccessfulSync   = 0;
string   g_masterDashboardState = "";

#define MASTER_DASHBOARD_PREFIX "CTM_DASH_"

string JsonEscape(string value)
{
   string escaped = "";

   for(int index = 0; index < StringLen(value); index++)
   {
      ushort character = StringGetCharacter(value, index);

      if(character == 34)
         escaped += "\\\"";
      else if(character == 92)
         escaped += "\\\\";
      else if(character == 8)
         escaped += "\\b";
      else if(character == 9)
         escaped += "\\t";
      else if(character == 10)
         escaped += "\\n";
      else if(character == 12)
         escaped += "\\f";
      else if(character == 13)
         escaped += "\\r";
      else if(character < 32)
         escaped += StringFormat("\\u%04X", character);
      else
         escaped += ShortToString(character);
   }

   return escaped;
}

string CurrentUtcIso8601()
{
   MqlDateTime value;
   TimeToStruct(TimeGMT(), value);

   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
      value.year,
      value.mon,
      value.day,
      value.hour,
      value.min,
      value.sec);
}

int SymbolPriceDigits(const string symbol)
{
   long digits = 8;
   if(!SymbolInfoInteger(symbol, SYMBOL_DIGITS, digits))
      return 8;

   return (int)digits;
}

string MasterDashboardTime(const datetime value)
{
   return value > 0 ? TimeToString(value, TIME_SECONDS) : "NEVER";
}

string MasterDashboardClip(const string value, const int maximumLength)
{
   if(StringLen(value) <= maximumLength)
      return value;
   return StringSubstr(value, 0, maximumLength - 3) + "...";
}

void MasterDashboardSetLabel(const string key,
                             const int y,
                             const string text,
                             const color textColor,
                             const int fontSize)
{
   string name = MASTER_DASHBOARD_PREFIX + key;
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 18);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }

   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateMasterDashboard()
{
   if(!ShowDashboard)
      return;

   string background = MASTER_DASHBOARD_PREFIX + "BACKGROUND";
   if(ObjectFind(0, background) < 0)
   {
      if(!ObjectCreate(0, background, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, background, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, background, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, background, OBJPROP_YDISTANCE, 15);
      ObjectSetInteger(0, background, OBJPROP_XSIZE, 315);
      ObjectSetInteger(0, background, OBJPROP_YSIZE, 188);
      ObjectSetInteger(0, background, OBJPROP_BGCOLOR, C'20,24,32');
      ObjectSetInteger(0, background, OBJPROP_COLOR, C'65,75,92');
      ObjectSetInteger(0, background, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, background, OBJPROP_BACK, false);
      ObjectSetInteger(0, background, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, background, OBJPROP_HIDDEN, true);
   }
}

void UpdateMasterDashboard()
{
   if(!ShowDashboard)
      return;

   string apiStatus = g_apiOnline ? "ONLINE" : "ERROR";
   string httpStatus = g_lastHttpStatus == 0
      ? "N/A"
      : IntegerToString(g_lastHttpStatus);
   string broker = MasterDashboardClip(AccountInfoString(ACCOUNT_COMPANY), 35);
   string server = MasterDashboardClip(AccountInfoString(ACCOUNT_SERVER), 35);
   string displayState = StringFormat(
      "%s|%I64d|%s|%s|%d|%s|%s",
      apiStatus,
      AccountInfoInteger(ACCOUNT_LOGIN),
      broker,
      server,
      ChartSymbolPositions(),
      MasterDashboardTime(g_lastSuccessfulSync),
      httpStatus);

   if(displayState == g_masterDashboardState)
      return;
   g_masterDashboardState = displayState;

   CreateMasterDashboard();
   MasterDashboardSetLabel("TITLE", 23, "COPY TRADE MASTER", C'80,200,255', 10);
   MasterDashboardSetLabel("API", 45, "API: " + apiStatus,
      g_apiOnline ? C'70,220,130' : C'255,100,100', 9);
   MasterDashboardSetLabel("ACCOUNT", 63,
      "Account: " + (string)AccountInfoInteger(ACCOUNT_LOGIN), clrWhite, 9);
   MasterDashboardSetLabel("BROKER", 81, "Broker: " + broker, clrWhite, 9);
   MasterDashboardSetLabel("SERVER", 99, "Server: " + server, clrWhite, 9);
   MasterDashboardSetLabel("POSITIONS", 117,
      _Symbol + " Positions: " + IntegerToString(ChartSymbolPositions()), clrWhite, 9);
   MasterDashboardSetLabel("SYNC", 135,
      "Last Sync: " + MasterDashboardTime(g_lastSuccessfulSync), clrWhite, 9);
   MasterDashboardSetLabel("HTTP", 153, "HTTP: " + httpStatus, clrWhite, 9);
   MasterDashboardSetLabel("STATUS", 171, "Status: RUNNING", C'70,220,130', 9);
   ChartRedraw();
}

int ChartSymbolPositions()
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return count;
}

void DeleteMasterDashboard()
{
   ObjectsDeleteAll(0, MASTER_DASHBOARD_PREFIX);
   g_masterDashboardState = "";
}

string BuildMasterStateJson(string &snapshotForComparison)
{
   ulong tickets[];
   int total = PositionsTotal();
   ArrayResize(tickets, total);

   int ticketCount = 0;
   for(int index = 0; index < total; index++)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket > 0)
         tickets[ticketCount++] = ticket;
   }

   ArrayResize(tickets, ticketCount);
   ArraySort(tickets);

   string positionsJson = "[";
   int serializedCount = 0;

   for(int index = 0; index < ticketCount; index++)
   {
      ulong ticket = tickets[index];
      if(!PositionSelectByTicket(ticket))
         continue;

      ENUM_POSITION_TYPE positionType =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(positionType != POSITION_TYPE_BUY &&
         positionType != POSITION_TYPE_SELL)
         continue;

      // Only the chart's symbol is copied: attach the Master to the XAUUSD chart
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != _Symbol)
         continue;

      int priceDigits = SymbolPriceDigits(symbol);

      if(serializedCount > 0)
         positionsJson += ",";

      positionsJson += StringFormat(
         "{\"ticket\":\"%I64u\",\"symbol\":\"%s\",\"type\":\"%s\","
         "\"volume\":%s,\"openPrice\":%s,\"stopLoss\":%s,\"takeProfit\":%s}",
         ticket,
         JsonEscape(symbol),
         positionType == POSITION_TYPE_BUY ? "BUY" : "SELL",
         DoubleToString(PositionGetDouble(POSITION_VOLUME), 8),
         DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), priceDigits),
         DoubleToString(PositionGetDouble(POSITION_SL), priceDigits),
         DoubleToString(PositionGetDouble(POSITION_TP), priceDigits));

      serializedCount++;
   }

   positionsJson += "]";

   string accountJson = StringFormat(
      "\"accountNumber\":\"%I64d\",\"broker\":\"%s\",\"server\":\"%s\"",
      AccountInfoInteger(ACCOUNT_LOGIN),
      JsonEscape(AccountInfoString(ACCOUNT_COMPANY)),
      JsonEscape(AccountInfoString(ACCOUNT_SERVER)));

   // A timestamp is included in the request but excluded from comparison so
   // an otherwise identical state is only resent at the heartbeat interval.
   snapshotForComparison = accountJson + ",\"positions\":" + positionsJson;

   return "{" + snapshotForComparison +
      ",\"timestamp\":\"" + CurrentUtcIso8601() + "\"}";
}

bool SendMasterState(const string json)
{
   char requestBody[];
   char responseBody[];
   string responseHeaders;
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(ApiKey) > 0)
      headers += "X-EA-Key: " + ApiKey + "\r\n";

   StringToCharArray(json, requestBody, 0, WHOLE_ARRAY, CP_UTF8);
   if(ArraySize(requestBody) > 0)
      ArrayResize(requestBody, ArraySize(requestBody) - 1);

   ResetLastError();
   int status = WebRequest(
      "POST",
      ApiUrl,
      headers,
      2000,
      requestBody,
      responseBody,
      responseHeaders);

   if(status < 0)
   {
      int errorCode = GetLastError();
      g_apiOnline = false;
      g_lastHttpStatus = -1;
      PrintFormat(
         "CopyTradeMaster: WebRequest failed. error=%d url=%s",
         errorCode,
         ApiUrl);

      if(errorCode == 4060)
      {
         Print(
            "CopyTradeMaster: allow https://copy-trade-api.salatrades.com under "
            "Tools > Options > Expert Advisors > "
            "Allow WebRequest for listed URL.");
      }

      return false;
   }

   if(status < 200 || status >= 300)
   {
      g_apiOnline = false;
      g_lastHttpStatus = status;
      string response =
         CharArrayToString(responseBody, 0, WHOLE_ARRAY, CP_UTF8);
      PrintFormat(
         "CopyTradeMaster: API request failed. status=%d response=%s",
         status,
         response);
      return false;
   }

   g_apiOnline = true;
   g_lastHttpStatus = status;
   g_lastSuccessfulSync = TimeLocal();
   return true;
}

void PublishMasterStateIfNeeded()
{
   string currentSnapshot;
   string json = BuildMasterStateJson(currentSnapshot);
   uint now = GetTickCount();

   bool stateChanged = currentSnapshot != g_lastSuccessfulSnapshot;
   bool heartbeatDue = g_lastSuccessfulSendMs == 0 ||
      (uint)(now - g_lastSuccessfulSendMs) >= g_heartbeatIntervalMs;

   if(!stateChanged && !heartbeatDue)
      return;

   if(SendMasterState(json))
   {
      g_lastSuccessfulSnapshot = currentSnapshot;
      g_lastSuccessfulSendMs = now;
   }
}

int OnInit()
{
   if(StringFind(ApiUrl, "https://") == 0 && StringLen(ApiKey) == 0)
   {
      Print("CopyTradeMaster: set the API key input (EA_API_KEY from the server).");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(StringLen(ApiUrl) == 0)
   {
      Print("CopyTradeMaster: ApiUrl cannot be empty.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_syncIntervalMs = SyncIntervalMs > 0 ? SyncIntervalMs : 250;
   g_heartbeatIntervalMs =
      (uint)((HeartbeatIntervalSeconds > 0 ? HeartbeatIntervalSeconds : 5) * 1000);

   ResetLastError();
   if(!EventSetMillisecondTimer(g_syncIntervalMs))
   {
      PrintFormat(
         "CopyTradeMaster: failed to start timer. interval=%d error=%d",
         g_syncIntervalMs,
         GetLastError());
      return INIT_FAILED;
   }

   PrintFormat(
      "CopyTradeMaster started. url=%s sync=%dms heartbeat=%ds",
      ApiUrl,
      g_syncIntervalMs,
      HeartbeatIntervalSeconds > 0 ? HeartbeatIntervalSeconds : 5);

   CreateMasterDashboard();
   UpdateMasterDashboard();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteMasterDashboard();
   PrintFormat("CopyTradeMaster stopped. reason=%d", reason);
}

void OnTimer()
{
   PublishMasterStateIfNeeded();
   UpdateMasterDashboard();
}

// Sends the moment a position opens, closes (deal added) or its SL/TP changes
// (position changed), instead of waiting for the next timer tick. The timer
// stays as a backup and for the heartbeat; unchanged state is never resent.
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD &&
      trans.type != TRADE_TRANSACTION_POSITION)
      return;

   PublishMasterStateIfNeeded();
}
//+------------------------------------------------------------------+
