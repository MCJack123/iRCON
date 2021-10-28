//
//  ServersViewController.swift
//  iRCON
//
//  Created by Jack Bruienne on 10/26/21.
//

import UIKit

func randomUnicodeCharacter() -> String {
    let i = arc4random_uniform(0xFFFF)
    return (i > 0xD7FF && i < 0xE000) ? randomUnicodeCharacter() : String(UnicodeScalar(i)!)
}

class ServerCell: UITableViewCell {
    @IBOutlet var favicon: UIImageView!
    @IBOutlet var title: UILabel!
    @IBOutlet var motd: UILabel!
    @IBOutlet var players: UILabel!
    @IBOutlet var status: UIImageView!
    @IBOutlet var loadingWheel: UIActivityIndicatorView!
}

class ServersViewController: UITableViewController {
    let queue = DispatchQueue(label: "Server Polling", qos: .background, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil)
    var versionMap = [Int: Int]()
    
    override func viewDidLoad() {
        self.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
    }
    
    @IBAction func refresh(_ sender: Any) {
        self.tableView.reloadData()
        self.refreshControl?.endRefreshing()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {return ServerManager.instance.serverList.count}
        else {return 0}
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "serverCell", for: indexPath) as! ServerCell
        let info = ServerManager.instance.serverList[indexPath.item]
        cell.title.text = info.name
        cell.status.tintColor = ServerManager.instance.isConnected(to: info) ? UIColor.systemGreen : UIColor.systemOrange
        cell.motd.text = ""
        cell.players.text = ""
        queue.async {
            if let meta = ServerManager.instance.getInfo(for: info) {
                print(meta)
                DispatchQueue.main.async {
                    self.versionMap[info.id] = meta.protocolVersion
                    cell.status.tintColor = ServerManager.instance.isConnected(to: info) ? .systemGreen : .systemRed
                    cell.players.text = String(meta.playerCount) + "/" + String(meta.playerMax)
                    if let fv = meta.favicon {
                        cell.favicon.image = UIImage(cgImage: fv)
                    }
                    
                    var obfuscated = false, bold = false, strikethrough = false, underline = false, italic = false, color = UIColor.label
                    let str = NSMutableAttributedString()
                    var part = ""
                    var flag = false
                    for c in meta.motd {
                        if flag {
                            switch c {
                            case "0": color = .label; obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "1": color = UIColor(red: 0.0, green: 0.0, blue: 0.666, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "2": color = UIColor(red: 0.0, green: 0.666, blue: 0.0, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "3": color = UIColor(red: 0.0, green: 0.666, blue: 0.666, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "4": color = UIColor(red: 0.666, green: 0.0, blue: 0.0, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "5": color = UIColor(red: 0.666, green: 0.0, blue: 0.666, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "6": color = UIColor(red: 1.0, green: 0.666, blue: 0.0, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "7": color = UIColor(red: 0.666, green: 0.666, blue: 0.666, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "8": color = UIColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "9": color = UIColor(red: 0.333, green: 0.333, blue: 1, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "a": color = UIColor(red: 0.333, green: 1, blue: 0.333, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "b": color = UIColor(red: 0.333, green: 1, blue: 1, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "c": color = UIColor(red: 1, green: 0.333, blue: 0.333, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "d": color = UIColor(red: 1, green: 0.333, blue: 1, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "e": color = UIColor(red: 1, green: 1, blue: 0.333, alpha: 1); obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "f": color = .label; obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            case "k": obfuscated = true
                            case "l": bold = true
                            case "m": strikethrough = true
                            case "n": underline = true
                            case "o": italic = true
                            case "r": obfuscated = false; bold = false; strikethrough = false; underline = false; italic = false
                            default: break
                            }
                            flag = false
                        } else if c == "§" {
                            var traits = [UIFontDescriptor.SymbolicTraits]()
                            if bold {traits.append(.traitBold)}
                            if italic {traits.append(.traitItalic)}
                            if obfuscated {
                                var s = ""
                                for _ in part {s += randomUnicodeCharacter()}
                                part = s
                            }
                            str.append(NSMutableAttributedString(string: part, attributes: [
                                .foregroundColor: color,
                                .strikethroughStyle: strikethrough ? NSUnderlineStyle.single : 0,
                                .underlineStyle: underline ? NSUnderlineStyle.single : 0,
                                .font: UIFont(descriptor: UIFont.systemFont(ofSize: 17.0).fontDescriptor.withSymbolicTraits(UIFontDescriptor.SymbolicTraits(traits))!, size: 17.0),
                                
                            ]))
                            flag = true
                            part = ""
                        } else {
                            part.append(c)
                        }
                    }
                    cell.motd.attributedText = str
                }
            } else {
                DispatchQueue.main.async {
                    cell.status.tintColor = ServerManager.instance.isConnected(to: info) ? .systemGreen : .systemGray
                }
            }
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let info = ServerManager.instance.serverList[indexPath.item]
        let cell = tableView.cellForRow(at: indexPath)! as! ServerCell
        let connected = ServerManager.instance.isConnected(to: info)
        if !connected {
            cell.status.isHidden = true
            cell.loadingWheel.isHidden = false
        }
        queue.async {
            do {
                let conn = try ServerManager.instance.connect(to: info)
                DispatchQueue.main.async {
                    if !connected {
                        cell.status.tintColor = .systemGreen
                        cell.status.isHidden = false
                        cell.loadingWheel.isHidden = true
                    }
                    self.performSegue(withIdentifier: "showServerSegue", sender: (info, conn))
                }
            } catch {
                DispatchQueue.main.async {
                    if !connected {
                        cell.status.isHidden = false
                        cell.loadingWheel.isHidden = true
                    }
                    let alert = UIAlertController(title: "Failed to Connect", message: "An error occurred while connecting to the server: " + error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: {_ in alert.dismiss(animated: true, completion: nil)}))
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return "Delete"
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        ServerManager.instance.remove(server: ServerManager.instance.serverList[indexPath.item])
        tableView.deleteRows(at: [indexPath], with: .automatic)
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let vc = segue.destination as? ServerAddViewController {
            vc.delegate = self
        } else if let vc = segue.destination as? ServerMasterController {
            vc.serverList = self
            (vc.serverInfo, vc.connection) = sender! as! (ServerManager.ServerInfo, ServerManager.ServerConnection)
        }
    }
}

class ServerAddViewController: UITableViewController {
    @IBOutlet var serverName: UITextField!
    @IBOutlet var serverIP: UITextField!
    @IBOutlet var rconPort: UITextField!
    @IBOutlet var serverPort: UITextField!
    @IBOutlet var password: UITextField!
    @IBOutlet var addButton: UIButton!
    var delegate: ServersViewController!
    
    @IBAction func add(_ sender: Any) {
        updateInput(sender)
        if !addButton.isEnabled {return}
        ServerManager.instance.add(server: ServerManager.ServerInfo(id: 0, ip: serverIP.text!, name: serverName.text!, rconPort: UInt16(rconPort.text!)!, serverPort: serverPort.text!.isEmpty ? nil : UInt16(serverPort.text!)!, password: password.text!))
        delegate.tableView.reloadData()
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func updateInput(_ sender: Any) {
        addButton.isEnabled = !serverName.text!.isEmpty && !serverIP.text!.isEmpty && !rconPort.text!.isEmpty && !password.text!.isEmpty && UInt16(rconPort.text!) != nil && (serverPort.text!.isEmpty || UInt16(serverPort.text!) != nil)
    }
}
