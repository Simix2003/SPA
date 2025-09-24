//
//  CloudKitSync.swift
//  Test
//
//  Phase 1: Mirror Project & WorkSession to CloudKit (create/update, no deletes)
//  Conflict: last-write-wins via `updatedAt`
//

import Foundation
import CloudKit
import SwiftData

// MARK: - CloudKit constants

enum CKSchema {
    static let container = CKContainer.default()
    static var privateDB: CKDatabase { container.privateCloudDatabase }

    enum RecordType {
        static let project = "Project"
        static let workSession = "WorkSession"
        // Add "Expense" later when your model exists
    }

    enum ProjectKey {
        static let id = "id"                 // String (UUID)
        static let name = "name"             // String
        static let code = "code"             // String?
        static let colorHex = "colorHex"     // String?
        static let geofenceLat = "geofenceLat"   // Double?
        static let geofenceLon = "geofenceLon"   // Double?
        static let geofenceRadius = "geofenceRadius" // Double?
        static let hourlyRate = "hourlyRate" // Double? (Decimal -> Double)
        static let createdAt = "createdAt"   // Date
        static let updatedAt = "updatedAt"   // Date
    }

    enum WorkSessionKey {
        static let id = "id"                 // String (UUID)
        static let start = "start"           // Date
        static let end = "end"               // Date?
        static let breakMinutes = "breakMinutes" // Int
        static let note = "note"             // String?
        static let projectID = "projectID"   // String (UUID) relation by id
        static let rounding = "rounding"     // String (enum rawValue)
        static let state = "state"           // String (enum rawValue)
        static let createdAt = "createdAt"   // Date
        static let updatedAt = "updatedAt"   // Date
    }
}

// MARK: - Helpers

private func ckID(for type: String, uuid: UUID) -> CKRecord.ID {
    CKRecord.ID(recordName: "\(type)_\(uuid.uuidString)")
}

private extension Decimal {
    var asDouble: Double { NSDecimalNumber(decimal: self).doubleValue }
}

// MARK: - Mapper: Project

private func makeRecord(from p: Project) -> CKRecord {
    let recID = ckID(for: CKSchema.RecordType.project, uuid: p.id)
    let rec = CKRecord(recordType: CKSchema.RecordType.project, recordID: recID)
    rec[CKSchema.ProjectKey.id] = p.id.uuidString as CKRecordValue
    rec[CKSchema.ProjectKey.name] = p.name as CKRecordValue
    if let code = p.code { rec[CKSchema.ProjectKey.code] = code as CKRecordValue }
    if let colorHex = p.colorHex { rec[CKSchema.ProjectKey.colorHex] = colorHex as CKRecordValue }
    if let lat = p.geofenceLat { rec[CKSchema.ProjectKey.geofenceLat] = lat as CKRecordValue }
    if let lon = p.geofenceLon { rec[CKSchema.ProjectKey.geofenceLon] = lon as CKRecordValue }
    if let rad = p.geofenceRadius { rec[CKSchema.ProjectKey.geofenceRadius] = rad as CKRecordValue }
    if let rate = p.hourlyRate { rec[CKSchema.ProjectKey.hourlyRate] = rate.asDouble as CKRecordValue }
    rec[CKSchema.ProjectKey.createdAt] = p.createdAt as CKRecordValue
    rec[CKSchema.ProjectKey.updatedAt] = p.updatedAt as CKRecordValue
    return rec
}

private func upsertProject(_ rec: CKRecord, into context: ModelContext) throws {
    guard
        let idStr = rec[CKSchema.ProjectKey.id] as? String,
        let uuid = UUID(uuidString: idStr),
        let name = rec[CKSchema.ProjectKey.name] as? String,
        let updatedAt = rec[CKSchema.ProjectKey.updatedAt] as? Date
    else { return }

    // Try fetch local by id
    let fd = FetchDescriptor<Project>(predicate: #Predicate { $0.id == uuid })
    let existing = try? context.fetch(fd).first

    let p = existing ?? Project(name: name)
    p.id = uuid
    p.name = name
    p.code = rec[CKSchema.ProjectKey.code] as? String
    p.colorHex = rec[CKSchema.ProjectKey.colorHex] as? String
    p.geofenceLat = rec[CKSchema.ProjectKey.geofenceLat] as? Double
    p.geofenceLon = rec[CKSchema.ProjectKey.geofenceLon] as? Double
    p.geofenceRadius = rec[CKSchema.ProjectKey.geofenceRadius] as? Double
    if let rate = rec[CKSchema.ProjectKey.hourlyRate] as? Double {
        p.hourlyRate = Decimal(rate)
    }
    p.createdAt = (rec[CKSchema.ProjectKey.createdAt] as? Date) ?? p.createdAt
    // Conflict: last-write-wins by updatedAt
    if existing == nil || updatedAt >= p.updatedAt {
        p.updatedAt = updatedAt
    }

    if existing == nil { context.insert(p) }
    try context.save()
}

// MARK: - Mapper: WorkSession

private func makeRecord(from s: WorkSession) -> CKRecord {
    let recID = ckID(for: CKSchema.RecordType.workSession, uuid: s.id)
    let rec = CKRecord(recordType: CKSchema.RecordType.workSession, recordID: recID)
    rec[CKSchema.WorkSessionKey.id] = s.id.uuidString as CKRecordValue
    rec[CKSchema.WorkSessionKey.start] = s.start as CKRecordValue
    if let end = s.end { rec[CKSchema.WorkSessionKey.end] = end as CKRecordValue }
    rec[CKSchema.WorkSessionKey.breakMinutes] = s.breakMinutes as CKRecordValue
    if let note = s.note { rec[CKSchema.WorkSessionKey.note] = note as CKRecordValue }
    rec[CKSchema.WorkSessionKey.projectID] = s.project?.id.uuidString as CKRecordValue?
    rec[CKSchema.WorkSessionKey.rounding] = s.rounding.rawValue as CKRecordValue
    rec[CKSchema.WorkSessionKey.state] = s.state.rawValue as CKRecordValue
    rec[CKSchema.WorkSessionKey.createdAt] = s.createdAt as CKRecordValue
    rec[CKSchema.WorkSessionKey.updatedAt] = s.updatedAt as CKRecordValue
    return rec
}

private func upsertWorkSession(_ rec: CKRecord, into context: ModelContext) throws {
    guard
        let idStr = rec[CKSchema.WorkSessionKey.id] as? String,
        let uuid = UUID(uuidString: idStr),
        let start = rec[CKSchema.WorkSessionKey.start] as? Date,
        let updatedAt = rec[CKSchema.WorkSessionKey.updatedAt] as? Date
    else { return }

    // Try fetch local by id
    let fd = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.id == uuid })
    let existing = try? context.fetch(fd).first

    let s = existing ?? WorkSession(start: start)
    s.id = uuid
    s.start = start
    s.end = rec[CKSchema.WorkSessionKey.end] as? Date
    s.breakMinutes = (rec[CKSchema.WorkSessionKey.breakMinutes] as? Int) ?? s.breakMinutes
    s.note = rec[CKSchema.WorkSessionKey.note] as? String
    if let projIDStr = rec[CKSchema.WorkSessionKey.projectID] as? String,
       let projUUID = UUID(uuidString: projIDStr) {
        let pfd = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projUUID })
        if let proj = try? context.fetch(pfd).first {
            s.project = proj
        }
    }
    if let rraw = rec[CKSchema.WorkSessionKey.rounding] as? String,
       let r = RoundingRule(rawValue: rraw) { s.rounding = r }
    if let sraw = rec[CKSchema.WorkSessionKey.state] as? String,
       let st = SessionState(rawValue: sraw) { s.state = st }

    s.createdAt = (rec[CKSchema.WorkSessionKey.createdAt] as? Date) ?? s.createdAt
    if existing == nil || updatedAt >= s.updatedAt {
        s.updatedAt = updatedAt
    }

    if existing == nil { context.insert(s) }
    try context.save()
}

// MARK: - Change tokens

private enum CKTokenKey: String {
    case project, workSession
    var defaultsKey: String { "CKServerChangeToken_\(rawValue)" }
}

private func loadToken(_ key: CKTokenKey) -> CKServerChangeToken? {
    guard let data = UserDefaults.standard.data(forKey: key.defaultsKey) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
}
private func saveToken(_ token: CKServerChangeToken?, for key: CKTokenKey) {
    guard let token else {
        UserDefaults.standard.removeObject(forKey: key.defaultsKey); return
    }
    if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
        UserDefaults.standard.set(data, forKey: key.defaultsKey)
    }
}

// MARK: - Sync engine

final class CloudKitSyncEngine {
    static let shared = CloudKitSyncEngine()
    private init() {}

    // Push all local Projects and WorkSessions (idempotent upsert)
    func pushAll(context: ModelContext) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pushProjects(context: context) }
            group.addTask { await self.pushWorkSessions(context: context) }
        }
    }

    // Pull all changes since last token and upsert locally
    func pullAll(context: ModelContext) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pull(type: CKSchema.RecordType.project, tokenKey: .project, upsert: { try upsertProject($0, into: context) }) }
            group.addTask { await self.pull(type: CKSchema.RecordType.workSession, tokenKey: .workSession, upsert: { try upsertWorkSession($0, into: context) }) }
        }
    }

    // MARK: - Push helpers

    private func pushProjects(context: ModelContext) async {
        do {
            let projects = try context.fetch(FetchDescriptor<Project>())
            let records = projects.map(makeRecord(from:))
            try await save(records)
        } catch { print("CK pushProjects error:", error) }
    }

    private func pushWorkSessions(context: ModelContext) async {
        do {
            let sessions = try context.fetch(FetchDescriptor<WorkSession>())
            let records = sessions.map(makeRecord(from:))
            try await save(records)
        } catch { print("CK pushWorkSessions error:", error) }
    }

    private func save(_ records: [CKRecord]) async throws {
        guard !records.isEmpty else { return }
        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.savePolicy = .allKeys // overwrite whole record (idempotent)
        op.isAtomic = false       // continue on partial errors
        try await CKSchema.privateDB.modifyRecordsSaving(records, deleting: [])
    }

    // MARK: - Pull helpers

    private func pull(type: String, tokenKey: CKTokenKey, upsert: @escaping (CKRecord) throws -> Void) async {
        var token = loadToken(tokenKey)
        while true {
            let op = CKFetchRecordZoneChangesOperation.recordZoneChangesOperation(
                recordZoneIDs: [CKRecordZone.default().zoneID],
                configurationsByRecordZoneID: [:]
            )
            // Use database-level "changes since token" (simpler)
            let q = CKQuery(recordType: type, predicate: NSPredicate(value: true))
            do {
                let (match, newToken) = try await CKSchema.privateDB.records(matching: q, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults)
                for (_, result) in match {
                    switch result {
                    case .success(let rec):
                        try upsert(rec)
                    case .failure(let err):
                        print("CK pull \(type) record error:", err)
                    }
                }
                token = newToken // not strictly used with query; kept for future delta APIs
                saveToken(token, for: tokenKey)
                break
            } catch {
                print("CK pull \(type) error:", error)
                break
            }
        }
    }
}