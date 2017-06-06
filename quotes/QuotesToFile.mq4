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

//+------------------------------------------------------------------+

int handle = 0;
int hour  = -1;
int roll = 0;
void rollFile() {
   WinApiTime now;
   GetLocalTime(now);
   
   if (now.hour == hour && handle != 0) {
        return;
   }
   
   if (handle != 0) {
       FileClose(handle);
       handle = 0;
   }
   
   string fileName = Symbol() + "_" + now.year + "_" + now.month + "_" + now.day + "_" + now.hour;
   handle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   
   if (handle < 1) {
      Comment("File " + fileName + " can't be opened, the last error is ", GetLastError());
      return;
   }
   FileSeek(handle, 0, SEEK_END);
   
   hour = now.hour;
   roll++;
   FileWriteString(handle, "Time,Bid,Ask\n");
   Comment("File: " + fileName + ", roll: " + roll);
}

//+------------------------------------------------------------------+
//| expert initialization
//+------------------------------------------------------------------+
int init() {
    rollFile();
    return handle;
}

//+------------------------------------------------------------------+
//| expert deinitialization
//+------------------------------------------------------------------+
int deinit() {
   //Close file////////////////////////////////////////////////////////////////////////////////////////////////////
   FileClose(handle);
   return(0);
}

//+------------------------------------------------------------------+
//| expert start
//+------------------------------------------------------------------+
int start() {
   rollFile();
    
   WinApiTime now;
   GetLocalTime(now);
   FileWriteString(handle, now.hour + ":" + now.minute + ":" + now.second + "." + now.millis + "," + Bid + "," + Ask + "\n");
   FileFlush(handle);
   return 0;
}
//+------------------------------------------------------------------+
