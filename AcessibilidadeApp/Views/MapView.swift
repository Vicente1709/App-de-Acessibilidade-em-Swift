import SwiftUI
import MapKit
import SwiftData

struct MapView: View {
    @Bindable var viewModel: MapViewModel
    var locationManager: LocationManager

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Relatos da Sala do Mapa, desenhados como marcadores para a pessoa ver o que já foi registrado.
    @Query private var obstacles: [ObstacleReport]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showObstacleSheet = false
    /// Altura atual do painel de seleção de rotas (padrão: compacto).
    @State private var routeSheetDetent: SheetDetent = .compact

    private var activeObstacles: [ObstacleReport] {
        obstacles.filter { $0.isCurrentlyActive() }
    }

    /// A rota selecionada é desenhada por último (fica por cima); as demais, da mais longa
    /// para a mais curta.
    private var orderedRouteOptions: [AccessibleRouteResult] {
        viewModel.routeOptions.sorted { a, b in
            let aSelected = a.id == viewModel.selectedRouteID
            let bSelected = b.id == viewModel.selectedRouteID
            if aSelected != bSelected { return bSelected }
            return a.role > b.role
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer

            topBar

            VStack(spacing: 10) {
                Spacer()
                if viewModel.navigationState == .navigating {
                    HStack {
                        Spacer()
                        GlassCircleButton(systemImage: "location.fill", size: 50) {
                            recenterCamera()
                        }
                        .accessibilityLabel("Recentralizar no mapa")
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale))
                }
                if let place = viewModel.selectedPlace {
                    GlassPOIBanner(
                        place: place,
                        onClose: { viewModel.selectedPlaceID = nil },
                        onGoThere: { viewModel.useAsDestination(place) }
                    )
                }
                bottomPanel
            }
            .animation(.spring, value: viewModel.navigationState)
            .animation(.spring, value: viewModel.selectedPlaceID)
        }
        .onAppear {
            locationManager.startUpdating()
            // Ao reabrir o mapa (ex.: "Voltar à Rota"), a câmera precisa refletir o
            // estado atual imediatamente, não só reagir a mudanças futuras.
            applyCameraForCurrentState(animated: false)
        }
        // Recalcula as rotas sempre que um novo destino é confirmado — mas nunca durante
        // uma navegação já em andamento, para não sobrescrever o progresso do usuário
        // ao simplesmente reabrir o mapa a partir do botão "Voltar à Rota".
        .task(id: viewModel.destinationName) {
            guard !viewModel.destinationName.isEmpty,
                  viewModel.navigationState != .navigating,
                  let origin = locationManager.userLocation else { return }
            await viewModel.calculateRoute(from: origin)
        }
        // Ligar/desligar "incluir parada em farmácia" refaz as rotas (só na prévia).
        .onChange(of: viewModel.includePharmacyStop) { _, _ in
            guard viewModel.navigationState == .routePreview,
                  let origin = locationManager.userLocation else { return }
            Task { await viewModel.calculateRoute(from: origin) }
        }
        // Ajusta a câmera conforme o trajeto avança: enquadra todas as opções na prévia,
        // e passa a seguir o usuário de perto assim que a navegação começa.
        .onChange(of: viewModel.navigationState) { _, newState in
            if newState == .routePreview { routeSheetDetent = .compact }
            applyCameraForCurrentState(animated: true)
        }
        .onChange(of: viewModel.routeOptions.map(\.id)) { _, _ in
            if viewModel.navigationState == .routePreview {
                applyCameraForCurrentState(animated: true)
            }
        }
        // Relato de obstáculo durante a navegação (Sala do Mapa).
        .sheet(isPresented: $showObstacleSheet) {
            ObstacleReportSheet { kind, note, placement in
                viewModel.reportObstacle(kind: kind, note: note, placement: placement)
            }
        }
        // Feedback pós-trajeto (Salas de Histórico e Destinos). Ao fechar a tela de
        // feedback — salvando ou pulando — o mapa também é fechado.
        .sheet(item: $viewModel.pendingFeedback, onDismiss: { dismiss() }) { pending in
            TripFeedbackSheet(pending: pending) { input in
                viewModel.submitFeedback(input, for: pending)
            }
        }
        .alert(
            "Ops",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Mapa

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, selection: $viewModel.selectedPlaceID) {
                UserAnnotation()

                if let destination = viewModel.destinationCoordinate {
                    Marker(viewModel.destinationName, coordinate: destination)
                        .tint(.red)
                }

                if let waypoint = viewModel.waypoint {
                    Marker(waypoint.name, systemImage: waypoint.kind.systemImage, coordinate: waypoint.coordinate)
                        .tint(.mint)
                }

                // Rotas com visual de caminho de pedestre (nada de "estrada"): contorno branco
                // arredondado + linha colorida; a selecionada é sólida com pontilhado claro no
                // centro, e as demais ficam pontilhadas, como o Mapas da Apple faz a pé.
                ForEach(orderedRouteOptions) { option in
                    let isSelected = option.id == viewModel.selectedRouteID
                    let dash: [CGFloat] = isSelected ? [] : [0.5, 9]
                    let polyline = displayedPolyline(for: option)

                    MapPolyline(polyline)
                        .stroke(
                            Color.white.opacity(isSelected ? 0.95 : 0.6),
                            style: StrokeStyle(lineWidth: isSelected ? 11 : 8, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(polyline)
                        .stroke(
                            option.role.color.opacity(isSelected ? 1 : 0.6),
                            style: StrokeStyle(lineWidth: isSelected ? 7 : 5, lineCap: .round, lineJoin: .round, dash: dash)
                        )
                    if isSelected {
                        MapPolyline(polyline)
                            .stroke(
                                Color.white.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [0.5, 10])
                            )
                    }
                }

                ForEach(activeObstacles) { obstacle in
                    Marker(obstacle.kind.label, systemImage: obstacle.kind.systemImage, coordinate: obstacle.coordinate)
                        .tint(.orange)
                }

                ForEach(viewModel.pharmacies) { place in
                    Marker(place.name, systemImage: place.kind.systemImage, coordinate: place.coordinate)
                        .tint(.mint)
                        .tag(place.id)
                }

                ForEach(viewModel.shoppings) { place in
                    Marker(place.name, systemImage: place.kind.systemImage, coordinate: place.coordinate)
                        .tint(.purple)
                        .tag(place.id)
                }
            }
            .mapStyle(.standard(
                elevation: .flat,
                emphasis: .muted, // base mais discreta para as rotas se destacarem
                pointsOfInterest: .including([.hospital, .publicTransport, .restroom, .parking]),
                showsTraffic: false
            ))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.mapRegionChanged(context.region)
            }
            // Toque na polilinha: o MapKit não oferece seleção de polilinhas no iOS 17, então
            // convertemos o toque em coordenada e escolhemos a rota mais próxima.
            .onTapGesture { point in
                handleMapTap(at: point, proxy: proxy)
            }
        }
        .ignoresSafeArea()
    }

    /// Na navegação, a rota ativa mostra só o que falta: o trecho já percorrido some.
    private func displayedPolyline(for option: AccessibleRouteResult) -> MKPolyline {
        if viewModel.navigationState == .navigating,
           option.id == viewModel.selectedRouteID,
           let remaining = viewModel.remainingPolyline {
            return remaining
        }
        return option.route.polyline
    }

    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard viewModel.navigationState == .routePreview,
              let tapped = proxy.convert(point, from: .local),
              let edge = proxy.convert(CGPoint(x: point.x + 32, y: point.y), from: .local) else { return }

        // Tolerância de ~32 pt convertida para metros no zoom atual.
        let tolerance = PolylineGeometry.meters(between: tapped, and: edge)
        if viewModel.selectRoute(near: tapped, toleranceMeters: tolerance) {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: - Câmera

    /// Centraliza a lógica de câmera para os três estados do trajeto:
    /// - `idle`: visão automática padrão do MapKit.
    /// - `routePreview`: enquadra todas as opções de rota.
    /// - `navigating`: segue a localização do usuário de perto, rotacionando com a
    ///   bússola (`followsHeading: true`), como em apps de navegação turn-by-turn.
    private func applyCameraForCurrentState(animated: Bool) {
        let update = {
            switch viewModel.navigationState {
            case .idle:
                cameraPosition = .automatic
            case .routePreview:
                let union = viewModel.routeOptions
                    .map { $0.route.polyline.boundingMapRect }
                    .reduce(MKMapRect.null) { $0.union($1) }
                if !union.isNull {
                    // Folga extra para o painel inferior não cobrir a rota.
                    cameraPosition = .rect(union.insetBy(dx: -union.width * 0.2, dy: -union.height * 0.25))
                }
            case .navigating:
                cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
            }
        }
        if animated {
            withAnimation(.spring) { update() }
        } else {
            update()
        }
    }

    /// Volta a fixar a câmera no usuário, acompanhando a direção — útil depois de arrastar o mapa.
    private func recenterCamera() {
        withAnimation(.easeOut(duration: 0.25)) {
            cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
        }
    }

    // MARK: - Barra superior

    private var topBar: some View {
        HStack {
            GlassCircleButton(systemImage: "chevron.left") {
                // Se o trajeto ainda não foi confirmado (não está navegando),
                // descarta o estado atual ao sair do mapa.
                if viewModel.navigationState != .navigating {
                    viewModel.cancelRoute()
                }
                dismiss()
            }
            Spacer()
            if viewModel.navigationState == .navigating {
                GlassCircleButton(systemImage: "exclamationmark.triangle") {
                    showObstacleSheet = true
                }
                .accessibilityLabel("Relatar obstáculo")
            } else {
                // Camadas de POIs
                GlassCircleButton(systemImage: "pill.fill", isActive: viewModel.showPharmacies) {
                    viewModel.showPharmacies.toggle()
                }
                .accessibilityLabel("Mostrar farmácias")

                GlassCircleButton(systemImage: "bag.fill", isActive: viewModel.showShoppings) {
                    viewModel.showShoppings.toggle()
                }
                .accessibilityLabel("Mostrar shoppings")
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Painel inferior (busca, seleção de rota ou navegação ativa)

    @ViewBuilder
    private var bottomPanel: some View {
        switch viewModel.navigationState {
        case .idle:
            searchPanel
        case .routePreview:
            routeSummaryPanel
        case .navigating:
            navigatingPanel
        }
    }

    /// Aviso temporário ou indicador de recálculo.
    @ViewBuilder
    private var noticeView: some View {
        if viewModel.isRerouting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Recalculando rota…").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let notice = viewModel.notice {
            Text(notice)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchPanel: some View {
        VStack(spacing: 12) {
            GlassSearchBar(text: $viewModel.searchText)

            if viewModel.notice != nil {
                noticeView
                    .padding(.horizontal, 8)
            }

            if !viewModel.suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.suggestions, id: \.self) { result in
                            Button {
                                Task { await viewModel.selectCompletion(result) }
                            } label: {
                                SearchResultRow(
                                    title: result.title,
                                    subtitle: result.subtitle,
                                    style: viewModel.iconStyle(for: result)
                                )
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 1.02))
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 220)
                .glassPanel()
            }
        }
        .padding()
    }

    /// Painel de seleção de rotas: compacto por padrão, retrátil por arraste (veja `DetentBottomSheet`).
    private var routeSummaryPanel: some View {
        DetentBottomSheet(detent: $routeSheetDetent) {
            routeSheetHeader
        } content: {
            routeSheetBody
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Cabeçalho (sempre visível, mesmo recolhido): destino e resumo da rota escolhida.
    private var routeSheetHeader: some View {
        let tint = viewModel.selectedResult?.role.color ?? Color.accentColor

        return HStack(spacing: 10) {
            Image(systemName: "figure.roll")
                .font(.title3)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.destinationName)
                    .font(.headline)
                    .lineLimit(1)
                // Avisos temporários (ex.: "nenhuma farmácia no trajeto") ocupam o lugar do resumo.
                Text(viewModel.notice ?? routeSheetSummary)
                    .font(.caption)
                    .foregroundStyle(viewModel.notice == nil ? Color.warmGraphite.opacity(0.65) : Color.accentColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if viewModel.routeHasBlockingObstacle {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Possível bloqueio na rota")
            }
            Image(systemName: routeSheetDetent == .collapsed ? "chevron.up" : "chevron.down")
                .font(.footnote.bold())
                .foregroundStyle(Color.warmGraphite.opacity(0.65))
        }
    }

    private var routeSheetSummary: String {
        guard let selected = viewModel.selectedResult else { return "" }
        let minutes = max(1, Int((selected.estimatedDuration / 60).rounded()))
        return "\(selected.role.title) • \(minutes) min • \(selected.route.formattedDistance)"
    }

    /// Corpo: no nível compacto aparecem os cards e o botão; o aviso do Palácio e a opção de
    /// farmácia ficam abaixo, visíveis ao expandir.
    private var routeSheetBody: some View {
        VStack(spacing: 10) {
            // Escolha da rota ativa: toque num card (ou direto na linha no mapa).
            RouteOptionsPicker(
                options: viewModel.routeOptions,
                selectedID: viewModel.selectedRouteID,
                onSelect: { viewModel.selectRoute($0) }
            )

            Button {
                viewModel.startNavigation()
            } label: {
                Text("Iniciar Rota")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(viewModel.selectedResult?.role.color ?? Color.accentColor, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: (viewModel.selectedResult?.role.color ?? Color.accentColor).opacity(0.3), radius: 10, y: 5)
            }
            .buttonStyle(SpringPressButtonStyle())

            // Instrução montada pelo Palácio da Memória para a rota selecionada.
            if let briefing = viewModel.routeBriefing {
                Text(briefing)
                    .font(.caption)
                    .foregroundStyle(viewModel.routeHasBlockingObstacle ? Color.orange : Color.warmGraphite.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $viewModel.includePharmacyStop) {
                Label("Incluir parada em farmácia próxima", systemImage: "pill.fill")
                    .font(.footnote)
            }
            .disabled(viewModel.isCalculatingRoute)
        }
    }

    private var navigatingPanel: some View {
        let tint = viewModel.selectedResult?.role.color ?? Color.accentColor

        return VStack(spacing: 14) {
            Text("Navegando até \(viewModel.currentTargetName)")
                .font(.caption)
                .foregroundStyle(Color.warmGraphite.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            // Turn-by-turn: seta grande + instrução ("Vire à direita em 40 m").
            GlassTurnBanner(instruction: viewModel.turnInstruction, tint: tint)

            ProgressView(value: viewModel.routeProgress)
                .tint(tint)

            // Percorrido • tempo restante • restante
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                metric(
                    title: "Percorrido",
                    value: viewModel.formattedDistanceTraveled,
                    alignment: .leading,
                    frameAlignment: .leading
                )
                separatorDot
                metric(
                    title: "Tempo",
                    value: viewModel.formattedRemainingTime,
                    alignment: .center,
                    frameAlignment: .center
                )
                separatorDot
                metric(
                    title: viewModel.waypoint == nil ? "Restante" : "Até a parada",
                    value: viewModel.formattedRemainingDistance,
                    alignment: .trailing,
                    frameAlignment: .trailing
                )
            }

            noticeView

            Button(role: .destructive) {
                // Não chamamos dismiss() aqui: o ViewModel abre a tela de feedback e o
                // mapa fecha quando ela for dispensada (ver `.sheet(item:)` acima).
                viewModel.finishTrip(context: modelContext)
            } label: {
                Text("Finalizar Trajeto")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Color.softDanger, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color.softDanger.opacity(0.3), radius: 10, y: 5)
            }
            .buttonStyle(SpringPressButtonStyle())
        }
        .padding()
        .glassPanel()
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var separatorDot: some View {
        Text("•")
            .font(.subheadline.bold())
            .foregroundStyle(Color.warmGraphite.opacity(0.65))
            .accessibilityHidden(true)
    }

    /// Bloco compacto "rótulo em cima, valor embaixo" usado para as métricas de trajeto.
    private func metric(
        title: String,
        value: String,
        alignment: HorizontalAlignment,
        frameAlignment: Alignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.warmGraphite.opacity(0.65))
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}
