import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
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
