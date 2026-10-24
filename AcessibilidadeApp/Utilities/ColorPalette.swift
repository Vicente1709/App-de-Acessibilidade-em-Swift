import SwiftUI
import UIKit

// MARK: - Cores adaptativas (claro/escuro)

extension Color {
    /// Cor que troca sozinha entre o modo claro e o escuro. Os valores são hexadecimais 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Paleta Beiges & Terrosos

/// Paleta neutra e terrosa do app. Use sempre com o prefixo `Color.` (ex.: `Color.linen`).
///
/// Cada tom tem uma versão clara e uma escura, e o PAPEL de cada um se mantém nos dois modos:
/// - `linen`: fundo base da tela
/// - `cream`: superfícies (cartões, painéis) e reflexos
/// - `warmNude`: superfícies secundárias, trilhas, divisórias
/// - `softTerracotta`: cor de destaque (ícones, botão principal)
/// - `warmGraphite`: texto principal (use `.opacity(0.6–0.7)` para texto secundário)
/// - `sand`, `oatmeal`, `champagne`: lavagens quentes por baixo do vidro, para variar as superfícies
///
/// As cores FUNCIONAIS (verde da farmácia, amarelo/âmbar da cadeira de rodas, cores das rotas)
/// não fazem parte desta paleta e não devem ser substituídas por ela.
extension Color {
    static let linen          = Color(light: 0xF4EEE6, dark: 0x1F1B18)
    static let cream          = Color(light: 0xFBF7F1, dark: 0x2A2521)
    static let warmNude       = Color(light: 0xE6D5C3, dark: 0x3B332C)
    static let softTerracotta = Color(light: 0xA95F41, dark: 0xD99B7C)
    static let warmGraphite   = Color(light: 0x3B3531, dark: 0xF1E9DF)

    // Tons de apoio para variar as superfícies de vidro (painéis, cartões, sheets).
    static let sand           = Color(light: 0xDCCBB2, dark: 0x4A4037)
    static let oatmeal        = Color(light: 0xEDE3D3, dark: 0x342D27)
    static let champagne      = Color(light: 0xF5E8D3, dark: 0x3B3229)

    /// Cor funcional de ação destrutiva (excluir, finalizar), suavizada para a paleta.
    static let softDanger     = Color(light: 0xCC443D, dark: 0xE0675F)

    // Texto/ícone SOBRE os preenchimentos acima (mantém contraste ≥ 4,5:1 nos dois modos).
    static let onTerracotta   = Color(light: 0xFFFFFF, dark: 0x2A1D16)
    static let onWarmGraphite = Color(light: 0xFBF7F1, dark: 0x1F1B18)
}
