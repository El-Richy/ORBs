//+------------------------------------------------------------------+
//|                        ORB5min_EA.mq5                           |
//|          Opening Range Breakout - 5 Minutes (Versión Mejorada)  |
//|          Compatible: NAS100, US500, US30, JPN225                 |
//+------------------------------------------------------------------+
#property copyright "ORB Strategy EA"
#property version   "2.03"
#property strict

#include <Trade\Trade.mqh>

//=======================================================
// ENUMS
//=======================================================
enum TRAILING_MODE
  {
   TRAILING_R_FIJO,    // Trailing fijo (0.5R)
   TRAILING_ATR        // Trailing dinámico basado en ATR
  };

//=======================================================
// INPUTS CONFIGURABLES
//=======================================================

input string   separador1  = "----------- Tipo de riesgo -----------";       // ----------- Separador -----------
input bool     RiesgoDinamico   = true;                                       // true=dinámico, false=lote fijo
input double   FixedLot         = 0.10;                                       // Lote fijo (solo si RiesgoDinamico = false)
//--------------------------------------------------------------------
input string   separador2  = "----------- Horario -----------";               // ----------- Separador -----------
input string   StartOps         = "16:40";                                    // Hora inicio de entradas
input string   EndOps           = "17:30";                                    // Hora fin de entradas
input string   CloseOps         = "22:50";                                    // Hora cierre forzoso
//--------------------------------------------------------------------
input string   separador3  = "----------- Sesión ORB -----------";            // ----------- Separador -----------
input string   StartSession     = "16:20";                                    // Hora inicio del rango
input string   EndSession       = "16:40";                                    // Hora fin del rango
//--------------------------------------------------------------------
input string   separador4  = "----------- Gestión de riesgo -----------";     // ----------- Separador -----------
input double   MultiplierTP     = 3.0;                                        // Multiplicador RR para TP
input double   MultiplierSL     = 1.0;                                        // Multiplicador SL (1.0 = extremo opuesto del rango)
input double   RiskPercent      = 1.0;                                        // % de balance en riesgo por trade
input int      MaxTradesPerDay  = 3;                                          // Máx operaciones por día
input double   SL_Buffer_Points = 3.0;                                        // Buffer adicional en points para SL
input bool     UseSpreadFilter  = true;                                       // Filtro de spread máximo
input double   MaxSpreadPoints  = 5.0;                                        // Spread máximo permitido (en points)
//--------------------------------------------------------------------
input string   separador5  = "----------- Indicadores -----------";           // ----------- Separador -----------
input double   ATR_MinFactor    = 0.20;                                       // Factor mínimo ATR para validar rango
input int      ATR_Period       = 14;                                         // Período ATR
input int      EMA_Fast_Period  = 20;                                         // Período EMA rápida
input int      EMA_Slow_Period  = 50;                                         // Período EMA lenta
input int      Volume_MA_Period = 10;                                         // Período SMA de volumen
//--------------------------------------------------------------------
input string   separador5b = "------- Activar / Desactivar filtros -------"; // ----------- Separador -----------
input bool     UseFilterATR     = true;                                       // Filtro ATR: ORB_SIZE >= ATR * factor
input bool     UseFilterVWAP    = true;                                       // Filtro VWAP: precio del lado correcto
input bool     UseFilterEMA     = true;                                       // Filtro EMA: cruce rápida/lenta
input bool     UseFilterVela    = true;                                       // Filtro C3: vela alcista/bajista
input bool     UseFilterVolumen = true;                                       // Filtro C9: volumen > media
input bool     UseFilterC2      = true;                                       // Filtro C2: cierre previo dentro del rango
//--------------------------------------------------------------------
input string   separador5c = "------- Filtro de noticias -------";           // ----------- Separador -----------
input bool     UseNewsFilter    = true;                                       // Evitar entradas cerca de noticias
input int      NewsAvoidMins    = 30;                                         // Minutos a evitar antes/después de noticia
input string   NewsTimes        = "08:30,14:00,20:30";                       // Horarios de noticias (HH:MM separados por coma)
//--------------------------------------------------------------------
input string   separador5d = "------- Filtro días de semana -------";        // ----------- Separador -----------
input bool     TradeMonday      = true;                                       // Operar los lunes
input bool     TradeTuesday     = true;                                       // Operar los martes
input bool     TradeWednesday   = true;                                       // Operar los miércoles
input bool     TradeThursday    = true;                                       // Operar los jueves
input bool     TradeFriday      = true;                                       // Operar los viernes
//--------------------------------------------------------------------
input string   separador6  = "----------- Gestión de operación -----------";  // ----------- Separador -----------
input bool     UseBreakEven         = true;                                   // Activar Break-Even
input bool     UseTrailing          = true;                                   // Activar Trailing Stop
input TRAILING_MODE TrailingMode    = TRAILING_R_FIJO;                        // Modo trailing: fijo (0.5R) o ATR dinámico
input double   TrailingATRFactor    = 1.0;                                    // Factor ATR para trailing (solo si modo ATR)
input bool     UseDrawdownProtection= true;                                   // Protección de drawdown máximo
input double   MaxDDPercent         = 20.0;                                   // DD máximo permitido (% del balance)
input bool     UseOrbLines          = true;                                   // Dibujar líneas ORB_HIGH/LOW en gráfico
//--------------------------------------------------------------------
input string   separador7  = "----------- Identificación -----------";        // ----------- Separador -----------
input int      MagicNumber          = 100001;                                 // Magic Number del EA

//=======================================================
// VARIABLES GLOBALES
//=======================================================

CTrade trade;

// Handles de indicadores
int handleATR    = INVALID_HANDLE;  // ATR en D1 (filtro de rango)
int handleATR_TF = INVALID_HANDLE;  // ATR en _Period (trailing dinámico)
int handleEMAF   = INVALID_HANDLE;
int handleEMAS   = INVALID_HANDLE;

// Estado del ORB
double   ORB_HIGH     = 0.0;
double   ORB_LOW      = 0.0;
double   ORB_SIZE     = 0.0;
bool     rangeFormed  = false;

// Estado de sesión
bool     isBreakout   = false;
int      tradesToday  = 0;
datetime lastDay      = 0;

// VWAP acumuladores
double   vwap_cumPV   = 0.0;
double   vwap_cumVol  = 0.0;
double   currentVWAP  = 0.0;
datetime vwapLastBar  = 0;

// Gestión activa de posición
double   entryPrice    = 0.0;
double   slDistance    = 0.0;
bool     beActivated   = false;
bool     trailActivated= false;

// Protección de drawdown
bool     eaDisabled    = false;

//=======================================================
// NOMBRES DE OBJETOS PARA LÍNEAS ORB
//=======================================================
#define ORB_HIGH_LINE  "ORB_HIGH_LINE"
#define ORB_LOW_LINE   "ORB_LOW_LINE"

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!SymbolSelect(_Symbol, true))
     {
      Print("ERROR: No se pudo seleccionar el símbolo ", _Symbol);
      return INIT_FAILED;
     }

   handleATR    = iATR(_Symbol, PERIOD_D1, ATR_Period);
   handleATR_TF = iATR(_Symbol, _Period,   ATR_Period);
   handleEMAF   = iMA(_Symbol,  _Period, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMAS   = iMA(_Symbol,  _Period, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(handleATR    == INVALID_HANDLE || handleATR_TF == INVALID_HANDLE ||
      handleEMAF   == INVALID_HANDLE || handleEMAS   == INVALID_HANDLE)
     {
      Print("ERROR: Fallo al crear handles de indicadores. Código: ", GetLastError());
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print("EA ORB v2.03 iniciado en ", _Symbol, " TF=", EnumToString(_Period));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handleATR    != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleATR_TF != INVALID_HANDLE) IndicatorRelease(handleATR_TF);
   if(handleEMAF   != INVALID_HANDLE) IndicatorRelease(handleEMAF);
   if(handleEMAS   != INVALID_HANDLE) IndicatorRelease(handleEMAS);
   DeleteORBLines();
  }

//+------------------------------------------------------------------+
//| Dibuja líneas horizontales de ORB_HIGH y ORB_LOW en el gráfico  |
//+------------------------------------------------------------------+
void DrawORBLines()
  {
   if(!UseOrbLines) return;

   // Línea ORB_HIGH (azul)
   if(ObjectFind(0, ORB_HIGH_LINE) >= 0)
      ObjectDelete(0, ORB_HIGH_LINE);
   ObjectCreate(0, ORB_HIGH_LINE, OBJ_HLINE, 0, 0, ORB_HIGH);
   ObjectSetInteger(0, ORB_HIGH_LINE, OBJPROP_COLOR,  clrDodgerBlue);
   ObjectSetInteger(0, ORB_HIGH_LINE, OBJPROP_STYLE,  STYLE_DASH);
   ObjectSetInteger(0, ORB_HIGH_LINE, OBJPROP_WIDTH,  1);
   ObjectSetString(0,  ORB_HIGH_LINE, OBJPROP_TOOLTIP, "ORB HIGH: " + DoubleToString(ORB_HIGH, _Digits));

   // Línea ORB_LOW (rojo)
   if(ObjectFind(0, ORB_LOW_LINE) >= 0)
      ObjectDelete(0, ORB_LOW_LINE);
   ObjectCreate(0, ORB_LOW_LINE, OBJ_HLINE, 0, 0, ORB_LOW);
   ObjectSetInteger(0, ORB_LOW_LINE, OBJPROP_COLOR,  clrTomato);
   ObjectSetInteger(0, ORB_LOW_LINE, OBJPROP_STYLE,  STYLE_DASH);
   ObjectSetInteger(0, ORB_LOW_LINE, OBJPROP_WIDTH,  1);
   ObjectSetString(0,  ORB_LOW_LINE, OBJPROP_TOOLTIP, "ORB LOW: " + DoubleToString(ORB_LOW, _Digits));

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Elimina las líneas ORB del gráfico                               |
//+------------------------------------------------------------------+
void DeleteORBLines()
  {
   if(ObjectFind(0, ORB_HIGH_LINE) >= 0) ObjectDelete(0, ORB_HIGH_LINE);
   if(ObjectFind(0, ORB_LOW_LINE)  >= 0) ObjectDelete(0, ORB_LOW_LINE);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Calcula SMA del tick volume de las últimas N velas (_Period)     |
//+------------------------------------------------------------------+
double GetVolumeMA(int period)
  {
   double sum = 0.0;
   for(int i = 0; i < period; i++)
      sum += (double)iTickVolume(_Symbol, _Period, i);
   return (period > 0) ? sum / period : 0.0;
  }

//+------------------------------------------------------------------+
//| Convierte string "HH:MM" a segundos desde medianoche             |
//+------------------------------------------------------------------+
int TimeStringToSeconds(const string timeStr)
  {
   int h = (int)StringToInteger(StringSubstr(timeStr, 0, 2));
   int m = (int)StringToInteger(StringSubstr(timeStr, 3, 2));
   return h * 3600 + m * 60;
  }

//+------------------------------------------------------------------+
//| Retorna segundos desde medianoche del tiempo dado                |
//+------------------------------------------------------------------+
int TimeToSeconds(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 3600 + dt.min * 60 + dt.sec;
  }

//+------------------------------------------------------------------+
//| Retorna solo la fecha (inicio del día) del tiempo dado           |
//+------------------------------------------------------------------+
datetime DateOnly(datetime t)
  {
   return (datetime)((t / 86400) * 86400);
  }

//+------------------------------------------------------------------+
//| Filtro de noticias: devuelve true si hay que evitar operar       |
//| Parsea NewsTimes (e.g. "08:30,14:00,20:30") y chequea proximidad |
//+------------------------------------------------------------------+
bool IsNewsTime()
  {
   if(!UseNewsFilter) return false;

   int nowSec     = TimeToSeconds(TimeCurrent());
   int avoidSecs  = NewsAvoidMins * 60;

   string times[];
   int count = StringSplit(NewsTimes, ',', times);

   for(int i = 0; i < count; i++)
     {
      string t = times[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      if(StringLen(t) < 5) continue;

      int newsSec = TimeStringToSeconds(t);
      if(MathAbs(nowSec - newsSec) <= avoidSecs)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Filtro de día de semana                                          |
//+------------------------------------------------------------------+
bool IsTradingDay()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week)
     {
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      default: return false; // Sábado (6) y domingo (0)
     }
  }

//+------------------------------------------------------------------+
//| Verifica si hay una posición abierta con nuestro MagicNumber     |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Obtiene el ticket de la posición abierta con nuestro MagicNumber |
//+------------------------------------------------------------------+
ulong GetOpenPositionTicket()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return (ulong)PositionGetInteger(POSITION_TICKET);
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| PASO 8 — Reset diario de variables                               |
//+------------------------------------------------------------------+
void DailyReset()
  {
   ORB_HIGH       = 0.0;
   ORB_LOW        = 0.0;
   ORB_SIZE       = 0.0;
   rangeFormed    = false;
   isBreakout     = false;
   tradesToday    = 0;
   vwap_cumPV     = 0.0;
   vwap_cumVol    = 0.0;
   currentVWAP    = 0.0;
   vwapLastBar    = 0;
   entryPrice     = 0.0;
   slDistance     = 0.0;
   beActivated    = false;
   trailActivated = false;
   eaDisabled     = false;   // Reset protección DD al inicio del día
   DeleteORBLines();
   Print("=== RESET DIARIO === ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
  }

//+------------------------------------------------------------------+
//| Actualiza el VWAP intradío acumulando desde inicio de sesión     |
//+------------------------------------------------------------------+
void UpdateVWAP()
  {
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == vwapLastBar) return;

   MqlDateTime dtBar, dtNow;
   TimeToStruct(barTime,         dtBar);
   TimeToStruct(TimeCurrent(),   dtNow);

   if(dtBar.day == dtNow.day && dtBar.mon == dtNow.mon && dtBar.year == dtNow.year)
     {
      double hi  = iHigh(_Symbol,  _Period, 0);
      double lo  = iLow(_Symbol,   _Period, 0);
      double cl  = iClose(_Symbol, _Period, 0);
      long   vol = iTickVolume(_Symbol, _Period, 0);

      if(vol > 0)
        {
         double typicalPrice = (hi + lo + cl) / 3.0;
         vwap_cumPV  += typicalPrice * (double)vol;
         vwap_cumVol += (double)vol;
        }
     }

   if(vwap_cumVol > 0.0)
      currentVWAP = vwap_cumPV / vwap_cumVol;

   vwapLastBar = barTime;
  }

//+------------------------------------------------------------------+
//| PASO 1 — Formación del rango ORB con velas de la sesión         |
//| Compatible con cualquier temporalidad gracias a _Period          |
//+------------------------------------------------------------------+
void TryFormRange()
  {
   if(rangeFormed) return;

   int sessionStartSec = TimeStringToSeconds(StartSession);
   int sessionEndSec   = TimeStringToSeconds(EndSession);
   int nowSec          = TimeToSeconds(TimeCurrent());

   if(nowSec < sessionEndSec) return;

   double hi[]; double lo[];
   ArrayResize(hi, 0); ArrayResize(lo, 0);
   int count = 0;

   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);

   // Buscar hasta 200 barras atrás (cubre M1 con ventanas amplias)
   for(int i = 200; i >= 0; i--)
     {
      datetime    bTime = iTime(_Symbol, _Period, i);
      int         bSec  = TimeToSeconds(bTime);
      MqlDateTime dtBar;
      TimeToStruct(bTime, dtBar);

      if(dtBar.day  != dtNow.day  ||
         dtBar.mon  != dtNow.mon  ||
         dtBar.year != dtNow.year) continue;

      if(bSec >= sessionStartSec && bSec < sessionEndSec)
        {
         ArrayResize(hi, count + 1);
         ArrayResize(lo, count + 1);
         hi[count] = iHigh(_Symbol, _Period, i);
         lo[count] = iLow(_Symbol,  _Period, i);
         count++;
        }
     }

   if(count < 1)
     {
      Print("WARNING TryFormRange: No se encontraron velas en la sesión.");
      return;
     }

   ORB_HIGH = hi[0];
   ORB_LOW  = lo[0];
   for(int j = 1; j < count; j++)
     {
      if(hi[j] > ORB_HIGH) ORB_HIGH = hi[j];
      if(lo[j] < ORB_LOW)  ORB_LOW  = lo[j];
     }
   ORB_SIZE    = ORB_HIGH - ORB_LOW;
   rangeFormed = true;

   DrawORBLines();

   Print("PASO 1 — ORB formado (", count, " velas): HIGH=", DoubleToString(ORB_HIGH, _Digits),
         " LOW=", DoubleToString(ORB_LOW, _Digits),
         " SIZE=", DoubleToString(ORB_SIZE, _Digits));
  }

//+------------------------------------------------------------------+
//| Calcula el tamaño de lote                                        |
//+------------------------------------------------------------------+
double CalcLotSize(double entry, double sl)
  {
   if(!RiesgoDinamico) return NormalizeLot(FixedLot);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);
   double distSL    = MathAbs(entry - sl);

   if(distSL <= 0.0) { Print("ERROR CalcLotSize: distancia SL = 0"); return 0.0; }

   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0.0 || tickVal <= 0.0)
     {
      Print("ERROR CalcLotSize: tick_value=", tickVal, " tick_size=", tickSize);
      return 0.0;
     }

   double lot = riskMoney / ((distSL / tickSize) * tickVal);
   return NormalizeLot(lot);
  }

//+------------------------------------------------------------------+
//| Normaliza el lote según los límites del símbolo                  |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepLot <= 0.0) stepLot = 0.01;
   lot = MathFloor(lot / stepLot) * stepLot;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
//| Verificación de margen disponible                                |
//+------------------------------------------------------------------+
bool CheckMarginOK(ENUM_ORDER_TYPE orderType, double lot)
  {
   double price = 0.0;
   if(orderType == ORDER_TYPE_BUY)
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double margin = 0.0;
   if(!OrderCalcMargin(orderType, _Symbol, lot, price, margin))
     {
      Print("ERROR: No se pudo calcular margen. Código: ", GetLastError());
      return false;
     }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > freeMargin * 0.95)
     {
      Print("ADVERTENCIA: Margen insuficiente. Requerido=", margin, " Libre=", freeMargin);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Protección de drawdown: cierra todo y desactiva el EA            |
//+------------------------------------------------------------------+
void CheckDrawdownProtection()
  {
   if(!UseDrawdownProtection || eaDisabled) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(balance <= 0.0) return;

   double ddPercent = (balance - equity) / balance * 100.0;

   if(ddPercent >= MaxDDPercent)
     {
      Print("⚠️ PROTECCIÓN DD — DD actual=", DoubleToString(ddPercent, 2),
            "% >= límite=", MaxDDPercent, "%. Cerrando posiciones y desactivando EA.");

      // Cerrar posición abierta con nuestro magic
      ulong ticket = GetOpenPositionTicket();
      if(ticket > 0)
        {
         if(!trade.PositionClose(ticket))
            Print("ERROR cerrando posición en DD protection: ", GetLastError());
        }

      eaDisabled = true;
     }
  }

//+------------------------------------------------------------------+
//| PASO 6 — Gestión activa: Break-Even y Trailing Stop              |
//+------------------------------------------------------------------+
void ManageOpenPosition()
  {
   ulong ticket = GetOpenPositionTicket();
   if(ticket == 0) return;
   if(!PositionSelectByTicket(ticket)) return;

   ENUM_POSITION_TYPE posType   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double             currentSL = PositionGetDouble(POSITION_SL);
   double             currentTP = PositionGetDouble(POSITION_TP);
   double             spread    = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;

   if(slDistance <= 0.0) return;
   double R = slDistance;

   // Obtener ATR del timeframe actual para trailing dinámico
   double atrTFBuf[1];
   double atrTF = R * 0.5; // Fallback: fijo si no hay datos
   if(CopyBuffer(handleATR_TF, 0, 0, 1, atrTFBuf) >= 1)
      atrTF = atrTFBuf[0];

   if(posType == POSITION_TYPE_BUY)
     {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Break-Even: precio >= Entry + 1R
      if(UseBreakEven && !beActivated && price >= entryPrice + R)
        {
         double newSL = NormalizeDouble(entryPrice + spread, _Digits);
         if(newSL > currentSL)
           {
            if(trade.PositionModify(ticket, newSL, currentTP))
              { beActivated = true; Print("BREAK-EVEN BUY. SL=", DoubleToString(newSL, _Digits)); }
            else
               Print("ERROR BE BUY: ", GetLastError());
           }
        }

      // Trailing Stop
      if(UseTrailing && price >= entryPrice + 1.5 * R)
        {
         double trailDist = (TrailingMode == TRAILING_ATR) ? atrTF * TrailingATRFactor : 0.5 * R;
         double newSL     = NormalizeDouble(price - trailDist, _Digits);
         if(newSL > currentSL)
           {
            if(trade.PositionModify(ticket, newSL, currentTP))
               trailActivated = true;
            else
               Print("ERROR Trailing BUY: ", GetLastError());
           }
        }
     }
   else if(posType == POSITION_TYPE_SELL)
     {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Break-Even: precio <= Entry - 1R
      if(UseBreakEven && !beActivated && price <= entryPrice - R)
        {
         double newSL = NormalizeDouble(entryPrice - spread, _Digits);
         if(currentSL == 0.0 || newSL < currentSL)
           {
            if(trade.PositionModify(ticket, newSL, currentTP))
              { beActivated = true; Print("BREAK-EVEN SELL. SL=", DoubleToString(newSL, _Digits)); }
            else
               Print("ERROR BE SELL: ", GetLastError());
           }
        }

      // Trailing Stop
      if(UseTrailing && price <= entryPrice - 1.5 * R)
        {
         double trailDist = (TrailingMode == TRAILING_ATR) ? atrTF * TrailingATRFactor : 0.5 * R;
         double newSL     = NormalizeDouble(price + trailDist, _Digits);
         if(currentSL == 0.0 || newSL < currentSL)
           {
            if(trade.PositionModify(ticket, newSL, currentTP))
               trailActivated = true;
            else
               Print("ERROR Trailing SELL: ", GetLastError());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| PASO 7 — Cierre forzoso por tiempo                               |
//+------------------------------------------------------------------+
void CheckForceClose()
  {
   int closeTimeSec = TimeStringToSeconds(CloseOps);
   int nowSec       = TimeToSeconds(TimeCurrent());

   if(nowSec >= closeTimeSec && HasOpenPosition())
     {
      ulong ticket = GetOpenPositionTicket();
      if(ticket > 0)
        {
         if(trade.PositionClose(ticket))
            Print("PASO 7 — Posición cerrada por tiempo: ", TimeToString(TimeCurrent(), TIME_MINUTES));
         else
            Print("ERROR cierre por tiempo: ", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| OnTick — función principal                                       |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();

   //--- PASO 8: Reset diario
   datetime today = DateOnly(now);
   if(today != lastDay)
     {
      DailyReset();
      lastDay = today;
     }

   //--- Protección de drawdown (chequeo continuo)
   CheckDrawdownProtection();
   if(eaDisabled) return;

   //--- Actualizar VWAP
   UpdateVWAP();

   //--- PASO 7: Cierre forzoso por tiempo
   CheckForceClose();

   //--- PASO 6: Gestión activa de posición
   if(HasOpenPosition())
     {
      ManageOpenPosition();
      if(MaxTradesPerDay <= 1) return;
     }

   //--- Filtro: día de semana
   if(!IsTradingDay()) return;

   //--- PASO 1: Formar el rango ORB
   TryFormRange();
   if(!rangeFormed) return;

   //--- Leer buffers de indicadores
   double atrBuf[1], emaFBuf[2], emaSBuf[2];
   if(CopyBuffer(handleATR,  0, 0, 1, atrBuf)  < 1) return;
   if(CopyBuffer(handleEMAF, 0, 0, 2, emaFBuf) < 2) return;
   if(CopyBuffer(handleEMAS, 0, 0, 2, emaSBuf) < 2) return;

   double atrD1   = atrBuf[0];
   double emaFast = emaFBuf[0];
   double emaSlow = emaSBuf[0];

   //--- Volumen
   double volAvg = GetVolumeMA(Volume_MA_Period);
   long   volNow = iTickVolume(_Symbol, _Period, 0);

   //--- PASO 2: Filtro de volatilidad mínima (ATR)
   if(UseFilterATR && ORB_SIZE < atrD1 * ATR_MinFactor) return;

   //--- Variables de precio de la vela actual
   double closeNow  = iClose(_Symbol, _Period, 0);
   double closePrev = iClose(_Symbol, _Period, 1);
   double openNow   = iOpen(_Symbol,  _Period, 0);

   //--- PASO 3: Filtros de sesgo (BIAS)
   bool vwapAlcista = UseFilterVWAP ? (closeNow > currentVWAP) : true;
   bool vwapBajista = UseFilterVWAP ? (closeNow < currentVWAP) : true;
   bool emaAlcista  = UseFilterEMA  ? (emaFast  > emaSlow)     : true;
   bool emaBajista  = UseFilterEMA  ? (emaFast  < emaSlow)     : true;

   bool biasAlcista = vwapAlcista && emaAlcista;
   bool biasBajista = vwapBajista && emaBajista;

   if(!biasAlcista && !biasBajista) return;

   //--- Verificar horario de entrada
   int nowSec      = TimeToSeconds(now);
   int startOpsSec = TimeStringToSeconds(StartOps);
   int endOpsSec   = TimeStringToSeconds(EndOps);
   if(nowSec < startOpsSec || nowSec > endOpsSec) return;

   //--- Filtro de spread
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(UseSpreadFilter && (ask - bid) / _Point > MaxSpreadPoints)
     {
      // No logear cada tick para no saturar el journal
      return;
     }

   //--- Filtro de noticias
   if(IsNewsTime()) return;

   //--- C7: Límite de trades diarios
   if(tradesToday >= MaxTradesPerDay) return;

   //--- PASO 4 & 5: SEÑAL LARGA (BUY)
   bool c1L = (closeNow  > ORB_HIGH);
   bool c2L = UseFilterC2      ? (closePrev <= ORB_HIGH)              : true;
   bool c3L = UseFilterVela    ? (closeNow  > openNow)                : true;
   bool c4L = UseFilterVWAP    ? (closeNow  > currentVWAP)            : true;
   bool c5L = UseFilterEMA     ? (emaFast   > emaSlow)                : true;
   bool c6L = UseFilterATR     ? (ORB_SIZE  >= atrD1 * ATR_MinFactor) : true;
   bool c9L = UseFilterVolumen ? ((double)volNow > volAvg)            : true;

   if(c1L && c2L && c3L && c4L && c5L && c6L && c9L && biasAlcista)
     {
      double entry = ask;
      double sl    = NormalizeDouble(ORB_LOW - ORB_SIZE * (MultiplierSL - 1.0) - SL_Buffer_Points * _Point, _Digits);
      double dist  = MathAbs(entry - sl);
      double tp    = NormalizeDouble(entry + dist * MultiplierTP, _Digits);

      double lot = CalcLotSize(entry, sl);
      if(lot <= 0.0) { Print("ERROR: Lote BUY = 0. Cancelado."); return; }
      if(!CheckMarginOK(ORDER_TYPE_BUY, lot)) return;

      Print("SEÑAL BUY | Entry=", entry, " SL=", sl, " TP=", tp, " Lot=", lot);

      if(trade.Buy(lot, _Symbol, entry, sl, tp, "ORB BUY"))
        {
         tradesToday++;
         isBreakout = true; entryPrice = entry; slDistance = dist;
         beActivated = false; trailActivated = false;
         Print("BUY ejecutado. tradesToday=", tradesToday, " ORB_SIZE=", DoubleToString(ORB_SIZE, _Digits));
        }
      else
         Print("ERROR abriendo BUY: ", GetLastError());
      return;
     }

   //--- PASO 4 & 5: SEÑAL CORTA (SELL)
   bool c1S = (closeNow  < ORB_LOW);
   bool c2S = UseFilterC2      ? (closePrev >= ORB_LOW)               : true;
   bool c3S = UseFilterVela    ? (closeNow  < openNow)                : true;
   bool c4S = UseFilterVWAP    ? (closeNow  < currentVWAP)            : true;
   bool c5S = UseFilterEMA     ? (emaFast   < emaSlow)                : true;
   bool c6S = UseFilterATR     ? (ORB_SIZE  >= atrD1 * ATR_MinFactor) : true;
   bool c9S = UseFilterVolumen ? ((double)volNow > volAvg)            : true;

   if(c1S && c2S && c3S && c4S && c5S && c6S && c9S && biasBajista)
     {
      double entry = bid;
      double sl    = NormalizeDouble(ORB_HIGH + ORB_SIZE * (MultiplierSL - 1.0) + SL_Buffer_Points * _Point, _Digits);
      double dist  = MathAbs(entry - sl);
      double tp    = NormalizeDouble(entry - dist * MultiplierTP, _Digits);

      double lot = CalcLotSize(entry, sl);
      if(lot <= 0.0) { Print("ERROR: Lote SELL = 0. Cancelado."); return; }
      if(!CheckMarginOK(ORDER_TYPE_SELL, lot)) return;

      Print("SEÑAL SELL | Entry=", entry, " SL=", sl, " TP=", tp, " Lot=", lot);

      if(trade.Sell(lot, _Symbol, entry, sl, tp, "ORB SELL"))
        {
         tradesToday++;
         isBreakout = true; entryPrice = entry; slDistance = dist;
         beActivated = false; trailActivated = false;
         Print("SELL ejecutado. tradesToday=", tradesToday, " ORB_SIZE=", DoubleToString(ORB_SIZE, _Digits));
        }
      else
         Print("ERROR abriendo SELL: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction — reset isBreakout al cerrar posición         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(!HasOpenPosition() && MaxTradesPerDay > 1 && tradesToday < MaxTradesPerDay)
        {
         isBreakout = false; beActivated = false; trailActivated = false;
         entryPrice = 0.0;   slDistance  = 0.0;
         Print("Posición cerrada. isBreakout reseteado. tradesToday=", tradesToday);
        }
     }
  }

//+------------------------------------------------------------------+