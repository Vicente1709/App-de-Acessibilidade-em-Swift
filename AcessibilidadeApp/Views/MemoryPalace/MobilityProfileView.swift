import SwiftUI
import SwiftData

/// Edição da Sala do Perfil & Mobilidade ("Meu perfil"). As alterações são salvas na hora
/// (SwiftData). Visual unificado com o resto do app: fundo terroso, tipografia arredondada.
struct MobilityProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [MobilityProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    MobilityProfileForm(profile: profile)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { modelContext.insert(MobilityProfile()) }
                }
            }
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { ThemedTitle("Meu perfil") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(Color.softTerracotta)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themedSheet()
    }
}

private struct MobilityProfileForm: View {
    @Bindable var profile: MobilityProfile

    var body: some View {
        Form {
            Section {
                Picker("Tipo de cadeira", selection: $profile.wheelchairType) {
                    ForEach(WheelchairType.allCases) { Text($0.label).tag($0) }
                }
                Picker("Autonomia", selection: $profile.autonomyLevel) {
                    ForEach(AutonomyLevel.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                ThemedHeader("Cadeira e autonomia")
            }
            .listRowBackground(ThemedRowBackground())

            Section {
                Stepper(value: $profile.averageSpeedKmh, in: 1...10, step: 0.5) {
                    Text("Velocidade média: \(profile.averageSpeedKmh, specifier: "%.1f") km/h")
                        .monospacedDigit()
                }
                Stepper(value: $profile.maxInclinePercent, in: 2...12, step: 0.5) {
                    Text("Inclinação máxima: \(profile.maxInclinePercent, specifier: "%.1f")%")
                        .monospacedDigit()
                }
            } header: {
                ThemedHeader("Ritmo e inclinação")
            } footer: {
                Text("A velocidade ajusta o tempo estimado. A inclinação fica guardada, mas ainda não influencia a rota: o mapa não fornece dados de relevo.")
            }
            .listRowBackground(ThemedRowBackground())

            Section {
                Toggle("Prefiro trechos com sombra", isOn: $profile.prefersShade)
                Toggle("Evitar pisos irregulares", isOn: $profile.avoidsUnevenSurfaces)
                Toggle("Preciso de calçadas rebaixadas", isOn: $profile.needsCurbCuts)
            } header: {
                ThemedHeader("Preferências de rota")
            } footer: {
                Text("Estes dados ficam somente neste aparelho.")
            }
            .listRowBackground(ThemedRowBackground())
        }
        .themedForm()
    }
}
