import Foundation

/// Monta o texto final da regra de execução: depois de consultar Perfil e Mapa (e, para o
/// aviso, Destinos e Histórico), responde com uma instrução clara, calma e honesta.
enum RouteAdvisor {

    static func briefing(
        for result: AccessibleRouteResult,
        place: PlaceAccessibility?,
        lastFeedback: RouteFeedback?
    ) -> String {
        var lines: [String] = []

        let minutes = max(1, Int((result.estimatedDuration / 60).rounded()))
        lines.append("Cerca de \(minutes) min no seu ritmo.")

        // Sala 2 · obstáculos no caminho
        if result.obstaclesNearRoute.isEmpty {
            lines.append("Não há obstáculos registrados neste trajeto.")
        } else {
            if !result.blockingObstacles.isEmpty {
                lines.append(
                    "Atenção: há relato de \(summary(of: result.blockingObstacles)) perto do caminho, "
                    + "e isso pode impedir a passagem. Vale confirmar antes de seguir."
                )
            }
            let others = result.obstaclesNearRoute.filter { obstacle in
                !result.blockingObstacles.contains { $0.latitude == obstacle.latitude && $0.longitude == obstacle.longitude }
            }
            if !others.isEmpty {
                lines.append("No trajeto: \(summary(of: others)). Vá com calma nesses trechos.")
            }
        }

        // Sala 3 · o destino
        if let place {
            var issues: [String] = []
            if place.hasAdaptedEntrance == false { issues.append("entrada sem adaptação") }
            if place.hasAccessibleRestroom == false { issues.append("sem banheiro adaptado") }
            // Referência comum (NBR 9050): vão livre de porta de pelo menos 80 cm.
            if let width = place.doorWidthCm, width < 80 { issues.append("porta estreita (\(Int(width)) cm)") }
            if !issues.isEmpty {
                lines.append("No destino (\(place.name)), seus registros indicam: \(issues.joined(separator: ", ")).")
            }
        }

        // Sala 4 · como foi da última vez
        if let last = lastFeedback {
            let comment = last.comment.trimmed
            if last.rating <= 2 {
                lines.append("Da última vez você achou este trajeto difícil" + (comment.isEmpty ? "." : ": “\(comment)”."))
            } else if last.rating >= 4, !comment.isEmpty {
                lines.append("Da última vez: “\(comment)”.")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Ex.: "buraco (2), degraus (1)".
    private static func summary(of obstacles: [ObstacleSnapshot]) -> String {
        var counts: [ObstacleKind: Int] = [:]
        obstacles.forEach { counts[$0.kind, default: 0] += 1 }
        return counts
            .sorted { $0.key.label < $1.key.label }
            .map { "\($0.key.label.lowercased()) (\($0.value))" }
            .joined(separator: ", ")
    }
}
