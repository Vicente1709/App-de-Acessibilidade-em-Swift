import Foundation
import MapKit
import CoreLocation

extension MKRoute {
    /// Distância da rota formatada para exibição na UI (ex.: "850 m", "1,2 km").
    var formattedDistance: String {
        MetricDistance.string(from: distance)
    }
}

// MARK: - Strings

extension String {
    /// Remove espaços e quebras de linha das pontas.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Coordenadas

extension CLLocationCoordinate2D {
    /// Ponto a `meters` de distância, seguindo o rumo `bearingDegrees` (0° = norte).
    /// Usa a fórmula esférica de destino; o erro é desprezível para dezenas de metros.
    func offset(meters: CLLocationDistance, bearingDegrees: CLLocationDirection) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angularDistance = meters / earthRadius
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
