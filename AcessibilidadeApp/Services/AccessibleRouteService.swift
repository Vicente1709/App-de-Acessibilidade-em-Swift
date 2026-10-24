import Foundation
import MapKit

/// Papel de cada opção de rota. A cor correspondente fica em `GlassComponents.swift`.
enum RouteRole: Int, Comparable {
    case ideal        // azul   — melhor combinação de tempo e obstáculos
    case alternative  // verde  — tempo moderado, trajeto seguro
    case detour       // laranja — maior duração, contornando áreas críticas

    var title: String {
        switch self {
        case .ideal: return "Ideal"
        case .alternative: return "Alternativa"
        case .detour: return "Contorno"
        }
    }

    static func < (lhs: RouteRole, rhs: RouteRole) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Uma rota calculada + o que o Palácio da Memória sabe sobre ela.
struct AccessibleRouteResult: Identifiable {
    let id = UUID()
    let route: MKRoute
    /// Soma ponderada dos obstáculos próximos ao trajeto (quanto menor, melhor).
    let score: Double
    /// Custo combinado em "segundos equivalentes": duração + penalidades. Define a rota ideal.
    let cost: Double
    let obstaclesNearRoute: [ObstacleSnapshot]
    let blockingObstacles: [ObstacleSnapshot]
    /// Tempo estimado no ritmo do perfil (não o do MapKit, que assume pedestre comum).
    let estimatedDuration: TimeInterval
    var role: RouteRole = .ideal
}

enum RouteServiceError: Error {
    case noRouteFound
}

/// Calcula rotas a pé e as classifica combinando duração, obstáculos e perfil de mobilidade.
///
/// ⚠️ Limitações reais do MapKit: ele não informa rampas, calçadas rebaixadas, largura de
/// passeio nem relevo, e devolve poucas alternativas (de 1 a 3). Este serviço só consegue
/// ESCOLHER e CLASSIFICAR entre elas — não consegue forçar um desvio que o MapKit não ofereça.
/// Por isso os papéis são relativos: "contorno" é a alternativa mais longa que veio, e o card
/// mostra os fatos (minutos, obstáculos) em vez de prometer que ela evita algo.
final class AccessibleRouteService {

    static let maxRoutes = 3
    /// Cada ponto de pontuação de obstáculo equivale a este tanto de segundos de caminhada.
    static let secondsPerScorePoint = 2.0
    /// Obstáculo que pode bloquear a passagem pesa como 30 minutos a mais.
    static let blockingPenaltySeconds = 1800.0

    func calculateAccessibleRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: MobilitySnapshot,
        obstacles: [ObstacleSnapshot]
    ) async throws -> [AccessibleRouteResult] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        // Estritamente a pé: o MapKit usa caminhos de pedestre (calçadas, travessias, passarelas)
        // quando existem nos dados do mapa.
        request.transportType = .walking
        request.requestsAlternateRoutes = true

        let response = try await MKDirections(request: request).calculate()
        guard !response.routes.isEmpty else { throw RouteServiceError.noRouteFound }

        let evaluated = response.routes
            .prefix(Self.maxRoutes)
            .map { evaluate($0, profile: profile, obstacles: obstacles) }

        return Self.assignRoles(to: evaluated)
    }

    // MARK: - Avaliação

    private func evaluate(
        _ route: MKRoute,
        profile: MobilitySnapshot,
        obstacles: [ObstacleSnapshot]
    ) -> AccessibleRouteResult {
        var score = 0.0
        var near: [ObstacleSnapshot] = []

        for obstacle in obstacles {
            let weight = obstacle.kind.weight(for: profile)
            guard weight > 0 else { continue } // não importa para este perfil

            let coordinate = CLLocationCoordinate2D(latitude: obstacle.latitude, longitude: obstacle.longitude)
            let distance = PolylineGeometry.distanceMeters(from: coordinate, to: route.polyline)
            guard distance < obstacle.radiusMeters else { continue }

            score += (obstacle.radiusMeters - distance) * weight
            near.append(obstacle)
        }

        let blocking = near.filter { $0.kind.isBlocking(for: profile) }
        let duration = route.distance / profile.speedMetersPerSecond
        let cost = duration
            + score * Self.secondsPerScorePoint
            + Double(blocking.count) * Self.blockingPenaltySeconds

        return AccessibleRouteResult(
            route: route,
            score: score,
            cost: cost,
            obstaclesNearRoute: near,
            blockingObstacles: blocking,
            estimatedDuration: duration
        )
    }

    // MARK: - Classificação (azul / verde / laranja)

    /// - Ideal: menor custo combinado (empate → a mais curta).
    /// - Contorno: a de maior duração entre as restantes (se houver 2+ restantes, ou se a única
    ///   restante for pelo menos 25% mais longa que a ideal).
    /// - Alternativa: as demais.
    /// O resultado sai ordenado: ideal, alternativa, contorno.
    static func assignRoles(to results: [AccessibleRouteResult]) -> [AccessibleRouteResult] {
        guard !results.isEmpty else { return [] }

        let byCost = results.sorted { ($0.cost, $0.route.distance) < ($1.cost, $1.route.distance) }
        var ideal = byCost[0]
        ideal.role = .ideal

        let rest = byCost.dropFirst().sorted { $0.estimatedDuration < $1.estimatedDuration }
        var output = [ideal]

        for (index, element) in rest.enumerated() {
            var item = element
            let isLongest = index == rest.count - 1
            let notablyLonger = item.estimatedDuration > ideal.estimatedDuration * 1.25
            item.role = (isLongest && (rest.count >= 2 || notablyLonger)) ? .detour : .alternative
            output.append(item)
        }
        return output
    }
}
