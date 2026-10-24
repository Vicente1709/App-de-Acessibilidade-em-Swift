import Foundation
import MapKit

/// Busca de pontos de interesse (farmácias e shoppings) via `MKLocalSearch`.
final class POISearchService {

    /// Acima disso o mapa está "afastado demais" e a busca devolveria resultados espalhados.
    static let maxSearchSpanDegrees: CLLocationDegrees = 0.5

    /// POI do tipo pedido mais próximo de `coordinate`. Amplia o raio da busca aos poucos
    /// (≈ 5, 16 e 44 km); a distância é em linha reta, não a pé.
    func nearest(_ kind: PlaceKind, to coordinate: CLLocationCoordinate2D) async -> PlaceItem? {
        for span in [0.05, 0.15, 0.4] {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
            let results = await search(kind, in: region, limit: 15)
            let closest = results.min {
                PolylineGeometry.meters(between: coordinate, and: $0.coordinate)
                    < PolylineGeometry.meters(between: coordinate, and: $1.coordinate)
            }
            if let closest { return closest }
        }
        return nil
    }

    func search(_ kind: PlaceKind, in region: MKCoordinateRegion, limit: Int = 12) async -> [PlaceItem] {
        guard region.span.latitudeDelta <= Self.maxSearchSpanDegrees else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = kind.query
        request.region = region
        request.resultTypes = .pointOfInterest
        if let categories = kind.categories {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        }

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        return response.mapItems.prefix(limit).compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            return PlaceItem(name: name, kind: kind, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}
