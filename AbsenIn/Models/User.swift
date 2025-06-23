import Foundation
import SwiftData
import Vision

@Model
final class User {
    @Attribute(.unique) var id: String
    var name: String
    var registrationDate: Date
    
    @Attribute(.externalStorage)
    var facialVectorData: Data?
    
    init(id: String = UUID().uuidString, name: String, registrationDate: Date = .now, facialVectorData: Data? = nil) {
        self.id = id
        self.name = name
        self.registrationDate = registrationDate
        self.facialVectorData = facialVectorData
    }
}
