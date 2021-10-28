//
//  ServerManager.swift
//  iRCON
//
//  Created by Jack Bruienne on 10/25/21.
//

import Foundation
import CoreFoundation
import CoreGraphics
import SwiftSocket

class Lock {
    class Guard {
        private var lock: Lock
        public init(lock: Lock) {
            self.lock = lock
            lock.lock()
        }
        deinit {lock.unlock()}
    }
    private var mutex = pthread_mutex_t()
    public init() {pthread_mutex_init(&mutex, nil)}
    deinit {pthread_mutex_destroy(&mutex)}
    public func lock() {pthread_mutex_lock(&mutex)}
    public func unlock() {pthread_mutex_unlock(&mutex)}
    public func lockGuard() -> Guard {return Guard(lock: self)}
    public func sync<R>(block: () -> R) -> R {
        pthread_mutex_lock(&mutex)
        defer {pthread_mutex_unlock(&mutex)}
        return block()
    }
    public func sync<R>(block: () throws -> R) rethrows -> R {
        pthread_mutex_lock(&mutex)
        defer {pthread_mutex_unlock(&mutex)}
        return try block()
    }
}

class ServerManager {
    struct ServerInfo: Codable {
        public var id: Int
        public var ip: String
        public var name: String
        public var rconPort: UInt16 = 25575
        public var serverPort: UInt16?
        public var password: String
    }
    
    struct ServerMetadata {
        public var version: String
        public var protocolVersion: Int
        public var playerCount: Int
        public var playerMax: Int
        public var motd: String
        public var favicon: CGImage?
    }
    
    class ServerConnection {
        private var connection: TCPClient
        private var _nextID: UInt32 = 0
        private var nextPayload: [Byte]? = nil
        private var lock = Lock()
        
        private var nextID: UInt32 {
            get {
                _nextID += 1
                return _nextID - 1
            }
        }
        
        public enum PacketType: UInt32 {
            case response = 0
            case command = 2
            case login = 3
        }
        
        private func makePacket(from payload: String, type: PacketType, forID id: UInt32) -> Data {
            let payload_data = payload.data(using: .isoLatin1) ?? Data()
            var buf = Data(capacity: payload_data.count + 13)
            var size = CFSwapInt32HostToLittle(UInt32(payload_data.count + 9))
            var id_ = CFSwapInt32HostToLittle(id)
            var type_ = CFSwapInt32HostToLittle(type.rawValue)
            buf.append(Data(bytes: &size, count: 4))
            buf.append(Data(bytes: &id_, count: 4))
            buf.append(Data(bytes: &type_, count: 4))
            buf.append(payload_data)
            buf.append(0)
            return buf
        }
        
        private func receivePacket(allowAnyType: Bool = false) -> (UInt32, String)? {
            var final_payload: String? = nil
            var id: UInt32? = nil
            var ok: Bool
            repeat {
                ok = false
                var data: [Byte]
                if let d = nextPayload {
                    data = d
                    nextPayload = nil
                } else {
                    guard let size_data = connection.read(4, timeout: 1) else {break}
                    let size = size_data.withUnsafeBytes {CFSwapInt32LittleToHost($0.load(as: UInt32.self))}
                    if size > 4110 {return nil} // woah! we have trouble
                    if let d = connection.read(Int(size), timeout: 1) {data = d} else {break}
                }
                let (_id, type) = data.withUnsafeBytes {
                    (CFSwapInt32LittleToHost($0.load(as: UInt32.self)),
                     CFSwapInt32LittleToHost($0.load(fromByteOffset: 4, as: UInt32.self)))
                }
                if let i = id, _id != i {
                    nextPayload = data
                    break
                }
                id = _id
                data.removeFirst(8)
                data.removeLast()
                let payload = String(bytes: data, encoding: .isoLatin1) ?? ""
                if !allowAnyType && type != 0 {break}
                final_payload = (final_payload ?? "") + payload
                if data.count == 4096 {ok = true}
            } while ok
            if var p = final_payload, let i = id {p.removeLast(); return (i, p)}
            else {return nil}
        }
        
        fileprivate init(to info: ServerInfo) throws {
            connection = TCPClient(address: info.ip, port: Int32(info.rconPort))
            var res = connection.connect(timeout: 5)
            if res.isFailure {throw res.error!}
            let id = nextID
            res = connection.send(data: makePacket(from: info.password, type: .login, forID: id))
            if res.isFailure {
                connection.close()
                throw res.error!
            }
            guard let (inID, _) = receivePacket(allowAnyType: true) else {throw SocketError.connectionTimeout}
            if inID == 0xFFFFFFFF {
                connection.close()
                throw POSIXError(.EAUTH)
            }
        }
        
        deinit {
            connection.close()
        }
        
        public func send(command: String) throws -> String {
            return try lock.sync {
                while connection.read(1) != nil {} // clear buffer
                let id = nextID
                let res = connection.send(data: makePacket(from: command, type: .command, forID: id))
                if res.isFailure {throw res.error!}
                guard let (inID, data) = receivePacket() else {throw SocketError.connectionTimeout}
                if inID != id {throw SocketError.unknownError}
                return data
            }
        }
    }
    
    static var instance = ServerManager()
    public var serverList = [ServerInfo]()
    public var serverConnections = [Int: ServerConnection]()
    
    private static func readVarInt(_ bytes: [Byte], startingAt i: Int = 0) -> (Int, Int) {
        var value: UInt = 0
        var bitOffset = 0
        var currentByte: Byte
        var i = i
        repeat {
            if (bitOffset == 35) {return (Int(bitPattern: value), i)} // non-conforming!
            currentByte = bytes[i]
            i += 1
            value |= UInt(currentByte & 0x7F) << bitOffset
            bitOffset += 7
        } while (currentByte & 0x80) != 0
        return (Int(bitPattern: value), i)
    }
    
    private static func writeVarInt(_ value: Int) -> [Byte] {
        var value = UInt(bitPattern: value)
        var retval = [Byte]()
        while true {
            if (value & 0xFFFFFF80) == 0 {
                retval.append(Byte(value))
                return retval
            }
            retval.append(Byte((value & 0x7F) | 0x80))
            value >>= 7
        }
    }
    
    private init() {
        try? serverList = JSONDecoder().decode([ServerInfo].self, from: Data(contentsOf: FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("servers.json")))
    }
    
    deinit {
        save()
    }
    
    public func save() {
        try? JSONEncoder().encode(serverList).write(to: FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("servers.json"))
    }
    
    public func add(server info: ServerInfo) {
        var info = info
        var max = 0
        for i in serverList {if i.id > max {max = i.id}}
        info.id = max + 1
        serverList.append(info)
        save()
    }
    
    public func remove(server info: ServerInfo) {
        serverList = serverList.filter {$0.id != info.id}
        save()
    }
    
    public func connect(to info: ServerInfo) throws -> ServerConnection {
        if let conn = serverConnections[info.id] {return conn}
        let conn = try ServerConnection(to: info)
        serverConnections[info.id] = conn
        return conn
    }
    
    public func isConnected(to info: ServerInfo) -> Bool {
        return serverConnections.contains(where: {$0.key == info.id})
    }
    
    public func disconnect(from conn: ServerConnection) {
        serverConnections = serverConnections.filter {$0.value !== conn}
    }
    
    public func getInfo(for info: ServerInfo) -> ServerMetadata? {
        if info.serverPort == nil {return nil}
        let conn = TCPClient(address: info.ip, port: Int32(info.serverPort!))
        var res = conn.connect(timeout: 5)
        if res.isFailure {return nil}
        let ip = info.ip.data(using: .isoLatin1) ?? Data()
        let ipLength = ServerManager.writeVarInt(ip.count)
        let length = ServerManager.writeVarInt(ipLength.count + ip.count + 9)
        var port = CFSwapInt16HostToBig(info.serverPort!)
        var data = Data(capacity: length.count + ipLength.count + ip.count + 9)
        data.append(contentsOf: length)
        data.append(contentsOf: [0, 0xff, 0xff, 0xff, 0xff, 0x0f])
        data.append(contentsOf: ipLength)
        data.append(ip)
        data.append(Data(bytes: &port, count: 2))
        data.append(1)
        res = conn.send(data: data)
        if res.isFailure {conn.close(); return nil}
        res = conn.send(data: [1, 0])
        if res.isFailure {conn.close(); return nil}
        res = conn.send(data: [9, 1, 0, 0, 0, 0, 0, 0, 0, 0])
        if res.isFailure {conn.close(); return nil}
        var lenb = [Byte]()
        repeat {
            guard let b = conn.read(1, timeout: 1) else {
                conn.close()
                return nil
            }
            lenb.append(contentsOf: b)
        } while (lenb.last! & 0x80) != 0
        let (len, _) = ServerManager.readVarInt(lenb)
        guard var packet = conn.read(len, timeout: 1) else {
            conn.close()
            return nil
        }
        while packet.count < len {
            guard let s = conn.read(len - packet.count, timeout: 1) else {
                conn.close()
                return nil
            }
            packet += s
        }
        
        conn.close()
        if packet[0] != 0 {return nil}
        let (strlen, start) = ServerManager.readVarInt(packet, startingAt: 1)
        guard let json = try? JSONSerialization.jsonObject(with: Data(packet[start..<start+strlen])) else {return nil}
        if let root = json as? [String: Any] {
            let version: String
            let protocolVersion: Int
            let playerCount: Int
            let playerMax: Int
            let motd: String
            let favicon: CGImage?
            if let ver = root["version"] as? [String: Any] {
                version = ver["name"] as? String ?? ""
                protocolVersion = ver["protocol"] as? Int ?? -1
            } else {
                version = ""
                protocolVersion = -1
            }
            if let players = root["players"] as? [String: Any] {
                playerCount = players["online"] as? Int ?? 0
                playerMax = players["max"] as? Int ?? 0
            } else {
                playerCount = 0
                playerMax = 0
            }
            if let description = root["description"] as? [String: Any] {
                motd = description["text"] as? String ?? ""
            } else {
                motd = ""
            }
            if let _favicon = root["favicon"] as? String,
               let fd = Data(base64Encoded: String(_favicon[_favicon.index(_favicon.startIndex, offsetBy: 22)...])) as NSData?,
               let cfd = CFDataCreate(kCFAllocatorDefault, fd.bytes.assumingMemoryBound(to: UInt8.self), fd.length),
               let provider = CGDataProvider(data: cfd) {
                favicon = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            } else {
                favicon = nil
            }
            return ServerMetadata(version: version, protocolVersion: protocolVersion, playerCount: playerCount, playerMax: playerMax, motd: motd, favicon: favicon)
        } else {return nil}
    }
}
