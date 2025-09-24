import SwiftUI

struct ContentView: View {
    @State private var showingSheet = false

    var body: some View {
        ZStack {
            TabView {
                Tab("Home", systemImage: "house") {
                    HomeView()
                }

                Tab("Storico", systemImage: "memories") {
                    HistoryView()
                }

                Tab("New", systemImage: "plus", role: .search) {
                    Color.clear
                        .onAppear {
                            showingSheet = true
                        }
                }
            }
        }
        // ⬇️ attach the sheet here, not on Tab
        .sheet(isPresented: $showingSheet) {
            AddSheetView(onClose: { showingSheet = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
