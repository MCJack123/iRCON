//
//  ServerMasterController.swift
//  iRCON
//
//  Created by Jack Bruienne on 10/26/21.
//

import UIKit

class ServerMasterController: UITabBarController {
    public var serverInfo: ServerManager.ServerInfo!
    public var connection: ServerManager.ServerConnection!
    public var serverList: ServersViewController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = serverInfo.name
    }
    
    @IBAction func disconnect(_ sender: Any) {
        ServerManager.instance.disconnect(from: connection)
        presentedViewController?.dismiss(animated: true, completion: nil)
        selectedViewController?.dismiss(animated: true, completion: nil)
        dismiss(animated: true, completion: nil)
        navigationController?.popToRootViewController(animated: true)
        serverList.tableView.reloadData()
    }
}

class TapGestureRecognizerEvent: UITapGestureRecognizer {
    public var lastEvent: UIEvent?
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        lastEvent = event
        super.touchesEnded(touches, with: event)
    }
}

class ConsoleViewController: UIViewController {
    @IBOutlet var textView: UITextView!
    @IBOutlet var commandBox: UITextField!
    @IBOutlet var tapRecognizer: TapGestureRecognizerEvent!
    @IBOutlet var commandBoxConstraint: NSLayoutConstraint!
    var connection: ServerManager.ServerConnection!
    var queue: DispatchQueue!
    var observers = [NSObjectProtocol]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addGestureRecognizer(tapRecognizer)
        connection = (tabBarController! as! ServerMasterController).connection
        queue = (tabBarController! as! ServerMasterController).serverList.queue
        textView.text = "Connected to " + (tabBarController! as! ServerMasterController).serverInfo.ip + ".\n"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observers = [
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: OperationQueue.main, using: {event in
                let k = -((event.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height - self.tabBarController!.tabBar.bounds.maxY + 8)
                UIView.animate(withDuration: TimeInterval(1), animations: {self.commandBoxConstraint.constant = k})
            }),
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: OperationQueue.main, using: {event in
                UIView.animate(withDuration: TimeInterval(1), animations: {self.commandBoxConstraint.constant = -8})
            })
        ]
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        for o in observers {NotificationCenter.default.removeObserver(o, name: nil, object: nil)}
    }
    
    @IBAction func sendCommand(_ sender: Any) {
        let command = commandBox.text!
        if command.isEmpty {return}
        queue.async {
            do {
                let response = try self.connection.send(command: command)
                DispatchQueue.main.async {
                    self.textView.text! += response + "\n"
                    self.textView.scrollRangeToVisible(NSRange(location: self.textView.text!.count - 2, length: 1))
                    self.commandBox.text = ""
                }
            } catch {
                print(error)
                // todo
            }
        }
    }
    
    @IBAction func handleTap(_ sender: Any) {
        if commandBox.hitTest(tapRecognizer.location(ofTouch: 0, in: view), with: tapRecognizer.lastEvent) == nil {
            commandBox.endEditing(true)
        }
    }
}

class PlayersViewController: UITableViewController {
    var connection: ServerManager.ServerConnection!
    var queue: DispatchQueue!
    var players = [String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        connection = (tabBarController! as! ServerMasterController).connection
        queue = (tabBarController! as! ServerMasterController).serverList.queue
        do {
            let response = try connection.send(command: "list")
            guard let c = response.lastIndex(of: ":") else {return}
            for p in response[(response.index(c, offsetBy: 2))...].split(separator: ",") {
                players.append(p.filter({$0 != " " && $0 != "\0"}))
            }
        } catch {}
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? players.count : 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "playerCell", for: indexPath)
        if #available(iOS 14.0, *) {
            var config = cell.defaultContentConfiguration()
            config.text = players[indexPath.item]
            config.image = UIImage(systemName: "person.fill")
            config.imageProperties.maximumSize = CGSize(width: 24, height: 24)
            queue.async {
                guard let data = try? Data(contentsOf: URL(string: "https://www.mc-heads.net/avatar/\(self.players[indexPath.item])/64")!) else {return}
                DispatchQueue.main.async {
                    config.image = UIImage(data: data)
                    cell.contentConfiguration = config
                }
            }
            cell.contentConfiguration = config
        } else {
            cell.textLabel?.text = players[indexPath.item]
            queue.async {
                guard let data = try? Data(contentsOf: URL(string: "https://www.mc-heads.net/avatar/\(self.players[indexPath.item])/24")!) else {return}
                DispatchQueue.main.async {
                    cell.imageView?.image = UIImage(data: data)
                }
            }
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: {_ in
            return UIMenu(title: "", children: [
                UIAction(title: "Set Game Mode", image: UIImage(systemName: "dial.fill"), identifier: nil, attributes: [], handler: {_ in
                    let sheet = UIAlertController(title: "Select a game mode:", message: nil, preferredStyle: .actionSheet)
                    sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
                    sheet.addAction(UIAlertAction(title: "Survival", style: .default, handler: {_ in self.run(command: "gamemode survival \(self.players[indexPath.item])")}))
                    sheet.addAction(UIAlertAction(title: "Creative", style: .default, handler: {_ in self.run(command: "gamemode creative \(self.players[indexPath.item])")}))
                    sheet.addAction(UIAlertAction(title: "Adventure", style: .default, handler: {_ in self.run(command: "gamemode adventure \(self.players[indexPath.item])")}))
                    sheet.addAction(UIAlertAction(title: "Spectator", style: .default, handler: {_ in self.run(command: "gamemode spectator \(self.players[indexPath.item])")}))
                    sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                    self.present(sheet, animated: true, completion: nil)
                }),
                UIAction(title: "Toggle Op", image: UIImage(systemName: "shield.lefthalf.fill"), identifier: nil, attributes: [], handler: {_ in
                    self.queue.async {
                        do {
                            let res = try self.connection.send(command: "op " + self.players[indexPath.item])
                            if res.contains("already") {
                                _ = try self.connection.send(command: "deop " + self.players[indexPath.item])
                            }
                        } catch {
                            DispatchQueue.main.async {
                                let alert = UIAlertController(title: "Failed to Send Command", message: "An error occurred while sending the command: " + error.localizedDescription, preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                                self.present(alert, animated: true, completion: nil)
                            }
                        }
                    }
                }),
                UIAction(title: "Kill", image: UIImage(systemName: "person.crop.circle.fill.badge.xmark"), identifier: nil, attributes: [], handler: {_ in self.run(command: "kill \(self.players[indexPath.item])")}),
                UIAction(title: "Kick", image: UIImage(systemName: "slash.circle.fill"), identifier: nil, attributes: [], handler: self.commandFunction(for: "kick", indexPath: indexPath)),
                UIAction(title: "Ban", image: UIImage(systemName: "xmark.octagon.fill"), identifier: nil, attributes: .destructive, handler: self.commandFunction(for: "ban", indexPath: indexPath)),
                UIAction(title: "Ban IP", image: UIImage(systemName: "xmark.seal.fill"), identifier: nil, attributes: .destructive, handler: self.commandFunction(for: "ban-ip", indexPath: indexPath))
            ])
        })
    }
    
    @IBAction func refresh(_ sender: Any) {
        players.removeAll()
        queue.async {
            do {
                let response = try self.connection.send(command: "list")
                guard let c = response.lastIndex(of: ":") else {return}
                for p in response[(response.index(c, offsetBy: 2))...].split(separator: ",") {
                    self.players.append(p.filter({$0 != " " && $0 != "\0"}))
                }
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                    self.refreshControl?.endRefreshing()
                }
            } catch {}
        }
    }
    
    func run(command: String) {queue.async {_ = try? self.connection.send(command: command)}}
    
    func commandFunction(for command: String, indexPath: IndexPath) -> UIActionHandler {
        return {_ in
            if command == "kick" {
                self.queue.async {
                    _ = try? self.connection.send(command: command + " " + self.players[indexPath.item])
                }
                return
            }
            let alert = UIAlertController(title: "Confirm Command", message: "Are you sure you want to do this action?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .destructive, handler: {_ in self.queue.async {
                _ = try? self.connection.send(command: command + " " + self.players[indexPath.item])
            }}))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
}

class SettingsViewController: UITableViewController {
    var connection: ServerManager.ServerConnection!
    var queue: DispatchQueue!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        connection = (tabBarController! as! ServerMasterController).connection
        queue = (tabBarController! as! ServerMasterController).serverList.queue
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            switch indexPath.item {
            case 0:
                let sheet = UIAlertController(title: "Select a difficulty:", message: nil, preferredStyle: .actionSheet)
                sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
                sheet.addAction(UIAlertAction(title: "Peaceful", style: .default, handler: {_ in self.run(command: "difficulty peaceful")}))
                sheet.addAction(UIAlertAction(title: "Easy", style: .default, handler: {_ in self.run(command: "difficulty easy")}))
                sheet.addAction(UIAlertAction(title: "Normal", style: .default, handler: {_ in self.run(command: "difficulty normal")}))
                sheet.addAction(UIAlertAction(title: "Hard", style: .default, handler: {_ in self.run(command: "difficulty hard")}))
                sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                present(sheet, animated: true, completion: nil)
            case 1:
                let sheet = UIAlertController(title: "Select a game mode:", message: nil, preferredStyle: .actionSheet)
                sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
                sheet.addAction(UIAlertAction(title: "Survival", style: .default, handler: {_ in self.run(command: "defaultgamemode survival")}))
                sheet.addAction(UIAlertAction(title: "Creative", style: .default, handler: {_ in self.run(command: "defaultgamemode creative")}))
                sheet.addAction(UIAlertAction(title: "Adventure", style: .default, handler: {_ in self.run(command: "defaultgamemode adventure")}))
                sheet.addAction(UIAlertAction(title: "Spectator", style: .default, handler: {_ in self.run(command: "defaultgamemode spectator")}))
                sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                present(sheet, animated: true, completion: nil)
            case 2:
                break // todo
            case 3:
                let sheet = UIAlertController(title: "Select the weather:", message: nil, preferredStyle: .actionSheet)
                sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
                sheet.addAction(UIAlertAction(title: "Clear", style: .default, handler: {_ in self.run(command: "weather clear")}))
                sheet.addAction(UIAlertAction(title: "Rain", style: .default, handler: {_ in self.run(command: "weather rain")}))
                sheet.addAction(UIAlertAction(title: "Thunder", style: .default, handler: {_ in self.run(command: "weather thunder")}))
                sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                present(sheet, animated: true, completion: nil)
            default: break
            }
        } else {
            switch indexPath.item {
            case 1:
                run(command: "save-all")
            case 5:
                let alert = UIAlertController(title: "Confirm Command", message: "Are you sure you want to stop the server?", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .destructive, handler: {_ in
                    self.queue.async {
                        _ = try? self.connection.send(command: "stop")
                        DispatchQueue.main.async {
                            (self.tabBarController! as! ServerMasterController).disconnect(self)
                        }
                    }
                }))
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                self.present(alert, animated: true, completion: nil)
            default: break
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @IBAction func autosave(_ sender: Any) {
        let button = sender as! UISegmentedControl
        if button.selectedSegmentIndex == 0 {
            run(command: "save-on")
        } else {
            run(command: "save-off")
        }
    }
    
    @IBAction func whitelist(_ sender: Any) {
        let button = sender as! UISegmentedControl
        if button.selectedSegmentIndex == 0 {
            run(command: "whitelist on")
        } else {
            run(command: "whitelist off")
        }
    }
    
    func run(command: String) {queue.async {_ = try? self.connection.send(command: command)}}
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let vc = segue.destination as? GameruleViewController {
            vc.connection = connection
            vc.queue = queue
            vc.protocolVersion = (tabBarController! as! ServerMasterController).serverList.versionMap[(tabBarController! as! ServerMasterController).serverInfo.id]
        } else if let vc = segue.destination as? TimeViewController {
            vc.connection = connection
            vc.queue = queue
        } else if let vc = segue.destination as? ListViewController {
            vc.connection = connection
            vc.queue = queue
            vc.isWhite = segue.identifier == "whitelistSegue"
        }
    }
}
