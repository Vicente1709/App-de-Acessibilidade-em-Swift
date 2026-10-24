import Foundation
import SwiftData
import CoreLocation

/// [SALA DE DESTINOS & ESTABELECIMENTOS]
/// Nível de acessibilidade de locais frequentes. Os campos opcionais distinguem
/// "não sei" (`nil`) de "não tem" (`false`) — a diferença importa na hora de avisar a pessoa.
@Model
final class PlaceAccessibility {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var hasAdaptedEntrance: Bool?
    var hasAccessibleRestroom: Bool?
    var hasReservedParking: Bool?
    /// O local empresta cadeira de rodas (ex.: shopping). Alimenta o atalho "Cadeira de rodas
    /// mais próxima" da Home.
    var hasWheelchairLoan: Bool?
    /// Largura livre da porta principal, em centímetros.
    var doorWidthCm: Double?
    var updatedAt: Date

    init(name: String, coordinate: CLLocationCoordinate2D) {
        self.id = UUID()
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.updatedAt = .now
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
