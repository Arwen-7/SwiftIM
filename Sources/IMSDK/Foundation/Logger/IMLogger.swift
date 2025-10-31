/// IMLogger - 日志系统
/// 提供统一的日志管理，支持多级别日志和文件输出

import Foundation
import os.log

/// 日志级别
public enum IMLogLevel: Int, Comparable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case none = 5
    
    public static func < (lhs: IMLogLevel, rhs: IMLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    var emoji: String {
        switch self {
        case .verbose: return "💬"
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .none: return ""
        }
    }
    
    var description: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .none: return "NONE"
        }
    }
}

/// 日志配置
public struct IMLoggerConfig {
    /// 最低日志级别
    public var minimumLevel: IMLogLevel
    /// 是否启用控制台输出
    public var enableConsole: Bool
    /// 是否启用文件输出
    public var enableFileOutput: Bool
    /// 日志文件路径
    public var logFilePath: String?
    /// 日志文件最大大小（字节）
    public var maxFileSize: UInt64
    /// 最大日志文件数量
    public var maxFileCount: Int
    
    public init(
        minimumLevel: IMLogLevel = .info,
        enableConsole: Bool = true,
        enableFileOutput: Bool = true,
        logFilePath: String? = nil,
        maxFileSize: UInt64 = 10 * 1024 * 1024, // 10MB
        maxFileCount: Int = 5
    ) {
        self.minimumLevel = minimumLevel
        self.enableConsole = enableConsole
        self.enableFileOutput = enableFileOutput
        self.logFilePath = logFilePath
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount
    }
}

/// 日志管理器
public final class IMLogger {
    
    // MARK: - Singleton
    
    public static let shared = IMLogger()
    
    // MARK: - Properties
    
    private var config: IMLoggerConfig
    private let queue = DispatchQueue(label: "com.imsdk.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let osLog = OSLog(subsystem: "com.imsdk", category: "IMSDK")
    
    // MARK: - Initialization
    
    private init() {
        self.config = IMLoggerConfig()
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        setupLogFile()
    }
    
    // MARK: - Public Methods
    
    /// 配置日志系统
    public func configure(_ config: IMLoggerConfig) {
        queue.async { [weak self] in
            self?.config = config
            self?.setupLogFile()
        }
    }
    
    /// 记录 verbose 日志
    public func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .verbose, file: file, function: function, line: line)
    }
    
    /// 记录 debug 日志
    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    /// 记录 info 日志
    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    /// 记录 warning 日志
    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    /// 记录 error 日志
    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    /// 清除日志文件
    public func clearLogs() {
        queue.async { [weak self] in
            self?.clearLogFiles()
        }
    }
    
    // MARK: - Private Methods
    
    private func log(_ message: String, level: IMLogLevel, file: String, function: String, line: Int) {
        guard level >= config.minimumLevel else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(level.emoji) [\(level.description)] [\(fileName):\(line)] \(function) - \(message)"
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 控制台输出
            if self.config.enableConsole {
                self.logToConsole(logMessage, level: level)
            }
            
            // 文件输出
            if self.config.enableFileOutput {
                self.logToFile(logMessage)
            }
        }
    }
    
    private func logToConsole(_ message: String, level: IMLogLevel) {
        let osLogType: OSLogType
        switch level {
        case .verbose, .debug:
            osLogType = .debug
        case .info:
            osLogType = .info
        case .warning:
            osLogType = .default
        case .error:
            osLogType = .error
        case .none:
            osLogType = .default
        }
        
        os_log("%{public}@", log: osLog, type: osLogType, message)
        print(message)
    }
    
    private func logToFile(_ message: String) {
        guard let fileHandle = fileHandle else { return }
        
        if let data = (message + "\n").data(using: .utf8) {
            fileHandle.write(data)
            
            // 检查文件大小
            if let fileSize = try? fileHandle.offset(), fileSize > config.maxFileSize {
                rotateLogFiles()
            }
        }
    }
    
    private func setupLogFile() {
        guard config.enableFileOutput else { return }
        
        let logPath = config.logFilePath ?? defaultLogPath()
        
        // 创建日志目录
        let logDirectory = (logPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)
        
        // 创建或打开日志文件
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        
        fileHandle = FileHandle(forWritingAtPath: logPath)
        fileHandle?.seekToEndOfFile()
    }
    
    private func defaultLogPath() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        let logsDirectory = (documentsDirectory as NSString).appendingPathComponent("IMSDKLogs")
        return (logsDirectory as NSString).appendingPathComponent("imsdk.log")
    }
    
    private func rotateLogFiles() {
        fileHandle?.closeFile()
        
        guard let logPath = config.logFilePath ?? defaultLogPath() as String? else { return }
        
        // 轮转日志文件
        for i in stride(from: config.maxFileCount - 1, through: 1, by: -1) {
            let oldPath = "\(logPath).\(i)"
            let newPath = "\(logPath).\(i + 1)"
            
            if FileManager.default.fileExists(atPath: oldPath) {
                try? FileManager.default.removeItem(atPath: newPath)
                try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
            }
        }
        
        // 重命名当前日志文件
        let backupPath = "\(logPath).1"
        try? FileManager.default.moveItem(atPath: logPath, toPath: backupPath)
        
        // 创建新的日志文件
        setupLogFile()
    }
    
    private func clearLogFiles() {
        fileHandle?.closeFile()
        fileHandle = nil
        
        guard let logPath = config.logFilePath ?? defaultLogPath() as String? else { return }
        
        let logDirectory = (logPath as NSString).deletingLastPathComponent
        
        if let files = try? FileManager.default.contentsOfDirectory(atPath: logDirectory) {
            for file in files where file.hasPrefix("imsdk.log") {
                let filePath = (logDirectory as NSString).appendingPathComponent(file)
                try? FileManager.default.removeItem(atPath: filePath)
            }
        }
        
        setupLogFile()
    }
    
    deinit {
        fileHandle?.closeFile()
    }
}

// MARK: - Convenience Functions

/// 全局日志函数
public func IMLog(_ message: String, level: IMLogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
    IMLogger.shared.log(message, level: level, file: file, function: function, line: line)
}

