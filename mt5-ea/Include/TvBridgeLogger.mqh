//+------------------------------------------------------------------+
//|                                               TvBridgeLogger.mqh |
//|                                  Logging Utility for TvBridge EA |
//+------------------------------------------------------------------+
#property copyright "TvBridge"
#property link      ""
#property strict

//--- Log levels
enum ENUM_LOG_LEVEL
{
   LOG_LEVEL_DEBUG = 0,   // Debug messages
   LOG_LEVEL_INFO = 1,    // Informational messages
   LOG_LEVEL_WARNING = 2, // Warning messages
   LOG_LEVEL_ERROR = 3    // Error messages
};

//--- Global log level
input ENUM_LOG_LEVEL InpLogLevel = LOG_LEVEL_INFO; // Minimum log level to display

//--- Log file settings
input bool InpEnableFileLogging = false; // Enable logging to file
input string InpLogFileName = "TvBridgeEA.log"; // Log file name

//+------------------------------------------------------------------+
//| Write log message to journal and optionally to file              |
//+------------------------------------------------------------------+
void LogMessage(ENUM_LOG_LEVEL level, string module, string message)
{
   // Filter by log level
   if(level < InpLogLevel)
      return;

   string levelStr;
   switch(level)
   {
      case LOG_LEVEL_DEBUG:
         levelStr = "DEBUG";
         break;
      case LOG_LEVEL_INFO:
         levelStr = "INFO";
         break;
      case LOG_LEVEL_WARNING:
         levelStr = "WARN";
         break;
      case LOG_LEVEL_ERROR:
         levelStr = "ERROR";
         break;
      default:
         levelStr = "UNKNOWN";
   }

   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   string logEntry = StringFormat("[%s] [%s] [%s] %s", timestamp, levelStr, module, message);

   // Print to journal
   Print(logEntry);

   // Write to file if enabled
   if(InpEnableFileLogging)
   {
      int handle = FileOpen(InpLogFileName, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI, '\n');
      if(handle != INVALID_HANDLE)
      {
         FileSeek(handle, 0, SEEK_END);
         FileWriteString(handle, logEntry + "\n");
         FileClose(handle);
      }
   }
}

//+------------------------------------------------------------------+
//| Convenience logging functions                                    |
//+------------------------------------------------------------------+
void LogDebug(string module, string message)
{
   LogMessage(LOG_LEVEL_DEBUG, module, message);
}

void LogInfo(string module, string message)
{
   LogMessage(LOG_LEVEL_INFO, module, message);
}

void LogWarning(string module, string message)
{
   LogMessage(LOG_LEVEL_WARNING, module, message);
}

void LogError(string module, string message)
{
   LogMessage(LOG_LEVEL_ERROR, module, message);
}

//+------------------------------------------------------------------+
//| Log trade result with details                                    |
//+------------------------------------------------------------------+
void LogTradeResult(string action, string symbol, double volume, bool success, int errorCode = 0)
{
   string message;
   if(success)
   {
      message = StringFormat("%s executed successfully: symbol=%s, volume=%.2f", action, symbol, volume);
      LogInfo("Trade", message);
   }
   else
   {
      message = StringFormat("%s failed: symbol=%s, volume=%.2f, error=%d", action, symbol, volume, errorCode);
      LogError("Trade", message);
   }
}

//+------------------------------------------------------------------+
//| Log HTTP request/response                                        |
//+------------------------------------------------------------------+
void LogHttpRequest(string method, string url, int statusCode, string response = "")
{
   string message = StringFormat("%s %s - Status: %d", method, url, statusCode);

   if(statusCode == 200)
   {
      LogInfo("HTTP", message);
   }
   else
   {
      LogError("HTTP", message);
      if(StringLen(response) > 0)
      {
         LogError("HTTP", "Response: " + response);
      }
   }
}

//+------------------------------------------------------------------+
//| Clear log file                                                    |
//+------------------------------------------------------------------+
void ClearLogFile()
{
   if(InpEnableFileLogging)
   {
      FileDelete(InpLogFileName);
      LogInfo("Logger", "Log file cleared");
   }
}
//+------------------------------------------------------------------+
