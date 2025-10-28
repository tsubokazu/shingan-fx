//+------------------------------------------------------------------+
//|                                                 TvBridgeHttp.mqh |
//|                                    HTTP Utility for TvBridge EA |
//+------------------------------------------------------------------+
#property copyright "TvBridge"
#property link      ""
#property strict

//+------------------------------------------------------------------+
//| HTTP GET request to poll pending signals                         |
//+------------------------------------------------------------------+
string HttpGetPendingSignals(string baseUrl, string pollToken, string symbol, int limit)
{
   string url = StringFormat("%s/api/poll?symbol=%s&limit=%d", baseUrl, symbol, limit);
   string headers = "Authorization: Bearer " + pollToken + "\r\n";

   char data[];
   char result[];
   string responseHeaders;

   int timeout = 5000; // 5 seconds

   // WebRequest(method, url, headers, timeout, data, data_size, result, result_headers)
   int statusCode = WebRequest("GET", url, headers, timeout, data, result, responseHeaders);

   if(statusCode == -1)
   {
      int errorCode = GetLastError();
      PrintFormat("[TvBridgeHttp] WebRequest error: %d. URL may not be in allowed list.", errorCode);
      return "";
   }

   if(statusCode != 200)
   {
      PrintFormat("[TvBridgeHttp] Poll failed. Status: %d", statusCode);
      if(ArraySize(result) > 0)
      {
         string errorBody = CharArrayToString(result);
         PrintFormat("[TvBridgeHttp] Response: %s", errorBody);
      }
      return "";
   }

   string response = CharArrayToString(result);
   PrintFormat("[TvBridgeHttp] Poll successful. Status: %d, Response length: %d bytes", statusCode, StringLen(response));
   return response;
}

//+------------------------------------------------------------------+
//| HTTP POST request to acknowledge processed signals               |
//+------------------------------------------------------------------+
bool HttpAckSignals(string baseUrl, string pollToken, const string &ackBody)
{
   string url = baseUrl + "/api/ack";
   string headers = "Authorization: Bearer " + pollToken + "\r\nContent-Type: application/json\r\n";

   char data[];
   StringToCharArray(ackBody, data, 0, StringLen(ackBody));

   char result[];
   string responseHeaders;

   int timeout = 5000; // 5 seconds

   int statusCode = WebRequest("POST", url, headers, timeout, data, result, responseHeaders);

   if(statusCode == -1)
   {
      int errorCode = GetLastError();
      PrintFormat("[TvBridgeHttp] WebRequest error: %d. URL may not be in allowed list.", errorCode);
      return false;
   }

   if(statusCode != 200)
   {
      PrintFormat("[TvBridgeHttp] Ack failed. Status: %d", statusCode);
      if(ArraySize(result) > 0)
      {
         string errorBody = CharArrayToString(result);
         PrintFormat("[TvBridgeHttp] Response: %s", errorBody);
      }
      return false;
   }

   PrintFormat("[TvBridgeHttp] Ack successful: %s", ackBody);
   return true;
}

//+------------------------------------------------------------------+
//| Build ACK request body from array of keys                        |
//+------------------------------------------------------------------+
string BuildAckRequestBody(const string &keys[])
{
   int count = ArraySize(keys);
   if(count == 0)
      return "";

   string json = "{\"keys\":[";

   for(int i = 0; i < count; i++)
   {
      if(i > 0)
         json += ",";
      json += "\"" + keys[i] + "\"";
   }

   json += "]}";

   return json;
}
//+------------------------------------------------------------------+
