//
//  DB.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 03/02/2024
//  Using Swift 5.0
//  Running on macOS 14.3
//
//  Copyright © 2024 Serhiy Mytrovtsiy. All rights reserved.
//

import Foundation

public class DB {
    public static let shared = DB()
    
    private var lldb: LLDB? = nil
    private let queue = DispatchQueue(label: "eu.exelban.db")
    private let ttl: Int = 60*60
    
    public var keys: [String] = []
    
    private var _values: [String: Codable] = [:]
    public var values: [String: Codable] {
        get { self.queue.sync { self._values } }
        set { self.queue.sync { self._values = newValue } }
    }
    
    init() {
        var dbPath: URL
        
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupportURL.appendingPathComponent("Stats")
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
            dbPath = folder.appendingPathComponent("lldb")
        } catch {
            dbPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Stats").appendingPathComponent("lldb")
        }
        
        self.lldb = LLDB(dbPath.path)
    }
    
    deinit {
        self.lldb?.close()
    }
    
    public func setup<T: Codable>(_ type: T.Type, _ key: String) {
        self.keys.append(key)
        self.clean(key)
        
        if let raw = self.lldb?.findOne(key), let value = try? JSONDecoder().decode(type, from: Data(raw.utf8)) {
            self.values[key] = value
        }
    }
    
    public func insert(key: String, value: Codable, ts: Bool = true) {
        self.values[key] = value
        guard let blobData = try? JSONEncoder().encode(value) else { return }
        self.lldb?.insert(key, value: String(decoding: blobData, as: UTF8.self))
        if ts {
            self.lldb?.insert("\(key)@\(Date().currentTimeSeconds())", value: String(decoding: blobData, as: UTF8.self))
        }
    }
    
    public func findOne<T: Decodable>(_ dynamicType: T.Type, key: String) -> T? {
        return self.values[key] as? T
    }
    
    public func findMany<T: Decodable>(_ type: T.Type, key: String) -> [T] {
        guard let values = self.lldb?.findMany(key) as? [String] else { return [] }
        
        var list: [T] = []
        values.forEach({ value in
            if let value = try? JSONDecoder().decode(type, from: Data(value.utf8)) {
                list.append(value)
            }
        })
        
        return list
    }
    
    private func clean(_ key: String) {
        guard let keys = self.lldb?.keys(key) as? [String] else { return }
        let maxLiveTS = Date().currentTimeSeconds() - self.ttl
        var toDeleteKeys: [String] = []
        
        keys.forEach { (key: String) in
            if let ts = key.split(separator: "@").last, let ts = Int(ts), ts < maxLiveTS {
                toDeleteKeys.append(key)
            }
        }
        
        self.lldb?.deleteMany(toDeleteKeys)
    }
}
