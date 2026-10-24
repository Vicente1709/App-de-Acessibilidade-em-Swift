import SwiftUI

/// Aparece ao finalizar um trajeto. Alimenta a Sala do Histórico (avaliação, favorita,
/// atalho aprovado) e a Sala de Destinos (acessibilidade do local). Tudo é opcional.
struct TripFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pending: PendingFeedback
    let onSubmit: (TripFeedbackInput) -> Void

    @State private var input = TripFeedbackInput()
    @State private var doorWidthText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                input.rating = star
                            } label: {
                                Image(systemName: star <= input.rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(star <= input.rating ? Color.yellow : Color.warmGraphite.opacity(0.35))
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 1.15))
                            .accessibilityLabel("\(star) de 5")
                        }
                        Spacer()
                    }
                    TextField(
                        "Comentário",
                        text: $input.comment,
                        prompt: Text("Comentário (ex.: calçada lisa, bem iluminado)").foregroundStyle(Color.warmGraphite.opacity(0.55)),
                        axis: .vertical
                    )
                        .lineLimit(1...4)
                    Toggle("Rota favorita", isOn: $input.isFavorite)
                    Toggle("Atalho aprovado", isOn: $input.approvedShortcut)
                } header: {
                    ThemedHeader("Como foi o trajeto até \(pending.destinationName)?")
                }
                .listRowBackground(ThemedRowBackground())

                Section {
                    TriStatePicker(title: "Entrada adaptada", selection: $input.hasAdaptedEntrance)
                    TriStatePicker(title: "Banheiro adaptado", selection: $input.hasAccessibleRestroom)
                    TriStatePicker(title: "Vaga reservada", selection: $input.hasReservedParking)
                    TriStatePicker(title: "Empréstimo de cadeira de rodas", selection: $input.hasWheelchairLoan)
                    HStack {
                        Text("Largura da porta")
                        Spacer()
                        TextField("cm", text: $doorWidthText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                } header: {
                    ThemedHeader("Acessibilidade do local")
                } footer: {
                    Text("Preencha só o que você souber. Isso vira um aviso na próxima vez que for para lá.")
                }
                .listRowBackground(ThemedRowBackground())
            }
            .themedForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { ThemedTitle("Trajeto concluído") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Pular") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        input.doorWidthCm = Double(doorWidthText.replacingOccurrences(of: ",", with: "."))
                        onSubmit(input)
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
        }
        .tint(Color.softTerracotta)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themedSheet()
    }
}

/// "Não sei / Sim / Não" — distingue informação desconhecida de informação negativa.
private struct TriStatePicker: View {
    let title: String
    @Binding var selection: Bool?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Não sei").tag(Bool?.none)
            Text("Sim").tag(Bool?.some(true))
            Text("Não").tag(Bool?.some(false))
        }
    }
}
