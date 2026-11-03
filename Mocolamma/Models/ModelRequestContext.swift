import Foundation

struct ModelRequestContext: Hashable, Sendable {
    let serverID: UUID?
    let host: String?
    let revision: UUID
}

struct ModelDetailRequest: Hashable {
    let context: ModelRequestContext
    let modelName: String
    let cacheRevision: UUID
}
