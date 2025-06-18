//
//  AppModels.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import Foundation
import SwiftData

// Model untuk menyimpan data pengguna dan faceprint-nya
@Model
final class User {
    @Attribute(.unique) var id: String // ID unik, bisa pakai UUID().uuidString
    var name: String
    var registrationDate: Date
    
    // Faceprint (fitur wajah) disimpan dalam bentuk Data.
    // Vision framework menghasilkan VNFaceFeaturePrintObservation yang bisa di-archive.
    @Attribute(.externalStorage) // Direkomendasikan untuk data besar
    var faceprintData: Data?

    init(id: String = UUID().uuidString, name: String, registrationDate: Date = .now, faceprintData: Data? = nil) {
        self.id = id
        self.name = name
        self.registrationDate = registrationDate
        self.faceprintData = faceprintData
    }
}

// Model untuk mencatat setiap kali presensi berhasil
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
