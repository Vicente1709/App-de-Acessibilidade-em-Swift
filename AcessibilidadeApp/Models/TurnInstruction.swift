import Foundation
import CoreLocation

/// Próxima manobra da navegação passo a passo, já pronta para exibir.
///
/// O MapKit não informa o TIPO da manobra (só um texto localizado em `MKRoute.Step.instructions`),
/// então a seta vem da geometria: o ângulo entre o rumo com que o passo atual termina e o rumo
/// com que o próximo começa. O texto do MapKit é usado como complemento (nome da rua).
struct TurnInstruction: Equatable {
    enum Maneuver: Equatable {
        case straight
        case slightRight, slightLeft
        case right, left
        case sharpRight, sharpLeft
        case uTurn
        case arrive
    }

    let maneuver: Maneuver
    /// Quanto falta (m) para a manobra, andando pela rota.
    let distanceToManeuver: CLLocationDistance
    /// Instrução textual do MapKit para a manobra (ex.: "Vire à direita na Rua X"), se houver.
    let streetHint: String?
    /// Nome do ponto de chegada (destino ou parada), usado na manobra `.arrive`.
    let arrivalName: String

    // MARK: Classificação do ângulo

    /// Converte o ângulo da curva (positivo = direita) em manobra.
    static func maneuver(forTurnAngle angle: Double) -> Maneuver {
        let magnitude = abs(angle)
        let isRight = angle > 0
        switch magnitude {
        case ..<25: return .straight
        case ..<60: return isRight ? .slightRight : .slightLeft
        case ..<135: return isRight ? .right : .left
        case ..<160: return isRight ? .sharpRight : .sharpLeft
        default: return .uTurn
        }
    }

    // MARK: Apresentação

    /// A partir desta distância a manobra ainda está "longe": a seta mostra seguir em frente.
    private static let farThreshold: CLLocationDistance = 150
    private static let arrivalThreshold: CLLocationDistance = 20

    private var isFar: Bool { distanceToManeuver > Self.farThreshold }

    /// Distância arredondada para falar em voz humana ("40 m", "350 m"), sempre em m/km.
    private var spokenDistance: String {
        let d = distanceToManeuver
        let rounded = d < 200 ? (d / 10).rounded() * 10 : (d / 50).rounded() * 50
        return MetricDistance.string(from: rounded)
    }

    private var isNow: Bool { distanceToManeuver < 10 }

    private var turnName: String {
        switch maneuver {
        case .straight, .arrive: return "Siga em frente"
        case .slightRight: return "Vire levemente à direita"
        case .slightLeft: return "Vire levemente à esquerda"
        case .right: return "Vire à direita"
        case .left: return "Vire à esquerda"
        case .sharpRight: return "Faça a curva fechada à direita"
        case .sharpLeft: return "Faça a curva fechada à esquerda"
        case .uTurn: return "Faça o retorno"
        }
    }

    /// Seta grande exibida no painel.
    var systemImage: String {
        switch maneuver {
        case .arrive:
            return distanceToManeuver <= Self.arrivalThreshold ? "mappin.circle.fill" : "arrow.up"
        case .straight:
            return "arrow.up"
        default:
            if isFar { return "arrow.up" }
            switch maneuver {
            case .slightRight: return "arrow.up.right"
            case .slightLeft: return "arrow.up.left"
            case .right: return "arrow.turn.up.right"
            case .left: return "arrow.turn.up.left"
            case .sharpRight: return "arrow.turn.down.right"
            case .sharpLeft: return "arrow.turn.down.left"
            case .uTurn: return "arrow.uturn.down"
            default: return "arrow.up"
            }
        }
    }

    /// Linha principal ("Vire à direita em 40 m", "Siga em frente na rota").
    var headline: String {
        switch maneuver {
        case .arrive:
            return distanceToManeuver <= Self.arrivalThreshold
                ? "Chegando em \(arrivalName)"
                : "Siga até \(arrivalName)"
        case .straight:
            return "Siga em frente na rota"
        default:
            if isFar { return "Siga em frente na rota" }
            return isNow ? "\(turnName) agora" : "\(turnName) em \(spokenDistance)"
        }
    }

    /// Linha de apoio (prévia da próxima curva, distância restante ou nome da rua).
    var detail: String? {
        switch maneuver {
        case .arrive:
            return "Faltam \(spokenDistance)"
        case .straight:
            return "Continue por \(spokenDistance)"
        default:
            if isFar { return "\(turnName) em \(spokenDistance)" }
            return streetHint
        }
    }
}
