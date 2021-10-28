//
//  SettingViewControllers.swift
//  iRCON
//
//  Created by Jack Bruienne on 10/27/21.
//

import UIKit

let allGamerules: [(String, Bool, Int)] = [
    ("announceAdvancements", true, 326),
    ("commandBlockOutput", true, 0),
    ("disableElytraMovementCheck", true, 101),
    ("disableRaids", true, 488),
    ("doDaylightCycle", true, 0),
    ("doEntityDrops", true, 47),
    ("doFireTick", true, 0),
    ("doInsomnia", true, 552),
    ("doImmediateRespawn", true, 552),
    ("doLimitedCrafting", true, 318),
    ("doMobLoot", true, 0),
    ("doMobSpawning", true, 0),
    ("doPatrolSpawning", true, 576),
    ("doTileDrops", true, 0),
    ("doTraderSpawning", true, 576),
    ("doWeatherCycle", true, 306),
    ("drowningDamage", true, 552),
    ("fallDamage", true, 552),
    ("fireDamage", true, 552),
    ("forgiveDeadPlayers", true, 721),
    ("freezeDamage", true, 755),
    ("keepInventory", true, 0),
    ("logAdminCommands", true, 6),
    ("mobGriefing", true, 0),
    ("naturalRegeneration", true, 0),
    ("reducedDebugInfo", true, 29),
    ("sendCommandFeedback", true, 23),
    ("showDeathMessages", true, 13),
    ("spectatorsGenerateChunks", true, 71),
    ("universalAnger", true, 721),
    ("maxCommandChainLength", false, 323),
    ("maxEntityCramming", false, 306),
    ("playersSleepingPercentage", false, 755),
    ("randomTickSpeed", false, 15),
    ("spawnRadius", false, 94)
]

protocol GameruleCell: UITableViewCell {
    var connection: ServerManager.ServerConnection! {get set}
    var queue: DispatchQueue! {get set}
    var name: String {get set}
    var boolValue: Bool {get set}
    var intValue: Int {get set}
}

class BooleanGameruleCell: UITableViewCell, GameruleCell {
    var connection: ServerManager.ServerConnection!
    var queue: DispatchQueue!
    var _name = ""
    var name: String {
        get {return _name}
        set {
            _name = newValue
            titleLabel.text = _name.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression, range: _name.range(of: _name)).trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }
    }
    var boolValue: Bool {
        get {return toggle.isOn}
        set {toggle.isOn = newValue}
    }
    var intValue: Int {get {return 0} set {}}
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var toggle: UISwitch!
    
    @IBAction func changeValue(_ sender: Any) {
        let val = toggle.isOn
        queue.async {
            _ = try? self.connection.send(command: "gamerule \(self._name) \(val ? "true" : "false")")
        }
    }
}

class IntegerGameruleCell: UITableViewCell, GameruleCell {
    var connection: ServerManager.ServerConnection!
    var queue: DispatchQueue!
    var _name = ""
    var name: String {
        get {return _name}
        set {
            _name = newValue
            titleLabel.text = _name.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression, range: _name.range(of: _name)).trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }
    }
    var boolValue: Bool {get {return false} set {}}
    var intValue: Int {
        get {return Int(textField.text!) ?? 0}
        set {textField.text = String(newValue)}
    }
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var textField: UITextField!
    
    @IBAction func changeValue(_ sender: Any) {
        let val = textField.text!
        queue.async {
            _ = try? self.connection.send(command: "gamerule \(self._name) \(val)")
        }
    }
    
    @IBAction func done(_ sender: Any) {
        textField.endEditing(false)
    }
}

class ListViewController: UITableViewController {
    var connection: ServerManager.ServerConnection!
    var queue: DispatchQueue!
    var isWhite: Bool = false
    var players = [String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = isWhite ? "Whitelist" : "Ban List"
        reload(false)
    }
    
    func reload(_ reloadTable: Bool = true) {
        players.removeAll()
        queue.async {
            guard let response = try? self.connection.send(command: self.isWhite ? "whitelist list" : "banlist") else {return}
            if self.isWhite {
                guard let c = response.lastIndex(of: ":") else {return}
                for p in response[(response.index(c, offsetBy: 2))...].split(separator: ",") {
                    self.players.append(p.filter({$0 != " " && $0 != "\0"}))
                }
            } else {
                guard let regex = try? NSRegularExpression(pattern: "([A-Za-z0-9_]+|\\d+\\.\\d+\\.\\d+\\.\\d+) was banned", options: []) else {return}
                regex.enumerateMatches(in: response, options: [], range: NSRange(response.startIndex..<response.endIndex, in: response)) {(match, _, stop) in
                    guard let match = match else {return}
                    if let r = Range(match.range(at: 1), in: response) {
                        self.players.append(String(response[r]))
                    }
                }
            }
            if reloadTable {
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? players.count : 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "playerCell", for: indexPath)
        if #available(iOS 14.0, *) {
            var config = cell.defaultContentConfiguration()
            config.text = players[indexPath.item]
            config.imageProperties.maximumSize = CGSize(width: 24, height: 24)
            if config.text!.range(of: "^\\d+\\.\\d+\\.\\d+\\.\\d+$", options: .regularExpression) == nil {
                config.image = UIImage(systemName: "person.fill")
                queue.async {
                    guard let data = try? Data(contentsOf: URL(string: "https://www.mc-heads.net/avatar/\(self.players[indexPath.item])/64")!) else {return}
                    DispatchQueue.main.async {
                        config.image = UIImage(data: data)
                        cell.contentConfiguration = config
                    }
                }
            } else {
                config.image = UIImage(systemName: "network")
            }
            cell.contentConfiguration = config
        } else {
            cell.textLabel?.text = players[indexPath.item]
            if cell.textLabel!.text!.range(of: "^\\d+\\.\\d+\\.\\d+\\.\\d+$", options: .regularExpression) == nil {
                queue.async {
                    guard let data = try? Data(contentsOf: URL(string: "https://www.mc-heads.net/avatar/\(self.players[indexPath.item])/24")!) else {return}
                    DispatchQueue.main.async {
                        cell.imageView?.image = UIImage(data: data)
                    }
                }
            }
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return "Delete"
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        let text = players.remove(at: indexPath.item)
        let cmd = self.isWhite ? "whitelist remove" : (text.range(of: "^\\d+\\.\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil ? "pardon-ip" : "pardon")
        tableView.deleteRows(at: [indexPath], with: .automatic)
        queue.async {
            _ = try? self.connection.send(command: "\(cmd) \(text)")
        }
    }
    
    @IBAction func add(_ sender: Any) {
        let alert = UIAlertController(title: "Add Player", message: "Enter the player name\(isWhite ? "" : " or IP"):", preferredStyle: .alert)
        alert.addTextField(configurationHandler: nil)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add", style: .default, handler: {_ in
            let text = alert.textFields![0].text!
            let cmd = self.isWhite ? "whitelist add" : (text.range(of: "^\\d+\\.\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil ? "ban-ip" : "ban")
            self.queue.async {
                _ = try? self.connection.send(command: "\(cmd) \(text)")
                self.reload()
            }
        }))
        present(alert, animated: true, completion: nil)
    }
    
    @IBAction func edit(_ sender: UIBarButtonItem) {
        tableView.setEditing(!tableView.isEditing, animated: true)
        if tableView.isEditing {
            sender.title = "Done"
            sender.style = .done
        } else {
            sender.title = "Edit"
            sender.style = .plain
        }
    }
}

class TimeViewController: UITableViewController {
    var connection: ServerManager.ServerConnection!
    var queue: DispatchQueue!
    @IBOutlet var timeWheel: UIDatePicker!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        timeWheel.timeZone = TimeZone(abbreviation: "UTC")
        queue.async {
            guard let res = try? self.connection.send(command: "time query daytime") else {return}
            guard let time = Int(res.filter {$0.isNumber}) else {return}
            DispatchQueue.main.async {
                self.timeWheel.setDate(Date(timeIntervalSince1970: TimeInterval((time + 6000) % 24000) * (86400.0 / 24000.0)), animated: false)
            }
        }
    }
    
    @IBAction func setTime(_ sender: Any) {
        let time = Int(timeWheel.date.timeIntervalSince1970 * (24000.0 / 86400.0) + 18000.0) % 24000
        queue.async {
            _ = try? self.connection.send(command: "time set \(time)")
        }
        dismiss(animated: true, completion: nil)
    }
}

class GameruleViewController: UITableViewController {
    var connection: ServerManager.ServerConnection!
    var queue: DispatchQueue!
    var protocolVersion: Int?
    var gamerules = [(String, Bool)]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        for rule in allGamerules {
            if protocolVersion == nil || protocolVersion! >= rule.2 {
                gamerules.append((rule.0, rule.1))
            }
        }
        gamerules.sort {$0.0 < $1.0}
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? gamerules.count : 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let rule = gamerules[indexPath.item]
        let cell = tableView.dequeueReusableCell(withIdentifier: rule.1 ? "booleanGamerule" : "integerGamerule", for: indexPath) as! GameruleCell
        cell.connection = connection
        cell.queue = queue
        cell.name = rule.0
        queue.async {
            guard let response = try? self.connection.send(command: "gamerule \(rule.0)") else {return}
            guard let c = response.lastIndex(of: ":") else {return}
            let value = response[(response.index(c, offsetBy: 2))...].filter {$0.isLowercase || $0.isNumber}
            DispatchQueue.main.async {
                if rule.1 {cell.boolValue = value == "true"}
                else {cell.intValue = Int(value) ?? 0}
            }
        }
        return cell
    }
}
