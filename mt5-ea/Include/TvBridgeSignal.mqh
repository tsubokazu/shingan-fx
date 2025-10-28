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
bool HandleSignal(const Signal &sig, double defaultLot, string lotMode,
                  double balancePerLot, double minLot, double maxLot,
                  bool closeBeforeEntry, bool autoStopLoss, int slLookback, double slBuffer,
                  bool trailingStopOnTP, double trailingStopRatio)
{
   if(sig.action == "BUY")
   {
      // エントリー前の全決済（オプション）
      if(closeBeforeEntry)
      {
         PrintFormat("[TvBridgeSignal] Closing all positions for %s before BUY entry", sig.symbol);
         CloseAll(sig.symbol);
      }

      // Worker側から volume が指定されていない（0.0）場合は EA 側で計算
      double actualVolume = sig.volume;

      if(actualVolume <= 0)
      {
         // ロット計算モードに応じて決定
         if(lotMode == "BALANCE_RATIO")
         {
            actualVolume = CalculateBalanceRatioLot(defaultLot, balancePerLot, minLot, maxLot);
            PrintFormat("[TvBridgeSignal] Processing BUY signal: key=%s, symbol=%s, volume=%.2f (balance ratio)",
                        sig.key, sig.symbol, actualVolume);
         }
         else
         {
            actualVolume = defaultLot;
            PrintFormat("[TvBridgeSignal] Processing BUY signal: key=%s, symbol=%s, volume=%.2f (fixed)",
                        sig.key, sig.symbol, actualVolume);
         }
      }
      else
      {
         PrintFormat("[TvBridgeSignal] Processing BUY signal: key=%s, symbol=%s, volume=%.2f (from signal)",
                     sig.key, sig.symbol, actualVolume);
      }

      return OpenBuy(sig.symbol, actualVolume, autoStopLoss, slLookback, slBuffer);
   }
   else if(sig.action == "SELL")
   {
      // エントリー前の全決済（オプション）
      if(closeBeforeEntry)
      {
         PrintFormat("[TvBridgeSignal] Closing all positions for %s before SELL entry", sig.symbol);
         CloseAll(sig.symbol);
      }

      // Worker側から volume が指定されていない（0.0）場合は EA 側で計算
      double actualVolume = sig.volume;

      if(actualVolume <= 0)
      {
         // ロット計算モードに応じて決定
         if(lotMode == "BALANCE_RATIO")
         {
            actualVolume = CalculateBalanceRatioLot(defaultLot, balancePerLot, minLot, maxLot);
            PrintFormat("[TvBridgeSignal] Processing SELL signal: key=%s, symbol=%s, volume=%.2f (balance ratio)",
                        sig.key, sig.symbol, actualVolume);
         }
         else
         {
            actualVolume = defaultLot;
            PrintFormat("[TvBridgeSignal] Processing SELL signal: key=%s, symbol=%s, volume=%.2f (fixed)",
                        sig.key, sig.symbol, actualVolume);
         }
      }
      else
      {
         PrintFormat("[TvBridgeSignal] Processing SELL signal: key=%s, symbol=%s, volume=%.2f (from signal)",
                     sig.key, sig.symbol, actualVolume);
      }

      return OpenSell(sig.symbol, actualVolume, autoStopLoss, slLookback, slBuffer);
   }
   else if(sig.action == "CLOSE_PARTIAL")
   {
      PrintFormat("[TvBridgeSignal] Processing CLOSE_PARTIAL signal: key=%s, symbol=%s, ratio=%.2f, trailing=%s",
                  sig.key, sig.symbol, sig.volume_ratio,
                  trailingStopOnTP ? "enabled" : "disabled");
      return ClosePartial(sig.symbol, sig.volume_ratio, trailingStopOnTP, trailingStopRatio);
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
int ProcessSignals(const Signal &signals[], string &successKeys[], double defaultLot,
                   string lotMode, double balancePerLot, double minLot, double maxLot,
                   bool closeBeforeEntry, bool autoStopLoss, int slLookback, double slBuffer,
                   bool trailingStopOnTP, double trailingStopRatio)
{
   int signalCount = ArraySize(signals);
   int ackCount = 0;

   ArrayResize(successKeys, signalCount);

   for(int i = 0; i < signalCount; i++)
   {
      // 空のシグナルをスキップ（JSONパース失敗）
      if(StringLen(signals[i].key) == 0 || StringLen(signals[i].symbol) == 0)
      {
         PrintFormat("[TvBridgeSignal] Skipping empty signal at index %d", i);
         continue;
      }

      bool success = HandleSignal(signals[i], defaultLot, lotMode, balancePerLot, minLot, maxLot,
                                   closeBeforeEntry, autoStopLoss, slLookback, slBuffer,
                                   trailingStopOnTP, trailingStopRatio);

      // 成功・失敗に関わらずACKする（キューから削除）
      successKeys[ackCount] = signals[i].key;
      ackCount++;

      if(success)
      {
         PrintFormat("[TvBridgeSignal] Signal processed successfully: key=%s", signals[i].key);
      }
      else
      {
         PrintFormat("[TvBridgeSignal] Signal processing failed (will ACK anyway): key=%s, action=%s",
                     signals[i].key, signals[i].action);
      }
   }

   // Resize to actual ACK count
   ArrayResize(successKeys, ackCount);

   return ackCount;
}
//+------------------------------------------------------------------+
