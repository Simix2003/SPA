import SwiftData
import Foundation
import SwiftUI


enum RoundingRule: String, Codable, CaseIterable {
    case off, nearest5, nearest15, nearest30
}

enum SessionState: String, Codable, CaseIterable {
    case open, closed
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String                 // ← no .spotlight
    var code: String?
    var colorHex: String?
    var geofenceLat: Double?
    var geofenceLon: Double?
    var geofenceRadius: Double?
    var hourlyRate: Decimal?         // ← no .spotlight

    var createdAt: Date
    var updatedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class WorkSession {
    @Attribute(.unique) var id: UUID
    var start: Date                  // ← no .indexed
    var end: Date?
    var breakMinutes: Int
    var note: String?

    var project: Project?
    var rounding: RoundingRule
    var state: SessionState

    var overrideHourlyRate: Decimal?

    var createdAt: Date
    var updatedAt: Date

    init(start: Date, project: Project? = nil, rounding: RoundingRule = .off) {
        self.id = UUID()
        self.start = start
        self.end = nil
        self.breakMinutes = 0
        self.note = nil
        self.project = project
        self.rounding = rounding
        self.state = .open
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
