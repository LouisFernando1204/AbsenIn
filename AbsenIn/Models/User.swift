import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: String
    var name: String
    @Attribute(.externalStorage) var facialEmbeddingData: Data?
    init(id: String = UUID().uuidString, name: String, facialEmbeddingData: Data? = nil) {
        self.id = id; self.name = name; self.facialEmbeddingData = facialEmbeddingData
    }
    func getEmbedding() -> FacialVector? {
        guard let data = facialEmbeddingData else { return nil }
        return try? JSONDecoder().decode(FacialVector.self, from: data)
    }
}
