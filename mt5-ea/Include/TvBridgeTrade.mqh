//+------------------------------------------------------------------+
//|                                                TvBridgeTrade.mqh |
//|                                  Trading Utility for TvBridge EA |
//+------------------------------------------------------------------+
#property copyright "TvBridge"
#property link      ""
#property strict

#include <Trade\Trade.mqh>

// Global trade object
CTrade g_trade;

// Input parameters for trade settings
input double InpStopLossPips = 0;     // Stop Loss in pips (0 = no SL)
input double InpTakeProfitPips = 0;   // Take Profit in pips (0 = no TP)
input int    InpSlippagePoints = 10;  // Maximum slippage in points
input string InpTradeComment = "TvBridge"; // Trade comment

//+------------------------------------------------------------------+
//| Initialize trade settings                                        |
//+------------------------------------------------------------------+
void InitTrade()
{
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC); // Immediate or Cancel
   g_trade.SetAsyncMode(false); // Synchronous mode
}

//+------------------------------------------------------------------+
//| Calculate lot size based on symbol                               |
//+------------------------------------------------------------------+
double NormalizeLotSize(string symbol, double requestedLot)
{
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(requestedLot < minLot)
      requestedLot = minLot;
   if(requestedLot > maxLot)
      requestedLot = maxLot;

   // Round to lot step
   requestedLot = MathFloor(requestedLot / lotStep) * lotStep;

   return requestedLot;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on balance ratio                        |
//| balancePerLot: 1.0 lot あたりの基準残高（例: 10000 = 1万ドルで1.0lot）|
//+------------------------------------------------------------------+
double CalculateBalanceRatioLot(double baseLot, double balancePerLot, double minLot, double maxLot)
{
   if(balancePerLot <= 0)
   {
      PrintFormat("[TvBridgeTrade] Invalid balancePerLot: %.2f, using base lot", balancePerLot);
      return baseLot;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double calculatedLot = (balance / balancePerLot) * baseLot;

   // Apply min/max constraints
   if(calculatedLot < minLot)
      calculatedLot = minLot;
   if(calculatedLot > maxLot)
      calculatedLot = maxLot;

   PrintFormat("[TvBridgeTrade] Balance ratio lot: balance=%.2f, ratio=%.2f, calculated=%.2f",
               balance, balance / balancePerLot, calculatedLot);

   return calculatedLot;
}

//+------------------------------------------------------------------+
//| Get recent low price from N bars                                 |
//+------------------------------------------------------------------+
double GetRecentLow(string symbol, int lookbackBars)
{
   double low = DBL_MAX;

   for(int i = 1; i <= lookbackBars; i++)
   {
      double barLow = iLow(symbol, PERIOD_CURRENT, i);
      if(barLow < low)
         low = barLow;
   }

   return (low == DBL_MAX) ? 0 : low;
}

//+------------------------------------------------------------------+
//| Get recent high price from N bars                                |
//+------------------------------------------------------------------+
double GetRecentHigh(string symbol, int lookbackBars)
{
   double high = 0;

   for(int i = 1; i <= lookbackBars; i++)
   {
      double barHigh = iHigh(symbol, PERIOD_CURRENT, i);
      if(barHigh > high)
         high = barHigh;
   }

   return high;
}

//+------------------------------------------------------------------+
//| Calculate SL based on swing high/low with buffer                 |
//+------------------------------------------------------------------+
double CalculateStopLossFromSwing(string symbol, ENUM_ORDER_TYPE orderType, double price,
                                   int lookbackBars, double bufferPercent)
{
   if(lookbackBars <= 0 || bufferPercent < 0)
      return 0;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double sl = 0;

   if(orderType == ORDER_TYPE_BUY)
   {
      // LONG時: 直近安値 - バッファ
      double recentLow = GetRecentLow(symbol, lookbackBars);
      if(recentLow > 0)
      {
         double buffer = recentLow * (bufferPercent / 100.0);
         sl = NormalizeDouble(recentLow - buffer, digits);
         PrintFormat("[TvBridgeTrade] BUY SL: recent_low=%.5f, buffer=%.5f (%.1f%%), sl=%.5f",
                     recentLow, buffer, bufferPercent, sl);
      }
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      // SHORT時: 直近高値 + バッファ
      double recentHigh = GetRecentHigh(symbol, lookbackBars);
      if(recentHigh > 0)
      {
         double buffer = recentHigh * (bufferPercent / 100.0);
         sl = NormalizeDouble(recentHigh + buffer, digits);
         PrintFormat("[TvBridgeTrade] SELL SL: recent_high=%.5f, buffer=%.5f (%.1f%%), sl=%.5f",
                     recentHigh, buffer, bufferPercent, sl);
      }
   }

   return sl;
}

//+------------------------------------------------------------------+
//| Calculate SL/TP prices (legacy method using pips)                |
//+------------------------------------------------------------------+
double CalculateStopLoss(string symbol, ENUM_ORDER_TYPE orderType, double price)
{
   if(InpStopLossPips <= 0)
      return 0;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double pipSize = point * 10; // Assume 5-digit broker

   if(orderType == ORDER_TYPE_BUY)
      return NormalizeDouble(price - InpStopLossPips * pipSize, digits);
   else if(orderType == ORDER_TYPE_SELL)
      return NormalizeDouble(price + InpStopLossPips * pipSize, digits);

   return 0;
}

double CalculateTakeProfit(string symbol, ENUM_ORDER_TYPE orderType, double price)
{
   if(InpTakeProfitPips <= 0)
      return 0;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double pipSize = point * 10; // Assume 5-digit broker

   if(orderType == ORDER_TYPE_BUY)
      return NormalizeDouble(price + InpTakeProfitPips * pipSize, digits);
   else if(orderType == ORDER_TYPE_SELL)
      return NormalizeDouble(price - InpTakeProfitPips * pipSize, digits);

   return 0;
}

//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
bool OpenBuy(string symbol, double volume, bool autoStopLoss = false,
             int slLookback = 30, double slBuffer = 1.0)
{
   double lot = NormalizeLotSize(symbol, volume);
   if(lot <= 0)
   {
      PrintFormat("[TvBridgeTrade] Invalid lot size: %.2f for symbol %s", volume, symbol);
      return false;
   }

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double sl = 0;
   double tp = CalculateTakeProfit(symbol, ORDER_TYPE_BUY, ask);

   // SL設定: autoStopLoss が有効ならスイング高値/安値ベース、無効ならピップスベース
   if(autoStopLoss)
   {
      sl = CalculateStopLossFromSwing(symbol, ORDER_TYPE_BUY, ask, slLookback, slBuffer);
   }
   else
   {
      sl = CalculateStopLoss(symbol, ORDER_TYPE_BUY, ask);
   }

   bool result = g_trade.Buy(lot, symbol, 0, sl, tp, InpTradeComment);

   if(result)
   {
      PrintFormat("[TvBridgeTrade] BUY order opened: %s, lot=%.2f, price=%.5f, sl=%.5f, tp=%.5f",
                  symbol, lot, ask, sl, tp);
   }
   else
   {
      PrintFormat("[TvBridgeTrade] BUY order failed: %s, error=%d", symbol, GetLastError());
   }

   return result;
}

//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
bool OpenSell(string symbol, double volume, bool autoStopLoss = false,
              int slLookback = 30, double slBuffer = 1.0)
{
   double lot = NormalizeLotSize(symbol, volume);
   if(lot <= 0)
   {
      PrintFormat("[TvBridgeTrade] Invalid lot size: %.2f for symbol %s", volume, symbol);
      return false;
   }

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double sl = 0;
   double tp = CalculateTakeProfit(symbol, ORDER_TYPE_SELL, bid);

   // SL設定: autoStopLoss が有効ならスイング高値/安値ベース、無効ならピップスベース
   if(autoStopLoss)
   {
      sl = CalculateStopLossFromSwing(symbol, ORDER_TYPE_SELL, bid, slLookback, slBuffer);
   }
   else
   {
      sl = CalculateStopLoss(symbol, ORDER_TYPE_SELL, bid);
   }

   bool result = g_trade.Sell(lot, symbol, 0, sl, tp, InpTradeComment);

   if(result)
   {
      PrintFormat("[TvBridgeTrade] SELL order opened: %s, lot=%.2f, price=%.5f, sl=%.5f, tp=%.5f",
                  symbol, lot, bid, sl, tp);
   }
   else
   {
      PrintFormat("[TvBridgeTrade] SELL order failed: %s, error=%d", symbol, GetLastError());
   }

   return result;
}

//+------------------------------------------------------------------+
//| Close all positions for a symbol                                 |
//+------------------------------------------------------------------+
bool CloseAll(string symbol)
{
   int closed = 0;
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      if(g_trade.PositionClose(ticket))
      {
         closed++;
         PrintFormat("[TvBridgeTrade] Position closed: ticket=%I64u, symbol=%s", ticket, symbol);
      }
      else
      {
         PrintFormat("[TvBridgeTrade] Failed to close position: ticket=%I64u, error=%d", ticket, GetLastError());
      }
   }

   PrintFormat("[TvBridgeTrade] CloseAll: %d positions closed for %s", closed, symbol);
   return (closed > 0);
}

//+------------------------------------------------------------------+
//| Update trailing stop for remaining positions after partial close |
//+------------------------------------------------------------------+
bool UpdateTrailingStop(string symbol, double trailingRatio)
{
   if(trailingRatio <= 0 || trailingRatio > 1.0)
   {
      PrintFormat("[TvBridgeTrade] Invalid trailing ratio: %.2f", trailingRatio);
      return false;
   }

   int updated = 0;
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double currentPrice = (posType == POSITION_TYPE_BUY)
                            ? SymbolInfoDouble(symbol, SYMBOL_BID)
                            : SymbolInfoDouble(symbol, SYMBOL_ASK);

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double newSL = 0;

      // 利益を計算
      double profit = 0;
      if(posType == POSITION_TYPE_BUY)
      {
         profit = currentPrice - entryPrice;
         if(profit > 0)
         {
            newSL = NormalizeDouble(entryPrice + (profit * trailingRatio), digits);

            // 既存のSLより有利な場合のみ更新
            if(currentSL <= 0 || newSL > currentSL)
            {
               if(g_trade.PositionModify(ticket, newSL, currentTP))
               {
                  updated++;
                  PrintFormat("[TvBridgeTrade] Trailing stop updated: ticket=%I64u, entry=%.5f, current=%.5f, old_sl=%.5f, new_sl=%.5f (%.1f%%)",
                              ticket, entryPrice, currentPrice, currentSL, newSL, trailingRatio * 100);
               }
               else
               {
                  PrintFormat("[TvBridgeTrade] Failed to update trailing stop: ticket=%I64u, error=%d", ticket, GetLastError());
               }
            }
            else
            {
               PrintFormat("[TvBridgeTrade] Trailing stop not updated (current SL is better): ticket=%I64u, current_sl=%.5f, calculated=%.5f",
                           ticket, currentSL, newSL);
            }
         }
         else
         {
            PrintFormat("[TvBridgeTrade] No profit yet for BUY position: ticket=%I64u, entry=%.5f, current=%.5f",
                        ticket, entryPrice, currentPrice);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         profit = entryPrice - currentPrice;
         if(profit > 0)
         {
            newSL = NormalizeDouble(entryPrice - (profit * trailingRatio), digits);

            // 既存のSLより有利な場合のみ更新
            if(currentSL <= 0 || newSL < currentSL)
            {
               if(g_trade.PositionModify(ticket, newSL, currentTP))
               {
                  updated++;
                  PrintFormat("[TvBridgeTrade] Trailing stop updated: ticket=%I64u, entry=%.5f, current=%.5f, old_sl=%.5f, new_sl=%.5f (%.1f%%)",
                              ticket, entryPrice, currentPrice, currentSL, newSL, trailingRatio * 100);
               }
               else
               {
                  PrintFormat("[TvBridgeTrade] Failed to update trailing stop: ticket=%I64u, error=%d", ticket, GetLastError());
               }
            }
            else
            {
               PrintFormat("[TvBridgeTrade] Trailing stop not updated (current SL is better): ticket=%I64u, current_sl=%.5f, calculated=%.5f",
                           ticket, currentSL, newSL);
            }
         }
         else
         {
            PrintFormat("[TvBridgeTrade] No profit yet for SELL position: ticket=%I64u, entry=%.5f, current=%.5f",
                        ticket, entryPrice, currentPrice);
         }
      }
   }

   PrintFormat("[TvBridgeTrade] Trailing stop: %d positions updated for %s (ratio=%.1f%%)",
               updated, symbol, trailingRatio * 100);
   return (updated > 0);
}

//+------------------------------------------------------------------+
//| Close partial positions for a symbol by ratio                    |
//+------------------------------------------------------------------+
bool ClosePartial(string symbol, double ratio, bool enableTrailing = false, double trailingRatio = 0.5)
{
   if(ratio <= 0 || ratio > 1.0)
   {
      PrintFormat("[TvBridgeTrade] Invalid ratio: %.2f", ratio);
      return false;
   }

   int closed = 0;
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      double closeVolume = NormalizeLotSize(symbol, currentVolume * ratio);

      if(closeVolume <= 0)
         continue;

      // Partial close
      if(closeVolume >= currentVolume)
      {
         // Close entire position
         if(g_trade.PositionClose(ticket))
         {
            closed++;
            PrintFormat("[TvBridgeTrade] Position fully closed: ticket=%I64u, volume=%.2f", ticket, currentVolume);
         }
      }
      else
      {
         // MQL5 doesn't support direct partial close, we need to close and reopen
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(g_trade.PositionClosePartial(ticket, closeVolume))
         {
            closed++;
            PrintFormat("[TvBridgeTrade] Position partially closed: ticket=%I64u, volume=%.2f/%.2f",
                        ticket, closeVolume, currentVolume);
         }
         else
         {
            PrintFormat("[TvBridgeTrade] Failed to partially close: ticket=%I64u, error=%d", ticket, GetLastError());
         }
      }
   }

   PrintFormat("[TvBridgeTrade] ClosePartial: %d positions closed (%.1f%%) for %s", closed, ratio * 100, symbol);

   // トレーリングストップを実行（部分決済後）
   if(closed > 0 && enableTrailing)
   {
      PrintFormat("[TvBridgeTrade] Applying trailing stop after partial close...");
      UpdateTrailingStop(symbol, trailingRatio);
   }

   return (closed > 0);
}
//+------------------------------------------------------------------+
