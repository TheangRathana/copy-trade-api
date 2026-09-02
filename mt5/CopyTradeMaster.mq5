//+------------------------------------------------------------------+
//|                                              CopyTradeMaster.mq5 |
//| Publishes the current MT5 account state to the copy-trade API.   |
//| This EA never opens, modifies, or closes trades.                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Read-only Master account state publisher"

input group "Copy Trade Master"
input string ApiUrl                   = "http://127.0.0.1:4000/api/master/state";
input int    SyncIntervalMs           = 250;
input int    HeartbeatIntervalSeconds = 5;

string g_lastSuccessfulSnapshot = "";
uint   g_lastSuccessfulSendMs   = 0;
int    g_syncIntervalMs         = 250;
uint   g_heartbeatIntervalMs    = 5000;

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

      string symbol = PositionGetString(POSITION_SYMBOL);
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
      PrintFormat(
         "CopyTradeMaster: WebRequest failed. error=%d url=%s",
         errorCode,
         ApiUrl);

      if(errorCode == 4060)
      {
         Print(
            "CopyTradeMaster: allow http://127.0.0.1:4000 under "
            "Tools > Options > Expert Advisors > "
            "Allow WebRequest for listed URL.");
      }

      return false;
   }

   if(status < 200 || status >= 300)
   {
      string response =
         CharArrayToString(responseBody, 0, WHOLE_ARRAY, CP_UTF8);
      PrintFormat(
         "CopyTradeMaster: API request failed. status=%d response=%s",
         status,
         response);
      return false;
   }

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

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   PrintFormat("CopyTradeMaster stopped. reason=%d", reason);
}

void OnTimer()
{
   PublishMasterStateIfNeeded();
}
//+------------------------------------------------------------------+
