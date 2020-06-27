//
//  ContentView.swift
//  SMServer
//
//  Created by Ian Welker on 4/30/20.
//  Copyright © 2020 Ian Welker. All rights reserved.
//

import SwiftUI
import GCDWebServer
import SQLite3
import MessageUI

struct ContentView: View {
    let server = GCDWebServer()
    let bbheight: CGFloat? = 40
    let bbsize: CGSize = CGSize(width: 1.8, height: 1.8)
    let debug = true
    static let default_num_chats = 40
    static let default_num_messages = 100
    
    @State var server_running = false
    @State var egnum = "8741"
    @State var password = "toor"
    @State var main_url = ""
    @State var past_latest_texts = [String:[String:[String:String]]]() /// Should be in the format of [address: [Chats]]
    @State var authenticated_addresses = [String]()
    
    let messagesString = "/private/var/mobile/Library/SMS/sms.db"
    let messagesURL = URL(fileURLWithPath: "/private/var/mobile/Library/SMS/sms.db")
    static let imageStoragePrefix = "/private/var/mobile/Library/SMS/Attachments/"
    static let userHomeString = "/private/var/mobile/"
    internal let SQLITE_STATIC = unsafeBitCast(0, to: sqlite3_destructor_type.self)
    internal let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    var requests_page = """
    <!DOCTYPE html>
        <body style="background-color: #222;">
            <p style="color: #DDD; font-family: Verdana; font-size: 24px; padding: 20px;">
                This is the requests page! Thanks for visiting :)
            </p>
        </body>
    </html>
    """
    @State var main_page =
    """
    """
    @State var main_page_style =
    """
    """
    @State var main_page_script =
    """
    """
    @State var gatekeeper_page =
    """
    """
    
    private let messageComposeDelegate = MessageComposerDelegate()
    
    func loadServer(port_num: UInt16) {
        
        server.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self, processBlock: { request in
            if self.debug {
                print("headers:")
                print(request.headers)
                print("query:")
                print(request.query)
                print("url:")
                print(request.url)
                print("lad:")
                print(request.localAddressData)
                print(request.localAddressString)
                print("ras:")
                print(request.remoteAddressString)
            }
            
            self.debug ? print("entered default handler") : nil
            
            if self.checkIfAuthenticated(ras: String(request.remoteAddressString.prefix(upTo: request.remoteAddressString.firstIndex(of: ":")!))) {
                return GCDWebServerDataResponse(html: self.main_page)
            } else {
                return GCDWebServerDataResponse(html: self.gatekeeper_page)
            }
        })
        
        server.addHandler(forMethod: "GET", path: "/requests", request: GCDWebServerRequest.self, processBlock: { request in
            if self.debug {
                print("headers:")
                print(request.headers)
                print("query:")
                print(request.query)
                print("url:")
                print(request.url)
                print("lad:")
                print(request.localAddressData)
                print(request.localAddressString)
                print("ras:")
                print(request.remoteAddressString)
            }
            
            let query = request.query
            
            if query != nil && query?.count == 0 {
                return GCDWebServerDataResponse(html: self.requests_page)
            } else {
                var address = ""
                
                do {
                    address = try String(request.remoteAddressString.prefix(upTo: request.remoteAddressString.firstIndex(of: ":")!))
                } catch {
                    address = ""
                }
                
                let response = self.parseAndReturn(params: query ?? [String:String](), address: address)
                
                return GCDWebServerDataResponse(text: response)
            }
        })
        
        server.addHandler(forMethod: "GET", path: "/attachments", request: GCDWebServerRequest.self, processBlock: { request in
            
            if !self.checkIfAuthenticated(ras: String(request.remoteAddressString.prefix(upTo: request.remoteAddressString.firstIndex(of: ":")!))) {
                return GCDWebServerDataResponse(text: "")
            }
            
            return GCDWebServerDataResponse(data: self.getAttachmentDataFromPath(path: request.query?["path"] ?? ""), contentType: "image/jpeg")
        })
        
        server.addHandler(forMethod: "GET", path: "/profile", request: GCDWebServerRequest.self, processBlock: { request in
            
            if !self.checkIfAuthenticated(ras: String(request.remoteAddressString.prefix(upTo: request.remoteAddressString.firstIndex(of: ":")!))) {
                return GCDWebServerDataResponse(text: "")
            }
            
            //return GCDWebServerDataResponse(data: self.getAttachmentDataFromPath(path: request.query?["chat_id"] ?? ""), contentType: "image/jpeg")
            return GCDWebServerDataResponse(data: self.returnImageData(chat_id: request.query?["chat_id"] ?? ""), contentType: "image/jpeg")
        })
        
        server.addHandler(forMethod: "GET", path: "/style.css", request: GCDWebServerRequest.self, processBlock: { request in
            
            if !self.checkIfAuthenticated(ras: String(request.remoteAddressString.prefix(upTo: request.remoteAddressString.firstIndex(of: ":")!))) {
                return GCDWebServerDataResponse(text: "")
            }
            
            return GCDWebServerDataResponse(text: self.main_page_style)
        })
        
        server.start(withPort: UInt(egnum) ?? UInt(8741), bonjourName: "GCD Web Server")
        
        self.server_running = server.isRunning
    }
    
    func loadFiles() {
        if let h = Bundle.main.url(forResource: "chats", withExtension: "html", subdirectory: "html"),
        let c = Bundle.main.url(forResource: "style", withExtension: "css", subdirectory: "html"),
        let g = Bundle.main.url(forResource: "gatekeeper", withExtension: "html", subdirectory: "html") {
            do {
                self.main_page = try String(contentsOf: h, encoding: .utf8)
                self.main_page_style = try String(contentsOf: c, encoding: .utf8)
                self.gatekeeper_page = try String(contentsOf: g, encoding: .utf8)
            }
            catch {
                print("WARNING: ran into an error with loading the files, try again.")
            }
        }
    }
    
    func checkIfAuthenticated(ras: String) -> Bool {
        var clear = false
        
        for i in self.authenticated_addresses {
            if i == ras {
                clear = true
            }
        }
        
        return clear
    }
    
    func encodeToJson(object: Any, title: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted) else {
            return ""
        }
        var data_string = String(decoding: data, as: UTF8.self)
        data_string = "{ \"\(title)\": \(data_string)\n}"
        return data_string
    }
    
    func parseAndReturn(params: [String:String], address: String = "") -> String {
        if self.debug {
            print("parsing:")
            print(params)
        }
        
        if Array(params.keys)[0] == "password" {
            self.debug ? print("comparing " + Array(params.values)[0] + " to " + self.password) : nil
            if Array(params.values)[0] == password {
                var already_in = false;
                for i in authenticated_addresses {
                    if i == address {
                        already_in = true
                    }
                }
                if !already_in {
                    authenticated_addresses.append(address)
                }
                return "true"
            } else {
                return "false"
            }
        }
        
        if !self.checkIfAuthenticated(ras: address) {
            return ""
        }
        
        var person = ""
        var num_texts = 0
        var offset = 0
        
        var chat_id = ""
        
        var sendBody = ""
        var sendAddress = ""
        
        let f = Array(params.keys)[0]
        var s = ""
        if params.count > 1 {
            s = Array(params.keys)[1]
        }
        var t = ""
        if params.count > 2 {
            t = Array(params.keys)[2]
        }
        if f == "person" || f == "num" || f == "offset" {
            
            person = f == "person" ? Array(params.values)[0] : (s == "person" ? Array(params.values)[1] : Array(params.values)[2])
            num_texts = ContentView.default_num_chats
            if f == "num" || s == "num" || t == "num" {
                num_texts = (f == "num" ? Int(Array(params.values)[0]) : (s == "num" ? Int(Array(params.values)[1]) : Int(Array(params.values)[2]))) ?? ContentView.default_num_chats
            }
            if f == "offset" || s == "offset" || t == "offset" {
                offset = (f == "offset" ? Int(Array(params.values)[0]) : (s == "offset" ? Int(Array(params.values)[1]) : Int(Array(params.values)[2]))) ?? 0
            }
            
            self.debug ? print("selecting person: " + person + ", num: " + String(num_texts)) : nil
            
            if person.contains("\"") { /// Just in case, I guess?
                person = person.replacingOccurrences(of: "\"", with: "")
            }
            let texts_array = loadMessages(num: person, num_items: num_texts, offset: offset)
            let texts = encodeToJson(object: texts_array, title: "texts")
            return texts
            
        } else if f == "chat" || f == "num_chats" {
            
            num_texts = ContentView.default_num_chats
            if f == "num_chats" || s == "num_chats" {
                num_texts = (f == "num_chats" ? Int(Array(params.values)[0]) : Int(Array(params.values)[1])) ?? ContentView.default_num_chats
            }
            
            let chats_array = loadChats(num_to_load: num_texts)
            let chats = encodeToJson(object: chats_array, title: "chats")
            DispatchQueue.main.async {
                self.setFirstTexts(address: address);
            }
            return chats
            
        } else if f == "name" {
            
            chat_id = Array(params.values)[0]
            
            let name = getDisplayName(chat_id: chat_id)
            return name
            
        } /*else if f == "image" {
            
            chat_id = Array(params.values)[0]
            let image_string = returnImageBase64(chat_id: chat_id)
            return image_string
            
        } */else if f == "send" || f == "to" {
            
            sendBody = f == "send" ?  Array(params.values)[0] : Array(params.values)[1]
            sendAddress = s == "to" ? Array(params.values)[1] : Array(params.values)[0]
            sendText(body: sendBody, address: [sendAddress])
            
        } else if f == "check" {
            
            let lt = encodeToJson(object: checkLatestTexts(address: address), title: "chat_ids")
            if self.debug  {
                print("lt:")
                print(lt)
            }
            return lt
            
        } else {
            self.debug ? print("We haven't implemented this functionality yet, sorry :/") : nil
        }
        
        return ""
    }
    
    func stopServer() {
        self.server.stop()
        self.debug ? print("Stopped server") : nil
        self.authenticated_addresses = [String]()
        server_running = server.isRunning
    }
    
    func sendText(body: String, address: [String]) {
        self.presentMessageCompose(body: body, address: address)
    }
    
    func createConnection(connection_string: String = "/private/var/mobile/Library/SMS/sms.db") -> OpaquePointer? {
        var db: OpaquePointer?
        let connection_url = URL(fileURLWithPath: connection_string)
        guard sqlite3_open(connection_url.path, &db) == SQLITE_OK else {
            print("WARNING: error opening database")
            sqlite3_close(db)
            db = nil
            return db
        }
        
        self.debug ? print("opened database") : nil
        
        return db
    }
    
    func selectFromSql(db: OpaquePointer?, columns: [String], table: String, condition: String = "", num_items: Int = 0, offset: Int = 0) -> [[String:String]] { /// Flawless.
        
        var sqlString = "SELECT "
        for i in columns {
            sqlString += i
            if i != columns[columns.count - 1] {
                sqlString += ", "
            }
        }
        sqlString += " from " + table
        if condition != "" {
            sqlString += " " + condition
        }
        if num_items != 0 {
            sqlString += " LIMIT \(offset), \(String(num_items))"
        }
        sqlString += ";"
        
        self.debug ? print("full sql query: " + sqlString) : nil
        
        var statement: OpaquePointer?
        
        self.debug ? print("opened statement") : nil
        
        if sqlite3_prepare_v2(db, sqlString, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("WARNING: error preparing select: \(errmsg)")
        }
        
        var main_return = [[String:String]]()
        
        if num_items != 0 {
            var i = 0
            while sqlite3_step(statement) == SQLITE_ROW && i < num_items {
                var minor_return = [String:String]()
                for j in 0..<columns.count {
                    var tiny_return = ""
                    if let tiny_return_cstring = sqlite3_column_text(statement, Int32(j)) {
                        tiny_return = String(cString: tiny_return_cstring)
                    } else {
                        print("WARNING: Nothing returned for tiny_return_cstring when num_items != 0")
                    }
                    minor_return[columns[j]] = tiny_return
                }
                main_return.append(minor_return)
                i += 1
            }
        } else {
            while sqlite3_step(statement) == SQLITE_ROW {
                var minor_return = [String:String]()
                for j in 0..<columns.count {
                    var tiny_return = ""
                    if let tiny_return_cstring = sqlite3_column_text(statement, Int32(j)) {
                        tiny_return = String(cString: tiny_return_cstring)
                    } else {
                        print("WARNING: Nothing returned for tiny_return_cstring when num_items != 0")
                    }
                    minor_return[columns[j]] = tiny_return
                }
                main_return.append(minor_return)
            }
        }
        
        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("WARNING: error finalizing prepared statement: \(errmsg)")
        }

        statement = nil
        
        self.debug ? print("destroyed statement") : nil
        
        return main_return
    }
    
    func selectFromSqlWithId(db: OpaquePointer?, columns: [String], table: String, identifier: String, condition: String = "", num_items: Int = 0) -> [String: [String:String]] { /// Flawless.
        
        var sqlString = "SELECT "
        for i in columns {
            sqlString += i
            if i != columns[columns.count - 1] {
                sqlString += ", "
            }
        }
        sqlString += " from " + table
        if condition != "" {
            sqlString += " " + condition
        }
        if num_items != 0 {
            sqlString += " LIMIT \(String(num_items))"
        }
        sqlString += ";"
        
        self.debug ? print("full sql query: " + sqlString) : nil
        
        var statement: OpaquePointer?
        
        self.debug ? print("opened statement") : nil
        
        if sqlite3_prepare_v2(db, sqlString, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("WARNING: error preparing select: \(errmsg)")
        }
        
        var main_return = [String: [String:String]]()
        
        if num_items != 0 {
            var i = 0
            while sqlite3_step(statement) == SQLITE_ROW && i < num_items {
                var minor_return = [String:String]()
                var minor_identifier = ""
                for j in 0..<columns.count {
                    var tiny_return = ""
                    if let tiny_return_cstring = sqlite3_column_text(statement, Int32(j)) {
                        tiny_return = String(cString: tiny_return_cstring)
                    } else {
                        print("WARNING: Nothing returned for tiny_return_cstring when num_items != 0")
                    }
                    minor_return[columns[j]] = tiny_return
                    if columns[j] == identifier {
                        minor_identifier = tiny_return
                    }
                }
                main_return[minor_identifier] = minor_return
                i += 1
            }
        } else {
            while sqlite3_step(statement) == SQLITE_ROW {
                var minor_return = [String:String]()
                var minor_identifier = ""
                for j in 0..<columns.count {
                    var tiny_return = ""
                    if let tiny_return_cstring = sqlite3_column_text(statement, Int32(j)) {
                        tiny_return = String(cString: tiny_return_cstring)
                    } else {
                        print("WARNING: Nothing returned for tiny_return_cstring when num_items == 0")
                    }
                    minor_return[columns[j]] = tiny_return
                    if columns[j] == identifier {
                        minor_identifier = tiny_return
                    }
                }
                main_return[minor_identifier] = minor_return
            }
        }
        
        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("WARNING: error finalizing prepared statement: \(errmsg)")
        }

        statement = nil
        
        self.debug ? print("destroyed statement") : nil
        
        return main_return
    }
    
    func parsePhoneNum(num: String) -> String {
        let new_num = num.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if new_num.count == 0 {
            return ""
        }
        if num.count <= 7 {
            let num_zero = new_num[new_num.startIndex ..< (new_num.index(new_num.startIndex, offsetBy: 3, limitedBy: new_num.endIndex) ?? new_num.endIndex)]
            let num_one = new_num[(new_num.index(new_num.startIndex, offsetBy: 3, limitedBy: new_num.endIndex) ?? new_num.endIndex) ..< new_num.endIndex]
            return num_zero + "_" + num_one
        } else {
            let num_zero = String(new_num[new_num.startIndex ..< (new_num.index(new_num.startIndex, offsetBy: (new_num.count - 10), limitedBy: new_num.endIndex) ?? new_num.endIndex)])
            let num_one = String(new_num[(new_num.index(new_num.startIndex, offsetBy: (new_num.count - 10), limitedBy: new_num.endIndex) ?? new_num.endIndex) ..< (new_num.index(new_num.startIndex, offsetBy: (new_num.count - 7), limitedBy: new_num.endIndex) ?? new_num.endIndex)])
            let num_two = String(new_num[(new_num.index(new_num.startIndex, offsetBy: (new_num.count - 7), limitedBy: new_num.endIndex) ?? new_num.endIndex) ..< (new_num.index(new_num.startIndex, offsetBy: (new_num.count - 4), limitedBy: new_num.endIndex) ?? new_num.endIndex)])
            let num_three = String(new_num[(new_num.index(new_num.startIndex, offsetBy: (new_num.count - 4), limitedBy: new_num.endIndex) ?? new_num.endIndex) ..< new_num.endIndex])
            return "%" + num_zero + "%" + num_one + "%" + num_two + "%" + num_three + "%"
        }
    }
    
    func getDisplayName(chat_id: String) -> String {
        var db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
        
        var display_name_array = [[String:String]]()
        
        if chat_id.contains("@") {
            display_name_array = selectFromSql(db: db, columns: ["c0First", "c1Last"], table: "ABPersonFullTextSearch_content", condition: "WHERE c17Email LIKE \"%\(chat_id)%\"")
        } else {
            let parsed_num = parsePhoneNum(num: chat_id)
            
            display_name_array = selectFromSql(db: db, columns: ["c0First", "c1Last"], table: "ABPersonFullTextSearch_content", condition: "WHERE c16Phone LIKE \"\(parsed_num)\"", num_items: 1)
            
        }
        
        if sqlite3_close(db) != SQLITE_OK {
            print("WARNING: error closing database")
        }

        db = nil
        
        self.debug ? print("destroyed db") : nil
        
        if display_name_array.count != 0 {
            let full_name: String = (display_name_array[0]["c0First"] ?? "no_first") + " " + (display_name_array[0]["c1Last"] ?? "no_last")
            return full_name
        }
        
        return ""
    }
    
    func getDisplayNameWithDb(db: OpaquePointer?, chat_id: String) -> String {
        
        var display_name_array = [[String:String]]()
        
        if chat_id.contains("@") {
            display_name_array = selectFromSql(db: db, columns: ["c0First", "c1Last"], table: "ABPersonFullTextSearch_content", condition: "WHERE c17Email LIKE \"%\(chat_id)%\"")
        } else {
            let parsed_num = parsePhoneNum(num: chat_id)
            display_name_array = selectFromSql(db: db, columns: ["c0First", "c1Last"], table: "ABPersonFullTextSearch_content", condition: "WHERE c16Phone LIKE \"\(parsed_num)\"", num_items: 1)
            
        }
        
        if display_name_array.count != 0 {
            let full_name: String = (display_name_array[0]["c0First"] ?? "no_first") + " " + (display_name_array[0]["c1Last"] ?? "no_last")
            return full_name
        }
        
        return ""
    }
    
    func loadMessages(num: String, num_items: Int = default_num_messages, offset: Int = 0) -> [[String:String]] {
        var db = createConnection()
        
        var messages = selectFromSql(db: db, columns: ["ROWID", "text", "is_from_me", "date", "service", "cache_has_attachments"], table: "message", condition: "WHERE ROWID IN (SELECT message_id FROM chat_message_join WHERE chat_id IN (SELECT ROWID from chat WHERE chat_identifier is \"\(num)\") ORDER BY message_date DESC) ORDER BY date DESC", num_items: num_items, offset: offset)
        
        messages = messages.reversed()
        
        for i in 0..<messages.count {
            if messages[i]["cache_has_attachments"] == "1" {
                let a = getAttachmentFromMessage(mid: messages[i]["ROWID"]!)
                var file_string = ""
                var type_string = ""
                for i in a {
                    file_string += i[0] + ":" /// Cause ':' can't exist in files in MacOS (I'm fairly certain?)
                    type_string += i[1] + ":"
                }
                messages[i]["attachment_file"] = file_string
                messages[i]["attachment_type"] = type_string
            }
        }
        
        if sqlite3_close(db) != SQLITE_OK {
            print("WARNING: error closing database")
        }

        db = nil
        
        self.debug ? print("destroyed db") : nil
        
        self.debug ? print("returning messages!") : nil
        return messages
    }
    
    func loadChats(num_to_load: Int = 0) -> [[String:String]] {
        var db = createConnection()
        var contacts_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
        var image_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBookImages.sqlitedb")
        
        let messages = selectFromSqlWithId(db: db, columns: ["ROWID", "is_read", "is_from_me", "text", "item_type", "is_empty"], table: "message", identifier: "ROWID", condition: "WHERE ROWID in (select message_id from chat_message_join where message_date in (select max(message_date) from chat_message_join group by chat_id) order by message_date desc)")
        let chat_ids_ordered = selectFromSql(db: db, columns: ["chat_id", "message_id"], table: "chat_message_join", condition: "where message_date in (select max(message_date) from chat_message_join group by chat_id) order by message_date desc LIMIT \(num_to_load)");
        let chats = selectFromSqlWithId(db: db, columns: ["ROWID", "chat_identifier", "display_name"], table: "chat", identifier: "ROWID", condition: "WHERE ROWID in (select chat_id from chat_message_join where message_date in (select max(message_date) from chat_message_join group by chat_id))")
        
        var chats_array = [[String:String]]()
        var already_selected = [String:Int]() /// Just making it a dictionary so I have O(1) access instead of iterating through, as with an array
        
        for i in chat_ids_ordered {
            if chats[i["chat_id"] ?? ""] == nil {
                continue
            }
            
            let ci = chats[i["chat_id"]!]!["chat_identifier"]
            
            if already_selected[ci!] != nil {
                continue;
            }
            
            var new_chat = chats[i["chat_id"]!]
            
            new_chat!["has_unread"] = "false"
            if messages[i["message_id"]!]!["is_from_me"] == "0" && messages[i["message_id"]!]!["is_read"] == "1" && messages[i["message_id"]!]!["text"] != nil && messages[i["message_id"]!]!["is_empty"] != "0" && messages[i["message_id"]!]!["item_type"] == "0" {
                new_chat!["has_unread"] = "true"
            }
            
            if new_chat?["display_name"]!.count == 0 {
                new_chat?["display_name"] = getDisplayNameWithDb(db: contacts_db, chat_id: ci ?? "")
            }
            
            //new_chat?["image_text"] = returnImageBase64DB(chat_id: ci ?? "", contact_db: contacts_db!, image_db: image_db!)
            
            chats_array.append(new_chat!)
            already_selected[ci!] = 0
        }
        
        if sqlite3_close(image_db) != SQLITE_OK {
            print("WARNING: error closing image db")
        }
        
        image_db = nil
        
        if sqlite3_close(contacts_db) != SQLITE_OK {
            print("WARNING: error closing database")
        }

        contacts_db = nil
        
        if sqlite3_close(db) != SQLITE_OK {
            print("WARNING: error closing database")
        }

        db = nil
        
        self.debug ? print("destroyed db") : nil
        
        return chats_array
    }
    
    /*func returnImageBase64(chat_id: String) -> String {
        var contact_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
        var image_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBookImages.sqlitedb")
        
        var return_val = returnImageBase64DB(chat_id: chat_id, contact_db: contact_db!, image_db: image_db!)
        
        if sqlite3_close(contact_db) != SQLITE_OK {
            print("WARNING: error closing database")
        }

        contact_db = nil
        
        if sqlite3_close(image_db) != SQLITE_OK {
            print("WARNING: error closing database")
        }

        image_db = nil
        
        return return_val /// So uh it should be a base64 encoded string?
    }
    
    func returnImageBase64DB(chat_id: String, contact_db: OpaquePointer, image_db: OpaquePointer) -> String {
        
        var docid = [[String:String]]()
        
        if chat_id.contains("@") {
            docid = selectFromSql(db: contact_db, columns: ["docid"], table: "ABPersonFullTextSearch_content", condition: "WHERE c17Email LIKE \"%\(chat_id)%\"", num_items: 1)
        } else {
            let parsed_num = parsePhoneNum(num: chat_id)
            docid = selectFromSql(db: contact_db, columns: ["docid"], table: "ABPersonFullTextSearch_content", condition: "WHERE c16Phone LIKE \"\(parsed_num)\"", num_items: 1)
        }
        
        if docid.count == 0 {
            
            let image_dat = UIImage(named: "profile")
            let pngdata = image_dat?.pngData()
            let image = pngdata!.base64EncodedString(options: .lineLength64Characters)
            
            return image
        }
            
        let sqlString = "SELECT data FROM ABThumbnailImage WHERE record_id=\"\(String(describing: docid[0]["docid"]!))\""
        
        var image: String = ""
        
        var statement: OpaquePointer?
        
        self.debug ? print("opened statement") : nil
        
        if sqlite3_prepare_v2(image_db, sqlString, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(image_db)!)
            print("WARNING: error preparing select: \(errmsg)")
        }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            if let tiny_return_blob = sqlite3_column_blob(statement, 0) {
                let len: Int32 = sqlite3_column_bytes(statement, 0)
                let dat: NSData = NSData(bytes: tiny_return_blob, length: Int(len))
                
                let image_w_dat = UIImage(data: Data(dat))
                let pngdata = image_w_dat?.pngData()
                image = pngdata!.base64EncodedString(options: .lineLength64Characters)
                
            } else {
                print("WARNING: Nothing returned for tiny_return_cstring when num_items != 0. Using default.")
                let image_dat = UIImage(named: "profile")
                let pngdata = image_dat?.pngData()
                image = pngdata!.base64EncodedString(options: .lineLength64Characters)
            }
        } else {
            let image_dat = UIImage(named: "profile")
            let pngdata = image_dat?.pngData()
            image = pngdata!.base64EncodedString(options: .lineLength64Characters)
        }
        
        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(image_db)!)
            print("WARNING: error finalizing prepared statement: \(errmsg)")
        }

        statement = nil
        
        self.debug ? print("destroyed statement") : nil
        
        return image /// So uh it should be a base64 encoded string?
    }*/
    
    func returnImageData(chat_id: String) -> Data {
        var contact_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb")
        var image_db = createConnection(connection_string: "/private/var/mobile/Library/AddressBook/AddressBookImages.sqlitedb")
        
        let return_val = returnImageDataDB(chat_id: chat_id, contact_db: contact_db!, image_db: image_db!)
        
        if sqlite3_close(contact_db) != SQLITE_OK {
            print("WARNING: error closing database")
        }

        contact_db = nil
        
        if sqlite3_close(image_db) != SQLITE_OK {
            print("WARNING: error closing database")
        }

        image_db = nil
        
        return return_val /// So uh it should be a base64 encoded string?
    }
    
    func returnImageDataDB(chat_id: String, contact_db: OpaquePointer, image_db: OpaquePointer) -> Data {
        
        var docid = [[String:String]]()
        
        if chat_id.contains("@") {
            docid = selectFromSql(db: contact_db, columns: ["docid"], table: "ABPersonFullTextSearch_content", condition: "WHERE c17Email LIKE \"%\(chat_id)%\"", num_items: 1)
        } else {
            let parsed_num = parsePhoneNum(num: chat_id)
            docid = selectFromSql(db: contact_db, columns: ["docid"], table: "ABPersonFullTextSearch_content", condition: "WHERE c16Phone LIKE \"\(parsed_num)\"", num_items: 1)
        }
        
        if docid.count == 0 {
            
            let image_dat = UIImage(named: "profile")
            let pngdata = (image_dat?.pngData())!
            //let image = pngdata!.base64EncodedString(options: .lineLength64Characters)
            
            //return image
            return pngdata
        }
            
        let sqlString = "SELECT data FROM ABThumbnailImage WHERE record_id=\"\(String(describing: docid[0]["docid"]!))\""
        
        //var image: String = ""
        
        var statement: OpaquePointer?
        
        self.debug ? print("opened statement") : nil
        
        if sqlite3_prepare_v2(image_db, sqlString, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(image_db)!)
            print("WARNING: error preparing select: \(errmsg)")
        }
        
        var pngdata: Data;
        
        if sqlite3_step(statement) == SQLITE_ROW {
            if let tiny_return_blob = sqlite3_column_blob(statement, 0) {
                let len: Int32 = sqlite3_column_bytes(statement, 0)
                let dat: NSData = NSData(bytes: tiny_return_blob, length: Int(len))
                
                let image_w_dat = UIImage(data: Data(dat))
                pngdata = (image_w_dat?.pngData())!
                //image = pngdata!.base64EncodedString(options: .lineLength64Characters)
                
            } else {
                print("WARNING: Nothing returned for tiny_return_cstring when num_items != 0. Using default.")
                let image_dat = UIImage(named: "profile")
                pngdata = (image_dat?.pngData())!
                //image = pngdata!.base64EncodedString(options: .lineLength64Characters)
            }
        } else {
            let image_dat = UIImage(named: "profile")
            pngdata = (image_dat?.pngData())!
            //image = pngdata!.base64EncodedString(options: .lineLength64Characters)
        }
        
        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(image_db)!)
            print("WARNING: error finalizing prepared statement: \(errmsg)")
        }

        statement = nil
        
        self.debug ? print("destroyed statement") : nil
        
        //return image /// So uh it should be a base64 encoded string?
        return pngdata
    }
    
    func setFirstTexts(address: String) {
        past_latest_texts[address] = getLatestTexts();
    }
    
    func checkLatestTexts(address: String) -> [String] {
        self.debug ? print("Ran checkLatestTexts(\(address))") : nil
        var db = createConnection()
        let latest_texts = getLatestTexts()
        let ap_latest_texts = past_latest_texts[address]
        if latest_texts == ap_latest_texts {
            self.debug ? print("They're identical.") : nil
            return [] /// If they haven't received any new messages, just return nothing
        }
        
        if ap_latest_texts == nil {
            self.debug ? print("Haven't pinged before") : nil
            let string = selectFromSql(db: db, columns: ["chat_identifier"], table: "chat")
            var ret = [String]()
            for i in 0..<string.count {
                ret.append(string[i]["chat_identifier"] ?? "chat_identifier not found")
            }
            return ret
        }
        
        var new_texts: [String] = [] /// Will just contain a list of all the chats that have new messages since they've last checked
        
        for i in Array(latest_texts.keys) {
            self.debug ? print("checking between \(String(describing: ap_latest_texts?[i]?["text"])) and \(String(describing: latest_texts[i]?["text"]))") : nil
            if latest_texts[i] != ap_latest_texts?[i] {
                if let check_message_id = latest_texts[i]?["ROWID"] {
                    let append_num = selectFromSql(db: db, columns: ["chat_identifier"], table: "chat", condition: "where ROWID in (select chat_id from chat_message_join where message_id is \(check_message_id))")
                    
                    new_texts.append(append_num[0]["chat_identifier"] ?? "")
                }
            }
        }
        
        if sqlite3_close(db) != SQLITE_OK {
            print("WARNING: error closing database")
        }
        
        db = nil
        
        if self.debug {
            print("new texts:")
            print(new_texts)
        }
        
        past_latest_texts[address] = latest_texts
        
        return new_texts;
    }
    
    func getLatestTexts() -> [String: [String:String]] {
        var db = createConnection()
        
        let latest_texts = selectFromSqlWithId(db: db, columns: ["ROWID", "text", "date_read"], table: "message", identifier: "ROWID", condition: "WHERE ROWID in (select message_id from chat_message_join where message_date in (select max(message_date) from chat_message_join group by chat_id) order by message_date desc)" )
        
        if self.debug {
            print("Latest texts:")
            print(latest_texts)
        }
        
        if sqlite3_close(db) != SQLITE_OK {
            print("WARNING: error closing database")
        }
        
        db = nil
        
        return latest_texts
    }
    
    func getAttachmentFromMessage(mid: String) -> [[String]] { /// So this will just return the partial file name/path & mime_type
        let db = createConnection()
        let file = selectFromSql(db: db, columns: ["filename", "mime_type", "hide_attachment"], table: "attachment", condition: "WHERE ROWID in (SELECT attachment_id from message_attachment_join WHERE message_id is \(mid))")
        
        var return_val = [[String]]()
        
        if file.count > 0 {
            for i in file {
                //var suffixed = String(i["filename"]?.dropFirst(imageStoragePrefix.count - FileManager.default.homeDirectoryForCurrentUser.path.count + 1) ?? "")
                var suffixed = String(i["filename"]?.dropFirst(ContentView.imageStoragePrefix.count - ContentView.userHomeString.count + 2) ?? "")
                suffixed = suffixed.replacingOccurrences(of: "/", with: "._.")
                let type = i["mime_type"] ?? ""
                return_val.append([suffixed, type])
            }
        }
        
        return return_val
    }
    
    func getAttachmentDataFromPath(path: String) -> Data {
        let parsed_path = path.replacingOccurrences(of: "._.", with: "/")
        
        do {
            let attachment_data = try Data.init(contentsOf: URL(fileURLWithPath: ContentView.imageStoragePrefix + parsed_path))
            return attachment_data
        } catch {
            print("WARNING: failed to load image for path \(ContentView.imageStoragePrefix + path)")
            return Data.init(capacity: 0)
        }
    }
    
    func checkIfLatestTexts() -> [[String:String]] {
        return [[String:String]]()
    }
    
    func loadBundle() {
        
    }
    
    func getWiFiAddress() -> String? {
        var address : String?

        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

                // Check interface name:
                let name = String(cString: interface.ifa_name)
                if  name == "en0" {

                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)

        return address
    }
    
    func sendAttachment() {
        
    }
    
    func displaySettings() {
        
    }
    
    var body: some View {
        NavigationView {
                VStack {
                    Text("Visit \(self.getWiFiAddress() ?? "your phone's private IP, port "):\(self.egnum) in your browser to view your messages")
                        .font(Font.custom("smallTitle", size: 22))
                        .padding()
                
                    Spacer().frame(height: 20)
                    
                    HStack {
                        VStack {
                            HStack {
                                Text("Change default port").font(.subheadline)
                                Spacer()
                            }
                            
                            TextField("Change default server port", text: $egnum)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Spacer().frame(height: 20)
                            
                            HStack {
                                Text("Change password").font(.subheadline)
                                Spacer()
                            }
                            
                            TextField("Change requests password", text: $password)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                            Spacer().frame(height: 20)
                                
                            HStack {
                                Text("Change main chats url").font(.subheadline)
                                Spacer()
                            }
                                
                            TextField("Change main chats url", text: $main_url)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }.padding()
                    
                    Spacer()
                    
                    HStack {
                        
                        HStack {
                            
                            Button(action: {
                                self.loadFiles()
                            }) {
                                Image(systemName: "goforward")
                                    .scaleEffect(1.5)
                                    .foregroundColor(Color.purple)
                            }
                            
                            Spacer().frame(width: 30)
                            
                            Button(action: {
                                self.server_running ? self.stopServer() : nil
                            }) {
                                Image(systemName: "stop.fill")
                                    .scaleEffect(1.5)
                                    .foregroundColor(self.server_running ? Color.red : Color.gray)
                            }
                            
                            Spacer().frame(width: 30)
                            
                            Button(action: {
                                self.server_running ? nil : self.loadServer(port_num: UInt16(self.egnum)!)
                            }) {
                                Image(systemName: "play.fill")
                                    .scaleEffect(1.5)
                                    .foregroundColor(self.server_running ? Color.gray : Color.green)
                            }
                            
                        }
                        .padding(10)
                        
                        Spacer()
                        
                        HStack {
                            Button(action: {
                                self.displaySettings()
                            }) {
                                Image(systemName: "gear")
                                    .scaleEffect(1.5)
                            }
                        }.padding(10)
                    }
                    .padding()
                    
                }.navigationBarTitle(Text("SMServer").font(.largeTitle))
            
        }
        .onAppear() {
            self.loadFiles()
        }
    }
}

extension ContentView {

    private class MessageComposerDelegate: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            // Customize here
            controller.dismiss(animated: true)
        }
    }
    /// Present an message compose view controller modally in UIKit environment
    private func presentMessageCompose(body: String, address: [String]) {
        guard MFMessageComposeViewController.canSendText() else {
            return
        }
        DispatchQueue.main.async {
            let vc = UIApplication.shared.windows.filter {$0.isKeyWindow}.first?.rootViewController
            let composeVC = MFMessageComposeViewController()
            composeVC.body = body
            composeVC.recipients = address
            
            composeVC.messageComposeDelegate = self.messageComposeDelegate
            vc?.present(composeVC, animated: true)
        }
    }
    
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

/// In case I still ever need these
/*enum dbprop_types {
       case int
       case text
       case null
       case blob
   }
   
   class dbprop {
       init(data: String, type: dbprop_types, num: Int) {
           self.data = data
           self.type = type
           self.num = num
       }
       var data: String
       var type: dbprop_types //will be an enum
       var num: Int
   }
   
   class chat_dbprops {
       var ROWID = dbprop(data: "ROWID", type: dbprop_types.int, num: 0)
       var guid = dbprop(data: "guid", type: dbprop_types.text, num: 1)
       var style = dbprop(data: "style", type: dbprop_types.int, num: 2)
       var state = dbprop(data: "state", type: dbprop_types.int, num: 3)
       var account_id = dbprop(data: "account_id", type: dbprop_types.text, num: 4)
       var properties = dbprop(data: "properties", type: dbprop_types.blob, num: 5)
       var chat_identifier = dbprop(data: "chat_identifier", type: dbprop_types.text, num: 6)
       var service_name = dbprop(data: "service_name", type: dbprop_types.text, num: 7)
       var room_name = dbprop(data: "room_name", type: dbprop_types.text, num: 8)
       var account_login = dbprop(data: "account_login", type: dbprop_types.text, num: 9)
       var is_archived = dbprop(data: "is_archived", type: dbprop_types.int, num: 10)
       var last_addressed_handle = dbprop(data: "last_addressed_handle", type: dbprop_types.text, num: 11)
       var display_name = dbprop(data: "display_name", type: dbprop_types.text, num: 12)
       var group_id = dbprop(data: "group_id", type: dbprop_types.text, num: 13)
       var is_filtered = dbprop(data: "is_filtered", type: dbprop_types.int, num: 14)
       var successful_query = dbprop(data: "successful_query", type: dbprop_types.int, num: 15)
       var engram_id = dbprop(data: "engram_id", type: dbprop_types.null, num: 16)
       var server_change_token = dbprop(data: "server_change_token", type: dbprop_types.text, num: 17)
       var ck_sync_state = dbprop(data: "ck_sync_state", type: dbprop_types.int, num: 18)
       var last_read_message_timestamp = dbprop(data: "last_read_message_timestamp", type: dbprop_types.int, num: 19)
       var ck_record_system_property_blob = dbprop(data: "ck_record_system_property_blob", type: dbprop_types.null, num: 20)
       var original_group_id = dbprop(data: "original_group_id", type: dbprop_types.text, num: 21)
       var sr_server_change_token = dbprop(data: "sr_server_change_token", type: dbprop_types.null, num: 22)
       var sr_ck_sync_state = dbprop(data: "sr_ck_sync_state", type: dbprop_types.int, num: 23)
       var sr_ck_record_system_property_blob = dbprop(data: "sr_ck_record_system_property", type: dbprop_types.null, num: 24)
       var cloudkit_record_id = dbprop(data: "cloudkit_record_id", type: dbprop_types.text, num: 25)
       var sr_cloudkit_record_id = dbprop(data: "sr_cloudkit_record_id", type: dbprop_types.null, num: 26)
       var last_addressed_sim_id = dbprop(data: "last_addressed_sim_id", type: dbprop_types.text, num: 27)
       var is_blackholed = dbprop(data: "is_blackholed", type: dbprop_types.int, num: 28)
       var num_items = 29
       subscript(index: Int) -> dbprop {
           let items = [ROWID, guid, style, state, account_id, properties, chat_identifier, service_name, room_name, account_login, is_archived, last_addressed_handle, display_name, group_id, is_filtered, successful_query, engram_id, server_change_token, ck_sync_state, last_read_message_timestamp, ck_record_system_property_blob, original_group_id, sr_server_change_token, sr_ck_sync_state, sr_ck_record_system_property_blob, cloudkit_record_id, sr_cloudkit_record_id, last_addressed_sim_id, is_blackholed]
           return items[index]
       }
   }
   
   class message_dbprops {
       var ROWID = dbprop(data: "ROWID", type: dbprop_types.int, num: 0)
       var guid = dbprop(data: "guid", type: dbprop_types.text, num: 1)
       var text = dbprop(data: "text", type: dbprop_types.text, num: 2)
       var replace = dbprop(data: "replace", type: dbprop_types.int, num: 3)
       var service_center = dbprop(data: "service_center", type: dbprop_types.null, num: 4)
       var handle_id = dbprop(data: "handle_id", type: dbprop_types.int, num: 5)
       var subject = dbprop(data: "subject", type: dbprop_types.text, num: 6)
       var country = dbprop(data: "country", type: dbprop_types.null, num: 7)
       var attributedBody = dbprop(data: "attributedBody", type: dbprop_types.blob, num: 8)
       var version = dbprop(data: "version", type: dbprop_types.int, num: 9)
       var type = dbprop(data: "type", type: dbprop_types.int, num: 10)
       var service = dbprop(data: "service", type: dbprop_types.text, num: 11)
       var account = dbprop(data: "account", type: dbprop_types.text, num: 12)
       var account_guid = dbprop(data: "account_guid", type: dbprop_types.text, num: 13)
       var error = dbprop(data: "error", type: dbprop_types.int, num: 14)
       var date = dbprop(data: "date", type: dbprop_types.text, num: 15)
       var date_read = dbprop(data: "date_read", type: dbprop_types.text, num: 16)
       var date_delivered = dbprop(data: "date_delivered", type: dbprop_types.text, num: 17)
       var is_delivered = dbprop(data: "is_delivered", type: dbprop_types.int, num: 18)
       var is_from_me = dbprop(data: "is_from_me", type: dbprop_types.int, num: 21)
       var cache_roomnames = dbprop(data: "cache_roomnames", type: dbprop_types.text, num: 35)
       var is_audio_message = dbprop(data: "is_audio_message", type: dbprop_types.int, num: 38)
       var is_played = dbprop(data: "is_played", type: dbprop_types.int, num: 39) // Only applies to audio messages
       var group_title = dbprop(data: "group_title", type: dbprop_types.text, num: 43)
       var associated_message_guid = dbprop(data: "associated_message_guid", type: dbprop_types.text, num: 51)
       var destination_caller_id = dbprop(data: "destination_caller_id", type: dbprop_types.text, num: 63)
       var num_items: Int = 26 //Just how many other dbprop items are here
       subscript(index: Int) -> dbprop {
           let total_items = [ROWID, guid, text, replace, service_center, handle_id, subject, country, attributedBody, version, type, service, account, account_guid, error, date, date_read, date_delivered, is_delivered, is_from_me, cache_roomnames, is_audio_message, is_played, group_title, associated_message_guid, destination_caller_id]
           return total_items[index]
       }
       
   }*/

/*struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}*/
