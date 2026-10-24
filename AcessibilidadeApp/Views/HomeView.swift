import SwiftUI
import SwiftData
import MapKit

struct HomeView: View {
    // `locationManager` e `mapViewModel` andam juntos porque o ViewModel precisa da MESMA
    // instância do LocationManager usada pela MapView — é isso que permite que a distância
    // percorrida e a rota ativa sobrevivam ao fechar/reabrir o mapa (botão "Voltar à Rota").
    // O LocationManager agora vem do `RootView`, que o compartilha com a Splash.
    @State private var locationManager: LocationManager
    @State private var mapViewModel: MapViewModel
    @State private var showMap = false
    /// Perfil de MOBILIDADE (botão da direita).
    @State private var showProfile = false
    /// Perfil do USUÁRIO + histórico de viagens (avatar da esquerda).
    @State private var showUserProfile = false
    @State private var showSettings = false
    /// "Repetir viagem" escolhido dentro do perfil: o mapa só abre depois que a sheet fecha.
    @State private var pendingRepeat = false
    /// Dispara a entrada escalonada dos blocos da tela.
    @State private var appeared = false
    /// Sugestão da busca que está sendo resolvida em coordenada (mostra um spinner na linha).
    @State private var resolvingKey: String?

    @AppStorage(AppSettings.Keys.showRecentTrips) private var showRecentTrips = true
    @AppStorage(AppSettings.Keys.profileName) private var profileName = ""
    private let avatarStore = AvatarStore.shared

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TripRecord.date, order: .reverse) private var recentTrips: [TripRecord]

    init(locationManager: LocationManager) {
        _locationManager = State(initialValue: locationManager)
        _mapViewModel = State(initialValue: MapViewModel(locationManager: locationManager))
    }

    /// Existe um trajeto em andamento que o usuário deixou rodando ao voltar para a Home.
    private var hasActiveTrip: Bool {
        mapViewModel.navigationState == .navigating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 22) {
                    header
                        .reveal(0, appeared: appeared)

                    GlassSearchBar(text: $mapViewModel.searchText, onSubmit: submitSearch)
                        .padding(.horizontal)
                        .disabled(hasActiveTrip)
                        // A lista flutua logo abaixo da barra, por cima do resto da tela.
                        .overlay(alignment: .bottom) {
                            suggestionsList
                                .alignmentGuide(.bottom) { $0[.top] - 8 }
                        }
                        .animation(.homeSpring, value: mapViewModel.suggestions.count)
                        .reveal(1, appeared: appeared)
//                        .onTapGesture { showMap = true }
                        .zIndex(10)

                    if showRecentTrips && !recentTrips.isEmpty {
                        recentTripsSection
                            .reveal(2, appeared: appeared)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer()

                    VStack(spacing: 14) {
                        quickShortcuts
                        centralActionButton
                    }
                    .padding(.bottom, 40)
                    .reveal(3, appeared: appeared)
                }
                .padding(.top, 12)
                .animation(.homeSpring, value: recentTrips.count)
                .animation(.homeSpring, value: showRecentTrips)
            }
            .onAppear {
                appeared = true
                locationManager.requestPermission()
                // Conecta o ViewModel ao SwiftData (Palácio da Memória).
                mapViewModel.configure(context: modelContext)
            }
            .fullScreenCover(isPresented: $showMap) {
                MapView(viewModel: mapViewModel, locationManager: locationManager)
                    .appAppearance()
            }
            // Perfil do usuário + histórico. "Repetir viagem" fecha a sheet e, quando ela
            // termina de fechar, abre o mapa (apresentar os dois ao mesmo tempo falharia).
            .sheet(isPresented: $showUserProfile, onDismiss: {
                if pendingRepeat {
                    pendingRepeat = false
                    showMap = true
                }
            }) {
                UserProfileView(canRepeat: !hasActiveTrip) { trip in
                    mapViewModel.loadTrip(trip)
                    pendingRepeat = true
                    showUserProfile = false
                }
                .appAppearance()
            }
            .sheet(isPresented: $showProfile) {
                MobilityProfileView()
                    .appAppearance()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .appAppearance()
            }
            // Chegada automática com o mapa fechado (usuário voltou à Home com a rota ativa):
            // reabre o mapa, onde a tela de feedback é apresentada.
            .onChange(of: mapViewModel.pendingFeedback?.id) { _, newValue in
                if newValue != nil { showMap = true }
            }
            // Erros dos atalhos (sem localização, nenhum POI encontrado). Com o mapa aberto,
            // quem mostra os erros é a própria MapView.
            .alert(
                "Ops",
                isPresented: Binding(
                    get: { mapViewModel.errorMessage != nil && !showMap },
                    set: { if !$0 { mapViewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mapViewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Autocomplete

    private func key(for completion: MKLocalSearchCompletion) -> String {
        "\(completion.title)|\(completion.subtitle)"
    }

    /// Sugestões de locais/endereços (MapKit) para o que está sendo digitado.
    @ViewBuilder
    private var suggestionsList: some View {
        let items = Array(mapViewModel.suggestions.prefix(6))

        if !items.isEmpty && !hasActiveTrip {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, completion in
                        Button {
                            selectSuggestion(completion)
                        } label: {
                            HStack(spacing: 8) {
                                SearchResultRow(
                                    title: completion.title,
                                    subtitle: completion.subtitle,
                                    style: mapViewModel.iconStyle(for: completion)
                                )
                                if resolvingKey == key(for: completion) {
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 1.02))

                        if index < items.count - 1 {
                            Divider().overlay(Color.warmGraphite.opacity(0.08))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            // Altura explícita: dentro de um overlay, o ScrollView receberia só a altura da barra.
            .frame(height: min(CGFloat(items.count) * 52 + 12, 300))
            .foregroundStyle(Color.warmGraphite)
            .homeGlass(cornerRadius: 22, material: .regularMaterial, wash: .champagne)
            .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    /// Toque numa sugestão: resolve o endereço, define o destino no ViewModel e abre o mapa,
    /// que já calcula as rotas acessíveis alternativas.
    private func selectSuggestion(_ completion: MKLocalSearchCompletion) {
        guard resolvingKey == nil else { return }
        resolvingKey = key(for: completion)
        Keyboard.dismiss()

        Task {
            let resolved = await mapViewModel.selectCompletion(completion)
            resolvingKey = nil
            if resolved { showMap = true }
        }
    }

    /// "Buscar" no teclado: segue com a primeira sugestão.
    private func submitSearch() {
        guard let first = mapViewModel.suggestions.first else { return }
        selectSuggestion(first)
    }

    // MARK: - Cabeçalho

    /// Esquerda: avatar (abre o perfil do usuário e o histórico). Direita: perfil de
    /// mobilidade e configurações.
    private var header: some View {
        HStack(spacing: 10) {
            Button { showUserProfile = true } label: {
                ProfileAvatarView(image: avatarStore.image, size: 46)
            }
            .buttonStyle(SpringPressButtonStyle())
            .accessibilityLabel("Meu perfil e histórico de viagens")

            VStack(alignment: .leading, spacing: 2) {
                Text(profileName.isEmpty ? "Olá!" : "Olá, \(profileName)!")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.warmGraphite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Para onde vamos hoje?")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.warmGraphite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            GlassCircleButton(systemImage: "person.crop.circle") { showProfile = true }
                .accessibilityLabel("Meu perfil de mobilidade")
            GlassCircleButton(systemImage: "gearshape.fill") { showSettings = true }
                .accessibilityLabel("Configurações")
        }
        .padding(.horizontal)
    }

    // MARK: - Atalhos rápidos

    /// Atalhos rápidos: vão direto à farmácia ou ao local com cadeira de rodas mais próximos.
    /// As cores funcionais — VERDE (farmácia) e AMARELO/ÂMBAR (cadeira de rodas) — são
    /// intencionalmente independentes da paleta terrosa. Ficam desativados enquanto há um
    /// trajeto em andamento, para não o sobrescrever.
    private var quickShortcuts: some View {
        HStack(spacing: 12) {
            GlassShortcutButton(
                title: "Farmácia mais próxima",
                subtitle: "Rota até a drogaria mais perto",
                systemImage: "pill.fill",
                tint: .green,
                isLoading: mapViewModel.quickSearchInProgress == .pharmacy
            ) {
                runShortcut(.pharmacy)
            }

            GlassShortcutButton(
                title: "Cadeira de rodas disponível",
                subtitle: "Local mais próximo com empréstimo",
                systemImage: "figure.roll",
                tint: Color(red: 0.98, green: 0.72, blue: 0.20), // amarelo/âmbar
                isLoading: mapViewModel.quickSearchInProgress == .wheelchairLoan
            ) {
                runShortcut(.wheelchairLoan)
            }
        }
        .padding(.horizontal, 24)
        .disabled(hasActiveTrip)
        .animation(.homeSpring, value: hasActiveTrip)
        .accessibilityHint(hasActiveTrip ? "Finalize o trajeto atual para usar os atalhos." : "")
    }

    /// Busca o destino do atalho e, se achar, abre o mapa já pronto para calcular as rotas.
    private func runShortcut(_ quick: QuickDestination) {
        guard mapViewModel.quickSearchInProgress == nil else { return }
        Task {
            if await mapViewModel.startQuickRoute(to: quick) {
                showMap = true
            }
        }
    }

    // MARK: - Botão principal

    private var centralActionButton: some View {
        let fill = hasActiveTrip ? Color.warmGraphite : Color.softTerracotta
        let label = hasActiveTrip ? Color.onWarmGraphite : Color.onTerracotta

        return Button {
            // Se já existe um trajeto ativo, apenas reabre o mapa — o estado
            // (rota, distância percorrida, posição) já está preservado no ViewModel.
            showMap = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: hasActiveTrip ? "location.north.line.fill" : "figure.roll")
                    .contentTransition(.symbolEffect(.replace))
                Text(hasActiveTrip ? "Voltar à Rota" : "Iniciar Trajeto Acessível")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(label)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: fill.opacity(0.32), radius: 14, y: 8)
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            .animation(.homeSpring, value: hasActiveTrip)
        }
        .buttonStyle(SpringPressButtonStyle())
        .padding(.horizontal, 24)
    }

    // MARK: - Viagens recentes

    private var recentTripsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Viagens recentes")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.warmGraphite)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentTrips.prefix(5)) { trip in
                        Button {
                            // Refazer viagem: carrega o destino salvo e abre o mapa,
                            // que recalcula a rota acessível automaticamente.
                            mapViewModel.loadTrip(trip)
                            showMap = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(trip.destinationName)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.warmGraphite)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption2.bold())
                                        .foregroundStyle(Color.softTerracotta)
                                }
                                Text(trip.formattedDistance)
                                    .font(.caption)
                                    .foregroundStyle(Color.warmGraphite)
                            }
                            .padding(12)
                            .frame(width: 160, alignment: .leading)
                            .homeGlass(cornerRadius: 18, material: .ultraThinMaterial)
                        }
                        .buttonStyle(SpringPressButtonStyle())
                        // Com trajeto em andamento, refazer outra viagem o cancelaria.
                        .disabled(hasActiveTrip)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6) // folga para a sombra não ser cortada pelo scroll
            }
        }
    }
}

// MARK: - Entrada escalonada

private extension View {
    /// Faz o bloco subir e aparecer com mola, com um pequeno atraso por ordem.
    func reveal(_ order: Int, appeared: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .animation(.homeSpring.delay(Double(order) * 0.17), value: appeared)
    }
}

#Preview {
    HomeView(locationManager: LocationManager())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
