import SwiftData
import Foundation
import SwiftUI

// MARK: - Enums
enum RoundingRule: String, Codable, CaseIterable {
    case off, nearest5, nearest15, nearest30
}

enum SessionState: String, Codable, CaseIterable {
    case open, closed
}

// MARK: - Models
@Model
final class Project {
    // CloudKit: no unique constraints; provide defaults for non-optional
    var id: UUID = UUID()
    var name: String = ""
    var code: String?
    var colorHex: String?
    var geofenceLat: Double?
    var geofenceLon: Double?
    var geofenceRadius: Double?
    var hourlyRate: Decimal?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Inverse relationship required for CloudKit integration
    @Relationship(inverse: \WorkSession.project)
    var sessions: [WorkSession]?

    init(name: String) {
        self.name = name
    }
}

@Model
final class WorkSession {
    // CloudKit: defaults for all non-optional attributes
    var id: UUID = UUID()
    var start: Date = Date()
    var end: Date?
    var breakMinutes: Int = 0
    var note: String?

    // Relationship (inverse declared in Project)
    @Relationship
    var project: Project?

    var rounding: RoundingRule = RoundingRule.off
    var state: SessionState = SessionState.open

    var overrideHourlyRate: Decimal?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(start: Date, project: Project? = nil, rounding: RoundingRule = .off) {
        self.start = start
        self.project = project
        self.rounding = rounding
    }
}
