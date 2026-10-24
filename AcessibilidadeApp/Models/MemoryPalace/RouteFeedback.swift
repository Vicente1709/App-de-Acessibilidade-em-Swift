import Foundation
import SwiftData
import CoreLocation
import Observation

/// [SALA DE HISTÓRICO DE ROTAS]
/// Feedback da pessoa sobre trajetos já feitos: avaliação, comentário, favorita e atalho
/// aprovado. Complementa o `TripRecord` (que guarda só os números da viagem).
@Model
final class RouteFeedback {
    var id: UUID
    /// `TripRecord.id` da viagem avaliada (se houver).
    var tripID: UUID?
    var destinationName: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    /// 1 (muito difícil/cansativa) a 5 (ótima).
    var rating: Int
    var comment: String
    var isFavorite: Bool
    var approvedShortcut: Bool
    var createdAt: Date

    init(
        tripID: UUID?,
        destinationName: String,
        destination: CLLocationCoordinate2D,
        rating: Int,
        comment: String,
        isFavorite: Bool,
        approvedShortcut: Bool
    ) {
        self.id = UUID()
        self.tripID = tripID
        self.destinationName = destinationName
        self.destinationLatitude = destination.latitude
        self.destinationLongitude = destination.longitude
        self.rating = rating
        self.comment = comment
        self.isFavorite = isFavorite
        self.approvedShortcut = approvedShortcut
        self.createdAt = .now
    }
}

/// Lista única dos modelos persistidos — usada no `App` e nos `#Preview`.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        TripRecord.self,
        MobilityProfile.self,
        ObstacleReport.self,
        PlaceAccessibility.self,
        RouteFeedback.self
    ]
}
