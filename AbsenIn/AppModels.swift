//
//  AppModels.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import Foundation
import SwiftData
import UIKit

@Model
final class User {
    @Attribute(.unique) var id: String
    var name: String
    var registrationDate: Date
    
    // PERBAIKAN: Data ini sekarang akan menyimpan array [VNFeaturePrintObservation]
    // yang di-archive. Ini membuat model pengenalan lebih kuat.
    @Attribute(.externalStorage)
    var faceprintData: Data?
    
    init(id: String = UUID().uuidString, name: String, registrationDate: Date = .now, faceprintData: Data? = nil) {
        self.id = id
        self.name = name
        self.registrationDate = registrationDate
        self.faceprintData = faceprintData
    }
}

@Model
final class AttendanceRecord {
    var userID: String
    var userName: String
    var timestamp: Date
    
    init(userID: String, userName: String, timestamp: Date = .now) {
        self.userID = userID
        self.userName = userName
        self.timestamp = timestamp
    }
}
