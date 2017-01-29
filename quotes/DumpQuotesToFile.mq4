/**
    Logs quotes into file for every tick.
    Creates new log file every hour.

    File name format:
        <Instrument>_year_month_date_hour
        Example: EURUSD_2017_01_22_17

    File content format:
        <date>,<bid-price>,<ask-price>
        where date is <hour>:<minute>.<millis>, bid and ask price use '.' as a decimal separator
        Example: 1:22.872,1.07123,1.07127
*/
struct WinApiTime {
  ushort year;       // 2014 etc
  ushort month;      // 1 - 12
  ushort dayOfWeek;  // 0 - 6 with 0 = Sunday
  ushort day;        // 1 - 31
  ushort hour;       // 0 - 23
  ushort minute;     // 0 - 59
  ushort second;     // 0 - 59
  ushort millis;     // 0 - 999
};

#import "kernel32.dll"
    void GetLocalTime(WinApiTime& time);
#import

// handle for currently opened log file
int fileHandle = 0;

// current hour
int logFileHour  = -1;

// flag: if true -> new log file must be started
bool rollLogFile = false;

// Creates new log file if needed.
void rollFile() {
   WinApiTime now;
   GetLocalTime(now);

   if (now.hour == logFileHour && fileHandle != 0) {
        return;
   }

   if (fileHandle != 0) {
       FileClose(fileHandle);
       fileHandle = 0;
   }

   string fileName = Symbol() + "_" + now.year + "_" + now.month + "_" + now.day + "_" + now.hour;
   fileHandle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);

   if (fileHandle < 1) {
      Comment("File " + fileName + " can't be opened, the last error is ", GetLastError());
      return;
   }
   FileSeek(fileHandle, 0, SEEK_END);

   logFileHour = now.hour;
   rollLogFile = false;
   FileWriteString(fileHandle, "Time,Bid,Ask\n");
   Comment("New log file started: " + fileName);
}

// Expert initialization: opens log file and returns INIT_SUCCEEDED if there was no error.
int OnInit() {
    rollFile();
    return fileHandle <= 0 ? INIT_FAILED : INIT_SUCCEEDED;
}

// expert deinitialization: closes log file.
void OnDeinit(const int reason) {
   FileClose(fileHandle);
}

// Dump every tick to file.
void OnTick() {

   // roll file if needed
   rollFile();

   // store current time and quote into the file.
   WinApiTime now;
   GetLocalTime(now);
   FileWriteString(fileHandle, now.hour + ":" + now.minute + ":" + now.second + "." + now.millis + "," + Bid + "," + Ask + "\n");
   FileFlush(fileHandle);
}
