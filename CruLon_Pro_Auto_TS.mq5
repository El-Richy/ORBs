//+------------------------------------------------------------------+
//|         Richy's CruLon PRO Auto (Trailing Stop) Versión Institucional.mq5 |
//|                                            Sebastian Rivadeneira |
//|                                                        El__Richy |
//+------------------------------------------------------------------+
#property copyright "Sebastian Rivadeneira"
#property link "El__Richy"
#property version "3.00"

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| Inputs: Ajustes Base (mql5_ea_base)                              |
//+------------------------------------------------------------------+
sinput string sepBase = "--- Ajustes Institucionales ---";
input ulong InpMagicNumber = 777111; // Magic Number
input ulong InpSlippage = 3;         // Slippage Máximo (Puntos)
input double InpMaxSpread = 30.0;    // Spread Máximo Permitido (Puntos)
input int InpMaxRetries = 3;         // Intentos Máximos de Ejecución

//+------------------------------------------------------------------+
//| Inputs: Telegram (mql5_telegram)                                 |
//+------------------------------------------------------------------+
sinput string sepTele = "---- Telegram Bot Alertas ----";
input bool InpSendToTelegram = false;       // Activar Mensajes Telegram
input string InpBotToken = "TU_TOKEN_AQUI"; // Token del Bot (@BotFather)
input string InpChatID = "TU_ID_AQUI";      // Chat ID o Canal

//+------------------------------------------------------------------+
//| Inputs: Protecciones Macro (mql5_news_filter)                    |
//+------------------------------------------------------------------+
sinput string sepNews = "--- Protecciones Macro ---";
input bool InpUseWeekendClose = true; // Cerrar todo y borrar ordenes (Viernes)
input string InpFridayCloseTime = "21:00"; // Hora de cierre de Viernes (HH:MM)

//+------------------------------------------------------------------+
//| Inputs: Gestión de Riesgo (mql5_risk_management)                 |
//+------------------------------------------------------------------+
sinput string sepRisk = "--- Gestión de Riesgo ---";
input bool InpUseDynamicLot = true; // True = % de Balance, False = Capital fijo
input double InpRiskPercent = 0.5;  // Riesgo por Operación (%)
input double InpFixedCapital = 10000; // Capital base (Si Dinámico = false)
input double InpMaxDailyLoss = 1.0;   // Límite de Pérdida Diaria (%)

//+------------------------------------------------------------------+
//| Inputs: Horarios (mql5_time_sessions)                            |
//+------------------------------------------------------------------+
sinput string sepTime = "--- Horarios ---";
input string InpSessionStart = "07:00";   // Inicio Rango Sesión (HH:MM)
input string InpSessionEnd = "13:00";     // Fin Rango Sesión (HH:MM)
input string InpTakeValuesTime = "13:28"; // Lectura de Max/Min y ATR (HH:MM)
input string InpEntryStart = "13:29";     // Inicio ejecución de órdenes (HH:MM)
input string InpEntryEnd = "20:58";       // Fin ejecución de órdenes (HH:MM)

//+------------------------------------------------------------------+
//| Inputs: Estrategia y Pips                                        |
//+------------------------------------------------------------------+
sinput string sepPips = "-------- Estrategia ATR --------";
input ENUM_TIMEFRAMES InpTempATR = PERIOD_M30; // Temporalidad del ATR
input double InpMultiplierSL = 1.0;            // Multiplicador ATR para SL
input double InpMultiplierTP = 4.0;            // Multiplicador ATR para TP

//+------------------------------------------------------------------+
//| Inputs: Trade Management (mql5_trade_management)                 |
//+------------------------------------------------------------------+
sinput string sepManage = "----------- Trailing Stop -----------";
input double InpMultiplierITS = 2.0; // Multiplicador SL para iniciar T.S.
input double InpMultiplierDTS = 2.0; // Multiplicador SL distancia T.S.

//+------------------------------------------------------------------+
//| Variables Globales                                               |
//+------------------------------------------------------------------+
datetime lastBarTime = 0;
int currentDay = -1;
double dailyStartBalance = 0;

double maxPrice = 0;
double minPrice = 0;
double sessionSize = 0;
double currentATR = 0;
bool valuesTakenToday = false;
bool tradingDailyLock = false;

int atrHandle;

//+------------------------------------------------------------------+
//| Inicialización (OnInit)                                          |
//+------------------------------------------------------------------+
int OnInit() {
  trade.SetExpertMagicNumber(InpMagicNumber);
  trade.SetDeviationInPoints(InpSlippage);
  trade.SetTypeFilling(ORDER_FILLING_FOK);

  if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) {
    Print("Error: El AutoTrading está deshabilitado.");
    return (INIT_FAILED);
  }

  if (InpSessionStart == InpSessionEnd ||
      stringToMinutes(InpEntryStart) >= stringToMinutes(InpEntryEnd)) {
    Print("Error: Horarios configurados incorrectamente.");
    return (INIT_PARAMETERS_INCORRECT);
  }

  atrHandle = iATR(_Symbol, InpTempATR, 14);
  if (atrHandle == INVALID_HANDLE) {
    Print("Error al crear Handle ATR");
    return (INIT_FAILED);
  }

  dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Tick Principal (OnTick)                                          |
//+------------------------------------------------------------------+
void OnTick() {
  MqlDateTime dt;
  TimeCurrent(dt);

  if (dt.day != currentDay) {
    currentDay = dt.day;
    dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    tradingDailyLock = false;
    valuesTakenToday = false;
    maxPrice = 0;
    minPrice = 0;
    sessionSize = 0;
    currentATR = 0;
    if (!MQLInfoInteger(MQL_OPTIMIZATION))
      Print("Nuevo día iniciado. Balance: ", dailyStartBalance);
  }

  if (tradingDailyLock)
    return;

  if (CheckDailyLossLimit()) {
    tradingDailyLock = true;
    cancelarOrdenesPendientes();
    return;
  }

  if (dt.day_of_week == 5 && InpUseWeekendClose) {
    int closeMinutes = stringToMinutes(InpFridayCloseTime);
    int currentMinutes = dt.hour * 60 + dt.min;
    if (currentMinutes >= closeMinutes) {
      cancelarOrdenesPendientes();
      return;
    }
  }

  double spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);

  ManageActiveTrades_TS();

  string currentTimeStr = TimeToString(TimeCurrent(), TIME_MINUTES);

  if (currentTimeStr == InpTakeValuesTime && !valuesTakenToday) {
    CalculateMaxMinPrice();
    CalculateATR();
    valuesTakenToday = true;
  }

  if (valuesTakenToday && isNewBar(PERIOD_M1)) {
    if (IsBetween(InpEntryStart, InpEntryEnd) && spread <= InpMaxSpread) {
      TryPlacePendingOrders();
    }

    if (!IsBetween(InpEntryStart, InpEntryEnd)) {
      cancelarOrdenesPendientes();
    }
  }
}

//+------------------------------------------------------------------+
//| Lógica de la Estrategia (Rupturas)                               |
//+------------------------------------------------------------------+
void TryPlacePendingOrders() {
  double closePrice = iClose(_Symbol, PERIOD_CURRENT, 0);
  double slDistance = currentATR * InpMultiplierSL;
  double tpDistance = currentATR * InpMultiplierTP;

  if (slDistance <= 0)
    return;

  double lotSize = CalculateLotSize(slDistance);
  int buyStopCount = contarOrdenesPendientes(ORDER_TYPE_BUY_STOP);
  int sellStopCount = contarOrdenesPendientes(ORDER_TYPE_SELL_STOP);

  if (closePrice < maxPrice && closePrice > minPrice) {
    if (!existeOrdenEnPrecio(maxPrice, ORDER_TYPE_BUY_STOP) &&
        buyStopCount < 2 && !hayPosicion(_Symbol)) {
      double price = maxPrice;
      double sl = NormalizeDouble(price - slDistance, _Digits);
      double tp = NormalizeDouble(price + tpDistance, _Digits);
      ExecutePending(ORDER_TYPE_BUY_STOP, lotSize, price, sl, tp,
                     "CruLon BuyStop High");
    }
  }

  if (closePrice > maxPrice && closePrice < maxPrice + sessionSize) {
    if (!existeOrdenEnPrecio(maxPrice, ORDER_TYPE_SELL_STOP) &&
        sellStopCount < 2 && !hayPosicion(_Symbol)) {
      double price = maxPrice;
      double sl = NormalizeDouble(price + slDistance, _Digits);
      double tp = NormalizeDouble(price - tpDistance, _Digits);
      ExecutePending(ORDER_TYPE_SELL_STOP, lotSize, price, sl, tp,
                     "CruLon SellStop High");
    }
  }

  if (closePrice < minPrice && closePrice > minPrice - sessionSize) {
    if (!existeOrdenEnPrecio(minPrice, ORDER_TYPE_BUY_STOP) &&
        buyStopCount < 2 && !hayPosicion(_Symbol)) {
      double price = minPrice;
      double sl = NormalizeDouble(price - slDistance, _Digits);
      double tp = NormalizeDouble(price + tpDistance, _Digits);
      ExecutePending(ORDER_TYPE_BUY_STOP, lotSize, price, sl, tp,
                     "CruLon BuyStop Low");
    }
  }

  if (closePrice > minPrice && closePrice < maxPrice) {
    if (!existeOrdenEnPrecio(minPrice, ORDER_TYPE_SELL_STOP) &&
        sellStopCount < 2 && !hayPosicion(_Symbol)) {
      double price = minPrice;
      double sl = NormalizeDouble(price + slDistance, _Digits);
      double tp = NormalizeDouble(price - tpDistance, _Digits);
      ExecutePending(ORDER_TYPE_SELL_STOP, lotSize, price, sl, tp,
                     "CruLon SellStop Low");
    }
  }
}

//+------------------------------------------------------------------+
//| Helpers Estratégicos                                             |
//+------------------------------------------------------------------+
void CalculateMaxMinPrice() {
  datetime startTime = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) +
                                    " " + InpSessionStart);
  datetime endTime = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " " +
                                  InpSessionEnd);
  if (startTime >= endTime) {
    datetime t = startTime;
    startTime = endTime;
    endTime = t;
  }

  ENUM_TIMEFRAMES tf = PERIOD_M15;
  int startIdx = iBarShift(_Symbol, tf, startTime, false);
  int endIdx = iBarShift(_Symbol, tf, endTime, false);
  if (startIdx > endIdx) {
    int t = startIdx;
    startIdx = endIdx;
    endIdx = t;
  }

  startIdx = MathMax(0, startIdx);
  endIdx = MathMin(iBars(_Symbol, tf) - 1, endIdx);

  maxPrice = iHigh(_Symbol, tf, startIdx);
  minPrice = iLow(_Symbol, tf, startIdx);
  for (int i = startIdx; i <= endIdx; i++) {
    maxPrice = MathMax(maxPrice, iHigh(_Symbol, tf, i));
    minPrice = MathMin(minPrice, iLow(_Symbol, tf, i));
  }
  if (maxPrice < minPrice) {
    double t = maxPrice;
    maxPrice = minPrice;
    minPrice = t;
  }
  sessionSize = maxPrice - minPrice;

  if (!MQLInfoInteger(MQL_OPTIMIZATION))
    Print("Rango de Sesión Capturado. Max: ", maxPrice, " Min: ", minPrice);
}

void CalculateATR() {
  double atrValues[];
  ArraySetAsSeries(atrValues, true);
  CopyBuffer(atrHandle, 0, 0, 1, atrValues);
  currentATR = atrValues[0];
  if (!MQLInfoInteger(MQL_OPTIMIZATION))
    Print("ATR Capturado: ", currentATR);
}

//+------------------------------------------------------------------+
//| Risk Management Skill                                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice) {
  double riskAmount;
  if (InpUseDynamicLot) {
    riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
  } else {
    riskAmount = InpFixedCapital * (InpRiskPercent / 100.0);
  }

  double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
  double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
  if (tickValue == 0 || tickSize == 0 || slDistancePrice == 0)
    return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

  double slPoints = slDistancePrice / tickSize;
  double lotSize = riskAmount / (slPoints * tickValue);

  double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

  lotSize = MathRound(lotSize / lotStep) * lotStep;
  if (lotSize < minLot)
    lotSize = minLot;
  if (lotSize > maxLot)
    lotSize = maxLot;

  return NormalizeDouble(lotSize, 2);
}

bool CheckDailyLossLimit() {
  double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
  if (currentEquity < dailyStartBalance) {
    double lossPercent =
        ((dailyStartBalance - currentEquity) / dailyStartBalance) * 100.0;
    if (lossPercent >= InpMaxDailyLoss) {
      if (!MQLInfoInteger(MQL_OPTIMIZATION))
        Print("¡ALERTA! Límite de pérdida diaria alcanzado.");
      return true;
    }
  }
  return false;
}

//+------------------------------------------------------------------+
//| Execution PRO Skill                                              |
//+------------------------------------------------------------------+
bool ExecutePending(ENUM_ORDER_TYPE orderType, double volume, double price,
                    double sl, double tp, string comment = "") {
  int attempts = 0;
  bool success = false;

  while (attempts < InpMaxRetries && !success) {
    if (orderType == ORDER_TYPE_BUY_STOP) {
      success = trade.BuyStop(volume, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0,
                              comment);
    } else if (orderType == ORDER_TYPE_SELL_STOP) {
      success = trade.SellStop(volume, price, _Symbol, sl, tp, ORDER_TIME_GTC,
                               0, comment);
    }

    if (success) {
      if (!MQLInfoInteger(MQL_OPTIMIZATION))
        Print("Orden colocada en intento ", attempts + 1);
      SendMessageToTelegram(
          "🟢 Nueva Orden Pendiente: " + EnumToString(orderType) + " en " +
          _Symbol + " | Precio: " + DoubleToString(price, _Digits));
      return true;
    } else {
      uint errorCode = trade.ResultRetcode();
      if (errorCode == TRADE_RETCODE_NO_MONEY ||
          errorCode == TRADE_RETCODE_TRADE_DISABLED ||
          errorCode == TRADE_RETCODE_INVALID_STOPS)
        break;
      attempts++;
      Sleep(250);
      SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }
  }
  return false;
}

//+------------------------------------------------------------------+
//| Trade Management Skill (Trailing Stop Optimizado)                |
//+------------------------------------------------------------------+
void ManageActiveTrades_TS() {
  for (int i = PositionsTotal() - 1; i >= 0; i--) {
    string symbol = PositionGetSymbol(i);
    if (symbol != _Symbol ||
        PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      continue;

    ulong ticket = PositionGetInteger(POSITION_TICKET);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    long posType = PositionGetInteger(POSITION_TYPE);

    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

    double riskDistance = MathAbs(openPrice - sl);
    if (riskDistance <= 0)
      riskDistance = currentATR * InpMultiplierSL;

    double tsStartDistance = riskDistance * InpMultiplierITS;
    double tsTrailingStep = riskDistance * InpMultiplierDTS;

    if (posType == POSITION_TYPE_BUY) {
      if ((bid - openPrice) >= tsStartDistance) {
        double newSL = NormalizeDouble(bid - tsTrailingStep, _Digits);
        if (newSL > sl && newSL > openPrice) {
          trade.PositionModify(ticket, newSL, tp);
        }
      }
    } else if (posType == POSITION_TYPE_SELL) {
      if ((openPrice - ask) >= tsStartDistance) {
        double newSL = NormalizeDouble(ask + tsTrailingStep, _Digits);
        if (newSL < sl || sl == 0) {
          trade.PositionModify(ticket, newSL, tp);
        }
      }
    }
  }
}

//+------------------------------------------------------------------+
//| Helper de Utilidades y Cancelaciones                             |
//+------------------------------------------------------------------+
int stringToMinutes(string timeStr) {
  return StringToInteger(StringSubstr(timeStr, 0, 2)) * 60 +
         StringToInteger(StringSubstr(timeStr, 3, 2));
}

bool IsBetween(string start, string end) {
  int currentMins = stringToMinutes(TimeToString(TimeCurrent(), TIME_MINUTES));
  int startMins = stringToMinutes(start);
  int endMins = stringToMinutes(end);
  if (startMins < endMins) {
    return (currentMins >= startMins && currentMins <= endMins);
  } else {
    return (currentMins >= startMins || currentMins <= endMins);
  }
}

void cancelarOrdenesPendientes() {
  int total = OrdersTotal();
  for (int i = total - 1; i >= 0; i--) {
    ulong t = OrderGetTicket(i);
    if (OrderSelect(t)) {
      if (OrderGetString(ORDER_SYMBOL) == _Symbol &&
          OrderGetInteger(ORDER_MAGIC) == InpMagicNumber) {
        trade.OrderDelete(t);
      }
    }
  }
}

bool existeOrdenEnPrecio(double precio, int tipoOrden) {
  for (int i = 0; i < OrdersTotal(); i++) {
    ulong t = OrderGetTicket(i);
    if (OrderSelect(t)) {
      if (OrderGetString(ORDER_SYMBOL) == _Symbol &&
          OrderGetInteger(ORDER_TYPE) == tipoOrden &&
          NormalizeDouble(OrderGetDouble(ORDER_PRICE_OPEN), _Digits) ==
              NormalizeDouble(precio, _Digits) &&
          OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
        return true;
    }
  }
  return false;
}

int contarOrdenesPendientes(int orderType) {
  int count = 0;
  for (int i = 0; i < OrdersTotal(); i++) {
    ulong t = OrderGetTicket(i);
    if (OrderSelect(t)) {
      if (OrderGetString(ORDER_SYMBOL) == _Symbol &&
          OrderGetInteger(ORDER_TYPE) == orderType &&
          OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
        count++;
    }
  }
  return count;
}

bool hayPosicion(string symbol) {
  for (int i = 0; i < PositionsTotal(); i++) {
    if (PositionGetSymbol(i) == symbol &&
        PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      return true;
  }
  return false;
}

bool isNewBar(ENUM_TIMEFRAMES timeframe) {
  datetime currentTime = iTime(_Symbol, timeframe, 0);
  if (currentTime != lastBarTime) {
    lastBarTime = currentTime;
    return true;
  }
  return false;
}

//+------------------------------------------------------------------+
//| Telegram Webhook (mql5_telegram)                                 |
//+------------------------------------------------------------------+
bool SendMessageToTelegram(string messageText) {
  if (!InpSendToTelegram)
    return true;
  if (InpBotToken == "TU_TOKEN_AQUI" || InpBotToken == "")
    return false;

  string url = "https://api.telegram.org/bot" + InpBotToken + "/sendMessage";
  string payload =
      "chat_id=" + InpChatID + "&text=" + messageText + "&parse_mode=HTML";

  char postData[];
  char resultData[];
  string resultHeaders;
  StringToCharArray(payload, postData, 0, StringLen(payload), CP_UTF8);

  int res = WebRequest("POST", url,
                       "Content-Type: application/x-www-form-urlencoded\r\n",
                       5000, postData, resultData, resultHeaders);
  return (res == 200);
}

//+------------------------------------------------------------------+
//| Estrategia de Optimización (mql5_tester_optimization)            |
//+------------------------------------------------------------------+
double OnTester() {
  double netProfit = TesterStatistics(STAT_PROFIT);
  double maxDrawdownPercent = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
  int totalTrades = (int)TesterStatistics(STAT_TRADES);
  double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);
  double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);

  if (totalTrades < 30)
    return -100.0;
  if (maxDrawdownPercent > 20.0)
    return -200.0;
  if (profitFactor < 1.1)
    return -300.0;

  double fitnessScore = 0.0;
  if (sharpeRatio > 0 && netProfit > 0) {
    fitnessScore = (sharpeRatio * 100) + (profitFactor * 50);
  }
  return fitnessScore;
}
