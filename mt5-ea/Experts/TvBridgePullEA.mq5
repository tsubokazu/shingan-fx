//+------------------------------------------------------------------+
//|                                             TvBridgePullEA.mq5   |
//|                                Pull-based EA for TvBridge        |
//|                        Polls signals from Cloudflare Workers API |
//+------------------------------------------------------------------+
#property copyright "TvBridge"
#property link      ""
#property version   "1.00"
#property strict

#include <../Include/TvBridgeHttp.mqh>
#include <../Include/TvBridgeJson.mqh>
#include <../Include/TvBridgeSignal.mqh>
#include <../Include/TvBridgeTrade.mqh>

//--- Input parameters
input group "=== API Settings ==="
input string InpBaseUrl = "https://tv-bridge.example.com"; // API Base URL
input string InpPollToken = "";                             // Poll Token (required)

input group "=== Polling Settings ==="
input string InpSymbolFilter = "EURUSD";  // Symbol to filter signals
input int    InpPollIntervalSec = 2;      // Polling interval (seconds)
input int    InpPollLimit = 10;           // Max signals per poll

input group "=== Trade Settings ==="
input double InpDefaultLot = 0.01;              // Default lot size (if signal doesn't specify)
input string InpLotMode = "FIXED";              // Lot calculation mode: FIXED or BALANCE_RATIO
input double InpBalancePerLot = 10000;          // Balance per 1.0 lot (for BALANCE_RATIO mode)
input double InpMinLot = 0.01;                  // Minimum lot size
input double InpMaxLot = 100.0;                 // Maximum lot size

input group "=== Error Handling ==="
input int    InpMaxConsecutiveErrors = 5; // Max consecutive errors before alert

//--- Global variables
int g_consecutiveErrors = 0;
datetime g_lastPollTime = 0;
int g_totalSignalsProcessed = 0;
int g_totalSignalsAcked = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   PrintFormat("[TvBridgePullEA] Initializing...");

   // Validate inputs
   if(StringLen(InpPollToken) == 0)
   {
      Alert("POLL_TOKEN is not set! Please configure InpPollToken parameter.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpPollIntervalSec < 1)
   {
      Alert("Poll interval must be at least 1 second.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Initialize trade settings
   InitTrade();

   // Set up timer for polling
   if(!EventSetTimer(InpPollIntervalSec))
   {
      PrintFormat("[TvBridgePullEA] Failed to set timer");
      return INIT_FAILED;
   }

   PrintFormat("[TvBridgePullEA] Initialized successfully");
   PrintFormat("[TvBridgePullEA] Base URL: %s", InpBaseUrl);
   PrintFormat("[TvBridgePullEA] Symbol Filter: %s", InpSymbolFilter);
   PrintFormat("[TvBridgePullEA] Poll Interval: %d seconds", InpPollIntervalSec);
   PrintFormat("[TvBridgePullEA] Poll Limit: %d", InpPollLimit);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   PrintFormat("[TvBridgePullEA] Deinitialized. Reason: %d", reason);
   PrintFormat("[TvBridgePullEA] Total signals processed: %d", g_totalSignalsProcessed);
   PrintFormat("[TvBridgePullEA] Total signals acknowledged: %d", g_totalSignalsAcked);
}

//+------------------------------------------------------------------+
//| Timer function - called every N seconds                           |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_lastPollTime = TimeCurrent();

   PrintFormat("[TvBridgePullEA] Polling... (interval: %d sec)", InpPollIntervalSec);

   // Poll for pending signals
   string jsonResponse = HttpGetPendingSignals(InpBaseUrl, InpPollToken, InpSymbolFilter, InpPollLimit);

   if(StringLen(jsonResponse) == 0)
   {
      g_consecutiveErrors++;

      if(g_consecutiveErrors >= InpMaxConsecutiveErrors)
      {
         Alert(StringFormat("TvBridge EA: %d consecutive poll failures!", g_consecutiveErrors));
         g_consecutiveErrors = 0; // Reset after alert
      }

      return;
   }

   // Reset error counter on successful poll
   g_consecutiveErrors = 0;

   // Parse signals
   Signal signals[];
   int signalCount = ParseSignals(jsonResponse, signals);

   if(signalCount == 0)
   {
      // No signals to process
      PrintFormat("[TvBridgePullEA] Polling successful. No pending signals for %s", InpSymbolFilter);
      return;
   }

   PrintFormat("[TvBridgePullEA] Received %d signal(s)", signalCount);

   // Process signals
   string successKeys[];
   int successCount = ProcessSignals(signals, successKeys, InpDefaultLot,
                                      InpLotMode, InpBalancePerLot, InpMinLot, InpMaxLot);

   g_totalSignalsProcessed += successCount;

   if(successCount == 0)
   {
      PrintFormat("[TvBridgePullEA] No signals were successfully processed");
      return;
   }

   // Acknowledge successful signals
   string ackBody = BuildAckRequestBody(successKeys);

   if(StringLen(ackBody) > 0)
   {
      bool ackResult = HttpAckSignals(InpBaseUrl, InpPollToken, ackBody);

      if(ackResult)
      {
         g_totalSignalsAcked += successCount;
         PrintFormat("[TvBridgePullEA] Acknowledged %d signal(s)", successCount);
      }
      else
      {
         PrintFormat("[TvBridgePullEA] Failed to acknowledge signals");
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function (not used for pull-based EA)                |
//+------------------------------------------------------------------+
void OnTick()
{
   // This EA uses timer-based polling, not tick-based logic
}

//+------------------------------------------------------------------+
//| Display EA status on chart                                        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      Comment(StringFormat("TvBridge Pull EA\n" +
                           "Status: Running\n" +
                           "Symbol Filter: %s\n" +
                           "Last Poll: %s\n" +
                           "Signals Processed: %d\n" +
                           "Signals Acked: %d\n" +
                           "Consecutive Errors: %d",
                           InpSymbolFilter,
                           TimeToString(g_lastPollTime, TIME_DATE | TIME_SECONDS),
                           g_totalSignalsProcessed,
                           g_totalSignalsAcked,
                           g_consecutiveErrors));
   }
}
//+------------------------------------------------------------------+
