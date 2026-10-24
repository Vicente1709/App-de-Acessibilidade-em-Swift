import Foundation
import SwiftData

enum WheelchairType: String, Codable, CaseIterable, Identifiable {
    case manual
    case motorized
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .motorized: return "Motorizada"
        case .other: return "Outra"
        }
    }
}

enum AutonomyLevel: String, Codable, CaseIterable, Identifiable {
    case independent
    case occasionalHelp
    case needsCompanion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .independent: return "Totalmente autônomo(a)"
        case .occasionalHelp: return "Precisa de ajuda ocasional"
        case .needsCompanion: return "Precisa de acompanhante"
        }
    }
}

/// [SALA DO PERFIL & MOBILIDADE]
/// Limitações e preferências físicas de quem usa o app. É sempre a PRIMEIRA sala consultada
/// ao calcular uma rota. Fica apenas no aparelho (SwiftData local).
///
/// Os valores padrão são conservadores e servem só como ponto de partida: a pessoa deve
/// ajustá-los na tela de perfil.
@Model
final class MobilityProfile {
    var wheelchairType: WheelchairType
    var autonomyLevel: AutonomyLevel
    /// Velocidade média de deslocamento, em km/h (usada para estimar o tempo da rota).
    var averageSpeedKmh: Double
    /// Inclinação máxima suportada, em %. Ainda não entra no cálculo: o MapKit não fornece
    /// dados de elevação. Fica guardada para quando houver uma fonte de relevo.
    var maxInclinePercent: Double
    var prefersShade: Bool
    var avoidsUnevenSurfaces: Bool
    var needsCurbCuts: Bool

    init(
        wheelchairType: WheelchairType = .manual,
        autonomyLevel: AutonomyLevel = .independent,
        averageSpeedKmh: Double = 3.5,
        maxInclinePercent: Double = 6,
        prefersShade: Bool = false,
        avoidsUnevenSurfaces: Bool = true,
        needsCurbCuts: Bool = true
    ) {
        self.wheelchairType = wheelchairType
        self.autonomyLevel = autonomyLevel
        self.averageSpeedKmh = averageSpeedKmh
        self.maxInclinePercent = maxInclinePercent
        self.prefersShade = prefersShade
        self.avoidsUnevenSurfaces = avoidsUnevenSurfaces
        self.needsCurbCuts = needsCurbCuts
    }
}
