import Foundation
import SwiftData
import CoreLocation

/// Dados preenchidos pela pessoa na tela de feedback pós-trajeto.
struct TripFeedbackInput {
    var rating: Int = 4
    var comment: String = ""
    var isFavorite: Bool = false
    var approvedShortcut: Bool = false
    // Acessibilidade do destino (`nil` = não sei / não informado)
    var hasAdaptedEntrance: Bool?
    var hasAccessibleRestroom: Bool?
    var hasReservedParking: Bool?
    var hasWheelchairLoan: Bool?
    var doorWidthCm: Double?
}

/// Ponto único de acesso às quatro "salas" do Palácio da Memória.
///
/// Ordem de consulta ao calcular uma rota (ver `MapViewModel.calculateRoute`):
/// 1. Sala do Perfil  →  2. Sala do Mapa  →  (3. Destinos e 4. Histórico para o aviso final).
final class MemoryPalace {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Sala 1 · Perfil & Mobilidade

    /// Retorna o perfil salvo; se ainda não existir, cria um com os padrões conservadores.
    func mobilityProfile() -> MobilityProfile {
        if let existing = (try? context.fetch(FetchDescriptor<MobilityProfile>()))?.first {
            return existing
        }
        let profile = MobilityProfile()
        context.insert(profile)
        return profile
    }

    func mobilitySnapshot() -> MobilitySnapshot {
        let profile = mobilityProfile()
        return MobilitySnapshot(
            chair: profile.wheelchairType,
            autonomy: profile.autonomyLevel,
            speedKmh: profile.averageSpeedKmh,
            maxInclinePercent: profile.maxInclinePercent,
            prefersShade: profile.prefersShade,
            avoidsUnevenSurfaces: profile.avoidsUnevenSurfaces,
            needsCurbCuts: profile.needsCurbCuts
        )
    }

    // MARK: - Sala 2 · Mapa & Obstáculos

    func activeObstacles(now: Date = .now) -> [ObstacleReport] {
        let all = (try? context.fetch(FetchDescriptor<ObstacleReport>())) ?? []
        return all.filter { $0.isCurrentlyActive(at: now) }
    }

    func obstacleSnapshots() -> [ObstacleSnapshot] {
        activeObstacles().map {
            ObstacleSnapshot(
                kind: $0.kind,
                latitude: $0.latitude,
                longitude: $0.longitude,
                radiusMeters: $0.radiusMeters,
                note: $0.note
            )
        }
    }

    @discardableResult
    func reportObstacle(kind: ObstacleKind, at coordinate: CLLocationCoordinate2D, note: String) -> ObstacleReport {
        let report = ObstacleReport(kind: kind, coordinate: coordinate, note: note.trimmed)
        context.insert(report)
        // Salva já: o re-routing recalcula a rota logo depois e precisa enxergar este relato.
        try? context.save()
        return report
    }

    // MARK: - Sala 3 · Destinos & Estabelecimentos

    func place(near coordinate: CLLocationCoordinate2D, within meters: CLLocationDistance = 75) -> PlaceAccessibility? {
        let places = (try? context.fetch(FetchDescriptor<PlaceAccessibility>())) ?? []
        return places
            .map { ($0, Self.distance(from: $0.coordinate, to: coordinate)) }
            .filter { $0.1 <= meters }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Locais que a pessoa registrou como emprestadores de cadeira de rodas.
    func placesWithWheelchairLoan() -> [PlaceAccessibility] {
        let all = (try? context.fetch(FetchDescriptor<PlaceAccessibility>())) ?? []
        return all.filter { $0.hasWheelchairLoan == true }
    }

    /// Atualiza (ou cria) o registro do local, sobrescrevendo apenas o que foi informado agora.
    func updatePlace(name: String, coordinate: CLLocationCoordinate2D, from input: TripFeedbackInput) {
        let hasNewInfo = input.hasAdaptedEntrance != nil
            || input.hasAccessibleRestroom != nil
            || input.hasReservedParking != nil
            || input.hasWheelchairLoan != nil
            || input.doorWidthCm != nil
        guard hasNewInfo else { return }

        let place: PlaceAccessibility
        if let existing = self.place(near: coordinate) {
            place = existing
        } else {
            place = PlaceAccessibility(name: name, coordinate: coordinate)
            context.insert(place)
        }

        if let value = input.hasAdaptedEntrance { place.hasAdaptedEntrance = value }
        if let value = input.hasAccessibleRestroom { place.hasAccessibleRestroom = value }
        if let value = input.hasReservedParking { place.hasReservedParking = value }
        if let value = input.hasWheelchairLoan { place.hasWheelchairLoan = value }
        if let value = input.doorWidthCm { place.doorWidthCm = value }
        place.updatedAt = .now
    }

    // MARK: - Sala 4 · Histórico de Rotas

    func latestFeedback(near coordinate: CLLocationCoordinate2D, within meters: CLLocationDistance = 150) -> RouteFeedback? {
        let descriptor = FetchDescriptor<RouteFeedback>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first {
            Self.distance(
                from: CLLocationCoordinate2D(latitude: $0.destinationLatitude, longitude: $0.destinationLongitude),
                to: coordinate
            ) <= meters
        }
    }

    func saveFeedback(
        tripID: UUID?,
        destinationName: String,
        destination: CLLocationCoordinate2D,
        input: TripFeedbackInput
    ) {
        let feedback = RouteFeedback(
            tripID: tripID,
            destinationName: destinationName,
            destination: destination,
            rating: min(max(input.rating, 1), 5),
            comment: input.comment.trimmed,
            isFavorite: input.isFavorite,
            approvedShortcut: input.approvedShortcut
        )
        context.insert(feedback)
        updatePlace(name: destinationName, coordinate: destination, from: input)
    }

    // MARK: - Utilitário

    private static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
