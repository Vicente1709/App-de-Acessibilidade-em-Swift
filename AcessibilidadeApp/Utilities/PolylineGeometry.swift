import Foundation
import MapKit

/// Geometria sobre trajetos. Usada para pontuar obstáculos, detectar desvio do usuário
/// (re-routing), escolher a rota tocada no mapa e montar as instruções turn-by-turn.
enum PolylineGeometry {

    // MARK: - Distância até a polilinha

    /// Menor distância (m) entre uma coordenada e qualquer SEGMENTO da polilinha.
    /// Medir só até os vértices falharia em trechos retos longos, que têm poucos pontos.
    static func distanceMeters(from coordinate: CLLocationCoordinate2D, to polyline: MKPolyline) -> CLLocationDistance {
        let count = polyline.pointCount
        guard count > 0 else { return .greatestFiniteMagnitude }

        let target = MKMapPoint(coordinate)
        let points = polyline.points()

        var best = Double.greatestFiniteMagnitude
        if count == 1 {
            best = hypot(target.x - points[0].x, target.y - points[0].y)
        } else {
            for i in 0..<(count - 1) {
                best = min(best, project(target, ontoSegmentFrom: points[i], to: points[i + 1]).distance)
            }
        }
        return best * MKMetersPerMapPointAtLatitude(coordinate.latitude)
    }

    /// Distância (m) em linha reta entre duas coordenadas.
    static func meters(between a: CLLocationCoordinate2D, and b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    // MARK: - Progresso ao longo da polilinha

    /// Quanto falta (m), ANDANDO pela polilinha, entre o ponto dela mais próximo da coordenada
    /// e o fim dela. É o que usamos para "vire em X metros".
    static func remainingDistance(from coordinate: CLLocationCoordinate2D, along polyline: MKPolyline) -> CLLocationDistance {
        let count = polyline.pointCount
        guard count >= 2 else { return 0 }

        let points = polyline.points()
        let target = MKMapPoint(coordinate)

        var bestIndex = 0
        var bestT = 0.0
        var bestDistance = Double.greatestFiniteMagnitude
        for i in 0..<(count - 1) {
            let projection = project(target, ontoSegmentFrom: points[i], to: points[i + 1])
            if projection.distance < bestDistance {
                bestDistance = projection.distance
                bestIndex = i
                bestT = projection.t
            }
        }

        // Resto do segmento atual + todos os segmentos seguintes.
        var remaining = (1 - bestT) * hypot(points[bestIndex + 1].x - points[bestIndex].x,
                                            points[bestIndex + 1].y - points[bestIndex].y)
        for j in (bestIndex + 1)..<(count - 1) {
            remaining += hypot(points[j + 1].x - points[j].x, points[j + 1].y - points[j].y)
        }
        return remaining * MKMetersPerMapPointAtLatitude(coordinate.latitude)
    }

    // MARK: - Corte progressivo (trecho já percorrido)

    /// Quanto da polilinha já foi percorrido: em qual segmento o usuário está e em que fração
    /// `t` (0 = início, 1 = fim) desse segmento. Só avança, nunca volta.
    struct Progress: Equatable {
        var segmentIndex = 0
        var t = 0.0
    }

    /// Corta a polilinha a partir da PROJEÇÃO PERPENDICULAR do usuário nela: o que ficou para
    /// trás some e o novo traçado começa exatamente no ponto projetado.
    ///
    /// - Quem caminha em paralelo (outra calçada, a alguns metros da linha) é tratado
    ///   corretamente: a projeção cai no ponto da rota "ao lado" dele, mesmo sem pisar na linha.
    /// - O progresso é monotônico: a busca começa no segmento anterior e olha só
    ///   `lookAheadMeters` à frente, então uma rota que volta a passar perto de si mesma não
    ///   "pula" o usuário para outro trecho, e o ruído do GPS não faz a linha reaparecer.
    static func trim(
        _ polyline: MKPolyline,
        to coordinate: CLLocationCoordinate2D,
        from progress: Progress,
        lookAheadMeters: CLLocationDistance = 250
    ) -> (polyline: MKPolyline, progress: Progress)? {
        let count = polyline.pointCount
        guard count >= 2 else { return nil }

        let points = polyline.points()
        let target = MKMapPoint(coordinate)
        let scale = MKMetersPerMapPointAtLatitude(coordinate.latitude)
        let startIndex = min(max(progress.segmentIndex, 0), count - 2)

        var best: (index: Int, t: Double, distance: Double)?
        var scanned = 0.0

        for i in startIndex..<(count - 1) {
            let a = points[i]
            let b = points[i + 1]
            var (distance, t) = project(target, ontoSegmentFrom: a, to: b)

            // No segmento em que já estávamos, o progresso não recua.
            if i == startIndex, t < progress.t {
                t = progress.t
                distance = hypot(target.x - (a.x + t * (b.x - a.x)), target.y - (a.y + t * (b.y - a.y)))
            }
            if best == nil || distance < best!.distance { best = (i, t, distance) }

            scanned += hypot(b.x - a.x, b.y - a.y) * scale
            if i >= startIndex + 2, scanned > lookAheadMeters { break }
        }

        guard let best else { return nil }

        let a = points[best.index]
        let b = points[best.index + 1]
        let projected = MKMapPoint(x: a.x + best.t * (b.x - a.x), y: a.y + best.t * (b.y - a.y))

        var remaining: [MKMapPoint] = [projected]
        remaining.append(contentsOf: UnsafeBufferPointer(start: points + best.index + 1, count: count - best.index - 1))
        if remaining.count < 2 { remaining.append(points[count - 1]) }

        let trimmed = remaining.withUnsafeBufferPointer { MKPolyline(points: $0.baseAddress!, count: $0.count) }
        return (trimmed, Progress(segmentIndex: best.index, t: best.t))
    }

    // MARK: - Direção (rumo) e ângulo de curva

    /// Rumo (0–360°, 0 = norte, sentido horário) com que a polilinha TERMINA. Olha pelo menos
    /// `minimumMeters` para trás, para não depender de dois pontos quase colados.
    static func exitBearing(of polyline: MKPolyline, minimumMeters: CLLocationDistance = 5) -> Double? {
        let count = polyline.pointCount
        guard count >= 2 else { return nil }
        let points = polyline.points()
        let end = points[count - 1]
        let scale = MKMetersPerMapPointAtLatitude(end.coordinate.latitude)

        var i = count - 2
        while i > 0, hypot(end.x - points[i].x, end.y - points[i].y) * scale < minimumMeters { i -= 1 }
        return bearing(from: points[i], to: end)
    }

    /// Rumo com que a polilinha COMEÇA (olhando pelo menos `minimumMeters` à frente).
    static func entryBearing(of polyline: MKPolyline, minimumMeters: CLLocationDistance = 5) -> Double? {
        let count = polyline.pointCount
        guard count >= 2 else { return nil }
        let points = polyline.points()
        let start = points[0]
        let scale = MKMetersPerMapPointAtLatitude(start.coordinate.latitude)

        var j = 1
        while j < count - 1, hypot(points[j].x - start.x, points[j].y - start.y) * scale < minimumMeters { j += 1 }
        return bearing(from: start, to: points[j])
    }

    /// Ângulo da curva entre dois rumos, em (-180°, 180°]. Positivo = direita, negativo = esquerda.
    static func turnAngle(fromBearing exit: Double, toBearing entry: Double) -> Double {
        var delta = entry - exit
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return delta
    }

    // MARK: - Privado

    /// Rumo entre dois "map points". A projeção Mercator preserva ângulos localmente; o eixo y
    /// cresce para o sul, daí o sinal negativo.
    private static func bearing(from a: MKMapPoint, to b: MKMapPoint) -> Double? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        guard dx != 0 || dy != 0 else { return nil }
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// Projeta um ponto num segmento: devolve a distância (em "map points") e a posição `t`
    /// da projeção ao longo do segmento (0 = início, 1 = fim).
    private static func project(
        _ p: MKMapPoint,
        ontoSegmentFrom a: MKMapPoint,
        to b: MKMapPoint
    ) -> (distance: Double, t: Double) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (hypot(p.x - a.x, p.y - a.y), 0) }

        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return (hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)), t)
    }
}
