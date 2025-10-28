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
//| Calculate SL/TP prices                                           |
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
bool OpenBuy(string symbol, double volume)
{
   double lot = NormalizeLotSize(symbol, volume);
   if(lot <= 0)
   {
      PrintFormat("[TvBridgeTrade] Invalid lot size: %.2f for symbol %s", volume, symbol);
      return false;
   }

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double sl = CalculateStopLoss(symbol, ORDER_TYPE_BUY, ask);
   double tp = CalculateTakeProfit(symbol, ORDER_TYPE_BUY, ask);

   bool result = g_trade.Buy(lot, symbol, 0, sl, tp, InpTradeComment);

   if(result)
   {
      PrintFormat("[TvBridgeTrade] BUY order opened: %s, lot=%.2f, price=%.5f", symbol, lot, ask);
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
bool OpenSell(string symbol, double volume)
{
   double lot = NormalizeLotSize(symbol, volume);
   if(lot <= 0)
   {
      PrintFormat("[TvBridgeTrade] Invalid lot size: %.2f for symbol %s", volume, symbol);
      return false;
   }

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double sl = CalculateStopLoss(symbol, ORDER_TYPE_SELL, bid);
   double tp = CalculateTakeProfit(symbol, ORDER_TYPE_SELL, bid);

   bool result = g_trade.Sell(lot, symbol, 0, sl, tp, InpTradeComment);

   if(result)
   {
      PrintFormat("[TvBridgeTrade] SELL order opened: %s, lot=%.2f, price=%.5f", symbol, lot, bid);
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
//| Close partial positions for a symbol by ratio                    |
//+------------------------------------------------------------------+
bool ClosePartial(string symbol, double ratio)
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
   return (closed > 0);
}
//+------------------------------------------------------------------+
