//+------------------------------------------------------------------+
//|                                                 InvestflowTC.mq4 |
//|                                                  Investflow & Co |
//|                                             http://investflow.ru |
//+------------------------------------------------------------------+
#property copyright "Investflow & Co"
#property link      "http://investflow.ru/ts"
#property version   "1.00"
#property strict

#include <stdlib.mqh> 

// входные параметры:
input string usersList = ""; // Имена участников для копирования через запятую
input int verbose = 1; // Режим детального лога. Если не равен 0 - копировщик будет сообщать в лог о каждом шаге.
input double lots = 0.1; // Объём сделки (лотность)
input int minSL = 100; // Минимальный размер Stop Loss. Будет использован если SL выставленный трейдером ниже.
input int maxSL = 1000; // Максимальный размер Stop Loss. Будет использоваться если SL выставленный трейдером выше или его нет.
input int minTP = 100; // Минимальный разрем Take Profit. Будет использован если TP выставленный трейдером ниже.
input int maxTP = 1000; // Максимальный размер Take Profit. Будет использоваться если TP выставленный трейдером выше или его нет.
input int slippage = 0; // Параметр slippage при открытии ордеров


// Классический код торгуемого инструмента (например EURUSD), без специфики брокера (суффиксы, префиксы)
string activeInstrument = "";

// список копируемых пользователей
string users[];

const int MAGIC = 397687501;

int OnInit() {
    if (StringLen(usersList) == 0 || StringSplit(usersList, ',', users) == 0) {
        Print("Не указано имя пользователя для копирования! Работаем в режиме закрытия позиций.");
    }
    if (lots <= 0 || lots > 10) {
        Print("Недопустимая лотность сделки!");
        return INIT_PARAMETERS_INCORRECT;
    }
    activeInstrument = symbolToIflowInstrument();
    if (StringLen(activeInstrument) == 0) {
        Print("Инструмент не участвует в конкурсе или не удалось сопоставить его ни с одним из конкурсных инструментов: ", Symbol());
        return INIT_PARAMETERS_INCORRECT;
    }

    Print("Инициализация завершена. Копируем: ", activeInstrument, " от " ,  usersList, ", 1 пункт в единицах цены: ", 1.0 / MathPow(10, Digits()));
   
    // раз в минуту будем проверять данные с Investflow.
    EventSetTimer(60);

    // делаем первую проверку сразу же
    OnTimer();

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    Print("OnDeinit, reason: ", reason);
}

void OnTick() {
    // вся работа идёт по событию таймера.
}


void OnTimer() {
    // проверяем открыт ли рынок для текущего инструмента.
    if (MarketInfo(Symbol(), MODE_TRADEALLOWED) <= 0) {
        return;
    }

    // проверяем состояние на Investflow, открываем новые позиции, если нужно.
    Verbose("Запрашиваем позиции с сервера");
    char request[], response[];
    string requestHeaders = "User-Agent: investflow-tc";
    string responseHeaders;
    int rc = WebRequest("GET", "http://investflow.ru/api/get-ts-orders?mode=csv&symbol=" + activeInstrument, requestHeaders, 30 * 1000, request, response, responseHeaders);
    if (rc < 0) {
        int err = GetLastError();
        Print("Ошибка при доступе к investflow. Код ошибки: ", ErrorDescription(err));
        return;
    }

    string csv = CharArrayToString(response, 0, WHOLE_ARRAY, CP_UTF8);
    string lines[];
    rc = StringSplit(csv, '\n', lines);
    if (rc < 0) {
        Verbose("Пустой ответ от investflow. Код ошибки: " + (string)GetLastError());
        return;
    }
    if (StringCompare("order, symbol, account, order_type, open_price, sl_price, tp_price", lines[0]) != 0) {
        Print("Неподдерживаемый формат ответа: ", lines[0]);
        return;
    }

    int nLines = ArraySize(lines);

    // массив для списка открытых на Investflow ордеров
    int iflowActiveOrderIds[];
    int nActiveOrders = 0;
    rc = ArrayResize(iflowActiveOrderIds, nLines);
    if (rc != nLines) {
        Print("Не удалось создать массив для открытых ордеров размером ", nLines);
        return;
    }

    for (int i = 1; i < nLines; i++) {
        string line = lines[i];
        if (StringLen(line) == 0) {
            continue;
        }
        string tokens[];
        rc = StringSplit(line, ',', tokens);
        if (rc != 7) {
            Print("Ошибка парсинга строки: ", line);
            break;
        }
        int iflowOrderId = StrToInteger(tokens[0]);
        string instrument = tokens[1];
        if (StringCompare(instrument, activeInstrument) != 0) { // другой инструмент
            continue;
        }
        string account = tokens[2];
        if (!isTrackedAccount(account)) { // этого пользователя мы не отслеживаем
            continue;
        }
        string orderType = tokens[3];
        double openPrice = StrToDouble(tokens[4]);
        double stopLossPrice = StrToDouble(tokens[5]);
        double takeProfitPrice = StrToDouble(tokens[6]);

        iflowActiveOrderIds[nActiveOrders] = iflowOrderId;
        nActiveOrders++;

        int type = StringCompare("buy", orderType) == 0 ? OP_BUY : StringCompare("sell", orderType) == 0 ? OP_SELL : -1;
        if (type != OP_BUY && type != OP_SELL) {
            Print("Ошибка парсинга типа ордера: ", line);
            break;
        }
        openOrderIfNeeded(iflowOrderId, account, type, openPrice, stopLossPrice, takeProfitPrice);
    }

    // закрываем все открытые советником ордера, которых нет в списке от Investflow
    closeOrdersNotInList(iflowActiveOrderIds, nActiveOrders);
}

bool isTrackedAccount(const string& account) {
    for (int i = 0, n = ArraySize(users); i < n; i++) {
        if (StringCompare(users[i], account) == 0) {
            return true;
        }
    }
    return false;
}

string getIflowOrderIdCommentToken(int iflowOrderId) {
    return "code: " + (string)iflowOrderId;
}

/* Возвращает true если в списке открытых или закрытых ордеров есть ордер советника InvestflowTC с данным iflowOrderId. */
bool isOrderProcessed(int iflowOrderId) {
    // ищем среди открытых ордеров
    for(int i = 0, n = OrdersTotal(); i < n; i++) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            int matchResult = matchOrderById(iflowOrderId);
            if (matchResult != 0) { // "да" или "ошибка" => отвечаем что уже скопирован
                return true;
            }
        }
    }
    // ищем среди закрытых ордеров, проверяем не более 100 последних ордеров
    for(int i = 0, n = OrdersHistoryTotal(); i < n && i < 100; i++) {
        int idx = n - i - 1;
        if (OrderSelect(idx, SELECT_BY_POS, MODE_HISTORY)) {
            int matchResult = matchOrderById(iflowOrderId);
            if (matchResult != 0) { // "да" или "ошибка" => отвечаем что уже скопирован
                return true;
            }
        }
    }
    return false;
}

/*
    Проверяет что текущий выбранный ордер имеет необходимый iflowOrderId (записан в комментарии)
    Если ордер открыт другим советником - возвращает 0 ("нет")
    Если iflowOrderId не совпал - возвращает 0 ("нет").
    Если iflowOrderId совпал - возращает 1 ("да").
    Если комментария нет возвращает -1 (ошибка)
*/
int matchOrderById(int iflowOrderId) {
    if (OrderMagicNumber() != MAGIC || OrderSymbol() != Symbol()) {
        return 0; // позиция открыта другим советникам или по другой паре- ответ "нет"
    }
    string comment = OrderComment();
    if (StringLen(comment) == 0) { // у позиции нет комментария - ответ "ошибка"
        Verbose("У позиции открытой советником нет комментария - невозможно определить оригинальный код! Ордер: " + (string)OrderTicket());
        return -1;
    }
    string token = getIflowOrderIdCommentToken(iflowOrderId);
    // ответ 1 ("да") если iflowOrderId совпал, иначе 0 ("нет")
    return StringFind(comment, token, 0) >= 0 ? 1 : 0;
}

/*
    Проверяет открыт ли ордер с данным iflowOrderId,
    если не открыт, проверяет не выполнены ли условия открытия
    и если условия выполнены - открывает ордер
*/
void openOrderIfNeeded(int iflowOrderId, string masterAccount, int orderType, double traderOpenPrice,
                        double originalStopLossPrice, double originalTakeProfitPrice) {
    // проверим, не был ли уже обработан ордер
    bool processed = isOrderProcessed(iflowOrderId);
    if (processed) {
        Verbose("Позиция уже была скопирована: " + masterAccount + ", " + getIflowOrderIdCommentToken(iflowOrderId));
        return;
    }
    Verbose("Обрабатываем позицию " + masterAccount + ", id: " + (string)iflowOrderId + ", тип: " + (orderType == OP_BUY ? "BUY" : "SELL")
            + " открытие трейдера: " + (string)traderOpenPrice);

    // ордер еще не отработан: откроем его если текущие условия те же или лучше указанных трейдером
    bool isBuy = orderType == OP_BUY;
    double currentPrice = MarketInfo(Symbol(), isBuy ? MODE_ASK : MODE_BID);

    // выставляем ордер только если текущая ситуация на рынке не хуже, чем цена при которой открывался мастер
    bool placeOrder  = traderOpenPrice > 0 && (isBuy ? currentPrice <= traderOpenPrice : currentPrice >= traderOpenPrice);
    if (!placeOrder) {
        Verbose("Не выполнены условия открытия для "+ masterAccount + ", текущая цена: " + (string)currentPrice);
        return;
    }

    string comment = masterAccount + ", " + getIflowOrderIdCommentToken(iflowOrderId);
    double stopLossPrice = getEffectiveStopPrice(currentPrice, orderType, originalStopLossPrice, true);
    double takeProfitPrice = getEffectiveStopPrice(currentPrice, orderType, originalTakeProfitPrice, false);

    Print("Копируем позицию " +  masterAccount + ", цена: " + (string)currentPrice +
        ", объём: " + (string)lots +
        ", тип: " + (isBuy ? "BUY" : "SELL") +
        ", SL: " + (string)stopLossPrice,
        ", TP: ", takeProfitPrice,
        ", iflow-код: ", iflowOrderId);

    int ticket = OrderSend(Symbol(), orderType, lots, currentPrice, slippage, stopLossPrice, takeProfitPrice, comment, MAGIC);
    if (ticket == -1) {
        int err = GetLastError();
        Print("Ошибка открытия позиции " + (string)err + ": "  + ErrorDescription(err));
    } else {
        Print("Позиция открыта, " + comment + ", Ордер: " + (string)ticket);
    }
}

double mid(double a, double b, double c) {
    return a > b ?
        (c > a ? a : (b > c ? b : c))
        : (c > b ? b : (a > c ? a : c));
}
/*
    Возвращает значение StopLoss/TakeProfit для текущего состояния цены.
    Использует значения minSL(minTP) и maxSL(maxTP) заданные пользователем.
*/
double getEffectiveStopPrice(double currentPrice, int orderType, double originalStopPrice, bool isSL) {
    double sign = isSL ? (orderType == OP_BUY ? -1 : 1) : (orderType == OP_BUY ? 1 : -1);
    double minS = isSL ? minSL : minTP;
    double maxS = isSL ? maxSL : maxTP;
    double pointsToPriceMultiplier = 1 / MathPow(10, Digits());
    double minStopPrice = currentPrice + sign * minS * pointsToPriceMultiplier;
    double maxStopPrice = currentPrice + sign * maxS * pointsToPriceMultiplier;
    if (originalStopPrice <= 0) {
        return maxStopPrice;
    }
    return mid(minStopPrice, originalStopPrice, maxStopPrice);
}

/* Возвращает значение между min & max. При val <=0 возвращается max. */
int getStopPoints(int min, int val, int max) {
    return val <= 0 || val > max ? max : val < min ? min : val; 
}

string IFLOW_INSTRUMENTS[] = {"EURUSD", "GBPUSD", "USDCHF", "USDJPY", "USDCAD", "AUDUSD", "XAUUSD"};

/* Возвращает Investflow имя для текущего Symbol() */
string symbolToIflowInstrument() {
    string chartSymbol = getChartSymbol();
    for (int i = 0, n = ArraySize(IFLOW_INSTRUMENTS); i < n; i++) {
        string iflowSymbol = IFLOW_INSTRUMENTS[i];
        if (StringCompare(chartSymbol, iflowSymbol) == 0) {
            return iflowSymbol;
        }
    }

    return NULL;
}

string getChartSymbol() {
    string result = Symbol();

    // Правка для AMarkets: инструменты могут иметь суффиксы 'b', 'c' ...
    int len = StringLen(result);
    if (len > 6) {
        result = StringSubstr(result, 0, 6);
    }
    return result;

}

void closeOrdersNotInList(const int & iflowActiveOrderIds[], const int nIflowActive) {
    // ищем среди открытых ордеров
    for(int i = 0, nOrders = OrdersTotal(); i < nOrders; i++) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if (OrderSymbol() != Symbol()) {
                continue;
            }
            Verbose("Проверяем условия закрытия для позиции: " + OrderComment());
            if (OrderMagicNumber() != MAGIC) {
                Verbose("Позиция открыта не нами: " + (string)OrderTicket() + " magic: " + (string)OrderMagicNumber() +
                        ", наш magic: " + (string)MAGIC);
                continue; // позиция открыта не нами - игнорируем.
            }
            bool activeOnIflow = false;
            for (int j = 0; j < nIflowActive; j++) {
                int matchResult = matchOrderById(iflowActiveOrderIds[j]);
                if (matchResult == 1) {
                    activeOnIflow = true;
                    break;
                }
            }
            if (activeOnIflow) {
                Verbose("Позиция найдена на Investflow и активна: " + OrderComment());
                continue; // ордер найден на investflow и активен - ничего не делаем.
            }
            // закрываем ордер.
            Print("Закрываем позицию. Причина: закрыта на Investflow: " + OrderComment());
            string symbol = OrderSymbol();
            double closePrice = MarketInfo(symbol, OrderType() == OP_BUY ? MODE_BID: MODE_ASK);
            int digits = (int)MarketInfo(symbol,MODE_DIGITS);
            bool ok = OrderClose(OrderTicket(), OrderLots(), NormalizeDouble(closePrice, digits), slippage);
            if (!ok) {
                int err = GetLastError();
                Print("Ошибка закрытия позиции " + OrderComment() + ": " + ErrorDescription(err));
            }
        }
    }
}

void Verbose(string message) {
    if (verbose) {
        Print(message);
    }
}
