import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<WorkSession> { $0.end == nil },
        sort: [SortDescriptor(\.start, order: .reverse)]
    ) private var openSessions: [WorkSession]
    @State private var isClosingSession = false
    @State private var closeErrorMessage: String?
    @State private var showingCloseError = false

    private var openSession: WorkSession? { openSessions.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    if let open = openSession {
                        activeSessionCard(open)
                    }

                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ciao Simix 👋")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Ecco il tuo resoconto settimanale")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink {
                            ProfileView()
                        } label: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    // Statistiche settimanali
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📊 Resoconto della Settimana")
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            StatCard(title: "Ore Totali", value: "42h")
                            StatCard(title: "Media Giornaliera", value: "6h")
                        }
                        
                        HStack(spacing: 16) {
                            StatCard(title: "Spese", value: "€120")
                            StatCard(title: "Commesse", value: "3 attive")
                        }
                    }
                    .padding()
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .overlay(
                        LinearGradient(colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    )
                    .padding(.horizontal)
                    
                    // Suggerimenti in stile AI
                    VStack(alignment: .leading, spacing: 8) {
                        Text("✨ Suggerimenti Intelligenti")
                            .font(.headline)
                        
                        Text("Hai lavorato più ore del solito martedì (+2h). Forse conviene bilanciare meglio i prossimi giorni.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                        
                        Text("La commessa *Progetto Alfa* ha assorbito il 60% delle tue ore questa settimana.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .overlay(
                        LinearGradient(colors: [.mint.opacity(0.2), .teal.opacity(0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    )
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .alert("Impossibile chiudere la sessione", isPresented: $showingCloseError, actions: {
            Button("OK", role: .cancel) {
                showingCloseError = false
                closeErrorMessage = nil
            }
        }, message: {
            Text(closeErrorMessage ?? "Si è verificato un errore sconosciuto.")
        })
    }
}

private extension HomeView {
    @ViewBuilder
    func activeSessionCard(_ session: WorkSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggerimento intelligente")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Sessione aperta")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Text(openSessionDescription(for: session))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(durationText(for: session))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }

            Button {
                closeSession(session)
            } label: {
                Label("Chiudi ora", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isClosingSession)
        }
        .padding()
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            LinearGradient(
                colors: [.blue.opacity(0.25), .purple.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(alignment: .topTrailing) {
            if isClosingSession {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
        .padding(.horizontal)
    }

    func openSessionDescription(for session: WorkSession) -> String {
        if let name = session.project?.name, !name.isEmpty {
            return "Hai una sessione attiva per \(name) iniziata alle \(session.start.formatted(date: .omitted, time: .shortened))."
        }
        return "Hai una sessione attiva iniziata alle \(session.start.formatted(date: .omitted, time: .shortened))."
    }

    func durationText(for session: WorkSession) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(session.start) / 60))
        let hours = minutes / 60
        let mins = minutes % 60
        return "Durata attuale: \(hours)h \(mins)m"
    }

    func closeSession(_ session: WorkSession) {
        guard !isClosingSession else { return }
        isClosingSession = true
        defer { isClosingSession = false }

        do {
            let store = WorkSessionStore(context)
            try store.stopSession(session)
            Task { await CloudKitSyncEngine.shared.pushAll(context: context) }
        } catch let ws as WorkSessionError {
            switch ws {
            case .overlapDetected:
                closeErrorMessage = "Non posso chiudere la sessione perché l'intervallo si sovrappone ad un'altra registrazione."
            case .noOpenSession:
                closeErrorMessage = "Non ho trovato sessioni aperte da chiudere."
            }
            showingCloseError = true
        } catch {
            let ns = error as NSError
            closeErrorMessage = "Chiusura non riuscita (\(ns.domain) \(ns.code))."
            showingCloseError = true
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            LinearGradient(colors: [.indigo.opacity(0.25), .blue.opacity(0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }
}
