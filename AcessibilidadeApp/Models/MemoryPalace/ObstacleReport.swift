import Foundation
import SwiftData
import CoreLocation

enum ObstacleKind: String, Codable, CaseIterable, Identifiable {
    case hole
    case brokenSidewalk
    case steps
    case construction
    case elevatorOut
    case rampNoHandrail
    case flooding
    case noShade
    case unevenPaving
    case missingCurbCut

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hole: return "Buraco"
        case .brokenSidewalk: return "Calçada danificada"
        case .steps: return "Degraus"
        case .construction: return "Obra"
        case .elevatorOut: return "Elevador fora de serviço"
        case .rampNoHandrail: return "Rampa sem corrimão"
        case .flooding: return "Alagamento"
        case .noShade: return "Trecho sem sombra"
        case .unevenPaving: return "Piso irregular"
        case .missingCurbCut: return "Calçada sem rebaixamento"
        }
    }

    var systemImage: String {
        switch self {
        case .hole: return "exclamationmark.circle"
        case .brokenSidewalk: return "exclamationmark.triangle"
        case .steps: return "figure.stairs"
        case .construction: return "hammer"
        case .elevatorOut: return "arrow.up.arrow.down.circle"
        case .rampNoHandrail: return "line.diagonal"
        case .flooding: return "drop.fill"
        case .noShade: return "sun.max.fill"
        case .unevenPaving: return "square.grid.3x3"
        case .missingCurbCut: return "arrow.down.to.line"
        }
    }

    /// Alguns problemas são temporários: depois desse prazo o relato deixa de pesar nas
    /// rotas (a menos que alguém o registre de novo). `nil` = não expira.
    var defaultShelfLife: TimeInterval? {
        switch self {
        case .flooding: return 3 * 86_400
        case .elevatorOut: return 14 * 86_400
        case .construction: return 60 * 86_400
        default: return nil
        }
    }
}

/// Onde o obstáculo está em relação a quem o relata.
enum ObstaclePlacement: String, CaseIterable, Identifiable {
    case here
    case ahead

    var id: String { rawValue }

    var label: String {
        switch self {
        case .here: return "Aqui"
        case .ahead: return "≈ 20 m à frente"
        }
    }
}

/// [SALA DO MAPA & OBSTÁCULOS]
/// Relatos sobre pontos específicos da cidade. É a SEGUNDA sala consultada ao calcular rotas.
@Model
final class ObstacleReport {
    /// Raio padrão (m) em que o relato é considerado "no caminho".
    static let defaultRadiusMeters: Double = 30

    var id: UUID
    var kind: ObstacleKind
    var latitude: Double
    var longitude: Double
    /// Distância (m) a partir do ponto em que o relato ainda é considerado "no caminho".
    var radiusMeters: Double
    var note: String
    var reportedAt: Date
    var expiresAt: Date?
    var isActive: Bool

    init(
        kind: ObstacleKind,
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Double = ObstacleReport.defaultRadiusMeters,
        note: String = "",
        reportedAt: Date = .now,
        isActive: Bool = true
    ) {
        self.id = UUID()
        self.kind = kind
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.radiusMeters = radiusMeters
        self.note = note
        self.reportedAt = reportedAt
        self.expiresAt = kind.defaultShelfLife.map { reportedAt.addingTimeInterval($0) }
        self.isActive = isActive
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func isCurrentlyActive(at date: Date = .now) -> Bool {
        isActive && (expiresAt.map { $0 > date } ?? true)
    }
}
