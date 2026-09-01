import Foundation
import os

enum Log {
    static let net = Logger(subsystem: "com.nobilva.app", category: "net")
    static let auth = Logger(subsystem: "com.nobilva.app", category: "auth")
    static let ui = Logger(subsystem: "com.nobilva.app", category: "ui")
}
