import Foundation
import CoreLocation
import Observation

/// Encapsula o `CLLocationManager` e expõe estado observável (via macro `@Observable`)
/// para ser consumido diretamente pelas Views e ViewModels, sem boilerplate de Combine.
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var heading: CLLocationDirection = 0
    /// Rumo do deslocamento (graus), quando o GPS consegue informar; -1 se desconhecido.
    private(set) var course: CLLocationDirection = -1

    /// Chamado a cada nova leitura de localização. O `MapViewModel` usa isso para detectar
    /// desvios de rota em tempo real. Fora do rastreamento do Observation de propósito.
    @ObservationIgnored var onLocationUpdate: ((CLLocation) -> Void)?

    // MARK: - Distância percorrida (usada durante uma navegação ativa)

    /// Distância acumulada, em metros, desde a última chamada a `beginDistanceTracking()`.
    private(set) var distanceTraveled: CLLocationDistance = 0
    private(set) var isTrackingDistance: Bool = false

    private var lastTrackedLocation: CLLocation?
    /// Ignora leituras com precisão pior que isso (em metros) para não somar "ruído" do GPS
    /// como se fosse deslocamento real — comum quando o usuário está parado.
    private let horizontalAccuracyThreshold: CLLocationAccuracy = 20

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // .fitness é adequado tanto para deslocamento a pé quanto em cadeira de rodas
        // (evita o filtro agressivo de "modo automotivo" para pequenos movimentos).
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Coordenada a `meters` à frente do usuário, no rumo do deslocamento (ou da bússola).
    func coordinate(ahead meters: CLLocationDistance) -> CLLocationCoordinate2D? {
        guard let origin = userLocation else { return nil }
        let bearing = course >= 0 ? course : heading
        return origin.offset(meters: meters, bearingDegrees: bearing)
    }

    // MARK: - Controle da distância percorrida

    /// Zera o acumulador e passa a somar a distância entre atualizações de localização.
    /// Chamado quando o usuário confirma o início de uma rota (`startNavigation`).
    func beginDistanceTracking() {
        distanceTraveled = 0
        lastTrackedLocation = nil
        isTrackingDistance = true
    }

    /// Para de acumular distância. Por padrão também zera o total (ex.: ao finalizar ou
    /// cancelar um trajeto); passe `reset: false` para apenas pausar mantendo o valor atual.
    func stopDistanceTracking(reset: Bool = true) {
        isTrackingDistance = false
        if reset {
            distanceTraveled = 0
            lastTrackedLocation = nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        userLocation = latest.coordinate
        if latest.course >= 0 { course = latest.course }
        onLocationUpdate?(latest)

        guard isTrackingDistance, latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= horizontalAccuracyThreshold else {
            // Ainda guarda a leitura mais recente para servir de base assim que a
            // precisão melhorar, evitando descartar o próximo trecho inteiro.
            if isTrackingDistance { lastTrackedLocation = latest }
            return
        }

        if let previous = lastTrackedLocation {
            distanceTraveled += latest.distance(from: previous)
        }
        lastTrackedLocation = latest
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Erro de localização: \(error.localizedDescription)")
    }
}
