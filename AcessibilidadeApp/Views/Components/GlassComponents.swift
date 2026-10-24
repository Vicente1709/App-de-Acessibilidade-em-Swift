import SwiftUI
import UIKit

/// Botão circular flutuante em Liquid Glass terroso: material, lavagem `cream`, borda sutil
/// e mola elástica ao toque.
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 44
    /// Destaca o botão quando ele representa uma camada/opção ligada.
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(isActive ? Color.softTerracotta : Color.warmGraphite)
                .frame(width: size, height: size)
                .background(.regularMaterial, in: Circle())
                .background(isActive ? Color.softTerracotta.opacity(0.28) : Color.cream.opacity(0.55), in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        isActive ? Color.softTerracotta : Color.white.opacity(0.4),
                        lineWidth: isActive ? 2 : 1
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(SpringPressButtonStyle())
    }
}

/// Modifier que aplica o "cartão de vidro" usado nos painéis flutuantes
/// (busca, resumo de rota, navegação ativa etc.)
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.warmGraphite)
            .padding()
            .homeGlass(cornerRadius: cornerRadius, material: .regularMaterial)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

/// Barra de busca em vidro com a paleta terrosa — a mesma na Home e no mapa. O campo "respira"
/// (mola) quando recebe foco. `onSubmit` é chamado ao tocar em "Buscar" no teclado.
struct GlassSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Para onde você vai?"
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.softTerracotta)

            TextField(
                "Buscar destino",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Color.warmGraphite.opacity(0.55))
            )
            .foregroundStyle(Color.warmGraphite)
            .focused($isFocused)
            .submitLabel(.search)
            .onSubmit { onSubmit?() }

            if !text.isEmpty {
                Button {
                    withAnimation(.homeSpring) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.warmGraphite.opacity(0.5))
                }
                .buttonStyle(SpringPressButtonStyle())
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .homeGlass(cornerRadius: 22, material: .regularMaterial)
        .shadow(color: isFocused ? Color.softTerracotta.opacity(0.22) : .clear, radius: 12, y: 4)
        .scaleEffect(isFocused ? 1.015 : 1)
        .animation(.homeSpring, value: isFocused)
        .animation(.homeSpring, value: text.isEmpty)
    }
}

// MARK: - Seleção de rotas

extension RouteRole {
    /// Azul = ideal, verde = alternativa, laranja = contorno.
    var color: Color {
        switch self {
        case .ideal: return .blue
        case .alternative: return .green
        case .detour: return .orange
        }
    }
}

/// Card de vidro COMPACTO que resume uma opção de rota. Tocar nele define a rota ativa.
struct RouteOptionCard: View {
    let option: AccessibleRouteResult
    let isSelected: Bool
    let action: () -> Void

    private var minutes: Int {
        max(1, Int((option.estimatedDuration / 60).rounded()))
    }

    private var obstacleText: String {
        let count = option.obstaclesNearRoute.count
        if !option.blockingObstacles.isEmpty { return "possível bloqueio" }
        switch count {
        case 0: return "sem obstáculos"
        case 1: return "1 obstáculo"
        default: return "\(count) obstáculos"
        }
    }

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(option.role.color)
                        .frame(width: 8, height: 8)
                    Text(option.role.title)
                        .font(.caption2.bold())
                        .foregroundStyle(Color.warmGraphite)
                }
                Text("\(minutes) min")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Color.warmGraphite)
                Text("\(option.route.formattedDistance) · \(obstacleText)")
                    .font(.caption2)
                    .foregroundStyle(option.blockingObstacles.isEmpty ? Color.warmGraphite.opacity(0.65) : Color.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 140, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(Color.champagne.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? option.role.color : Color.white.opacity(0.35), lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            .scaleEffect(isSelected ? 1.0 : 0.97)
            .animation(.spring(duration: 0.3), value: isSelected)
        }
        .buttonStyle(SpringPressButtonStyle())
        .accessibilityLabel("\(option.role.title), \(minutes) minutos, \(option.route.formattedDistance), \(obstacleText)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Faixa horizontal com as opções de rota disponíveis.
struct RouteOptionsPicker: View {
    let options: [AccessibleRouteResult]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options) { option in
                    RouteOptionCard(option: option, isSelected: option.id == selectedID) {
                        onSelect(option.id)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Banner de POI

/// Banner de vidro exibido ao tocar num marcador de farmácia ou shopping.
struct GlassPOIBanner: View {
    let place: PlaceItem
    let onClose: () -> Void
    let onGoThere: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: place.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(place.kind == .pharmacy ? Color.mint : Color.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline)
                    Text(place.kind.label).font(.caption).foregroundStyle(Color.warmGraphite.opacity(0.65))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.warmGraphite.opacity(0.65))
                }
                .buttonStyle(SpringPressButtonStyle())
                .accessibilityLabel("Fechar")
            }

            if let notice = place.kind.accessibilityNotice {
                Text(notice)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Informação geral, não verificada neste local.")
                    .font(.caption2)
                    .foregroundStyle(Color.warmGraphite.opacity(0.65))
            }

            Button(action: onGoThere) {
                Text("Ir até aqui")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.onTerracotta)
                    .background(Color.softTerracotta, in: Capsule())
                    .shadow(color: Color.softTerracotta.opacity(0.3), radius: 10, y: 5)
            }
            .buttonStyle(SpringPressButtonStyle())
        }
        .glassPanel()
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Turn-by-turn

/// Barra de instrução da navegação: seta grande + texto direto ("Vire à direita em 40 m").
struct GlassTurnBanner: View {
    let instruction: TurnInstruction?
    var tint: Color = .accentColor

    private var symbol: String { instruction?.systemImage ?? "arrow.up" }
    private var headline: String { instruction?.headline ?? "Siga a rota destacada no mapa" }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = instruction?.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.warmGraphite.opacity(0.65))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(duration: 0.35), value: symbol)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([instruction?.headline ?? headline, instruction?.detail].compactMap { $0 }.joined(separator: ". "))
    }
}

// MARK: - Atalhos rápidos

/// Atalho em vidro com um toque de cor (verde, âmbar…): material translúcido, borda sutil
/// e sombra difusa na cor do atalho.
struct GlassShortcutButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var isLoading = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle().fill(tint.opacity(0.25))
                    if isLoading {
                        ProgressView().tint(tint)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.warmGraphite)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Color.warmGraphite.opacity(0.62))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color.warmGraphite)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            .shadow(color: tint.opacity(0.18), radius: 12, y: 6)
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(SpringPressButtonStyle())
        .accessibilityLabel("\(title). \(subtitle)")
    }
}


// MARK: - Ícones de categoria (busca)

extension PlaceCategoryStyle.Theme {
    var color: Color {
        switch self {
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .blue: return .blue
        case .purple: return .purple
        case .indigo: return .indigo
        case .teal: return .teal
        case .gray: return .gray
        }
    }
}

/// Círculo sutil em Liquid Glass com o ícone da categoria e a cor do tema.
struct GlassPlaceIcon: View {
    let style: PlaceCategoryStyle
    var size: CGFloat = 38

    var body: some View {
        let color = style.theme.color
        Image(systemName: style.systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .background(color.opacity(0.18), in: Circle())
            .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Linha de resultado da busca: ícone da categoria à esquerda, nome e endereço ao lado.
struct SearchResultRow: View {
    let title: String
    let subtitle: String
    let style: PlaceCategoryStyle

    var body: some View {
        HStack(spacing: 12) {
            GlassPlaceIcon(style: style)
                .animation(.spring(duration: 0.3), value: style)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.warmGraphite)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.warmGraphite.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Painel retrátil (bottom sheet)

/// Alturas do painel retrátil.
/// - `collapsed`: só a alça e o resumo (revela o mapa).
/// - `compact`: padrão — cards de rota e botão de iniciar.
/// - `expanded`: acrescenta o aviso do Palácio e as opções extras.
enum SheetDetent: Int, CaseIterable, Comparable {
    case collapsed, compact, expanded

    var height: CGFloat {
        switch self {
        case .collapsed: return 72
        case .compact: return 200
        case .expanded: return 340
        }
    }

    static func < (lhs: SheetDetent, rhs: SheetDetent) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Folha inferior retrátil em Liquid Glass, com alça de arraste e animação de mola.
///
/// Implementação própria (em vez de `.sheet` + `presentationDetents`) porque uma `.sheet` do
/// sistema, ao ser arrastada para baixo, é DISPENSADA — aqui ela só se recolhe, a seleção
/// de rota continua, e não conflita com as outras sheets do mapa (obstáculo e feedback).
/// O arraste vale na alça e no cabeçalho; o corpo rola sozinho quando está expandido.
struct DetentBottomSheet<Header: View, Content: View>: View {
    @Binding var detent: SheetDetent
    private let header: () -> Header
    private let content: () -> Content

    @GestureState private var dragOffset: CGFloat = 0

    init(
        detent: Binding<SheetDetent>,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _detent = detent
        self.header = header
        self.content = content
    }

    private static var spring: Animation { .spring(response: 0.35, dampingFraction: 0.8) }

    /// Altura acompanhando o dedo, limitada entre o menor e o maior detent.
    private var liveHeight: CGFloat {
        min(max(detent.height - dragOffset, SheetDetent.collapsed.height), SheetDetent.expanded.height)
    }

    /// O corpo some aos poucos conforme o painel recolhe.
    private var bodyOpacity: Double {
        let range = SheetDetent.compact.height - SheetDetent.collapsed.height
        return Double(min(max((liveHeight - SheetDetent.collapsed.height) / range, 0), 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            grabArea

            ScrollView {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(detent != .expanded || dragOffset != 0)
            .opacity(bodyOpacity)
            .allowsHitTesting(detent != .collapsed)
        }
        .foregroundStyle(Color.warmGraphite)
        .frame(maxWidth: .infinity)
        .frame(height: liveHeight, alignment: .top)
        .background {
            // O fundo avança sobre a área segura inferior para não deixar fresta sob o painel.
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color.oatmeal.opacity(0.6))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 10, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(Self.spring, value: detent)
    }

    private var grabArea: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.warmGraphite.opacity(0.3))
                .frame(width: 40, height: 5)
            header()
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture {
            move(to: detent == .collapsed ? .compact : .collapsed)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Toque duas vezes para \(detent == .collapsed ? "expandir" : "recolher") o painel")
        .accessibilityAction(named: "Expandir") { step(by: 1) }
        .accessibilityAction(named: "Recolher") { step(by: -1) }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                // Projeta onde o dedo "pararia" e encaixa no detent mais próximo: um arrasto
                // curto mas rápido já troca de nível.
                let projected = detent.height - value.predictedEndTranslation.height
                let target = SheetDetent.allCases.min {
                    abs($0.height - projected) < abs($1.height - projected)
                } ?? detent
                move(to: target)
            }
    }

    private func step(by delta: Int) {
        guard let target = SheetDetent(rawValue: detent.rawValue + delta) else { return }
        move(to: target)
    }

    private func move(to target: SheetDetent) {
        guard target != detent else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Self.spring) { detent = target }
    }
}
