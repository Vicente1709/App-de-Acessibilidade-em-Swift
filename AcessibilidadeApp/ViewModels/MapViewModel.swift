import Foundation
import MapKit
import SwiftData
import Observation

/// Estado do fluxo de navegação exibido na `MapView`.
/// Também é o estado que a `HomeView` consulta para saber se existe um trajeto ativo
/// (ex.: para trocar o texto do botão central para "Voltar à Rota").
enum NavigationState {
    case idle          // aguardando o usuário buscar um destino
    case routePreview  // rotas calculadas, usuário escolhendo uma antes de iniciar
    case navigating    // trajeto confirmado, rastreando em tempo real
}

/// Trajeto recém-finalizado, à espera do feedback da pessoa (Sala do Histórico).
struct PendingFeedback: Identifiable {
    let id: UUID // id do TripRecord
    let destinationName: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Motivo de um recálculo automático. Cada um tem seu próprio tempo de espera (cooldown).
enum RerouteReason {
    case offRoute         // usuário se afastou da rota
    case newObstacle      // obstáculo relatado no caminho à frente
    case waypointReached  // chegou na parada (farmácia): seguir para o destino final

    var cooldown: TimeInterval {
        switch self {
        case .offRoute: return 20
        case .newObstacle: return 5
        case .waypointReached: return 0
        }
    }
}

/// Atalhos rápidos da Home: vão direto ao POI mais útil e mais próximo.
enum QuickDestination: Equatable {
    case pharmacy        // farmácia mais próxima
    case wheelchairLoan  // local com empréstimo de cadeira de rodas mais próximo
}

@MainActor
@Observable
final class MapViewModel: NSObject {

    /// Parâmetros do re-routing e da parada em farmácia.
    private enum Config {
        /// Distância (m) da rota a partir da qual o usuário é considerado "fora do trajeto".
        static let offRouteThreshold: CLLocationDistance = 25
        /// Leituras de GPS piores que isso (m) são ignoradas, para o ruído não disparar recálculos.
        static let maxReliableAccuracy: CLLocationAccuracy = 25
        /// Leituras consecutivas fora da rota exigidas antes de recalcular.
        static let offRouteStrikesToReroute = 2
        /// Raio (m) para considerar que o usuário chegou na parada.
        static let waypointArrivalRadius: CLLocationDistance = 30
        /// Distância máxima (m) entre a rota e a farmácia para ela contar como "no caminho".
        static let maxPharmacyOffset: CLLocationDistance = 300
        /// Raio (m) do destino final que encerra a navegação sozinha (faixa sugerida: 10–40 m).
        static let arrivalRadius: CLLocationDistance = 25
        /// Leituras consecutivas dentro do raio exigidas antes de encerrar (evita pico de GPS).
        static let arrivalStrikesRequired = 2
        /// Distância mínima percorrida antes de permitir a chegada automática (evita encerrar
        /// logo na largada se o destino estiver colado).
        static let minTravelBeforeArrival: CLLocationDistance = 10
        /// Raio (m) para marcar como "concluída" uma viagem finalizada manualmente.
        static let manualCompletionRadius: CLLocationDistance = 40
        /// Quantos resultados da busca têm a categoria resolvida (uma requisição cada).
        static let categoryLookups = 6
    }

    // MARK: Busca de destino

    var searchText: String = "" {
        didSet { completer.queryFragment = searchText }
    }
    var searchResults: [MKLocalSearchCompletion] = []
    /// Texto da última sugestão escolhida; enquanto o campo continuar igual a ele, a lista fica oculta.
    private(set) var selectedSuggestionText: String?

    /// Sugestões a exibir (Home e mapa): vazias quando o campo está vazio ou já contém a escolha.
    var suggestions: [MKLocalSearchCompletion] {
        guard !searchText.isEmpty, searchText != selectedSuggestionText else { return [] }
        return searchResults
    }

    // MARK: Rotas / navegação

    var destinationName: String = ""
    var destinationCoordinate: CLLocationCoordinate2D?
    /// Até 3 opções calculadas (ideal, alternativa, contorno). Durante a navegação, só a ativa.
    var routeOptions: [AccessibleRouteResult] = []
    var selectedRouteID: UUID?
    var navigationState: NavigationState = .idle
    var isCalculatingRoute: Bool = false
    var errorMessage: String?
    /// Aviso curto e temporário (ex.: "Rota recalculada", "Nenhuma farmácia perto do trajeto").
    var notice: String?

    // MARK: Palácio da Memória

    /// Instrução por rota, montada com o que as salas sabem (perfil, obstáculos, destino, histórico).
    private(set) var briefings: [UUID: String] = [:]
    /// Quando preenchido, a MapView abre a tela de feedback pós-trajeto.
    var pendingFeedback: PendingFeedback?

    // MARK: POIs (farmácias e shoppings)

    var showPharmacies = false {
        didSet {
            if !showPharmacies { pharmacies = [] }
            schedulePlacesRefresh()
        }
    }
    var showShoppings = false {
        didSet {
            if !showShoppings { shoppings = [] }
            schedulePlacesRefresh()
        }
    }
    private(set) var pharmacies: [PlaceItem] = []
    private(set) var shoppings: [PlaceItem] = []
    var selectedPlaceID: UUID?
    /// "Incluir parada/passagem por farmácia próxima".
    var includePharmacyStop = false
    /// Parada intermediária em andamento (a navegação vai até ela e depois segue ao destino).
    private(set) var waypoint: PlaceItem?

    // MARK: Re-routing

    private(set) var isRerouting = false

    // MARK: Turn-by-turn e atalhos

    /// Próxima manobra, atualizada a cada leitura de GPS durante a navegação.
    private(set) var turnInstruction: TurnInstruction?
    /// Atalho da Home cuja busca está em andamento (para mostrar o carregando no botão).
    private(set) var quickSearchInProgress: QuickDestination?

    // MARK: Trecho restante e ícones da busca

    /// Parte da rota ativa que ainda falta percorrer (o trecho já deixado para trás some).
    private(set) var remainingPolyline: MKPolyline?
    /// Categorias reais (MapKit) dos resultados da busca, resolvidas sob demanda.
    private(set) var resultCategories: [String: MKPointOfInterestCategory] = [:]

    // MARK: Dependências e estado interno

    private let completer = MKLocalSearchCompleter()
    private let routeService: AccessibleRouteService
    private let poiService: POISearchService
    /// Injetado a partir da `HomeView`: é a MESMA instância usada pela `MapView`, então a
    /// distância acumulada reflete o rastreamento real mesmo após fechar/reabrir o mapa.
    private let locationManager: LocationManager
    /// Criado em `configure(context:)`, pois o ModelContext só existe dentro da hierarquia de Views.
    @ObservationIgnored private var palace: MemoryPalace?

    @ObservationIgnored private var visibleRegion: MKCoordinateRegion?
    @ObservationIgnored private var placesTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var offRouteStrikes = 0
    @ObservationIgnored private var lastRerouteAt: Date?
    /// Distância acumulada no momento em que a rota atual começou (zero na largada; muda a
    /// cada recálculo). Permite medir "restante" na rota nova sem zerar o total percorrido.
    @ObservationIgnored private var routeBaseline: CLLocationDistance = 0
    /// Passo da rota em que o usuário está. Nunca regride, para o GPS não "voltar" a instrução.
    @ObservationIgnored private var currentStepIndex = 0
    @ObservationIgnored private var trimProgress = PolylineGeometry.Progress()
    @ObservationIgnored private var arrivalStrikes = 0
    /// Onde a navegação começou (a origem do `TripRecord`).
    @ObservationIgnored private var tripOrigin: CLLocationCoordinate2D?
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var categoryTask: Task<Void, Never>?
    @ObservationIgnored private var attemptedCategoryKeys: Set<String> = []

    init(
        locationManager: LocationManager,
        routeService: AccessibleRouteService = AccessibleRouteService(),
        poiService: POISearchService = POISearchService()
    ) {
        self.locationManager = locationManager
        self.routeService = routeService
        self.poiService = poiService
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
        // Restringe as sugestões de busca à região do Distrito Federal.
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -15.7942, longitude: -47.8822),
            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
        )
        // Monitoramento contínuo: cada leitura de GPS passa por `handleLocationUpdate`.
        locationManager.onLocationUpdate = { [weak self] location in
            Task { @MainActor in self?.handleLocationUpdate(location) }
        }
    }

    /// Conecta o ViewModel ao SwiftData. Chamado pela `HomeView` assim que ela aparece.
    func configure(context: ModelContext) {
        palace = MemoryPalace(context: context)
        modelContext = context
    }

    // MARK: - Rota selecionada (derivados)

    var selectedResult: AccessibleRouteResult? {
        routeOptions.first { $0.id == selectedRouteID }
    }

    var route: MKRoute? { selectedResult?.route }

    var routeBriefing: String? {
        selectedRouteID.flatMap { briefings[$0] }
    }

    var routeHasBlockingObstacle: Bool {
        !(selectedResult?.blockingObstacles.isEmpty ?? true)
    }

    /// Para onde a navegação está indo agora: a parada (se houver) ou o destino final.
    var currentTargetName: String {
        waypoint?.name ?? destinationName
    }

    var selectedPlace: PlaceItem? {
        (pharmacies + shoppings).first { $0.id == selectedPlaceID }
    }

    // MARK: - Busca e cálculo de rotas

    /// Resolve a sugestão de busca escolhida em uma coordenada concreta e a define como destino.
    /// Devolve `true` se deu certo — a Home então abre o mapa, que calcula as rotas sozinho
    /// (`.task(id: destinationName)` na MapView).
    @discardableResult
    func selectCompletion(_ completion: MKLocalSearchCompletion) async -> Bool {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else {
                errorMessage = "Não foi possível localizar o destino selecionado."
                return false
            }
            // Evita que a lista de sugestões reapareça quando o texto vira o título escolhido.
            selectedSuggestionText = completion.title
            destinationCoordinate = item.placemark.coordinate
            destinationName = completion.title
            searchResults = []
            searchText = completion.title
            return true
        } catch {
            errorMessage = "Não foi possível localizar o destino selecionado."
            return false
        }
    }

    /// Calcula as opções de rota (prévia) a partir da localização atual do usuário.
    /// Ordem do Palácio: 1) Sala do Perfil → 2) Sala do Mapa → rotas → aviso final.
    func calculateRoute(from origin: CLLocationCoordinate2D) async {
        guard let destination = destinationCoordinate else { return }
        let requestedName = destinationName
        isCalculatingRoute = true
        defer { isCalculatingRoute = false }

        do {
            var options = try await computeOptions(from: origin, to: destination)
            var stop: PlaceItem?

            // Parada em farmácia: acha a mais próxima do trajeto ideal e traça a rota até ela
            // primeiro. Ao chegar, o re-routing leva ao destino final.
            if includePharmacyStop, let ideal = options.first {
                if let pharmacy = await pharmacyAlongRoute(ideal.route) {
                    stop = pharmacy
                    options = try await computeOptions(from: origin, to: pharmacy.coordinate)
                } else {
                    showNotice("Nenhuma farmácia encontrada a até \(MetricDistance.string(from: Config.maxPharmacyOffset)) do trajeto.")
                }
            }

            // O usuário pode ter voltado/trocado de destino enquanto calculávamos.
            guard requestedName == destinationName, navigationState != .navigating else { return }

            waypoint = stop
            publish(options, selecting: options.first?.id)
            navigationState = .routePreview
        } catch {
            errorMessage = "Não foi possível calcular uma rota acessível para este destino."
        }
    }

    /// Lê Perfil (Sala 1) e Obstáculos (Sala 2) e pede as rotas ao serviço.
    private func computeOptions(
        from origin: CLLocationCoordinate2D,
        to target: CLLocationCoordinate2D
    ) async throws -> [AccessibleRouteResult] {
        let profile = palace?.mobilitySnapshot() ?? .default
        let obstacles = palace?.obstacleSnapshots() ?? []
        return try await routeService.calculateAccessibleRoute(
            from: origin,
            to: target,
            profile: profile,
            obstacles: obstacles
        )
    }

    /// Guarda as opções e monta o aviso de cada uma (cruzando Salas 3 e 4 pelo destino final).
    private func publish(_ options: [AccessibleRouteResult], selecting id: UUID?) {
        var texts: [UUID: String] = [:]
        let place = destinationCoordinate.flatMap { palace?.place(near: $0) }
        let last = destinationCoordinate.flatMap { palace?.latestFeedback(near: $0) }

        for option in options {
            var text = RouteAdvisor.briefing(for: option, place: place, lastFeedback: last)
            if let waypoint {
                text = "Parada: \(waypoint.name). Depois seguimos para \(destinationName).\n" + text
            }
            texts[option.id] = text
        }

        routeOptions = options
        briefings = texts
        selectedRouteID = id ?? options.first?.id

        // Rota nova durante a navegação (recálculo): recomeça a contar os passos daqui.
        if navigationState == .navigating {
            currentStepIndex = 0
            turnInstruction = nil
            trimProgress = PolylineGeometry.Progress()
            remainingPolyline = selectedResult?.route.polyline
            if let here = locationManager.userLocation {
                updateRemainingPolyline(at: here)
                refreshTurnInstruction(at: here)
            }
        }
    }

    // MARK: - Escolha da rota

    /// Define a rota ativa (card ou toque na polilinha) — só na prévia.
    func selectRoute(_ id: UUID) {
        guard navigationState == .routePreview, routeOptions.contains(where: { $0.id == id }) else { return }
        selectedRouteID = id
    }

    /// Seleciona a rota mais próxima de um toque no mapa. Devolve `true` se alguma estava
    /// dentro da tolerância (em metros).
    @discardableResult
    func selectRoute(near coordinate: CLLocationCoordinate2D, toleranceMeters: CLLocationDistance) -> Bool {
        guard navigationState == .routePreview else { return false }
        let nearest = routeOptions
            .map { ($0, PolylineGeometry.distanceMeters(from: coordinate, to: $0.route.polyline)) }
            .filter { $0.1 <= toleranceMeters }
            .min { $0.1 < $1.1 }
        guard let nearest else { return false }
        selectedRouteID = nearest.0.id
        return true
    }

    // MARK: - Ciclo da navegação

    /// Cancela a rota atual e retorna ao estado inicial.
    /// Chamado quando o usuário sai da MapView sem confirmar o trajeto, ou antes de
    /// carregar um novo destino a partir do histórico.
    func cancelRoute() {
        routeOptions = []
        selectedRouteID = nil
        briefings = [:]
        waypoint = nil
        includePharmacyStop = false
        notice = nil
        selectedPlaceID = nil
        destinationCoordinate = nil
        destinationName = ""
        searchText = ""
        searchResults = []
        selectedSuggestionText = nil
        navigationState = .idle
        isRerouting = false
        offRouteStrikes = 0
        lastRerouteAt = nil
        routeBaseline = 0
        currentStepIndex = 0
        turnInstruction = nil
        trimProgress = PolylineGeometry.Progress()
        remainingPolyline = nil
        arrivalStrikes = 0
        tripOrigin = nil
        locationManager.stopDistanceTracking()
    }

    /// Confirma a rota escolhida e começa a navegação.
    func startNavigation() {
        guard let selected = selectedResult else { return }
        // Durante a navegação só a rota escolhida continua no mapa.
        routeOptions = [selected]
        selectedRouteID = selected.id
        routeBaseline = 0
        offRouteStrikes = 0
        lastRerouteAt = nil
        currentStepIndex = 0
        trimProgress = PolylineGeometry.Progress()
        remainingPolyline = selected.route.polyline
        arrivalStrikes = 0
        tripOrigin = locationManager.userLocation
        navigationState = .navigating
        locationManager.beginDistanceTracking()
        if let here = locationManager.userLocation {
            updateRemainingPolyline(at: here)
            refreshTurnInstruction(at: here)
        }
    }

    /// Conclui o trajeto, persiste o registro no SwiftData (distância realmente percorrida)
    /// e pede o feedback da pessoa para a Sala do Histórico.
    ///
    /// - Parameter arrived: `true` quando a chegada foi detectada automaticamente (dispara o
    ///   feedback tátil de sucesso). Em finalização manual, a viagem só é marcada como concluída
    ///   se o usuário estiver a até `manualCompletionRadius` do destino.
    func finishTrip(context: ModelContext? = nil, arrived: Bool = false) {
        guard let destination = destinationCoordinate,
              let context = context ?? modelContext else { return }

        let traveled = locationManager.distanceTraveled
        // Fallback para a distância planejada caso o GPS não tenha acumulado nada
        // (ex.: trajetos muito curtos ou testes no simulador sem movimento simulado).
        let finalDistance = traveled > 0 ? traveled : (route?.distance ?? 0)

        let origin = tripOrigin ?? locationManager.userLocation ?? destination
        let reachedDestination = arrived || (locationManager.userLocation.map {
            PolylineGeometry.meters(between: $0, and: destination) <= Config.manualCompletionRadius
        } ?? false)

        let trip = TripRecord(
            originName: "Ponto de partida",
            originLatitude: origin.latitude,
            originLongitude: origin.longitude,
            destinationName: destinationName,
            destinationLatitude: destination.latitude,
            destinationLongitude: destination.longitude,
            isCompleted: reachedDestination,
            distanceInMeters: finalDistance
        )
        context.insert(trip)

        pendingFeedback = PendingFeedback(
            id: trip.id,
            destinationName: destinationName,
            latitude: destination.latitude,
            longitude: destination.longitude
        )

        cancelRoute()
        if arrived { Haptics.success() }
    }

    /// Recarrega o destino de uma viagem salva no histórico e prepara o ViewModel para
    /// que a `MapView` recalcule automaticamente a rota acessível até lá.
    func loadTrip(_ trip: TripRecord) {
        cancelRoute() // garante um estado limpo antes de carregar o novo destino
        destinationCoordinate = CLLocationCoordinate2D(
            latitude: trip.destinationLatitude,
            longitude: trip.destinationLongitude
        )
        destinationName = trip.destinationName
        selectedSuggestionText = trip.destinationName
        searchText = trip.destinationName
    }

    // MARK: - Re-routing automático

    /// Chamado a cada leitura de GPS durante a navegação.
    private func handleLocationUpdate(_ location: CLLocation) {
        guard navigationState == .navigating, let route else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Config.maxReliableAccuracy else { return }

        // Chegou ao destino final? Encerra sozinho (vale mesmo durante um recálculo).
        if checkArrival(at: location.coordinate) { return }

        guard !isRerouting else { return }

        // Chegou na parada? Segue para o destino final.
        if let waypoint,
           PolylineGeometry.meters(between: location.coordinate, and: waypoint.coordinate) <= Config.waypointArrivalRadius {
            completeWaypoint(named: waypoint.name)
            return
        }

        updateRemainingPolyline(at: location.coordinate)
        refreshTurnInstruction(at: location.coordinate)

        // Desvio: exige leituras consecutivas fora da rota para não reagir a um pico de GPS.
        let offRoute = PolylineGeometry.distanceMeters(from: location.coordinate, to: route.polyline)
        offRouteStrikes = offRoute > Config.offRouteThreshold ? offRouteStrikes + 1 : 0
        if offRouteStrikes >= Config.offRouteStrikesToReroute {
            requestReroute(reason: .offRoute)
        }
    }

    // MARK: - Chegada automática

    /// Encerra a navegação quando o usuário fica a até `arrivalRadius` do destino final
    /// (em linha reta) em leituras consecutivas. Devolve `true` se encerrou.
    private func checkArrival(at coordinate: CLLocationCoordinate2D) -> Bool {
        // Com parada pendente o destino final ainda não é o alvo; e só vale depois de andar um pouco.
        guard waypoint == nil,
              let destination = destinationCoordinate,
              locationManager.distanceTraveled >= Config.minTravelBeforeArrival else {
            arrivalStrikes = 0
            return false
        }

        if PolylineGeometry.meters(between: coordinate, and: destination) <= Config.arrivalRadius {
            arrivalStrikes += 1
        } else {
            arrivalStrikes = 0
        }
        guard arrivalStrikes >= Config.arrivalStrikesRequired else { return false }

        finishTrip(arrived: true)
        return true
    }

    // MARK: - Corte da polilinha

    /// Atualiza o trecho restante a partir da projeção do usuário na rota ativa.
    private func updateRemainingPolyline(at coordinate: CLLocationCoordinate2D) {
        guard let route else { remainingPolyline = nil; return }
        guard let result = PolylineGeometry.trim(route.polyline, to: coordinate, from: trimProgress) else { return }
        trimProgress = result.progress
        remainingPolyline = result.polyline
    }

    private func completeWaypoint(named name: String) {
        waypoint = nil
        includePharmacyStop = false
        showNotice("Parada em \(name) concluída. Seguindo para \(destinationName).")
        requestReroute(reason: .waypointReached)
    }

    /// Dispara um recálculo em segundo plano, respeitando o cooldown do motivo.
    private func requestReroute(reason: RerouteReason) {
        guard navigationState == .navigating, !isRerouting,
              let origin = locationManager.userLocation else { return }

        let now = Date()
        if let last = lastRerouteAt, now.timeIntervalSince(last) < reason.cooldown { return }
        lastRerouteAt = now
        offRouteStrikes = 0

        Task { await performReroute(from: origin, reason: reason) }
    }

    /// Recalcula SEM interromper a sessão: o estado continua `.navigating`, o rastreamento de
    /// distância não é zerado e nada é gravado no `TripRecord` (ele só nasce em `finishTrip`).
    private func performReroute(from origin: CLLocationCoordinate2D, reason: RerouteReason) async {
        guard let target = waypoint?.coordinate ?? destinationCoordinate else { return }
        let previousRole = selectedResult?.role

        isRerouting = true
        defer { isRerouting = false }

        do {
            let options = try await computeOptions(from: origin, to: target)

            // O trajeto pode ter sido encerrado enquanto calculávamos.
            guard navigationState == .navigating else { return }

            // Desvio: respeita o papel escolhido pela pessoa (se ainda existir).
            // Obstáculo novo / chegada na parada: a melhor rota atual (ideal).
            let chosen: AccessibleRouteResult? = (reason == .offRoute)
                ? (options.first { $0.role == previousRole } ?? options.first)
                : options.first

            guard let chosen else { return }
            publish([chosen], selecting: chosen.id)
            routeBaseline = locationManager.distanceTraveled

            switch reason {
            case .offRoute: showNotice("Você saiu da rota. Rota recalculada.")
            case .newObstacle: showNotice("Obstáculo registrado. Rota recalculada para tentar desviar.")
            case .waypointReached: break // o aviso de parada concluída já está na tela
            }
        } catch {
            // Mantém a rota atual; o cooldown já impede novas tentativas em sequência.
            showNotice("Não foi possível recalcular agora. Mantendo a rota atual.")
        }
    }

    // MARK: - Palácio da Memória · registros feitos pela pessoa

    /// Registra um obstáculo (Sala do Mapa). Vale para as próximas rotas e, se estiver no
    /// caminho durante a navegação, dispara um recálculo.
    @discardableResult
    func reportObstacle(kind: ObstacleKind, note: String, placement: ObstaclePlacement = .here) -> Bool {
        guard let palace, let location = locationManager.userLocation else {
            errorMessage = "Não foi possível registrar o obstáculo: localização indisponível."
            return false
        }
        let coordinate = placement == .ahead
            ? (locationManager.coordinate(ahead: 20) ?? location)
            : location

        palace.reportObstacle(kind: kind, at: coordinate, note: note)
        rerouteIfObstacleOnRoute(kind: kind, at: coordinate)
        return true
    }

    private func rerouteIfObstacleOnRoute(kind: ObstacleKind, at coordinate: CLLocationCoordinate2D) {
        guard navigationState == .navigating, let route else { return }
        let profile = palace?.mobilitySnapshot() ?? .default
        guard kind.weight(for: profile) > 0 else { return } // não importa para este perfil

        let distance = PolylineGeometry.distanceMeters(from: coordinate, to: route.polyline)
        if distance < ObstacleReport.defaultRadiusMeters {
            requestReroute(reason: .newObstacle)
        }
    }

    /// Salva o feedback do trajeto (Sala do Histórico) e o que a pessoa informou sobre o
    /// destino (Sala de Destinos).
    func submitFeedback(_ input: TripFeedbackInput, for pending: PendingFeedback) {
        palace?.saveFeedback(
            tripID: pending.id,
            destinationName: pending.destinationName,
            destination: pending.coordinate,
            input: input
        )
    }

    // MARK: - POIs

    /// Chamado pela MapView quando o usuário termina de mover/aproximar o mapa.
    func mapRegionChanged(_ region: MKCoordinateRegion) {
        visibleRegion = region
        schedulePlacesRefresh()
    }

    /// Busca com pequeno debounce, para não consultar a cada movimento do mapa.
    private func schedulePlacesRefresh() {
        placesTask?.cancel()
        guard showPharmacies || showShoppings else { return }

        placesTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.refreshPlaces()
        }
    }

    private func refreshPlaces() async {
        guard let region = visibleRegion else { return }

        if region.span.latitudeDelta > POISearchService.maxSearchSpanDegrees {
            showNotice("Aproxime o mapa para ver farmácias e shoppings.")
            return
        }
        if showPharmacies {
            let found = await poiService.search(.pharmacy, in: region)
            if !Task.isCancelled, showPharmacies { pharmacies = found }
        }
        if showShoppings {
            let found = await poiService.search(.shopping, in: region)
            if !Task.isCancelled, showShoppings { shoppings = found }
        }
    }

    /// Farmácia mais próxima do trajeto, desde que a até `maxPharmacyOffset` metros dele.
    private func pharmacyAlongRoute(_ route: MKRoute) async -> PlaceItem? {
        var region = MKCoordinateRegion(route.polyline.boundingMapRect)
        region.span.latitudeDelta = max(region.span.latitudeDelta * 1.3, 0.01)
        region.span.longitudeDelta = max(region.span.longitudeDelta * 1.3, 0.01)

        let candidates = await poiService.search(.pharmacy, in: region, limit: 15)
        return candidates
            .map { ($0, PolylineGeometry.distanceMeters(from: $0.coordinate, to: route.polyline)) }
            .filter { $0.1 <= Config.maxPharmacyOffset }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Usa um POI tocado no mapa como destino (a MapView recalcula as rotas).
    func useAsDestination(_ place: PlaceItem) {
        selectedPlaceID = nil
        guard navigationState != .navigating else { return }
        setDestination(name: place.name, coordinate: place.coordinate)
    }

    /// Define um novo destino e limpa qualquer prévia anterior. A MapView recalcula as rotas
    /// sozinha (`.task(id: destinationName)`).
    private func setDestination(name: String, coordinate: CLLocationCoordinate2D) {
        routeOptions = []
        selectedRouteID = nil
        briefings = [:]
        waypoint = nil
        includePharmacyStop = false
        destinationCoordinate = coordinate
        destinationName = name
        selectedSuggestionText = name
        searchText = name
        searchResults = []
        navigationState = .idle
    }

    // MARK: - Atalhos rápidos (Home)

    /// Procura o POI do atalho mais próximo do usuário e o define como destino.
    /// Devolve `true` se há um destino pronto — a Home então abre o mapa, que calcula as rotas.
    ///
    /// - Farmácia: a mais próxima em linha reta (via `POISearchService`).
    /// - Cadeira de rodas: primeiro os locais que a pessoa registrou com empréstimo (Sala de
    ///   Destinos); se não houver, o shopping mais próximo, com aviso para confirmar na chegada.
    @discardableResult
    func startQuickRoute(to quick: QuickDestination) async -> Bool {
        guard navigationState != .navigating else { return false }
        guard let origin = locationManager.userLocation else {
            errorMessage = "Não foi possível obter sua localização. Verifique a permissão de localização e tente de novo."
            return false
        }

        quickSearchInProgress = quick
        defer { quickSearchInProgress = nil }

        switch quick {
        case .pharmacy:
            guard let pharmacy = await poiService.nearest(.pharmacy, to: origin) else {
                errorMessage = "Não encontrei nenhuma farmácia por perto."
                return false
            }
            setDestination(name: pharmacy.name, coordinate: pharmacy.coordinate)
            return true

        case .wheelchairLoan:
            let registered = palace?.placesWithWheelchairLoan().min {
                PolylineGeometry.meters(between: origin, and: $0.coordinate)
                    < PolylineGeometry.meters(between: origin, and: $1.coordinate)
            }
            if let registered {
                setDestination(name: registered.name, coordinate: registered.coordinate)
                return true
            }

            guard let mall = await poiService.nearest(.shopping, to: origin) else {
                errorMessage = "Não encontrei nenhum local com cadeira de rodas por perto."
                return false
            }
            setDestination(name: mall.name, coordinate: mall.coordinate)
            showNotice("Nenhum local seu está registrado com empréstimo de cadeira. Indo ao shopping mais próximo — confirme a disponibilidade ao chegar.")
            return true
        }
    }

    // MARK: - Turn-by-turn

    /// Atualiza a próxima manobra a partir da posição do usuário.
    private func refreshTurnInstruction(at coordinate: CLLocationCoordinate2D) {
        guard let route else { turnInstruction = nil; return }
        // O primeiro passo do MapKit costuma ter distância 0 e nenhuma instrução.
        let steps = route.steps.filter { $0.distance > 0 && $0.polyline.pointCount >= 2 }
        guard !steps.isEmpty else { turnInstruction = nil; return }

        // Passo atual: o mais próximo entre o último conhecido e os dois seguintes. Em empate
        // (esquina entre dois passos) vale o mais antigo, até o usuário passar da esquina.
        let lower = min(currentStepIndex, steps.count - 1)
        let upper = min(lower + 2, steps.count - 1)
        var best = lower
        var bestDistance = PolylineGeometry.distanceMeters(from: coordinate, to: steps[lower].polyline)
        if upper > lower {
            for index in (lower + 1)...upper {
                let distance = PolylineGeometry.distanceMeters(from: coordinate, to: steps[index].polyline)
                if distance < bestDistance - 3 {
                    best = index
                    bestDistance = distance
                }
            }
        }
        currentStepIndex = best

        // Anda para frente até a próxima curva de verdade, somando os trechos retos
        // (o MapKit divide a rota em passos também em travessias, sem curva).
        var distanceToManeuver = PolylineGeometry.remainingDistance(from: coordinate, along: steps[best].polyline)
        var index = best
        var maneuver: TurnInstruction.Maneuver = .arrive
        var hint: String?

        while index + 1 < steps.count {
            let next = steps[index + 1]
            let candidate = junctionManeuver(from: steps[index], to: next)
            if candidate != .straight {
                maneuver = candidate
                let text = next.instructions.trimmed
                hint = text.isEmpty ? nil : text
                break
            }
            distanceToManeuver += next.distance
            index += 1
        }

        let instruction = TurnInstruction(
            maneuver: maneuver,
            distanceToManeuver: distanceToManeuver,
            streetHint: hint,
            arrivalName: currentTargetName
        )
        if instruction != turnInstruction { turnInstruction = instruction }
    }

    /// Tipo de manobra na junção entre dois passos, pela mudança de rumo.
    private func junctionManeuver(from current: MKRoute.Step, to next: MKRoute.Step) -> TurnInstruction.Maneuver {
        guard let exit = PolylineGeometry.exitBearing(of: current.polyline),
              let entry = PolylineGeometry.entryBearing(of: next.polyline) else { return .straight }
        return TurnInstruction.maneuver(
            forTurnAngle: PolylineGeometry.turnAngle(fromBearing: exit, toBearing: entry)
        )
    }

    // MARK: - Ícones dos resultados da busca

    private func categoryKey(_ completion: MKLocalSearchCompletion) -> String {
        "\(completion.title)|\(completion.subtitle)"
    }

    /// Ícone do resultado: categoria real do MapKit, se já resolvida; senão, um palpite pelo
    /// nome; senão, o genérico.
    func iconStyle(for completion: MKLocalSearchCompletion) -> PlaceCategoryStyle {
        PlaceCategoryStyle.style(for: resultCategories[categoryKey(completion)])
            ?? PlaceCategoryStyle.guess(fromTitle: completion.title)
            ?? .generic
    }

    /// O autocompletar (`MKLocalSearchCompletion`) NÃO traz a categoria do local — ela só existe
    /// no `MKMapItem` devolvido por uma busca. Por isso resolvemos os primeiros resultados, um
    /// a um e com um pequeno atraso (para não disparar requisições a cada tecla), guardando
    /// o resultado. Até chegar, vale o palpite pelo nome.
    private func resolveCategories(for completions: [MKLocalSearchCompletion]) {
        categoryTask?.cancel()
        let pending = completions.prefix(Config.categoryLookups).filter {
            resultCategories[categoryKey($0)] == nil && !attemptedCategoryKeys.contains(categoryKey($0))
        }
        guard !pending.isEmpty else { return }

        categoryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            for completion in pending {
                guard !Task.isCancelled, let self else { return }
                let key = self.categoryKey(completion)
                self.attemptedCategoryKeys.insert(key)

                let request = MKLocalSearch.Request(completion: completion)
                guard let response = try? await MKLocalSearch(request: request).start(),
                      let category = response.mapItems.first?.pointOfInterestCategory else { continue }
                self.resultCategories[key] = category
            }
        }
    }

    // MARK: - Avisos

    private func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - Métricas de trajeto em tempo real

    /// Distância já percorrida na sessão inteira (soma de todos os trechos, inclusive
    /// os anteriores a um recálculo).
    var distanceTraveled: CLLocationDistance {
        locationManager.distanceTraveled
    }

    private var traveledOnCurrentRoute: CLLocationDistance {
        max(locationManager.distanceTraveled - routeBaseline, 0)
    }

    /// Distância restante estimada (m) na rota atual. É uma simplificação: assume que o
    /// usuário segue a rota traçada; desvios disparam recálculo em vez de ajustar este valor.
    var remainingDistance: CLLocationDistance? {
        guard let route else { return nil }
        return max(route.distance - traveledOnCurrentRoute, 0)
    }

    var formattedDistanceTraveled: String {
        MetricDistance.string(from: distanceTraveled)
    }

    var formattedRemainingDistance: String {
        guard let remainingDistance else { return "—" }
        return MetricDistance.string(from: remainingDistance)
    }

    /// Tempo restante estimado no ritmo do perfil: a duração total da rota escolhida
    /// proporcional à distância que falta.
    var remainingDuration: TimeInterval? {
        guard let selected = selectedResult, selected.route.distance > 0,
              let remaining = remainingDistance else { return nil }
        return selected.estimatedDuration * (remaining / selected.route.distance)
    }

    var formattedRemainingTime: String {
        guard let seconds = remainingDuration else { return "—" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 1 { return "< 1 min" }
        if minutes >= 60 { return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min" }
        return "\(minutes) min"
    }

    /// Progresso da rota atual, de 0 a 1.
    var routeProgress: Double {
        guard let route, route.distance > 0 else { return 0 }
        return min(traveledOnCurrentRoute / route.distance, 1)
    }
}

extension MapViewModel: MKLocalSearchCompleterDelegate {
    // O MapKit entrega estes callbacks na thread principal; voltamos explicitamente ao
    // MainActor para satisfazer o isolamento da classe.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.searchResults = results
            self.resolveCategories(for: results)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Erro na busca de destinos: \(error.localizedDescription)")
    }
}
