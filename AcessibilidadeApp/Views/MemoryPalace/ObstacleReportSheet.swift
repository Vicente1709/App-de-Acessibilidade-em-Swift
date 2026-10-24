import SwiftUI

/// Registro rápido de um obstáculo encontrado no caminho (Sala do Mapa & Obstáculos).
/// O relato passa a pesar nas próximas rotas e, durante a navegação, pode disparar um recálculo.
struct ObstacleReportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ObstacleKind = .hole
    @State private var placement: ObstaclePlacement = .ahead
    @State private var note = ""

    let onSave: (ObstacleKind, String, ObstaclePlacement) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $kind) {
                        ForEach(ObstacleKind.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    ThemedHeader("O que você encontrou?")
                }
                .listRowBackground(ThemedRowBackground())

                Section {
                    Picker("Onde está?", selection: $placement) {
                        ForEach(ObstaclePlacement.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField(
                        "Detalhes (opcional)",
                        text: $note,
                        prompt: Text("Detalhes (opcional)").foregroundStyle(Color.warmGraphite.opacity(0.55)),
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                } footer: {
                    Text("Se o obstáculo estiver no seu caminho, a rota será recalculada para tentar desviar.")
                }
                .listRowBackground(ThemedRowBackground())
            }
            .themedForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { ThemedTitle("Relatar obstáculo") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registrar") {
                        onSave(kind, note, placement)
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
        }
        .tint(Color.softTerracotta)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .themedSheet()
    }
}
