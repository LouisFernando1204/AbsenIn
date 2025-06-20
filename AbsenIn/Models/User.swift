//
//  User.swift
//  AbsenIn
//
//  Created by Hayya U on 18/06/25.
//

import Foundation
import SwiftData
import Vision

@Model
final class User {
    @Attribute(.unique) var id: String
    var name: String
    var registrationDate: Date
    
    @Attribute(.externalStorage)
    var faceprintData: Data?
    
    @Attribute(.externalStorage)
    var faceLandmarksData: Data?
    
    init(id: String = UUID().uuidString, name: String, registrationDate: Date = .now, faceprintData: Data? = nil, faceLandmarksData: Data? = nil) {
        self.id = id
        self.name = name
        self.registrationDate = registrationDate
        self.faceprintData = faceprintData
        self.faceLandmarksData = faceLandmarksData
    }
}
