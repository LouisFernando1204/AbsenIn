import Foundation
import SwiftData

@Model
final class AttendanceRecord {
    var userID: String; var userName: String; var timestamp: Date
    init(userID: String, userName: String, timestamp: Date = .now) {
        self.userID = userID; self.userName = userName; self.timestamp = timestamp
    }
}
