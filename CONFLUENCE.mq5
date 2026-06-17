//+------------------------------------------------------------------+
//|                                         CONFLUENCE V1.0          |
//|                    INDIVIDUAL SESSION CONTROLS                   |
//|                           Created By - RATTANAC CHHORM           |
//+------------------------------------------------------------------+
#property copyright "RATTANAC CHHORM"
#property version   "1.0"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//===================== RISK MANAGEMENT INPUTS =====================//
input group "========== RISK MANAGEMENT =========="
input double   RiskPercent            = 0.5;      // Risk per trade (%) - 0 to disable
input double   FixedLot               = 0.0;      // Fixed lot size (0 = use risk%)
input double   MaxDailyLossPercent    = 10.0;     // Max daily loss (%)
input int      MaxTradesPerDay        = 10;       // Max trades per day
input double   RewardRiskRatio        = 1.5;      // Risk/Reward ratio

//===================== TRADE FILTERS =====================//
input group "========== TRADE FILTERS =========="
input bool     UseTimeFilter          = false;    // Use trading hours (false = trade 24/7)
input int      MaxSpreadPoints        = 50;       // Max spread allowed (0 = disable)
input int      MinStopDistance        = 20;       // Min stop distance in points
input int      MaxConsecutiveLosses   = 10;       // Stop after N consecutive losses

//===================== INDIVIDUAL SESSION CONTROLS =====================//
input group "========== INDIVIDUAL SESSIONS (GMT TIME) =========="
input bool     SessionSydney          = false;    // Sydney Session (22:00 - 07:00 GMT)
input bool     SessionTokyo           = false;    // Tokyo Session (00:00 - 09:00 GMT)
input bool     SessionLondon          = true;     // London Session (08:00 - 17:00 GMT) - RECOMMENDED
input bool     SessionNewYork         = true;     // New York Session (13:00 - 22:00 GMT) - RECOMMENDED

//===================== OVERLAP SESSIONS (HIGHEST VOLATILITY) =====================//
input group "========== OVERLAP SESSIONS (HIGHEST VOLATILITY) =========="
input bool     OverlapLondonNY        = true;     // London + NY Overlap (13:00 - 17:00 GMT) - BEST FOR XAUUSD
input bool     OverlapTokyoLondon     = false;    // Tokyo + London Overlap (08:00 - 09:00 GMT)

//===================== STOP LOSS & TRAILING =====================//
input group "========== STOP LOSS =========="
input int      SLBufferPips           = 15;       // Stop loss buffer in pips behind swing
input bool     UseTrailingStop        = false;    // Enable trailing stop
input int      TrailingStartPips      = 30;       // Start trailing after N pips profit
input int      TrailingStepPips       = 10;       // Trail stop by N pips

//===================== POSITION MANAGEMENT =====================//
input group "========== POSITION MANAGEMENT =========="
input bool     CloseOnFriday          = false;    // Close all positions on Friday
input int      FridayCloseHour        = 20;       // Hour to close on Friday (20 = 8 PM)
input bool     UseBreakeven           = true;     // Move SL to breakeven after profit
input int      BreakevenTriggerPips   = 20;       // Pips profit to trigger breakeven

//===================== SWING DETECTION - NEW =====================//
input group "========== SWING DETECTION =========="
input int      SwingLookbackBars      = 100;      // H1 bars to scan for swing (original used 50 M5 bars)
input int      SwingConfirmBars       = 5;        // Bars each side to confirm swing (original = 4)
input bool     ShowSwingLines         = true;     // Draw swing level on chart for visual check

//===================== DEBUG =====================//
input group "========== DEBUG =========="
input bool     ForceTrades            = true;     // Force trades (for testing)
input bool     UsePythonRisk          = false;    // Enable AI risk control

//===================== GLOBAL VARIABLES =====================//
int ATRHandle;
int FastEMAHandle;
int SlowEMAHandle;
datetime LastBarTime = 0;
int TodayTradeCount = 0;
int LastTradeDay = 0;
double TodayLoss = 0;
int consecutiveLosses = 0;
int SwingLineCount = 0;   // for unique chart object names

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ATRHandle = iATR(_Symbol, PERIOD_M15, 14);
   FastEMAHandle = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   SlowEMAHandle = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);

   trade.SetExpertMagicNumber(888777);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   Print("========================================");
   Print("CONFLUENCE V1.0 - Created By RATTANAC CHHORM");
   Print("Active Sessions:");
   if(SessionSydney) Print("  - Sydney (22:00-07:00 GMT)");
   if(SessionTokyo) Print("  - Tokyo (00:00-09:00 GMT)");
   if(SessionLondon) Print("  - London (08:00-17:00 GMT)");
   if(SessionNewYork) Print("  - New York (13:00-22:00 GMT)");
   if(OverlapLondonNY) Print("  - London+NY Overlap (13:00-17:00 GMT)");
   if(OverlapTokyoLondon) Print("  - Tokyo+London Overlap (08:00-09:00 GMT)");
   Print("Swing: H1 lookback=", SwingLookbackBars, " confirm=+-", SwingConfirmBars, " bars");
   Print("========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ATRHandle != INVALID_HANDLE) IndicatorRelease(ATRHandle);
   if(FastEMAHandle != INVALID_HANDLE) IndicatorRelease(FastEMAHandle);
   if(SlowEMAHandle != INVALID_HANDLE) IndicatorRelease(SlowEMAHandle);
   ObjectsDeleteAll(0, "SwingLine_");
   Comment("");
   Print("CONFLUENCE V1.0 SHUTDOWN");
}

//+------------------------------------------------------------------+
//| CHECK IF IN SYDNEY SESSION                                       |
//+------------------------------------------------------------------+
bool InSydneySession()
{
   if(!SessionSydney) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   double currentTime = dt.hour + dt.min / 60.0;

   // Sydney: 22:00 - 07:00 GMT (next day)
   if(currentTime >= 22.00 || currentTime < 7.00)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK IF IN TOKYO SESSION                                        |
//+------------------------------------------------------------------+
bool InTokyoSession()
{
   if(!SessionTokyo) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   double currentTime = dt.hour + dt.min / 60.0;

   // Tokyo: 00:00 - 09:00 GMT
   if(currentTime >= 0.00 && currentTime < 9.00)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK IF IN LONDON SESSION                                       |
//+------------------------------------------------------------------+
bool InLondonSession()
{
   if(!SessionLondon) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   double currentTime = dt.hour + dt.min / 60.0;

   // London: 08:00 - 17:00 GMT
   if(currentTime >= 8.00 && currentTime < 17.00)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK IF IN NEW YORK SESSION                                     |
//+------------------------------------------------------------------+
bool InNewYorkSession()
{
   if(!SessionNewYork) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   double currentTime = dt.hour + dt.min / 60.0;

   // New York: 13:00 - 22:00 GMT
   if(currentTime >= 13.00 && currentTime < 22.00)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK IF IN LONDON+NY OVERLAP                                    |
//+------------------------------------------------------------------+
bool InLondonNYOverlap()
{
   if(!OverlapLondonNY) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   double currentTime = dt.hour + dt.min / 60.0;

   // London + NY Overlap: 13:00 - 17:00 GMT
   if(currentTime >= 13.00 && currentTime < 17.00)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK IF IN TOKYO+LONDON OVERLAP                                 |
//+------------------------------------------------------------------+
bool InTokyoLondonOverlap()
{
   if(!OverlapTokyoLondon) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   double currentTime = dt.hour + dt.min / 60.0;

   // Tokyo + London Overlap: 08:00 - 09:00 GMT
   if(currentTime >= 8.00 && currentTime < 9.00)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK TRADING TIME - INDIVIDUAL SESSIONS                         |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   if(!UseTimeFilter) return true;

   // Check individual sessions
   if(InSydneySession()) return true;
   if(InTokyoSession()) return true;
   if(InLondonSession()) return true;
   if(InNewYorkSession()) return true;

   // Check overlaps (these are subsets of sessions above)
   if(InLondonNYOverlap()) return true;
   if(InTokyoLondonOverlap()) return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK SPREAD                                                     |
//+------------------------------------------------------------------+
bool IsSpreadOK()
{
   if(MaxSpreadPoints <= 0) return true;

   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;

   if(spread > MaxSpreadPoints)
   {
      Print("Spread too high: ", spread, " > ", MaxSpreadPoints);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| CHECK FRIDAY CLOSE                                               |
//+------------------------------------------------------------------+
void CheckFridayClose()
{
   if(!CloseOnFriday) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.day_of_week == 5 && dt.hour >= FridayCloseHour)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == 888777)
            {
               trade.PositionClose(ticket);
               Print("Friday close: Closed position ", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| APPLY TRAILING STOP                                              |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(!UseTrailingStop) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != 888777) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentPrice = type == POSITION_TYPE_BUY ?
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double profitPips = 0;

      if(type == POSITION_TYPE_BUY)
         profitPips = (currentPrice - openPrice) / _Point / 10;
      else
         profitPips = (openPrice - currentPrice) / _Point / 10;

      if(profitPips >= TrailingStartPips)
      {
         double newSL = 0;
         if(type == POSITION_TYPE_BUY)
            newSL = currentPrice - TrailingStepPips * 10 * _Point;
         else
            newSL = currentPrice + TrailingStepPips * 10 * _Point;

         newSL = NormalizeDouble(newSL, _Digits);

         if((type == POSITION_TYPE_BUY && newSL > currentSL) ||
            (type == POSITION_TYPE_SELL && newSL < currentSL))
         {
            if(trade.PositionModify(ticket, newSL, currentTP))
               Print("Trailing stop updated: ", ticket, " new SL = ", newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| APPLY BREAKEVEN                                                  |
//+------------------------------------------------------------------+
void ApplyBreakeven()
{
   if(!UseBreakeven) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != 888777) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double currentPrice = type == POSITION_TYPE_BUY ?
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profitPips = 0;
      if(type == POSITION_TYPE_BUY)
         profitPips = (currentPrice - openPrice) / _Point / 10;
      else
         profitPips = (openPrice - currentPrice) / _Point / 10;

      if(profitPips >= BreakevenTriggerPips)
      {
         double breakevenSL = type == POSITION_TYPE_BUY ?
                              openPrice + 1 * _Point :
                              openPrice - 1 * _Point;
         breakevenSL = NormalizeDouble(breakevenSL, _Digits);

         if((type == POSITION_TYPE_BUY && breakevenSL > currentSL) ||
            (type == POSITION_TYPE_SELL && breakevenSL < currentSL))
         {
            if(trade.PositionModify(ticket, breakevenSL, currentTP))
               Print("Breakeven set for ticket ", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| GET ATR POINTS                                                   |
//+------------------------------------------------------------------+
double GetATRPoints()
{
   double atr[1];
   if(CopyBuffer(ATRHandle, 0, 1, 1, atr) == 1)
      return atr[0] / _Point;
   return 20;
}

//+------------------------------------------------------------------+
//| GET TREND DIRECTION                                              |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   double fast[1], slow[1];
   if(CopyBuffer(FastEMAHandle, 0, 1, 1, fast) != 1) return 0;
   if(CopyBuffer(SlowEMAHandle, 0, 1, 1, slow) != 1) return 0;

   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| GET CANDLE DIRECTION                                             |
//+------------------------------------------------------------------+
int GetCandleDirection()
{
   MqlRates rates[2];
   if(CopyRates(_Symbol, PERIOD_M15, 0, 2, rates) != 2) return 0;

   if(rates[1].close > rates[1].open) return 1;
   if(rates[1].close < rates[1].open) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| DRAW SWING LINE ON CHART                                         |
//| Shows exactly where the swing level was detected.               |
//| Blue dashed = BUY swing low, Red dashed = SELL swing high.      |
//+------------------------------------------------------------------+
void DrawSwingLine(double price, bool isBuy, string source)
{
   if(!ShowSwingLines) return;

   SwingLineCount++;
   string name = "SwingLine_" + IntegerToString(SwingLineCount);

   // Keep only the last 6 lines to avoid clutter
   if(SwingLineCount > 6)
      ObjectDelete(0, "SwingLine_" + IntegerToString(SwingLineCount - 6));

   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   isBuy ? clrDodgerBlue : clrOrangeRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   2);
   ObjectSetInteger(0, name, OBJPROP_STYLE,   STYLE_DASH);
   ObjectSetString (0, name, OBJPROP_TOOLTIP,
                   (isBuy ? "SWING LOW: " : "SWING HIGH: ") +
                   DoubleToString(price, _Digits) + " [" + source + "]");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| FIND MAJOR SWING HIGH/LOW — IMPROVED                             |
//|                                                                  |
//| WHAT CHANGED vs original:                                        |
//|                                                                  |
//| Original: scanned only M5 bars (50 bars = ~4 hours), used ±4    |
//| bar confirmation window. This caught tiny noise wicks and micro  |
//| structure, not the real swing highs/lows you see on the chart.  |
//|                                                                  |
//| New:                                                             |
//|  1. Scans H1 first (SwingLookbackBars, default 100 = ~4 months) |
//|     Each H1 bar = 1 hour, so ±5 bars = 10-hour confirmation.    |
//|     This finds the major structure levels that matter for SL.   |
//|  2. Falls back to M15 (150 bars = ~37 hours) if H1 finds nothing|
//|  3. Falls back to ATR only as last resort — never silently       |
//|     like the original which used lowestLow/highestHigh as a     |
//|     fallback (that's just the extreme candle, not a real swing). |
//|  4. Draws a dashed horizontal line on the chart so you can      |
//|     visually verify every SL placement in real time.            |
//|  5. Safety check: rejects a swing that is on the wrong side     |
//|     of entry (original had no such guard).                      |
//+------------------------------------------------------------------+
void FindNearestSwing(bool isBuy, double &swingPrice)
{
   swingPrice = 0;

   //--- PASS 1: H1 — major structure --------------------------------
   MqlRates h1[];
   ArraySetAsSeries(h1, true);
   int h1Need = SwingLookbackBars + SwingConfirmBars + 5;

   if(CopyRates(_Symbol, PERIOD_H1, 0, h1Need, h1) >= SwingLookbackBars)
   {
      int bestIndex = -1;

      if(isBuy)
      {
         for(int i = SwingConfirmBars; i < SwingLookbackBars - SwingConfirmBars; i++)
         {
            bool isSwingLow = true;
            for(int j = i - SwingConfirmBars; j <= i + SwingConfirmBars; j++)
            {
               if(j == i || j < 0) continue;
               if(h1[j].low <= h1[i].low) { isSwingLow = false; break; }
            }
            if(isSwingLow)
               if(bestIndex == -1 || h1[i].low < h1[bestIndex].low)
                  bestIndex = i;
         }
         if(bestIndex > 0)
         {
            swingPrice = h1[bestIndex].low;
            DrawSwingLine(swingPrice, true, "H1");
            Print("Swing LOW  [H1 bar -", bestIndex, "]: ", DoubleToString(swingPrice, _Digits));
            return;
         }
      }
      else
      {
         for(int i = SwingConfirmBars; i < SwingLookbackBars - SwingConfirmBars; i++)
         {
            bool isSwingHigh = true;
            for(int j = i - SwingConfirmBars; j <= i + SwingConfirmBars; j++)
            {
               if(j == i || j < 0) continue;
               if(h1[j].high >= h1[i].high) { isSwingHigh = false; break; }
            }
            if(isSwingHigh)
               if(bestIndex == -1 || h1[i].high > h1[bestIndex].high)
                  bestIndex = i;
         }
         if(bestIndex > 0)
         {
            swingPrice = h1[bestIndex].high;
            DrawSwingLine(swingPrice, false, "H1");
            Print("Swing HIGH [H1 bar -", bestIndex, "]: ", DoubleToString(swingPrice, _Digits));
            return;
         }
      }
   }

   //--- PASS 2: M15 fallback ----------------------------------------
   Print("Swing: H1 not found, trying M15 fallback");
   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   int m15Lookback = 150;
   int m15Confirm  = 4;

   if(CopyRates(_Symbol, PERIOD_M15, 0, m15Lookback + m15Confirm + 5, m15) >= m15Lookback)
   {
      int bestIndex = -1;

      if(isBuy)
      {
         for(int i = m15Confirm; i < m15Lookback - m15Confirm; i++)
         {
            bool isSwingLow = true;
            for(int j = i - m15Confirm; j <= i + m15Confirm; j++)
            {
               if(j == i || j < 0) continue;
               if(m15[j].low <= m15[i].low) { isSwingLow = false; break; }
            }
            if(isSwingLow)
               if(bestIndex == -1 || m15[i].low < m15[bestIndex].low)
                  bestIndex = i;
         }
         if(bestIndex > 0)
         {
            swingPrice = m15[bestIndex].low;
            DrawSwingLine(swingPrice, true, "M15");
            Print("Swing LOW  [M15 bar -", bestIndex, "]: ", DoubleToString(swingPrice, _Digits));
            return;
         }
      }
      else
      {
         for(int i = m15Confirm; i < m15Lookback - m15Confirm; i++)
         {
            bool isSwingHigh = true;
            for(int j = i - m15Confirm; j <= i + m15Confirm; j++)
            {
               if(j == i || j < 0) continue;
               if(m15[j].high >= m15[i].high) { isSwingHigh = false; break; }
            }
            if(isSwingHigh)
               if(bestIndex == -1 || m15[i].high > m15[bestIndex].high)
                  bestIndex = i;
         }
         if(bestIndex > 0)
         {
            swingPrice = m15[bestIndex].high;
            DrawSwingLine(swingPrice, false, "M15");
            Print("Swing HIGH [M15 bar -", bestIndex, "]: ", DoubleToString(swingPrice, _Digits));
            return;
         }
      }
   }

   //--- PASS 3: nothing found — ATR used in CalculateStopLoss -------
   Print("No swing found on H1 or M15 — will fall back to ATR");
   swingPrice = 0;
}

//+------------------------------------------------------------------+
//| CALCULATE STOP LOSS                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(bool isBuy, double entry)
{
   double swingPrice = 0;
   FindNearestSwing(isBuy, swingPrice);

   double buffer = SLBufferPips * 10 * _Point;

   if(swingPrice > 0)
   {
      double sl = isBuy ? swingPrice - buffer : swingPrice + buffer;

      // Safety guard: swing must be on the correct side of entry
      if(isBuy  && sl >= entry) { Print("Swing SL above entry — using ATR fallback"); swingPrice = 0; }
      if(!isBuy && sl <= entry) { Print("Swing SL below entry — using ATR fallback"); swingPrice = 0; }

      if(swingPrice > 0) return sl;
   }

   double atrPoints = GetATRPoints();
   double atrValue = atrPoints * _Point;
   double fallbackSL = isBuy ? entry - atrValue * 1.5 : entry + atrValue * 1.5;
   Print("Swing not found - using ATR fallback");
   return fallbackSL;
}

//+------------------------------------------------------------------+
//| CALCULATE TAKE PROFIT                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(bool isBuy, double entry, double sl)
{
   double riskDistance = MathAbs(entry - sl);
   double tpDistance = riskDistance * RewardRiskRatio;

   if(isBuy)
      return entry + tpDistance;
   else
      return entry - tpDistance;
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   if(FixedLot > 0)
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      double lot = FixedLot;
      lot = MathMax(minLot, MathMin(maxLot, lot));
      lot = MathFloor(lot / lotStep) * lotStep;
      lot = NormalizeDouble(lot, 2);
      return lot;
   }

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   if(tickValue <= 0 || tickSize <= 0 || riskMoney <= 0)
      return 0.01;

   double lossPerLot = (slPoints * _Point / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0.01;

   double volume = riskMoney / lossPerLot;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / lotStep) * lotStep;
   volume = NormalizeDouble(volume, 2);

   if(volume < minLot) volume = minLot;
   if(volume > 0.10) volume = 0.10;

   return volume;
}

//+------------------------------------------------------------------+
//| UPDATE DAILY COUNTERS                                            |
//+------------------------------------------------------------------+
void UpdateDailyCounters()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentDay = dt.day;

   if(currentDay != LastTradeDay)
   {
      TodayTradeCount = 0;
      TodayLoss = 0;
      consecutiveLosses = 0;
      LastTradeDay = currentDay;
      Print("Daily counters reset");
   }
}

//+------------------------------------------------------------------+
//| CHECK DAILY LOSS LIMIT                                           |
//+------------------------------------------------------------------+
bool IsDailyLossLimitHit()
{
   if(MaxDailyLossPercent <= 0) return false;

   datetime todayStart;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   todayStart = StructToTime(dt);

   if(HistorySelect(todayStart, TimeCurrent()))
   {
      TodayLoss = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal > 0 && HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol)
         {
            double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
            if(profit < 0) TodayLoss += MathAbs(profit);
         }
      }
   }

   double maxLoss = AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100;
   return TodayLoss >= maxLoss;
}

//+------------------------------------------------------------------+
//| CHECK STOP DISTANCE                                              |
//+------------------------------------------------------------------+
bool IsStopDistanceOK(double slPoints)
{
   if(MinStopDistance <= 0) return true;
   return slPoints >= MinStopDistance;
}

//+------------------------------------------------------------------+
//| CHECK IF CAN TRADE                                               |
//+------------------------------------------------------------------+
bool CanTrade()
{
   UpdateDailyCounters();

   if(IsDailyLossLimitHit()) return false;
   if(TodayTradeCount >= MaxTradesPerDay) return false;
   if(consecutiveLosses >= MaxConsecutiveLosses) return false;
   if(!IsSpreadOK()) return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == 888777)
         {
            return false;
         }
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| PLACE TRADE                                                      |
//+------------------------------------------------------------------+
void PlaceTrade()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Failed to get tick");
      return;
   }

   // FORCE TRADES MODE
   if(ForceTrades)
   {
      static int forceCounter = 0;
      forceCounter++;
      bool isBuy = (forceCounter % 2 == 1);

      double entry = isBuy ? tick.ask : tick.bid;
      double sl = CalculateStopLoss(isBuy, entry);
      double tp = CalculateTakeProfit(isBuy, entry, sl);

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      double slPoints = MathAbs(entry - sl) / _Point;
      double volume = CalculateLotSize(slPoints);

      if(volume <= 0)
      {
         Print("Invalid volume calculation");
         return;
      }

      int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(slPoints < minStop)
      {
         Print("Stop too close: ", slPoints, " < ", minStop);
         return;
      }

      bool result = false;
      if(isBuy)
         result = trade.Buy(volume, _Symbol, entry, sl, tp, "CONFLUENCE BUY");
      else
         result = trade.Sell(volume, _Symbol, entry, sl, tp, "CONFLUENCE SELL");

      if(result)
      {
         TodayTradeCount++;
         Print("========================================");
         Print("TRADE: ", isBuy ? "BUY" : "SELL");
         Print("   Entry: ", DoubleToString(entry, _Digits));
         Print("   SL: ", DoubleToString(sl, _Digits), " (", DoubleToString(slPoints, 0), " points)");
         Print("   TP: ", DoubleToString(tp, _Digits));
         Print("   Volume: ", DoubleToString(volume, 2));
         Print("========================================");
      }
      else
      {
         Print("Trade failed: ", trade.ResultRetcodeDescription());
      }
      return;
   }

   // NORMAL TRADING MODE
   int trend = GetTrendDirection();
   int candle = GetCandleDirection();

   if(trend == 0)
   {
      Print("No clear trend - skipping");
      return;
   }

   bool isBuy = (trend == 1 && candle == 1);
   bool isSell = (trend == -1 && candle == -1);

   if(!isBuy && !isSell)
   {
      Print("Candle doesn't match trend - skipping");
      return;
   }

   double entry = isBuy ? tick.ask : tick.bid;
   double sl = CalculateStopLoss(isBuy, entry);
   double tp = CalculateTakeProfit(isBuy, entry, sl);

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double slPoints = MathAbs(entry - sl) / _Point;

   if(!IsStopDistanceOK(slPoints))
   {
      Print("Stop too close: ", slPoints, " < ", MinStopDistance);
      return;
   }

   double volume = CalculateLotSize(slPoints);

   if(volume <= 0)
   {
      Print("Invalid volume calculation");
      return;
   }

   bool result = false;
   if(isBuy)
      result = trade.Buy(volume, _Symbol, entry, sl, tp, "CONFLUENCE BUY");
   else
      result = trade.Sell(volume, _Symbol, entry, sl, tp, "CONFLUENCE SELL");

   if(result)
   {
      TodayTradeCount++;
      Print("========================================");
      Print("TRADE: ", isBuy ? "BUY" : "SELL");
      Print("   Entry: ", DoubleToString(entry, _Digits));
      Print("   SL: ", DoubleToString(sl, _Digits), " (", DoubleToString(slPoints, 0), " points)");
      Print("   TP: ", DoubleToString(tp, _Digits));
      Print("   Volume: ", DoubleToString(volume, 2));
      Print("========================================");
   }
   else
   {
      Print("Trade failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| UPDATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = equity - balance;
   int trend = GetTrendDirection();
   int candle = GetCandleDirection();
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;

   string info = "";
   info = info + "╔═══════════════════════════════════════════════════════════════════╗\n";
   info = info + "║         CONFLUENCE V1.0 - Created By - RATTANAC CHHORM           ║\n";
   info = info + "╠═══════════════════════════════════════════════════════════════════╣\n";
   info = info + "║ Balance: $" + DoubleToString(balance, 2) + "\n";
   info = info + "║ Profit:  $" + DoubleToString(profit, 2) + "\n";
   info = info + "╠═══════════════════════════════════════════════════════════════════╣\n";
   info = info + "║ Trend: " + (trend == 1 ? "BULLISH ▲" : (trend == -1 ? "BEARISH ▼" : "FLAT")) + "\n";
   info = info + "║ Candle: " + (candle == 1 ? "BULLISH" : (candle == -1 ? "BEARISH" : "DOJI")) + "\n";
   info = info + "║ Spread: " + DoubleToString(spread, 0) + " points\n";
   info = info + "║ Trades Today: " + IntegerToString(TodayTradeCount) + "/" + IntegerToString(MaxTradesPerDay) + "\n";
   info = info + "╠═══════════════════════════════════════════════════════════════════╣\n";
   info = info + "║ Time Filter: " + (UseTimeFilter ? "ON (sessions active)" : "OFF (trading 24/7)") + "\n";
   info = info + "║ SL: " + IntegerToString(SLBufferPips) + " pips behind swing  [H1 lookback=" + IntegerToString(SwingLookbackBars) + "]\n";
   info = info + "║ Force Trades: " + (ForceTrades ? "ON" : "OFF") + "\n";
   info = info + "╚═══════════════════════════════════════════════════════════════════╝";

   Comment(info);
}

//+------------------------------------------------------------------+
//| MAIN TICK FUNCTION                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   ChartSetString(ChartID(), CHART_COMMENT, "CONFLUENCE V1.0 - RATTANAC CHHORM");
   UpdateDisplay();

   CheckFridayClose();
   ApplyBreakeven();
   ApplyTrailingStop();

   if(ForceTrades)
   {
      static datetime lastForce = 0;
      if(TimeCurrent() - lastForce > 60)
      {
         lastForce = TimeCurrent();
         Print("FORCE MODE: Placing test trade");
         PlaceTrade();
      }
      return;
   }

   if(!CanTrade()) return;
   if(!IsTradingTime()) return;

   datetime barTime[1];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, barTime) != 1) return;

   if(barTime[0] != LastBarTime)
   {
      LastBarTime = barTime[0];
      PlaceTrade();
   }
}
