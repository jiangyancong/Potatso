

//
//  IndexViewController.swift
//  Potatso
//
//  Created by LEI on 5/27/16.
//  Copyright © 2016 TouchingApp. All rights reserved.
//

import Foundation
import PotatsoLibrary
import PotatsoModel
import Eureka
import ICDMaterialActivityIndicatorView
import Cartography

private let kFormName = "name"
private let kFormDNS = "dns"
private let kFormProxies = "proxies"
private let kFormDefaultToProxy = "defaultToProxy"

class HomeVC: FormViewController, UINavigationControllerDelegate, HomePresenterProtocol, UITextFieldDelegate {

    let presenter = HomePresenter()

    var ruleSetSection: Section!

    var status: VPNStatus {
        didSet(o) {
            updateConnectButton()
        }
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        self.status = .Off
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        presenter.bindToVC(vc: self)
        presenter.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Fix a UI stuck bug
        navigationController?.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationItem.titleView = titleButton
        // Post an empty message so we could attach to packet tunnel process
        Manager.sharedManager.postMessage()
        handleRefreshUI()
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: "List".templateImage, style: .plain, target: presenter, action: #selector(HomePresenter.chooseConfigGroups))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: presenter, action: #selector(HomePresenter.showAddConfigGroup))
    }

    // MARK: - HomePresenter Protocol

    func handleRefreshUI() {
        if presenter.group.isDefault {
            status = Manager.sharedManager.vpnStatus
        }else {
            status = .Off
        }
        updateTitle()
        updateForm()
    }

    func updateTitle() {
        titleButton.setTitle(presenter.group.name, for: .normal)
        titleButton.sizeToFit()
    }

    func updateForm() {
        form.delegate = nil
        form.removeAll()
        form +++ generateProxySection()
        form +++ generateRuleSetSection()
        form.delegate = self
        tableView?.reloadData()
    }

    func updateConnectButton() {
        connectButton.isEnabled = [VPNStatus.On, VPNStatus.Off].contains(status)
        connectButton.setTitleColor(UIColor.white, for: .normal)
        switch status {
        case .Connecting, .Disconnecting:
            connectButton.animating = true
        default:
            connectButton.setTitle(status.hintDescription, for: .normal)
            connectButton.animating = false
        }
        connectButton.backgroundColor = status.color
    }

    // MARK: - Form

    func generateProxySection() -> Section {
        let proxySection = Section()
        if let proxy = presenter.proxy {
            proxySection <<< ProxyRow(kFormProxies) {
                $0.value = proxy
            }.cellSetup({ (cell, row) -> () in
                cell.accessoryType = .DisclosureIndicator
                cell.selectionStyle = .Default
            }).onCellSelection({ [unowned self](cell, row) -> () in
                cell.setSelected(false, animated: true)
                self.presenter.chooseProxy()
            })
        }else {
            proxySection <<< LabelRow() {
                $0.title = "Proxy".localized()
                $0.value = "None".localized()
            }.cellSetup({ (cell, row) -> () in
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            }).onCellSelection({ [unowned self](cell, row) -> () in
                cell.setSelected(false, animated: true)
                self.presenter.chooseProxy()
            })
        }

        proxySection <<< SwitchRow(kFormDefaultToProxy) {
            $0.title = "Default To Proxy".localized()
            $0.value = presenter.group.defaultToProxy
            $0.hidden = Condition.function([kFormProxies]) { [unowned self] form in
                return self.presenter.proxy == nil
            }
        }.onChange({ [unowned self] (row) in
            do {
                try defaultRealm.write {
                    self.presenter.group.defaultToProxy = row.value ?? true
                }
            }catch {
                self.showTextHUD("\("Fail to modify default to proxy".localized()): \((error as NSError).localizedDescription)", dismissAfterDelay: 1.5)
            }
        })
        <<< TextRow(kFormDNS) {
            $0.title = "DNS".localized()
            $0.value = presenter.group.dns
        }.cellSetup { cell, row in
            cell.textField.placeholder = "System DNS".localized()
            cell.textField.autocorrectionType = .no
            cell.textField.autocapitalizationType = .none
        }
        return proxySection
    }

    func generateRuleSetSection() -> Section {
        ruleSetSection = Section("Rule Set".localized())
        for ruleSet in presenter.group.ruleSets {
            ruleSetSection
                <<< LabelRow () {
                    $0.title = "\(ruleSet.name)"
                    var count = 0
                    if ruleSet.ruleCount > 0 {
                        count = ruleSet.ruleCount
                    }else {
                        count = ruleSet.rules.count
                    }
                    if count > 1 {
                        $0.value = String(format: "%d rules".localized(),  count)
                    }else {
                        $0.value = String(format: "%d rule".localized(), count)
                    }
                }.cellSetup({ (cell, row) -> () in
                    cell.selectionStyle = .none
                })
        }
        ruleSetSection <<< BaseButtonRow () {
            $0.title = "Add Rule Set".localized()
        }.onCellSelection({ [unowned self] (cell, row) -> () in
            self.presenter.addRuleSet()
        })
        return ruleSetSection
    }


    // MARK: - Private Actions

    func handleConnectButtonPressed() {
        if status == .On {
            status = .Disconnecting
        }else {
            status = .Connecting
        }
        presenter.switchVPN()
    }

    func handleTitleButtonPressed() {
        presenter.changeGroupName()
    }

    // MARK: - TableView

    func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        if indexPath.section == ruleSetSection.index && indexPath.row < presenter.group.ruleSets.count {
            return true
        }
        return false
    }

    func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .delete {
            do {
                try defaultRealm.write {
                    presenter.group.ruleSets.removeAtIndex(indexPath.row)
                }
                form[indexPath as IndexPath].hidden = true
                form[indexPath as IndexPath].evaluateHidden()
            }catch {
                self.showTextHUD("\("Fail to delete item".localized()): \((error as NSError).localizedDescription)", dismissAfterDelay: 1.5)
            }
        }
    }

    func tableView(tableView: UITableView, editingStyleForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCellEditingStyle {
        return .delete
    }

    // MARK: - TextRow

    override func textInputDidEndEditing<T>(_ textInput: UITextInput, cell: Cell<T>) {
        guard let textField = textInput as? UITextField, let dnsString = textField.text , cell.row.tag == kFormDNS else {
            return
        }
        presenter.updateDNS(dnsString: dnsString)
        textField.text = presenter.group.dns
    }

    // MARK: - View Setup

    private let connectButtonHeight: CGFloat = 48

    override func loadView() {
        super.loadView()
        view.backgroundColor = Color.Background
        view.addSubview(connectButton)
        setupLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubview(toFront: connectButton)
        tableView?.contentInset = UIEdgeInsetsMake(0, 0, connectButtonHeight, 0)
    }

    func setupLayout() {
        constrain(connectButton, view) { connectButton, view in
            connectButton.trailing == view.trailing
            connectButton.leading == view.leading
            connectButton.height == connectButtonHeight
            connectButton.bottom == view.bottom
        }
    }

    lazy var connectButton: FlatButton = {
        let v = FlatButton(frame: CGRect.zero)
        v.addTarget(self, action: #selector(HomeVC.handleConnectButtonPressed), for: .touchUpInside)
        return v
    }()

    lazy var titleButton: UIButton = {
        let b = UIButton(type: .custom)
        b.setTitleColor(UIColor.blackColor, for: .normal)
        b.addTarget(self, action: #selector(HomeVC.handleTitleButtonPressed), for: .touchUpInside)
        if let titleLabel = b.titleLabel {
            titleLabel.font = UIFont.boldSystemFont(ofSize: titleLabel.font.pointSize)
        }
        return b
    }()

}

extension VPNStatus {

    var color: UIColor {
        switch self {
        case .On, .Disconnecting:
            return Color.StatusOn
        case .Off, .Connecting:
            return Color.StatusOff
        }
    }

    var hintDescription: String {
        switch self {
        case .On, .Disconnecting:
            return "Disconnect".localized()
        case .Off, .Connecting:
            return "Connect".localized()
        }
    }
}
