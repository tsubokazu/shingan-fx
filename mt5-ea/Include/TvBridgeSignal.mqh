//+------------------------------------------------------------------+
//|                                               TvBridgeSignal.mqh |
//|                               Signal Handler for TvBridge EA     |
//+------------------------------------------------------------------+
#property copyright "TvBridge"
#property link      ""
#property strict

#include "TvBridgeJson.mqh"
#include "TvBridgeTrade.mqh"

//+------------------------------------------------------------------+
//| Handle a single signal and execute corresponding trade action    |
//+------------------------------------------------------------------+
bool HandleSignal(const Signal &sig)
{
   if(sig.action == "BUY")
   {
      PrintFormat("[TvBridgeSignal] Processing BUY signal: key=%s, symbol=%s, volume=%.2f",
                  sig.key, sig.symbol, sig.volume);
      return OpenBuy(sig.symbol, sig.volume);
   }
   else if(sig.action == "SELL")
   {
      PrintFormat("[TvBridgeSignal] Processing SELL signal: key=%s, symbol=%s, volume=%.2f",
                  sig.key, sig.symbol, sig.volume);
      return OpenSell(sig.symbol, sig.volume);
   }
   else if(sig.action == "CLOSE_PARTIAL")
   {
      PrintFormat("[TvBridgeSignal] Processing CLOSE_PARTIAL signal: key=%s, symbol=%s, ratio=%.2f",
                  sig.key, sig.symbol, sig.volume_ratio);
      return ClosePartial(sig.symbol, sig.volume_ratio);
   }
   else if(sig.action == "CLOSE")
   {
      PrintFormat("[TvBridgeSignal] Processing CLOSE signal: key=%s, symbol=%s",
                  sig.key, sig.symbol);
      return CloseAll(sig.symbol);
   }
   else
   {
      PrintFormat("[TvBridgeSignal] Unknown action: %s for key=%s", sig.action, sig.key);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Process all signals and return array of successfully processed keys |
//+------------------------------------------------------------------+
int ProcessSignals(const Signal &signals[], string &successKeys[])
{
   int signalCount = ArraySize(signals);
   int successCount = 0;

   ArrayResize(successKeys, signalCount);

   for(int i = 0; i < signalCount; i++)
   {
      bool success = HandleSignal(signals[i]);

      if(success)
      {
         successKeys[successCount] = signals[i].key;
         successCount++;
         PrintFormat("[TvBridgeSignal] Signal processed successfully: key=%s", signals[i].key);
      }
      else
      {
         PrintFormat("[TvBridgeSignal] Signal processing failed: key=%s, action=%s",
                     signals[i].key, signals[i].action);
      }
   }

   // Resize to actual success count
   ArrayResize(successKeys, successCount);

   return successCount;
}
//+------------------------------------------------------------------+
