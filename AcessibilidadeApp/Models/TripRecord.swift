import Foundation
import SwiftData

/// Modelo persistido pelo SwiftData representando uma viagem concluída (ou em andamento).
///
/// Guardamos latitude/longitude como `Double` em vez de `CLLocationCoordinate2D` porque
/// esse tipo do CoreLocation não é diretamente persistível pelo SwiftData.
@Model
final class TripRecord {
    @Attribute(.unique) var id: UUID
    var date: Date

    var originName: String
    var originLatitude: Double
    var originLongitude: Double

    var destinationName: String
    var destinationLatitude: Double
    var destinationLongitude: Double

    var isCompleted: Bool
    var distanceInMeters: Double

    init(
        id: UUID = UUID(),
        date: Date = .now,
        originName: String,
        originLatitude: Double,
        originLongitude: Double,
        destinationName: String,
        destinationLatitude: Double,
        destinationLongitude: Double,
        isCompleted: Bool = false,
        distanceInMeters: Double = 0
    ) {
        self.id = id
        self.date = date
        self.originName = originName
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.destinationName = destinationName
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.isCompleted = isCompleted
        self.distanceInMeters = distanceInMeters
    }

    /// Distância formatada para exibição na UI (ex.: "1,2 km").
    var formattedDistance: String {
        MetricDistance.string(from: distanceInMeters)
    }
}
