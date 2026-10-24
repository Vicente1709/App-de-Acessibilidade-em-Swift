import Foundation

/// Cópia "congelada" da Sala do Perfil. Usamos structs simples (em vez dos @Model) para
/// passar dados ao serviço de rotas, que é assíncrono: valores são seguros de atravessar
/// fronteiras de concorrência, objetos do SwiftData não.
struct MobilitySnapshot: Sendable {
    var chair: WheelchairType
    var autonomy: AutonomyLevel
    var speedKmh: Double
    var maxInclinePercent: Double
    var prefersShade: Bool
    var avoidsUnevenSurfaces: Bool
    var needsCurbCuts: Bool

    var speedMetersPerSecond: Double { max(speedKmh, 0.5) / 3.6 }

    static let `default` = MobilitySnapshot(
        chair: .manual,
        autonomy: .independent,
        speedKmh: 3.5,
        maxInclinePercent: 6,
        prefersShade: false,
        avoidsUnevenSurfaces: true,
        needsCurbCuts: true
    )
}

/// Cópia "congelada" de um relato da Sala do Mapa.
struct ObstacleSnapshot: Sendable {
    let kind: ObstacleKind
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let note: String
}

extension ObstacleKind {
    /// Quanto o obstáculo "pesa" na pontuação da rota, de acordo com o perfil.
    /// Peso 0 significa que, para esta pessoa, o problema não importa.
    func weight(for profile: MobilitySnapshot) -> Double {
        switch self {
        case .steps, .elevatorOut:
            return 10
        case .missingCurbCut:
            return profile.needsCurbCuts ? 10 : 2
        case .construction, .flooding:
            return 4
        case .hole, .brokenSidewalk:
            return profile.avoidsUnevenSurfaces ? 4 : 2
        case .unevenPaving:
            if profile.avoidsUnevenSurfaces { return 4 }
            return profile.chair == .manual ? 2 : 1
        case .rampNoHandrail:
            return profile.autonomy == .independent ? 1 : 3
        case .noShade:
            return profile.prefersShade ? 1.5 : 0
        }
    }

    /// Obstáculos que podem simplesmente impedir a passagem.
    func isBlocking(for profile: MobilitySnapshot) -> Bool {
        switch self {
        case .steps, .elevatorOut: return true
        case .missingCurbCut: return profile.needsCurbCuts
        default: return false
        }
    }
}
