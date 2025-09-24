import SwiftUI

enum MainTab: Hashable {
    case home, history, new
}

struct ContentView: View {
    @State private var selected: MainTab = .home
    @State private var lastNonNew: MainTab = .home
    @State private var showingSheet = false

    var body: some View {
        TabView(selection: $selected) {
            Tab(value: .home) {
                HomeView()
                } label: {
                    Label("Home", systemImage: "house")
            }

                    Tab(value: .history) {
                        HistoryView()
                    } label: {
                        Label("Storico", systemImage: "clock.arrow.circlepath")
                    }

            Tab(value: .new, role: .search) {
                        Color.clear // or your AddSheet
                    } label: {
                        Label("New", systemImage: "plus")
                    }
        }
        .onChange(of: selected) { oldValue, newValue in
            if newValue == .new {
                showingSheet = true
                // immediately bounce back to the previous real tab
                selected = lastNonNew
            } else {
                lastNonNew = newValue
            }
        }
        .sheet(isPresented: $showingSheet) {
            // If AddSheetView already contains a NavigationStack, present it directly.
            // If it doesn't, wrap it in NavigationStack here.
            AddSheetView(onClose: { showingSheet = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
