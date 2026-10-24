import SwiftUI

/// Linha do histórico de viagens. Ao tocar ou deslizar para a ESQUERDA, o cartão encolhe na
/// horizontal e revela dois atalhos: repetir a viagem e excluí-la.
///
/// O estado "aberto" vive no pai (`revealedID`), assim só uma linha fica aberta por vez.
struct TripHistoryRow: View {
    let trip: TripRecord
    @Binding var revealedID: UUID?
    var canRepeat = true
    let onRepeat: () -> Void
    let onDelete: () -> Void

    @GestureState private var dragX: CGFloat = 0

    private let actionSize: CGFloat = 46
    private let actionSpacing: CGFloat = 10

    private var actionsWidth: CGFloat { actionSize * 2 + actionSpacing }
    private var isRevealed: Bool { revealedID == trip.id }

    /// 0 = fechada, 1 = totalmente aberta; acompanha o dedo durante o arrasto.
    private var progress: CGFloat {
        let base: CGFloat = isRevealed ? 1 : 0
        return min(max(base - dragX / actionsWidth, 0), 1)
    }

    var body: some View {
        HStack(spacing: actionSpacing * progress) {
            card
                .frame(maxWidth: .infinity) // encolhe conforme os botões ganham espaço

            actions
                .frame(width: actionsWidth * progress, alignment: .leading)
                .clipped()
                .opacity(Double(progress))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.homeSpring) { revealedID = isRevealed ? nil : trip.id }
        }
        .simultaneousGesture(swipeGesture)
        .animation(.homeSpring, value: isRevealed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.destinationName), \(trip.formattedDistance)")
        .accessibilityAction(named: "Repetir viagem") { if canRepeat { onRepeat() } }
        .accessibilityAction(named: "Excluir viagem") { onDelete() }
    }

    // MARK: - Cartão

    private var card: some View {
        HStack(spacing: 12) {
            Image(systemName: trip.isCompleted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(trip.isCompleted ? Color.softTerracotta : Color.warmGraphite.opacity(0.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.destinationName)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.warmGraphite)
                    .lineLimit(1)
                Text("\(trip.date.formatted(date: .abbreviated, time: .shortened)) • \(trip.formattedDistance)")
                    .font(.caption)
                    .foregroundStyle(Color.warmGraphite.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .homeGlass(cornerRadius: 18, material: .ultraThinMaterial)
    }

    // MARK: - Ações reveladas

    private var actions: some View {
        HStack(spacing: actionSpacing) {
            Button(action: onRepeat) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.onTerracotta)
                    .frame(width: actionSize, height: actionSize)
                    .background(Color.softTerracotta, in: Circle())
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            }
            .buttonStyle(SpringPressButtonStyle())
            .disabled(!canRepeat)
            .opacity(canRepeat ? 1 : 0.4)
            .accessibilityLabel("Repetir viagem")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: actionSize, height: actionSize)
                    .background(Color.softDanger, in: Circle())
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            }
            .buttonStyle(SpringPressButtonStyle())
            .accessibilityLabel("Excluir viagem")
        }
        .fixedSize()
        .scaleEffect(progress, anchor: .leading)
    }

    // MARK: - Gesto

    /// Só vale arrasto predominantemente horizontal, para não brigar com a rolagem da lista.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragX) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let projected = (isRevealed ? -actionsWidth : 0) + value.predictedEndTranslation.width
                withAnimation(.homeSpring) {
                    revealedID = projected < -actionsWidth / 2 ? trip.id : nil
                }
            }
    }
}
