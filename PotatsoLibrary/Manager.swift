
//
//  Manager.swift
//  Potatso
//
//  Created by LEI on 4/7/16.
//  Copyright © 2016 TouchingApp. All rights reserved.
//

import PotatsoBase
import PotatsoModel
import RealmSwift
import KissXML
import NetworkExtension
import ICSMainFramework
import MMWormhole

public enum ManagerError: Error {
    case InvalidProvider
    case VPNStartFail
}

public enum VPNStatus {
    case Off
    case Connecting
    case On
    case Disconnecting
}


public let kDefaultGroupIdentifier = "defaultGroup"
public let kDefaultGroupName = "defaultGroupName"
private let statusIdentifier = "status"
public let kProxyServiceVPNStatusNotification = "kProxyServiceVPNStatusNotification"

public class Manager {
    
    public static let sharedManager = Manager()
    
    public private(set) var vpnStatus = VPNStatus.Off {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: kProxyServiceVPNStatusNotification), object: nil)
        }
    }
    
    public let wormhole = MMWormhole(applicationGroupIdentifier: sharedGroupIdentifier, optionalDirectory: "wormhole")

    var observerAdded: Bool = false
    
    public var defaultConfigGroup: ConfigurationGroup {
        return getDefaultConfigGroup()
    }

    private init() {
        loadProviderManager { (manager) -> Void in
            if let manager = manager {
                self.updateVPNStatus(manager: manager)
            }
        }
        addVPNStatusObserver()
    }
    
    func addVPNStatusObserver() {
        guard !observerAdded else{
            return
        }
        loadProviderManager { [unowned self] (manager) -> Void in
            if let manager = manager {
                self.observerAdded = true
                NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: manager.connection, queue: OperationQueue.main, using: { [unowned self] (notification) -> Void in
                    self.updateVPNStatus(manager: manager)
                })
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func updateVPNStatus(manager: NEVPNManager) {
        switch manager.connection.status {
        case .connected:
            self.vpnStatus = .On
        case .connecting, .reasserting:
            self.vpnStatus = .Connecting
        case .disconnecting:
            self.vpnStatus = .Disconnecting
        case .disconnected, .invalid:
            self.vpnStatus = .Off
        }
    }

    public func switchVPN(completion: ((NETunnelProviderManager?, Error?) -> Void)? = nil) {
        loadProviderManager { [unowned self] (manager) in
            if let manager = manager {
                self.updateVPNStatus(manager: manager)
            }
            let current = self.vpnStatus
            guard current != .Connecting && current != .Disconnecting else {
                return
            }
            if current == .Off {
                self.startVPN { (manager, error) -> Void in
                    completion?(manager, error)
                }
            }else {
                self.stopVPN()
                completion?(nil, nil)
            }

        }
    }
    
    public func switchVPNFromTodayWidget(context: NSExtensionContext) {
        if let url = NSURL(string: "potatso://switch") {
            context.open(url as URL, completionHandler: nil)
        }
    }
    
    public func setup() {
        setupDefaultReaml()
        do {
            try copyGEOIPData()
        }catch{
            print("copyGEOIPData fail")
        }
        do {
            try copyTemplateData()
        }catch{
            print("copyTemplateData fail")
        }
    }

    func copyGEOIPData() throws {
        guard let fromURL = Bundle.main.url(forResource: "GeoLite2-Country", withExtension: "mmdb") else {
            return
        }
        let toURL = Potatso.sharedUrl().appendingPathComponent("GeoLite2-Country.mmdb")
        if FileManager.default.fileExists(atPath: fromURL.path) {
            if FileManager.default.fileExists(atPath: toURL.path) {
                try FileManager.default.removeItem(at: toURL)
            }
            try FileManager.default.copyItem(at: fromURL, to: toURL)
        }
    }

    func copyTemplateData() throws {
        guard let bundleURL = Bundle.main.url(forResource: "template", withExtension: "bundle") else {
            return
        }
        let fm = FileManager.default
        let toDirectoryURL = Potatso.sharedUrl().appendingPathComponent("httptemplate")
        if !fm.fileExists(atPath: toDirectoryURL.path) {
            try fm.createDirectory(at: toDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        for file in try fm.contentsOfDirectory(atPath: bundleURL.path) {
            let destURL = toDirectoryURL.appendingPathComponent(file)
            let dataURL = bundleURL.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: dataURL.path) {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try fm.copyItem(at: dataURL, to: destURL)
            }
        }
    }

    private func getDefaultConfigGroup() -> ConfigurationGroup {
        if let groupUUID = Potatso.sharedUserDefaults().string(forKey: kDefaultGroupIdentifier), let group = DBUtils.get(groupUUID, type: ConfigurationGroup.self) , !group.deleted {
            return group
        }else {
            var group: ConfigurationGroup
            if let g = DBUtils.allNotDeleted(ConfigurationGroup.self, sorted: "createAt").first {
                group = g
            }else {
                group = ConfigurationGroup()
                group.name = "Default".localized()
                do {
                    try DBUtils.add(group)
                }catch {
                    fatalError("Fail to generate default group")
                }
            }
            let uuid = group.uuid
            let name = group.name
            DispatchQueue.global().async {
                self.setDefaultConfigGroup(id: uuid, name: name)
            }

            return group
        }
    }
    
    public func setDefaultConfigGroup(id: String, name: String) {
        do {
            try regenerateConfigFiles()
        } catch {

        }
        Potatso.sharedUserDefaults().set(id, forKey: kDefaultGroupIdentifier)
        Potatso.sharedUserDefaults().set(name, forKey: kDefaultGroupName)
        Potatso.sharedUserDefaults().synchronize()
    }
    
    public func regenerateConfigFiles() throws {
        try generateGeneralConfig()
        try generateSocksConfig()
        try generateShadowsocksConfig()
        try generateHttpProxyConfig()
    }

}

extension ConfigurationGroup {

    public var isDefault: Bool {
        let defaultUUID = Manager.sharedManager.defaultConfigGroup.uuid
        let isDefault = defaultUUID == uuid
        return isDefault
    }
    
}

extension Manager {
    
    var upstreamProxy: Proxy? {
        return defaultConfigGroup.proxies.first
    }
    
    var defaultToProxy: Bool {
        return upstreamProxy != nil && defaultConfigGroup.defaultToProxy
    }
    
    func generateGeneralConfig() throws {
        let confURL = Potatso.sharedGeneralConfUrl()
        let json: NSDictionary = ["dns": defaultConfigGroup.dns ?? ""]
        try json.jsonString()?.write(to: confURL, atomically: true, encoding: String.Encoding.utf8)
    }
    
    func generateSocksConfig() throws {
        let root = NSXMLElement.element(withName: "antinatconfig") as! NSXMLElement
        let interface = NSXMLElement.element(withName: "interface", children: nil, attributes: [NSXMLNode.attribute(withName: "value", stringValue: "127.0.0.1") as! DDXMLNode]) as! NSXMLElement
        root.addChild(interface)
        
        let port = NSXMLElement.element(withName: "port", children: nil, attributes: [NSXMLNode.attribute(withName: "value", stringValue: "0") as! DDXMLNode])  as! NSXMLElement
        root.addChild(port)
        
        let maxbindwait = NSXMLElement.element(withName: "maxbindwait", children: nil, attributes: [NSXMLNode.attribute(withName: "value", stringValue: "10") as! DDXMLNode]) as! NSXMLElement
        root.addChild(maxbindwait)
        
        
        let authchoice = NSXMLElement.element(withName: "authchoice") as! NSXMLElement
        let select = NSXMLElement.element(withName: "select", children: nil, attributes: [NSXMLNode.attribute(withName: "mechanism", stringValue: "anonymous") as! DDXMLNode])  as! NSXMLElement
        
        authchoice.addChild(select)
        root.addChild(authchoice)
        
        let filter = NSXMLElement.element(withName: "filter") as! NSXMLElement
        if let upstreamProxy = upstreamProxy {
            let chain = NSXMLElement.element(withName: "chain", children: nil, attributes: [NSXMLNode.attribute(withName: "name", stringValue: upstreamProxy.name) as! DDXMLNode]) as! NSXMLElement
            switch upstreamProxy.type {
            case .Shadowsocks:
                let uriString = "socks5://127.0.0.1:${ssport}"
                let uri = NSXMLElement.element(withName: "uri", children: nil, attributes: [NSXMLNode.attribute(withName: "value", stringValue: uriString) as! DDXMLNode]) as! NSXMLElement
                chain.addChild(uri)
                let authscheme = NSXMLElement.element(withName: "authscheme", children: nil, attributes: [NSXMLNode.attribute(withName: "value", stringValue: "anonymous") as! DDXMLNode]) as! NSXMLElement
                chain.addChild(authscheme)
            default:
                break
            }
            root.addChild(chain)
        }
        
        let accept = NSXMLElement.element(withName: "accept") as! NSXMLElement
        filter.addChild(accept)
        root.addChild(filter)
        
        let socksConf = root.xmlString
        try socksConf.write(to: Potatso.sharedSocksConfUrl(), atomically: true, encoding: String.Encoding.utf8)
    }
    
    func generateShadowsocksConfig() throws {
        let confURL = Potatso.sharedProxyConfUrl()
        var content = ""
        
        if upstreamProxy?.type == .Shadowsocks || upstreamProxy?.type == .ShadowsocksR {
            if let upstreamProxy = upstreamProxy {
                let dic = ["host": upstreamProxy.host, "port": upstreamProxy.port, "password": upstreamProxy.password ?? "", "authscheme": upstreamProxy.authscheme ?? "", "ota": upstreamProxy.ota, "protocol": upstreamProxy.ssrProtocol ?? "", "obfs": upstreamProxy.ssrObfs ?? "", "obfs_param": upstreamProxy.ssrObfsParam ?? ""] as [String : Any]
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: dic, options: .prettyPrinted)
                    // here "jsonData" is the dictionary encoded in JSON data
                    
                    let decoded = try JSONSerialization.jsonObject(with: jsonData, options: [])
                    // here "decoded" is of type `Any`, decoded from JSON data
                    
                    // you can now cast it with the right type
                    if let dictFromJSON = decoded as? String {
                        // use dictFromJSON
                        
                        content = dictFromJSON
                    }
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
        
//        if let upstreamProxy = upstreamProxy , upstreamProxy.type == .Shadowsocks || upstreamProxy.type == .ShadowsocksR {
//            content = ["host": upstreamProxy.host, "port": upstreamProxy.port, "password": upstreamProxy.password ?? "", "authscheme": upstreamProxy.authscheme ?? "", "ota": upstreamProxy.ota, "protocol": upstreamProxy.ssrProtocol ?? "", "obfs": upstreamProxy.ssrObfs ?? "", "obfs_param": upstreamProxy.ssrObfsParam ?? ""].jsonString() ?? ""
//        }
        try content.write(to: confURL, atomically: true, encoding: String.Encoding.utf8)
    }
    
    func generateHttpProxyConfig() throws {
        let rootUrl = Potatso.sharedUrl()
        let confDirUrl = rootUrl.appendingPathComponent("httpconf")
        let templateDirPath = rootUrl.appendingPathComponent("httptemplate").path
        let temporaryDirPath = rootUrl.appendingPathComponent("httptemporary").path
        let logDir = rootUrl.appendingPathComponent("log").path
        let maxminddbPath = Potatso.sharedUrl().appendingPathComponent("GeoLite2-Country.mmdb").path
        let userActionUrl = confDirUrl.appendingPathComponent("potatso.action")
        for p in [confDirUrl.path, templateDirPath, temporaryDirPath, logDir] {
            if !FileManager.default.fileExists(atPath: p) {
                _ = try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true, attributes: nil)
            }
        }
        var mainConf: [String: AnyObject] = [:]
        if let path = Bundle.main.path(forResource: "proxy", ofType: "plist"), let defaultConf = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            mainConf = defaultConf
        }
        mainConf["confdir"] = confDirUrl.path as AnyObject?
        mainConf["templdir"] = templateDirPath as AnyObject?
        mainConf["logdir"] = logDir as AnyObject?
        mainConf["mmdbpath"] = maxminddbPath as AnyObject?
        mainConf["global-mode"] = defaultToProxy as AnyObject?
//        mainConf["debug"] = 1024+65536+1
//        mainConf["debug"] = 131071
        mainConf["debug"] = (mainConf["debug"] as! Int + 4096) as AnyObject?
        mainConf["actionsfile"] = userActionUrl.path as AnyObject?

        let mainContent = mainConf.map { "\($0) \($1)"}.joined(separator: "\n")
        try mainContent.write(to: Potatso.sharedHttpProxyConfUrl(), atomically: true, encoding: String.Encoding.utf8)

        var actionContent: [String] = []
        var forwardURLRules: [String] = []
        var forwardIPRules: [String] = []
        var forwardGEOIPRules: [String] = []
        let rules = defaultConfigGroup.ruleSets.flatMap({ $0.rules })
        for rule in rules {
            
            switch rule.type {
            case .GeoIP:
                forwardGEOIPRules.append(rule.description)
            case .IPCIDR:
                forwardIPRules.append(rule.description)
            default:
                forwardURLRules.append(rule.description)
            }
        }

        if forwardURLRules.count > 0 {
            actionContent.append("{+forward-rule}")
            actionContent.append(contentsOf: forwardURLRules)
        }

        if forwardIPRules.count > 0 {
            actionContent.append("{+forward-rule}")
            actionContent.append(contentsOf: forwardIPRules)
        }

        if forwardGEOIPRules.count > 0 {
            actionContent.append("{+forward-rule}")
            actionContent.append(contentsOf: forwardGEOIPRules)
        }

        // DNS pollution
        actionContent.append("{+forward-rule}")
        actionContent.append(contentsOf: Pollution.dnsList.map({ "DNS-IP-CIDR, \($0)/32, PROXY" }))

        let userActionString = actionContent.joined(separator: "\n")
        try userActionString.write(toFile: userActionUrl.path, atomically: true, encoding: String.Encoding.utf8)
    }

}

extension Manager {
    
    public func isVPNStarted(complete: @escaping (Bool, NETunnelProviderManager?) -> Void) {
        loadProviderManager { (manager) -> Void in
            if let manager = manager {
                complete(manager.connection.status == .connected, manager)
            }else{
                complete(false, nil)
            }
        }
    }
    
    public func startVPN(complete: ((NETunnelProviderManager?, Error?) -> Void)? = nil) {
        startVPNWithOptions(options: nil, complete: complete)
    }
    
    private func startVPNWithOptions(options: [String : NSObject]?, complete: ((NETunnelProviderManager?, Error?) -> Void)? = nil) {
        // regenerate config files
        do {
            try Manager.sharedManager.regenerateConfigFiles()
        }catch {
            complete?(nil, error)
            return
        }
        // Load provider
        loadAndCreateProviderManager { (manager, error) -> Void in
            if let error = error {
                complete?(nil, error)
            }else{
                guard let manager = manager else {
                    complete?(nil, ManagerError.InvalidProvider)
                    return
                }
                if manager.connection.status == .disconnected || manager.connection.status == .invalid {
                    do {
                        try manager.connection.startVPNTunnel(options: options)
                        self.addVPNStatusObserver()
                        complete?(manager, nil)
                    }catch {
                        complete?(nil, error)
                    }
                }else{
                    self.addVPNStatusObserver()
                    complete?(manager, nil)
                }
            }
        }
    }
    
    public func stopVPN() {
        // Stop provider
        loadProviderManager { (manager) -> Void in
            guard let manager = manager else {
                return
            }
            manager.connection.stopVPNTunnel()
        }
    }
    
    public func postMessage() {
        loadProviderManager { (manager) -> Void in
            if let session = manager?.connection as? NETunnelProviderSession,
                let message = "Hello".data(using: String.Encoding.utf8)
                , manager?.connection.status != .invalid
            {
                do {
                    try session.sendProviderMessage(message) { response in
                        
                    }
                } catch {
                    print("Failed to send a message to the provider")
                }
            }
        }
    }
    
    private func loadAndCreateProviderManager(complete: @escaping (NETunnelProviderManager?, Error?) -> Void ) {
        NETunnelProviderManager.loadAllFromPreferences { [unowned self] (managers, error) -> Void in
            if let managers = managers {
                let manager: NETunnelProviderManager
                if managers.count > 0 {
                    manager = managers[0]
                }else{
                    manager = self.createProviderManager()
                }
                manager.isEnabled = true
                manager.localizedDescription = AppEnv.appName
                manager.protocolConfiguration?.serverAddress = AppEnv.appName
                manager.isOnDemandEnabled = true
                let quickStartRule = NEOnDemandRuleEvaluateConnection()
                quickStartRule.connectionRules = [NEEvaluateConnectionRule(matchDomains: ["connect.potatso.com"], andAction: NEEvaluateConnectionRuleAction.connectIfNeeded)]
                manager.onDemandRules = [quickStartRule]
                manager.saveToPreferences(completionHandler: { (error) -> Void in
                    if let error = error {
                        complete(nil, error)
                    }else{
                        manager.loadFromPreferences(completionHandler: { (error) -> Void in
                            if let error = error {
                                complete(nil, error)
                            }else{
                                complete(manager, nil)
                            }
                        })
                    }
                })
            }else{
                complete(nil, error)
            }
        }
    }
    
    public func loadProviderManager(complete: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) -> Void in
            if let managers = managers {
                if managers.count > 0 {
                    let manager = managers[0]
                    complete(manager)
                    return
                }
            }
            complete(nil)
        }
    }
    
    private func createProviderManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        manager.protocolConfiguration = NETunnelProviderProtocol()
        return manager
    }
}

