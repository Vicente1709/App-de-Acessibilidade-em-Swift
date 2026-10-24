import SwiftUI
import SwiftData
import PhotosUI

/// Perfil da pessoa (foto, nome, números) + histórico completo de viagens do SwiftData,
/// com repetir e excluir em cada item.
struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TripRecord.date, order: .reverse) private var trips: [TripRecord]
    @AppStorage(AppSettings.Keys.profileName) private var name = ""

    private let avatarStore = AvatarStore.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var revealedID: UUID?

    /// `false` enquanto há uma navegação em andamento (repetir viagem a cancelaria).
    let canRepeat: Bool
    let onRepeat: (TripRecord) -> Void

    private var totalDistance: Double { trips.reduce(0) { $0 + $1.distanceInMeters } }
    private var completedCount: Int { trips.filter(\.isCompleted).count }

    var body: some View {
        NavigationStack {
            // Toda a página rola na vertical (sem barra de rolagem), então o histórico inteiro fica
            // acessível mesmo em telas pequenas; a margem inferior impede que a última viagem
            // fique escondida atrás do indicador de início do iPhone.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    stats
                    history
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .animation(.homeSpring, value: trips.count)
            }
            .contentMargins(.bottom, 40, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .fontDesign(.rounded)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { ThemedTitle("Perfil") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        avatarStore.save(imageData: data)
                    }
                    pickerItem = nil
                }
            }
        }
        .tint(Color.softTerracotta)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themedSheet()
    }

    // MARK: - Cabeçalho

    private var header: some View {
        VStack(spacing: 14) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ProfileAvatarView(image: avatarStore.image, size: 104)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color.onTerracotta)
                            .frame(width: 30, height: 30)
                            .background(Color.softTerracotta, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
                    }
            }
            .buttonStyle(SpringPressButtonStyle())
            .accessibilityLabel("Escolher foto de perfil")

            if avatarStore.image != nil {
                Button("Remover foto") {
                    withAnimation(.homeSpring) { avatarStore.remove() }
                }
                .buttonStyle(SpringPressButtonStyle())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.warmGraphite.opacity(0.7))
            }

            TextField(
                "Seu nome",
                text: $name,
                prompt: Text("Como podemos te chamar?").foregroundStyle(Color.warmGraphite.opacity(0.5))
            )
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.warmGraphite)
            .multilineTextAlignment(.center)
            .submitLabel(.done)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .homeGlass(cornerRadius: 18, material: .ultraThinMaterial)
        }
        .padding(.top, 8)
    }

    // MARK: - Números

    private var stats: some View {
        HStack(spacing: 10) {
            statTile(value: "\(trips.count)", title: "Viagens")
            statTile(value: MetricDistance.string(from: totalDistance), title: "Percorridos")
            statTile(value: "\(completedCount)", title: "Concluídas")
        }
    }

    private func statTile(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.warmGraphite)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.warmGraphite.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .homeGlass(cornerRadius: 16, material: .ultraThinMaterial)
    }

    // MARK: - Histórico

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Histórico de viagens")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.warmGraphite)

            if trips.isEmpty {
                Text("Suas viagens aparecerão aqui.")
                    .font(.subheadline)
                    .foregroundStyle(Color.warmGraphite.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .homeGlass(cornerRadius: 18, material: .ultraThinMaterial)
            } else {
                Text(canRepeat
                     ? "Toque ou deslize para a esquerda para repetir ou excluir."
                     : "Finalize o trajeto atual para poder repetir uma viagem.")
                    .font(.caption)
                    .foregroundStyle(Color.warmGraphite.opacity(0.7))

                LazyVStack(spacing: 10) {
                    ForEach(trips) { trip in
                        TripHistoryRow(
                            trip: trip,
                            revealedID: $revealedID,
                            canRepeat: canRepeat,
                            onRepeat: { onRepeat(trip) },
                            onDelete: { delete(trip) }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                }
            }
        }
    }

    /// Remove o registro do SwiftData com a mola padrão do app.
    private func delete(_ trip: TripRecord) {
        withAnimation(.homeSpring) {
            if revealedID == trip.id { revealedID = nil }
            modelContext.delete(trip)
            try? modelContext.save()
        }
    }
}
