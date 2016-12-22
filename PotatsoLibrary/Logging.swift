//
//  Logging.swift
//  Potatso
//
//  Created by LEI on 4/22/16.
//  Copyright © 2016 TouchingApp. All rights reserved.
//

import Foundation

private let kLoggingLevelIdentifier = "loggingLevel"

public enum LoggingLevel: Int{
    case OFF = 0
    case DEBUG = 1
    
    public static var currentLoggingLevel: LoggingLevel {
        get {
            if let saved = UserDefaults.standard.object(forKey: kLoggingLevelIdentifier) as? Int {
                return LoggingLevel(rawValue: saved) ?? .DEBUG
            }else{
                return .DEBUG
            }
        }
        set(o) {
            UserDefaults.standard.set(o.rawValue, forKey: kLoggingLevelIdentifier)
            UserDefaults.standard.synchronize()
        }
    }

}

extension LoggingLevel: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .OFF:
            return "Off"
        case .DEBUG:
            return "Debug"
        }
    }
    
}
