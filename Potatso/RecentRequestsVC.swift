//
//  RecentRequestsViewController.swift
//  Potatso
//
//  Created by LEI on 4/19/16.
//  Copyright © 2016 TouchingApp. All rights reserved.
//

import Foundation
import Cartography
import PotatsoModel
import RealmSwift
import PotatsoLibrary
import PotatsoBase

private let kRecentRequestCellIdentifier = "recentRequests"
private let kRecentRequestCachedIdentifier = "requestsCached"

class RecentRequestsVC: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    var requests: [Request] = []
    let wormhole = Manager.sharedManager.wormhole
    var timer: Timer?
    var appear = false
    var stopped = false
    var showingCache = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Recent Requests".localized()
        NotificationCenter.default.addObserver(self, selector: #selector(onVPNStatusChanged), name: NSNotification.Name(rawValue: kProxyServiceVPNStatusNotification), object: nil)
        wormhole.listenForMessage(withIdentifier: "tunnelConnectionRecords") { [unowned self](response) in
            self.updateUI(requestString: response as? String)
            Potatso.sharedUserDefaults().set(response as? String, forKey: kRecentRequestCachedIdentifier)
            Potatso.sharedUserDefaults().synchronize()
            return
        }
        self.updateUI(requestString: Potatso.sharedUserDefaults().string(forKey: kRecentRequestCachedIdentifier))
        if Manager.sharedManager.vpnStatus == .Off {
            showingCache = true
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appear = true
        onVPNStatusChanged()
    }
    
    func refresh() {
        wormhole.passMessageObject("" as NSCoding?, identifier: "getTunnelConnectionRecords")
    }
    
    func updateUI(requestString: String?) {
        if let responseStr = requestString, let jsonArray = responseStr.jsonArray() {
            self.requests = jsonArray.reversed().filter({ ($0 as? [String : AnyObject]) != nil }).flatMap({ Request(dict: $0 as! [String : AnyObject]) })
        }else {
            self.requests = []
        }
        tableView.reloadData()
    }
    
    func onVPNStatusChanged() {
        let on = [VPNStatus.On, VPNStatus.Connecting].contains(Manager.sharedManager.vpnStatus)
        hintLabel.isHidden = on
        if on {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refresh))
        }else {
            navigationItem.rightBarButtonItem = nil
        }
        if on && showingCache {
            updateUI(requestString: nil)
        }
        showingCache = !on
    }
    
    // MARK: - TableView DataSource & Delegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        emptyView.isHidden = requests.count > 0
        return requests.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kRecentRequestCellIdentifier, for: indexPath) as! RecentRequestsCell
        cell.config(request: requests[indexPath.row])
        return cell
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true)
        navigationController?.pushViewController(RequestDetailVC(request: requests[indexPath.row]), animated: true)
    }
    
    func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return true
    }

    override func loadView() {
        super.loadView()
        view.backgroundColor = Color.Background
        view.addSubview(tableView)
        view.addSubview(emptyView)
        view.addSubview(hintLabel)
        tableView.register(RecentRequestsCell.self, forCellReuseIdentifier: kRecentRequestCellIdentifier)
        setupLayout()
    }
    
    func setupLayout() {
        constrain(tableView, view) { tableView, view in
            tableView.edges == view.edges
        }
        constrain(hintLabel, emptyView, view) { hintLabel, emptyView, view in
            hintLabel.leading == view.leading
            hintLabel.trailing == view.trailing
            hintLabel.bottom == view.bottom
            hintLabel.height == 35
            
            emptyView.edges == view.edges
        }
    }
    
    lazy var tableView: UITableView = {
        let v = UITableView(frame: CGRect.zero, style: .plain)
        v.dataSource = self
        v.delegate = self
        v.tableFooterView = UIView()
        v.tableHeaderView = UIView()
        v.separatorStyle = .singleLine
        v.estimatedRowHeight = 70
        v.rowHeight = UITableViewAutomaticDimension
        return v
    }()
    
    lazy var emptyView: BaseEmptyView = {
        let v = BaseEmptyView()
        v.title = "You should manually refresh to see the request log.".localized()
        return v
    }()
    
    lazy var hintLabel: UILabel = {
        let v = UILabel()
        v.text = "Potatso is not connected".localized()
        v.textColor = UIColor.white
        v.backgroundColor = "E74C3C".color
        v.textAlignment = .center
        v.font = UIFont.systemFont(ofSize: 14)
        v.alpha = 0.8
        v.isHidden = true
        return v
    }()
    
}
