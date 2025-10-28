//+------------------------------------------------------------------+
//|                                                 TvBridgeJson.mqh |
//|                                   JSON Utility for TvBridge EA  |
//+------------------------------------------------------------------+
#property copyright "TvBridge"
#property link      ""
#property strict

//+------------------------------------------------------------------+
//| Signal structure                                                 |
//+------------------------------------------------------------------+
struct Signal
{
   string key;           // Unique signal identifier
   string action;        // "BUY", "SELL", "CLOSE", "CLOSE_PARTIAL"
   double volume;        // Lot size for the trade
   double volume_ratio;  // Ratio for partial close (0.0-1.0)
   string symbol;        // Trading symbol
   string bar_time;      // Bar timestamp
};

//+------------------------------------------------------------------+
//| Extract string value from JSON                                   |
//+------------------------------------------------------------------+
string JsonGetString(const string &json, const string &key)
{
   string searchKey = "\"" + key + "\":\"";
   int start = StringFind(json, searchKey);
   if(start == -1)
      return "";

   start += StringLen(searchKey);
   int end = StringFind(json, "\"", start);
   if(end == -1)
      return "";

   return StringSubstr(json, start, end - start);
}

//+------------------------------------------------------------------+
//| Extract numeric value from JSON                                  |
//+------------------------------------------------------------------+
double JsonGetNumber(const string &json, const string &key)
{
   string searchKey = "\"" + key + "\":";
   int start = StringFind(json, searchKey);
   if(start == -1)
      return 0.0;

   start += StringLen(searchKey);

   // Skip whitespace
   while(start < StringLen(json) && (StringGetCharacter(json, start) == ' ' || StringGetCharacter(json, start) == '\t'))
      start++;

   // Find end of number (comma, brace, or bracket)
   int end = start;
   while(end < StringLen(json))
   {
      ushort ch = StringGetCharacter(json, end);
      if(ch == ',' || ch == '}' || ch == ']' || ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n')
         break;
      end++;
   }

   if(end <= start)
      return 0.0;

   string numStr = StringSubstr(json, start, end - start);
   return StringToDouble(numStr);
}

//+------------------------------------------------------------------+
//| Parse signals from JSON response                                 |
//+------------------------------------------------------------------+
int ParseSignals(const string &jsonResponse, Signal &signals[])
{
   // Extract the "items" array from response
   int itemsStart = StringFind(jsonResponse, "\"items\":[");
   if(itemsStart == -1)
   {
      PrintFormat("[TvBridgeJson] No 'items' field found in response");
      return 0;
   }

   itemsStart += StringLen("\"items\":[");
   int itemsEnd = StringFind(jsonResponse, "]", itemsStart);
   if(itemsEnd == -1)
   {
      PrintFormat("[TvBridgeJson] Malformed 'items' array");
      return 0;
   }

   string itemsJson = StringSubstr(jsonResponse, itemsStart, itemsEnd - itemsStart);

   // Check if empty array
   string trimmed = itemsJson;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);
   if(StringLen(trimmed) == 0)
   {
      return 0; // Empty array, no signals
   }

   // Split by objects (simple split by "},{")
   string parts[];
   int objCount = 0;

   int searchPos = 0;
   int objStart = StringFind(itemsJson, "{", searchPos);

   while(objStart != -1)
   {
      int objEnd = StringFind(itemsJson, "}", objStart);
      if(objEnd == -1)
         break;

      objCount++;
      ArrayResize(parts, objCount);
      parts[objCount - 1] = StringSubstr(itemsJson, objStart, objEnd - objStart + 1);

      searchPos = objEnd + 1;
      objStart = StringFind(itemsJson, "{", searchPos);
   }

   if(objCount == 0)
   {
      return 0;
   }

   // Parse each object
   ArrayResize(signals, objCount);

   for(int i = 0; i < objCount; i++)
   {
      signals[i].key = JsonGetString(parts[i], "key");
      signals[i].action = JsonGetString(parts[i], "action");
      signals[i].volume = JsonGetNumber(parts[i], "volume");
      signals[i].volume_ratio = JsonGetNumber(parts[i], "volume_ratio");
      signals[i].symbol = JsonGetString(parts[i], "symbol");
      signals[i].bar_time = JsonGetString(parts[i], "bar_time");

      PrintFormat("[TvBridgeJson] Parsed signal[%d]: key=%s, action=%s, volume=%.2f, ratio=%.2f, symbol=%s",
                  i, signals[i].key, signals[i].action, signals[i].volume, signals[i].volume_ratio, signals[i].symbol);
   }

   return objCount;
}
//+------------------------------------------------------------------+
