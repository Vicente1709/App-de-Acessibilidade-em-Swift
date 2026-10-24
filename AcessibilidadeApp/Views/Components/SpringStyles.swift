import SwiftUI

extension Animation {
    /// Mola padrão das interações e transições do app.
    static let homeSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

/// Micro-interação elástica de toque, para TODOS os botões do app.
///
/// - Ao tocar: o elemento cresce um pouco, com uma mola rápida.
/// - Ao soltar: volta ao tamanho normal com uma mola "solta" (amortecimento baixo), que passa
///   um pouco do ponto e se acomoda — o efeito elástico.
struct SpringPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 1.05

    private static let pressSpring = Animation.spring(response: 0.18, dampingFraction: 0.65)
    private static let releaseSpring = Animation.spring(response: 0.45, dampingFraction: 0.42)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(
                configuration.isPressed ? Self.pressSpring : Self.releaseSpring,
                value: configuration.isPressed
            )
    }
}

/// Cartão em camadas de vidro: lavagem quente por baixo + material + reflexo na borda e
/// sombras suaves. Base de todas as superfícies do app (Home, mapa, painéis e sheets).
struct HomeGlassCard: ViewModifier {
    var cornerRadius: CGFloat
    var material: Material
    var wash: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    shape.fill(wash.opacity(0.55))
                    shape.fill(material)
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

extension View {
    /// Cartão de vidro do app. `.regularMaterial` para superfícies grandes,
    /// `.ultraThinMaterial` para itens pequenos sobre elas; `wash` escolhe o tom quente de base.
    func homeGlass(
        cornerRadius: CGFloat = 22,
        material: Material = .regularMaterial,
        wash: Color = .cream
    ) -> some View {
        modifier(HomeGlassCard(cornerRadius: cornerRadius, material: material, wash: wash))
    }
}
