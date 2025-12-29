//+------------------------------------------------------------------+
//|                                      Martim_ProtectorEA_V6.13.mq4 |
//|                CRÍTICO: Emergency Exit ELIMINADO + Bloqueo Señales|
//+------------------------------------------------------------------+
#property copyright "Guido - V6.13 EMERGENCY REMOVED"
#property version   "6.13"
#property strict

//+------------------------------------------------------------------+
//| PARÁMETROS EXTERNOS                                              |
//+------------------------------------------------------------------+

// === LOTES ===
input double TO_Lot = 0.01;              // Lote Trade Original
input double Hedge1_Lot = 0.02;          // Lote Hedge1 (2x TO)
input double Hedge2_Lot = 0.03;          // Lote Hedge2 (3x TO)

// === TRIGGERS OPERACIÓN ===
input double Entry_Loss_Pips = -1.0;     // TO pérdida → Hedge1 (pips)
input double Hedge2_Trigger_Pips = 1.0;  // TO recupera → Hedge2 (pips)
input double Min_Exit_Profit = 1.0;      // Profit mínimo salida (pips)

// === INDICADORES ===
input int HMA_Period = 7;                // Período HMA_Color
input string HMA_Indicator = "HMA_Color"; // Nombre indicador
input int RSI_Period = 2;                // Período RSI
input int RSI_Lower_Level = 10;          // RSI nivel bajo (buy)
input int RSI_Upper_Level = 90;          // RSI nivel alto (sell)
input int RSI_Extreme_Min = 5;           // RSI extremo mínimo deseado
input int HMA_Change_Window = 5;         // Barras ventana cambio HMA

// === PRIMERA BARRA PROTECTION ===
input int First_Bar_Seconds = 60;        // Tiempo primera barra (seg)
input bool Enable_First_Bar_Check = false; // Activar verificación primera barra

// === IDENTIFICACIÓN ===
input int Magic_Number = 12313;          // Magic Number V6.13
input string Comment_Prefix = "MartimV6"; // Prefijo comentarios

// === TEST SIGNALS (temporal) ===
input bool Enable_Test_Signals = false;  // Activar señales test simples
input bool Enable_Smart_signals = true;  // Activar señales HMA+RSI2
input int Signal_Interval = 10;          // Intervalo verificación señales (seg)
extern bool Enable_Smart_Signals = true;
//+------------------------------------------------------------------+
//| ESTRUCTURAS DE DATOS                                             |
//+------------------------------------------------------------------+

struct TradeGroup
{
   int ticket_TO;           // Ticket Trade Original
   int ticket_H1;           // Ticket Hedge1
   int ticket_H2;           // Ticket Hedge2
   
   int type_TO;             // Tipo TO (OP_BUY/OP_SELL)
   double entry_price_TO;   // Precio entrada TO
   datetime entry_time_TO;  // Tiempo entrada TO
   
   bool hedge1_active;      // Hedge1 activo
   bool hedge2_active;      // Hedge2 activo
   
   double max_profit_reached; // Máximo profit alcanzado
   // ELIMINADO: bool emergency_exit (V6.13)
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+

TradeGroup Groups[];
int GroupCount = 0;
datetime LastTestSignal = 0;
datetime LastSmartSignal = 0;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                             |
//+------------------------------------------------------------------+

int OnInit()
{
   Print("========================================");
   Print("🚀 MARTIM V6.13 INICIALIZADO");
   Print("   ✅ EMERGENCY EXIT ELIMINADO");
   Print("   ✅ Bloqueo señales repetidas");
   Print("   Magic: ", Magic_Number);
   Print("========================================");
   
   if(!ValidateIndicators())
   {
      Print("❌ ERROR: Indicadores no disponibles");
      return INIT_FAILED;
   }
   
   LoadExistingGroups();
   
   Print("✓ Grupos cargados: ", GroupCount);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   Print("Martim V6.13 detenido. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| EXPERT TICK                                                       |
//+------------------------------------------------------------------+

void OnTick()
{
   // Generar señales si habilitado
   if(Enable_Test_Signals)
      GenerateTestSignals();
   
   if(Enable_Smart_Signals)
      GenerateSmartSignals();
   
   // Monitorear y proteger operaciones
   MonitorAndProtectGroups();
}

//+------------------------------------------------------------------+
//| VALIDAR INDICADORES                                              |
//+------------------------------------------------------------------+

bool ValidateIndicators()
{
   // Validar HMA_Color
   double uptrend = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 0, 0);
   if(uptrend == EMPTY_VALUE || GetLastError() != 0)
   {
      Print("❌ HMA_Color no disponible");
      return false;
   }
   
   // Validar RSI
   double rsi = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 0);
   if(rsi == EMPTY_VALUE || GetLastError() != 0)
   {
      Print("❌ RSI no disponible");
      return false;
   }
   
   Print("✓ Indicadores validados: HMA_Color + RSI2");
   return true;
}

//+------------------------------------------------------------------+
//| CARGAR GRUPOS EXISTENTES                                         |
//+------------------------------------------------------------------+

void LoadExistingGroups()
{
   ArrayResize(Groups, 0);
   GroupCount = 0;
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      
      if(OrderMagicNumber() != Magic_Number)
         continue;
      
      string comment = OrderComment();
      
      // Detectar TO
      if(StringFind(comment, "_TO_") >= 0)
      {
         int idx = GroupCount;
         GroupCount++;
         ArrayResize(Groups, GroupCount);
         
         Groups[idx].ticket_TO = OrderTicket();
         Groups[idx].type_TO = OrderType();
         Groups[idx].entry_price_TO = OrderOpenPrice();
         Groups[idx].entry_time_TO = OrderOpenTime();
         Groups[idx].hedge1_active = false;
         Groups[idx].hedge2_active = false;
         Groups[idx].max_profit_reached = 0;
         Groups[idx].ticket_H1 = -1;
         Groups[idx].ticket_H2 = -1;
      }
   }
   
   // Buscar hedges para grupos existentes
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      
      if(OrderMagicNumber() != Magic_Number)
         continue;
      
      string comment = OrderComment();
      
      // Buscar H1
      if(StringFind(comment, "_H1_") >= 0)
      {
         for(int g = 0; g < GroupCount; g++)
         {
            if(StringFind(comment, IntegerToString(Groups[g].ticket_TO)) >= 0)
            {
               Groups[g].ticket_H1 = OrderTicket();
               Groups[g].hedge1_active = true;
               break;
            }
         }
      }
      
      // Buscar H2
      if(StringFind(comment, "_H2_") >= 0)
      {
         for(int g = 0; g < GroupCount; g++)
         {
            if(StringFind(comment, IntegerToString(Groups[g].ticket_TO)) >= 0)
            {
               Groups[g].ticket_H2 = OrderTicket();
               Groups[g].hedge2_active = true;
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| GENERAR SEÑALES TEST SIMPLES                                     |
//+------------------------------------------------------------------+

void GenerateTestSignals()
{
   if(TimeCurrent() - LastTestSignal < Signal_Interval)
      return;
   
   // Evitar nuevas señales si hay grupos activos
   if(GroupCount > 0)
      return;
   
   LastTestSignal = TimeCurrent();
   
   // Alternar BUY/SELL
   static bool nextBuy = true;
   int type = nextBuy ? OP_BUY : OP_SELL;
   nextBuy = !nextBuy;
   
   CreateNewGroup(type);
}

//+------------------------------------------------------------------+
//| GENERAR SEÑALES INTELIGENTES (HMA + RSI2)                        |
//+------------------------------------------------------------------+

void GenerateSmartSignals()
{
   if(TimeCurrent() - LastSmartSignal < Signal_Interval)
      return;
   
   // Evitar nuevas señales si hay grupos activos
   if(GroupCount > 0)
      return;
   
   LastSmartSignal = TimeCurrent();
   
   static int evaluation_count = 0;
   evaluation_count++;
   
   // CONTADORES: Barras desde último cambio HMA
   static int bars_since_hma_turned_bullish = 999;
   static int bars_since_hma_turned_bearish = 999;
   
   // BLOQUEO: Guardar contador cuando se usa señal
   static int last_used_bullish_at = -999;
   static int last_used_bearish_at = -999;
   
   // Leer indicadores
   double hma_up_current = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 0, 0);
   double hma_dn_current = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 1, 0);
   double hma_up_prev = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 0, 1);
   double hma_dn_prev = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 1, 1);
   
   double rsi_current = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 0);
   double rsi_prev = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi_prev2 = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 2);
   
   // Detectar cambio HMA considerando punto de conexión
   // Cambio a ALCISTA: DN desaparece (era valor, ahora EMPTY)
   bool hma_turned_bullish = (hma_dn_current == EMPTY_VALUE && hma_dn_prev != EMPTY_VALUE);
   
   // Cambio a BAJISTA: DN aparece (era EMPTY, ahora valor)
   bool hma_turned_bearish = (hma_dn_current != EMPTY_VALUE && hma_dn_prev == EMPTY_VALUE);
   
   // ACTUALIZAR CONTADORES
   if(hma_turned_bullish)
   {
      bars_since_hma_turned_bullish = 0;
      Print("🔄 HMA CAMBIÓ A ALCISTA - Contador reseteado");
   }
   else
   {
      bars_since_hma_turned_bullish++;
   }
   
   if(hma_turned_bearish)
   {
      bars_since_hma_turned_bearish = 0;
      Print("🔄 HMA CAMBIÓ A BAJISTA - Contador reseteado");
   }
   else
   {
      bars_since_hma_turned_bearish++;
   }
   
   // LOG DEBUG cada 5 minutos
   static datetime last_debug = 0;
   if(TimeCurrent() - last_debug >= 300)
   {
      last_debug = TimeCurrent();
      Print("🔍 Estado indicadores (evaluación #", evaluation_count, "):");
      Print("   HMA up: ", hma_up_current, " (prev: ", hma_up_prev, ")");
      Print("   HMA dn: ", hma_dn_current, " (prev: ", hma_dn_prev, ")");
      Print("   RSI(0): ", DoubleToString(rsi_current, 2), 
            " | RSI(1): ", DoubleToString(rsi_prev, 2), 
            " | RSI(2): ", DoubleToString(rsi_prev2, 2));
      Print("   Barras desde HMA alcista: ", bars_since_hma_turned_bullish);
      Print("   Barras desde HMA bajista: ", bars_since_hma_turned_bearish);
      Print("   Cruces RSI: UP=", (rsi_prev2 < RSI_Lower_Level && rsi_prev > RSI_Lower_Level), 
            " | DOWN=", (rsi_prev2 > RSI_Upper_Level && rsi_prev < RSI_Upper_Level));
   }
   
   // Detectar cruces RSI en barras cerradas
   bool rsi_crossing_up = (rsi_prev2 < RSI_Lower_Level && rsi_prev > RSI_Lower_Level);
   bool rsi_crossing_down = (rsi_prev2 > RSI_Upper_Level && rsi_prev < RSI_Upper_Level);
   
   // SEÑAL BUY: HMA cambió recientemente + RSI cruza + NO usado este cambio
   bool hma_changed_recently_bullish = (bars_since_hma_turned_bullish <= HMA_Change_Window);
   bool signal_not_used_bullish = (bars_since_hma_turned_bullish != last_used_bullish_at);
   
   if(hma_changed_recently_bullish && rsi_crossing_up && signal_not_used_bullish)
   {
      Print("📊 SEÑAL BUY: HMA cambió hace ", bars_since_hma_turned_bullish, " barras + RSI cruzó ", RSI_Lower_Level);
      Print("   RSI(2): ", DoubleToString(rsi_prev2, 2), " | RSI(1): ", DoubleToString(rsi_prev, 2));
      
      // MARCAR SEÑAL USADA
      last_used_bullish_at = bars_since_hma_turned_bullish;
      
      CreateNewGroup(OP_BUY);
      return;
   }
   
   // SEÑAL SELL: HMA cambió recientemente + RSI cruza + NO usado este cambio
   bool hma_changed_recently_bearish = (bars_since_hma_turned_bearish <= HMA_Change_Window);
   bool signal_not_used_bearish = (bars_since_hma_turned_bearish != last_used_bearish_at);
   
   if(hma_changed_recently_bearish && rsi_crossing_down && signal_not_used_bearish)
   {
      Print("📊 SEÑAL SELL: HMA cambió hace ", bars_since_hma_turned_bearish, " barras + RSI cruzó ", RSI_Upper_Level);
      Print("   RSI(2): ", DoubleToString(rsi_prev2, 2), " | RSI(1): ", DoubleToString(rsi_prev, 2));
      
      // MARCAR SEÑAL USADA
      last_used_bearish_at = bars_since_hma_turned_bearish;
      
      CreateNewGroup(OP_SELL);
      return;
   }
}

//+------------------------------------------------------------------+
//| CREAR NUEVO GRUPO                                                |
//+------------------------------------------------------------------+

void CreateNewGroup(int type)
{
   string comment = Comment_Prefix + "_TO_" + IntegerToString(TimeCurrent());
   
   int ticket = OrderSend(
      Symbol(),
      type,
      TO_Lot,
      type == OP_BUY ? Ask : Bid,
      3,
      0,
      0,
      comment,
      Magic_Number,
      0,
      type == OP_BUY ? clrBlue : clrRed
   );
   
   if(ticket > 0)
   {
      Print("✓ TO abierto: ", ticket, " | ", (type == OP_BUY ? "BUY" : "SELL"));
      
      // Agregar a grupos
      int idx = GroupCount;
      GroupCount++;
      ArrayResize(Groups, GroupCount);
      
      Groups[idx].ticket_TO = ticket;
      Groups[idx].type_TO = type;
      Groups[idx].hedge1_active = false;
      Groups[idx].hedge2_active = false;
      Groups[idx].max_profit_reached = 0;
      Groups[idx].ticket_H1 = -1;
      Groups[idx].ticket_H2 = -1;
      
      // Obtener precio y tiempo de entrada
      if(OrderSelect(ticket, SELECT_BY_TICKET))
      {
         Groups[idx].entry_price_TO = OrderOpenPrice();
         Groups[idx].entry_time_TO = OrderOpenTime();
      }
   }
   else
   {
      Print("✗ Error abriendo TO: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| MONITOREAR Y PROTEGER GRUPOS                                     |
//+------------------------------------------------------------------+

void MonitorAndProtectGroups()
{
   for(int i = GroupCount - 1; i >= 0; i--)
   {
      if(!OrderSelect(Groups[i].ticket_TO, SELECT_BY_TICKET))
      {
         RemoveGroup(i);
         continue;
      }
      
      // Calcular profit TO en pips
      double toPips = CalculatePips(
         Groups[i].entry_price_TO,
         Groups[i].type_TO == OP_BUY ? Bid : Ask,
         Groups[i].type_TO
      );
      
      // Actualizar máximo profit
      double totalGroupProfit = CalculateGroupProfit(i);
      if(totalGroupProfit > Groups[i].max_profit_reached)
         Groups[i].max_profit_reached = totalGroupProfit;
      
      // ============================================================
      // FASE 1: SIN HEDGES - Monitorear TO
      // ============================================================
      
      if(!Groups[i].hedge1_active && !Groups[i].hedge2_active)
      {
         // OPCIONAL: Verificar primera barra (desactivado por defecto)
         if(Enable_First_Bar_Check)
         {
            int seconds_since_entry = (int)(TimeCurrent() - Groups[i].entry_time_TO);
            
            if(seconds_since_entry <= First_Bar_Seconds)
            {
               if(toPips <= Entry_Loss_Pips)
               {
                  bool indicators_confirm_error = CheckIndicatorsConfirmError(i);
                  
                  if(indicators_confirm_error)
                  {
                     Print("🚨 PRIMERA BARRA ERROR DETECTADO");
                     Print("   TO: ", Groups[i].ticket_TO, " perdiendo ", DoubleToString(toPips, 2), "p");
                     Print("   → CERRAR TO + ABRIR H1");
                     
                     CloseTradeOriginalAndOpenHedge1(i);
                     continue;
                  }
               }
            }
         }
         
         // Lógica normal: Activar H1 si pérdida alcanza umbral
         if(toPips <= Entry_Loss_Pips)
         {
            Print("🔔 ACTIVAR H1: TO perdiendo ", DoubleToString(toPips, 2), "p");
            ActivateHedge1(i);
            continue;
         }
      }
      
      // ============================================================
      // FASE 2: H1 ACTIVO - Gestión transición
      // ============================================================
      
      if(Groups[i].hedge1_active && !Groups[i].hedge2_active)
      {
         // Verificar si TO recuperó y puede activar H2
         if(toPips >= Hedge2_Trigger_Pips)
         {
            if(CheckHMASupport(Groups[i].type_TO))
            {
               Print("🔄 TO recuperó ", DoubleToString(toPips, 2), "p → TRANSICIÓN H2");
               TransitionToHedge2(i);
               continue;
            }
         }
         
         // V6.13: EMERGENCY EXIT ELIMINADO
         // Sistema confía en H2 para recuperación
      }
      
      // ============================================================
      // FASE 3: H2 ACTIVO - Maximizar ganancias
      // ============================================================
      
      if(Groups[i].hedge2_active)
      {
         double groupProfit = CalculateGroupProfit(i);
         
         if(groupProfit >= Min_Exit_Profit)
         {
            // Verificar retroceso 50% desde máximo
            double retracement_pct = (Groups[i].max_profit_reached - groupProfit) / 
                                    MathMax(Groups[i].max_profit_reached, 0.01) * 100;
            
            if(retracement_pct >= 50.0)
            {
               Print("💰 SALIDA PROFIT: ", DoubleToString(groupProfit, 2), "p (retroceso 50%)");
               CloseGroup(i);
               continue;
            }
         }
         
         // V6.13: EMERGENCY EXIT ELIMINADO
         // Sistema permite máxima paciencia en H2
      }
   }
}

//+------------------------------------------------------------------+
//| VERIFICAR SI INDICADORES CONFIRMAN ERROR (PRIMERA BARRA)         |
//+------------------------------------------------------------------+

bool CheckIndicatorsConfirmError(int idx)
{
   // Leer HMA actual
   double hma_up = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 0, 0);
   double hma_dn = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 1, 0);
   
   // Leer RSI actual
   double rsi = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 0);
   
   int type_TO = Groups[idx].type_TO;
   
   // Si TO es BUY pero HMA muestra bajista Y RSI alto → Error confirmado
   if(type_TO == OP_BUY)
   {
      bool hma_bearish = (hma_dn != EMPTY_VALUE);
      bool rsi_high = (rsi > RSI_Upper_Level);
      
      if(hma_bearish && rsi_high)
      {
         Print("   ✓ Indicadores confirman error BUY:");
         Print("     HMA: Bajista | RSI: ", DoubleToString(rsi, 2));
         return true;
      }
   }
   
   // Si TO es SELL pero HMA muestra alcista Y RSI bajo → Error confirmado
   if(type_TO == OP_SELL)
   {
      bool hma_bullish = (hma_up != EMPTY_VALUE);
      bool rsi_low = (rsi < RSI_Lower_Level);
      
      if(hma_bullish && rsi_low)
      {
         Print("   ✓ Indicadores confirman error SELL:");
         Print("     HMA: Alcista | RSI: ", DoubleToString(rsi, 2));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| CERRAR TO Y ABRIR H1 (ERROR PRIMERA BARRA)                       |
//+------------------------------------------------------------------+

void CloseTradeOriginalAndOpenHedge1(int idx)
{
   // Cerrar TO
   if(OrderSelect(Groups[idx].ticket_TO, SELECT_BY_TICKET))
   {
      bool closed = OrderClose(
         Groups[idx].ticket_TO,
         OrderLots(),
         OrderType() == OP_BUY ? Bid : Ask,
         3,
         clrOrange
      );
      
      if(!closed)
      {
         Print("✗ Error cerrando TO: ", GetLastError());
         return;
      }
      
      Print("✓ TO cerrado (error primera barra)");
   }
   
   // Abrir H1 en dirección contraria
   int hedge_type = (Groups[idx].type_TO == OP_BUY) ? OP_SELL : OP_BUY;
   
   string comment = Comment_Prefix + "_H1_" + IntegerToString(Groups[idx].ticket_TO);
   
   int ticket_h1 = OrderSend(
      Symbol(),
      hedge_type,
      Hedge1_Lot,
      hedge_type == OP_BUY ? Ask : Bid,
      3,
      0,
      0,
      comment,
      Magic_Number,
      0,
      clrOrange
   );
   
   if(ticket_h1 > 0)
   {
      Groups[idx].ticket_H1 = ticket_h1;
      Groups[idx].hedge1_active = true;
      
      Print("✓ H1 abierto: ", ticket_h1, " (compensación error)");
   }
   else
   {
      Print("✗ Error abriendo H1: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| ACTIVAR HEDGE1 (LÓGICA NORMAL)                                   |
//+------------------------------------------------------------------+

void ActivateHedge1(int idx)
{
   int hedge_type = (Groups[idx].type_TO == OP_BUY) ? OP_SELL : OP_BUY;
   
   string comment = Comment_Prefix + "_H1_" + IntegerToString(Groups[idx].ticket_TO);
   
   int ticket = OrderSend(
      Symbol(),
      hedge_type,
      Hedge1_Lot,
      hedge_type == OP_BUY ? Ask : Bid,
      3,
      0,
      0,
      comment,
      Magic_Number,
      0,
      clrOrange
   );
   
   if(ticket > 0)
   {
      Groups[idx].ticket_H1 = ticket;
      Groups[idx].hedge1_active = true;
      
      Print("✓ H1 activado: ", ticket);
   }
   else
   {
      Print("✗ Error activando H1: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| TRANSICIÓN A HEDGE2                                              |
//+------------------------------------------------------------------+

void TransitionToHedge2(int idx)
{
   // Cerrar H1
   if(OrderSelect(Groups[idx].ticket_H1, SELECT_BY_TICKET))
   {
      bool closed = OrderClose(
         Groups[idx].ticket_H1,
         OrderLots(),
         OrderType() == OP_BUY ? Bid : Ask,
         3,
         clrYellow
      );
      
      if(!closed)
      {
         Print("✗ Error cerrando H1: ", GetLastError());
         return;
      }
   }
   
   // Abrir H2 (misma dirección que TO)
   string comment = Comment_Prefix + "_H2_" + IntegerToString(Groups[idx].ticket_TO);
   
   int ticket = OrderSend(
      Symbol(),
      Groups[idx].type_TO,
      Hedge2_Lot,
      Groups[idx].type_TO == OP_BUY ? Ask : Bid,
      3,
      0,
      0,
      comment,
      Magic_Number,
      0,
      clrGreen
   );
   
   if(ticket > 0)
   {
      Groups[idx].ticket_H2 = ticket;
      Groups[idx].hedge2_active = true;
      Groups[idx].hedge1_active = false;
      
      Print("✓ H2 activado: ", ticket);
   }
   else
   {
      Print("✗ Error activando H2: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| VERIFICAR SOPORTE HMA                                            |
//+------------------------------------------------------------------+

bool CheckHMASupport(int trade_type)
{
   double hma_up = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 0, 0);
   double hma_dn = iCustom(Symbol(), 0, HMA_Indicator, HMA_Period, 1, 0);
   
   if(trade_type == OP_BUY)
      return (hma_up != EMPTY_VALUE);
   else
      return (hma_dn != EMPTY_VALUE);
}

//+------------------------------------------------------------------+
//| CALCULAR PROFIT GRUPO                                            |
//+------------------------------------------------------------------+

double CalculateGroupProfit(int idx)
{
   double total = 0;
   
   if(OrderSelect(Groups[idx].ticket_TO, SELECT_BY_TICKET))
      total += OrderProfit() + OrderSwap() + OrderCommission();
   
   if(Groups[idx].hedge1_active && OrderSelect(Groups[idx].ticket_H1, SELECT_BY_TICKET))
      total += OrderProfit() + OrderSwap() + OrderCommission();
   
   if(Groups[idx].hedge2_active && OrderSelect(Groups[idx].ticket_H2, SELECT_BY_TICKET))
      total += OrderProfit() + OrderSwap() + OrderCommission();
   
   return total;
}

//+------------------------------------------------------------------+
//| CERRAR GRUPO COMPLETO                                            |
//+------------------------------------------------------------------+

void CloseGroup(int idx)
{
   double finalProfit = CalculateGroupProfit(idx);
   
   Print("📊 CERRAR GRUPO: ", Groups[idx].ticket_TO);
   Print("   Profit final: $", DoubleToString(finalProfit, 2));
   
   // Cerrar TO
   if(OrderSelect(Groups[idx].ticket_TO, SELECT_BY_TICKET))
   {
      bool closed = OrderClose(
         Groups[idx].ticket_TO,
         OrderLots(),
         OrderType() == OP_BUY ? Bid : Ask,
         3,
         clrRed
      );
      
      if(!closed)
         Print("✗ ERROR cerrando TO: ", GetLastError());
   }
   
   // Cerrar H1 si activo
   if(Groups[idx].hedge1_active && OrderSelect(Groups[idx].ticket_H1, SELECT_BY_TICKET))
   {
      bool closed = OrderClose(
         Groups[idx].ticket_H1,
         OrderLots(),
         OrderType() == OP_BUY ? Bid : Ask,
         3,
         clrOrange
      );
      
      if(!closed)
         Print("✗ ERROR cerrando H1: ", GetLastError());
   }
   
   // Cerrar H2 si activo
   if(Groups[idx].hedge2_active && OrderSelect(Groups[idx].ticket_H2, SELECT_BY_TICKET))
   {
      bool closed = OrderClose(
         Groups[idx].ticket_H2,
         OrderLots(),
         OrderType() == OP_BUY ? Bid : Ask,
         3,
         clrGreen
      );
      
      if(!closed)
         Print("✗ ERROR cerrando H2: ", GetLastError());
   }
   
   RemoveGroup(idx);
}

//+------------------------------------------------------------------+
//| ELIMINAR GRUPO DEL ARRAY                                         |
//+------------------------------------------------------------------+

void RemoveGroup(int idx)
{
   for(int i = idx; i < GroupCount - 1; i++)
      Groups[i] = Groups[i + 1];
   
   GroupCount--;
   ArrayResize(Groups, GroupCount);
}

//+------------------------------------------------------------------+
//| CALCULAR PIPS                                                    |
//+------------------------------------------------------------------+

double CalculatePips(double entry, double current, int type)
{
   double diff = (type == OP_BUY) ? (current - entry) : (entry - current);
   return diff / Point / 10;
}
//+------------------------------------------------------------------+