import Foundation

struct FacialVector: Codable {
    let values: [Float]
    
    func euclideanDistance(to other: FacialVector) -> Float {
        guard values.count == other.values.count else { return .greatestFiniteMagnitude }
        let sum = zip(values, other.values).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)
        return sqrt(sum)
    }
    
    func cosineDistance(to other: FacialVector) -> Float {
        guard values.count == other.values.count else { return 2.0 } // Return max distance
        let dotProduct = zip(values, other.values).map(*).reduce(0, +)
        let normA = sqrt(values.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(other.values.map { $0 * $0 }.reduce(0, +))
        guard normA > 0 && normB > 0 else { return 2.0 }
        let cosineSimilarity = dotProduct / (normA * normB)
        // Distance is 1 - similarity. The range is [0, 2].
        return 1.0 - cosineSimilarity
    }
}
