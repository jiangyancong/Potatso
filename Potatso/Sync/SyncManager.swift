//
//  SyncManager.swift
//  Potatso
//
//  Created by LEI on 8/2/16.
//  Copyright © 2016 TouchingApp. All rights reserved.
//

import Foundation
import CloudKit

public enum SyncServiceType: String {
    case None
    case iCloud
}

public protocol SyncServiceProtocol {
    func setup(completion: ((Error?) -> Void)?)
    func sync(manually: Bool, completion: ((Error?) -> Void)?)
    func stop()
}

public class SyncManager {

    static let shared = SyncManager()

    public static let syncServiceChangedNotification = "syncServiceChangedNotification"
    private var services: [SyncServiceType: SyncServiceProtocol] = [:]
    private static let serviceTypeKey = "serviceTypeKey"

    private(set) var syncing = false

    var currentSyncServiceType: SyncServiceType {
        get {
            if let raw = UserDefaults.standard.object(forKey: SyncManager.serviceTypeKey) as? String, let type = SyncServiceType(rawValue: raw) {
                return type
            }
            return .None
        }
        set(new) {
            guard currentSyncServiceType != new else {
                return
            }
            getCurrentSyncService()?.stop()
            UserDefaults.standard.set(new.rawValue, forKey: SyncManager.serviceTypeKey)
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: SyncManager.syncServiceChangedNotification), object: nil)
        }
    }

    init() {
    }

    func getCurrentSyncService() -> SyncServiceProtocol? {
        return getSyncService(forType: currentSyncServiceType)
    }

    func getSyncService(forType type: SyncServiceType) -> SyncServiceProtocol? {
        if let service = services[type] {
            return service
        }
        let s: SyncServiceProtocol
        switch type {
        case .iCloud:
            s = ICloudSyncService()
        default:
            return nil
        }
        services[type] = s
        return s
    }

    func showSyncVC(inVC vc:UIViewController? = nil) {
        guard let currentVC = vc ?? UIApplication.shared.keyWindow?.rootViewController else {
            return
        }
        let syncVC = SyncVC()
        currentVC.show(syncVC, sender: self)
    }

}

extension SyncManager {

    func setupNewService(type: SyncServiceType, completion: ((Error?) -> Void)?) {
        if let service = getSyncService(forType: type) {
            service.setup(completion: completion)
        } else {
            completion?(nil)
        }
    }

    func setup(completion: ((Error?) -> Void)?) {
        getCurrentSyncService()?.setup(completion: completion)
    }

    func sync(manually: Bool = false, completion: ((Error?) -> Void)? = nil) {
        if let service = getCurrentSyncService() {
            syncing = true
            NotificationCenter.default.postNotificationName(NSNotification.Name(rawValue: SyncManager.syncServiceChangedNotification), object: nil)
            service.sync(manually: manually) { [weak self] error in
                self?.syncing = false
                NotificationCenter.defaultCenter.postNotificationName(NSNotification.Name(rawValue: SyncManager.syncServiceChangedNotification), object: nil)
                completion?(error)
            }
        }
    }
    
}
