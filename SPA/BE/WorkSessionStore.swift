//
//  WorkSessionStore.swift
//  Test
//
//  Created by Simone Paparo on 24/09/25.
//


import SwiftData
import Foundation

enum WorkSessionError: Error, LocalizedError {
    case overlapDetected
    case noOpenSession
    var errorDescription: String? {
        switch self {
        case .overlapDetected: return "L'intervallo selezionato si sovrappone a un'altra sessione."
        case .noOpenSession:   return "Nessuna sessione aperta da chiudere."
        }
    }
}

final class WorkSessionStore {
    private let context: ModelContext
    init(_ context: ModelContext) { self.context = context }

    // Ensure only one open session exists
    func currentOpenSession() throws -> WorkSession? {
        let d = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.end == nil })
        return try context.fetch(d).first
    }

    @discardableResult
    func startSession(project: Project?, rounding: RoundingRule) throws -> WorkSession {
        if let open = try currentOpenSession() { return open } // idempotent
        let s = WorkSession(start: Date(), project: project, rounding: rounding)
        context.insert(s)
        try context.save()
        return s
    }

    @discardableResult
    func startSession(at startDate: Date, project: Project?, rounding: RoundingRule) throws -> WorkSession {
        if let open = try currentOpenSession() { return open } // idempotent safeguard
        let s = WorkSession(start: startDate, project: project, rounding: rounding)
        context.insert(s)
        try context.save()
        return s
    }
    
    @discardableResult
    func createClosedSession(start: Date, end: Date, breakMinutes: Int, project: Project?, note: String?, rounding: RoundingRule) throws -> WorkSession {
        try ensureNoOverlap(start: start, end: end, excluding: nil)
        let s = WorkSession(start: start, project: project, rounding: rounding)
        s.end = end
        s.breakMinutes = max(0, breakMinutes)
        s.note = note
        s.state = .closed
        s.updatedAt = Date()
        context.insert(s)
        try context.save()
        return s
    }

    func stopSession(_ session: WorkSession, breakMinutes: Int = 0, at endDate: Date = Date()) throws {
        guard session.end == nil else { return }
        try ensureNoOverlap(start: session.start, end: endDate, excluding: session.id)
        session.end = endDate
        session.breakMinutes = max(0, breakMinutes)
        session.state = .closed
        session.updatedAt = Date()
        try context.save()
    }

    func discardOpenSession() throws {
        if let open = try currentOpenSession() {
            context.delete(open)
            try context.save()
        }
    }

    @discardableResult
    func switchOpenSession(to project: Project?, rounding: RoundingRule, at date: Date = Date()) throws -> WorkSession {
        if let open = try currentOpenSession() {
            try stopSession(open, at: date)
        }
        return try startSession(at: date, project: project, rounding: rounding)
    }

    // Queries
    func sessions(in range: ClosedRange<Date>, project: Project? = nil) throws -> [WorkSession] {
        if let projectId = project?.id {
            let pred = #Predicate<WorkSession> { s in
                s.start >= range.lowerBound &&
                s.start <= range.upperBound &&
                s.project?.id == projectId
            }
            let d = FetchDescriptor<WorkSession>(predicate: pred, sortBy: [SortDescriptor(\.start, order: .reverse)])
            return try context.fetch(d)
        } else {
            let pred = #Predicate<WorkSession> { s in
                s.start >= range.lowerBound && s.start <= range.upperBound
            }
            let d = FetchDescriptor<WorkSession>(predicate: pred, sortBy: [SortDescriptor(\.start, order: .reverse)])
            return try context.fetch(d)
        }
    }

    func totalMinutes(in range: ClosedRange<Date>) throws -> Int {
        let list = try sessions(in: range)
        return list.reduce(0) { acc, s in
            guard let end = s.end else { return acc }
            return acc + payableMinutes(start: s.start, end: end, breakMin: s.breakMinutes, rule: s.rounding)
        }
    }
    
    // MARK: - Overlap protection
    private func ensureNoOverlap(start: Date, end: Date, excluding id: UUID?) throws {
        let pred = #Predicate<WorkSession> { s in
            s.end != nil &&
            start < s.end! && end > s.start &&
            (id == nil || s.id != id!)
        }
        let d = FetchDescriptor<WorkSession>(predicate: pred)
        let hits = try context.fetch(d)
        if !hits.isEmpty { throw WorkSessionError.overlapDetected }
    }
}

fileprivate func rounded(_ date: Date, rule: RoundingRule) -> Date {
    switch rule {
    case .off: return date
    case .nearest5:  return date.rounded(to: 5*60)
    case .nearest15: return date.rounded(to: 15*60)
    case .nearest30: return date.rounded(to: 30*60)
    }
}

fileprivate extension Date {
    func rounded(to step: TimeInterval) -> Date {
        let t = timeIntervalSince1970
        let r = (t / step).rounded() * step
        return Date(timeIntervalSince1970: r)
    }
}

fileprivate func payableMinutes(start: Date, end: Date, breakMin: Int, rule: RoundingRule) -> Int {
    let s = rounded(start, rule: rule)
    let e = rounded(end, rule: rule)
    return max(0, Int(e.timeIntervalSince(s)/60) - max(0, breakMin))
}
