import SwiftUI
import SwiftData

/// Configurações do app: tema, tela inicial, banner de navegação e limpeza de dados.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AppSettings.Keys.forceLightMode) private var forceLightMode = false
    @AppStorage(AppSettings.Keys.showRecentTrips) private var showRecentTrips = true

    @Query private var trips: [TripRecord]
    @Query private var obstacles: [ObstacleReport]

    @State private var confirmClearTrips = false
    @State private var confirmClearObstacles = false
    @State private var failureMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                homeSection
                dataSection
            }
            .themedForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { ThemedTitle("Configurações") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
            // Confirmação antes de apagar o histórico de trajetos.
            .confirmationDialog(
                "Tem certeza que deseja apagar todo o histórico de trajetos?",
                isPresented: $confirmClearTrips,
                titleVisibility: .visible
            ) {
                Button("Apagar histórico", role: .destructive) { clearTrips() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Essa ação não pode ser desfeita.")
            }
            // Confirmação antes de limpar os obstáculos sinalizados.
            .confirmationDialog(
                "Tem certeza que deseja apagar todos os obstáculos que você sinalizou?",
                isPresented: $confirmClearObstacles,
                titleVisibility: .visible
            ) {
                Button("Apagar obstáculos", role: .destructive) { clearObstacles() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("As próximas rotas deixarão de considerar esses relatos.")
            }
            .alert(
                "Não foi possível apagar",
                isPresented: Binding(
                    get: { failureMessage != nil },
                    set: { if !$0 { failureMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failureMessage ?? "")
            }
        }
        .tint(Color.softTerracotta)
        .presentationDragIndicator(.visible)
        .themedSheet()
    }

    // MARK: - Seções

    private var appearanceSection: some View {
        Section {
            Picker("Tema", selection: $forceLightMode) {
                Text("Padrão do sistema").tag(false)
                Text("Modo claro").tag(true)
            }
            .pickerStyle(.segmented)
        } header: {
            ThemedHeader("Aparência")
        } footer: {
            Text("O modo claro mantém as cores claras mesmo quando o iPhone está no modo escuro.")
        }
        .listRowBackground(rowBackground)
    }

    private var homeSection: some View {
        Section {
            Toggle("Mostrar trajetos recentes", isOn: $showRecentTrips.animation(.homeSpring))
        } header: {
            ThemedHeader("Tela inicial")
        }
        .listRowBackground(rowBackground)
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                confirmClearTrips = true
            } label: {
                dataRow("Apagar histórico de trajetos", count: trips.count)
            }
            .disabled(trips.isEmpty)

            Button(role: .destructive) {
                confirmClearObstacles = true
            } label: {
                dataRow("Limpar obstáculos sinalizados", count: obstacles.count)
            }
            .disabled(obstacles.isEmpty)
        } header: {
            ThemedHeader("Dados")
        } footer: {
            Text("Os dados ficam somente neste aparelho. Avaliações e locais que você registrou ao concluir trajetos não são apagados por estas ações.")
        }
        .listRowBackground(rowBackground)
    }

    private func dataRow(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(count == 0 ? Color.warmGraphite.opacity(0.4) : Color.softDanger)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(Color.warmGraphite.opacity(0.6))
        }
    }

    private var rowBackground: some View {
        ThemedRowBackground()
    }

    // MARK: - Limpeza (SwiftData)

    private func clearTrips() {
        withAnimation(.homeSpring) {
            do {
                try modelContext.delete(model: TripRecord.self)
                try modelContext.save()
            } catch {
                failureMessage = error.localizedDescription
            }
        }
    }

    private func clearObstacles() {
        withAnimation(.homeSpring) {
            do {
                try modelContext.delete(model: ObstacleReport.self)
                try modelContext.save()
            } catch {
                failureMessage = error.localizedDescription
            }
        }
    }
}
