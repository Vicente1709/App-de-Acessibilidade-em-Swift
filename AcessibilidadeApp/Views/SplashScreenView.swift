import SwiftUI
import SwiftData
import CoreLocation

/// Tela de abertura acolhedora. Enquanto o app prepara GPS e dados, uma cadeira de rodas
/// percorre um spinner circular; quando tudo está pronto, ela espirala até o centro e se
/// transforma numa pessoa caminhando, e a tela passa para a `HomeView`.
///
/// "Pronto" significa: dados iniciais garantidos + permissão de localização decidida +
/// (primeira posição OU permissão negada). Há um teto de espera (`maxWait`), para um GPS lento
/// nunca prender a pessoa na abertura, e um tempo mínimo (`minimumDuration`), para a animação
/// não virar um piscar de tela.
struct SplashScreenView: View {
    let locationManager: LocationManager
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Loader
    @State private var spin = 0.0
    @State private var orbitRadius: CGFloat = SplashScreenView.baseRadius
    @State private var ringTrim: CGFloat = 0.72
    @State private var iconScale: CGFloat = 1
    @State private var showWalker = false

    // Texto
    @State private var message = SplashScreenView.loadingMessages[0]

    private static let baseRadius: CGFloat = 54
    private static let minimumDuration: TimeInterval = 2.2
    private static let maxWait: TimeInterval = 10

    private static let loadingMessages = [
        "Como você está hoje?",
        "Preparando suas rotas acessíveis…"
    ]
    private static let readyMessage = "Tudo pronto. Vamos lá!"

    // Os dois ícones da transformação. Para usar ilustrações próprias (estilo cartoon),
    // troque estes nomes por imagens do seu catálogo de assets.
    private let wheelchairSymbol = "figure.roll"
    private let walkingSymbol = "figure.walk"

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.linen, Color.cream], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                loader

                Text(message)
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.warmGraphite)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .frame(minHeight: 60, alignment: .top)
                    .id(message)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear(perform: startSpinning)
        .task { await runStartup() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Loader

    private var loader: some View {
        let diameter = Self.baseRadius * 2

        return ZStack {
            // Trilha do spinner
            Circle()
                .stroke(Color.warmNude.opacity(0.7), lineWidth: 6)
                .frame(width: diameter, height: diameter)

            // Arco que gira; ao terminar, fecha o círculo completo.
            Circle()
                .trim(from: 0, to: reduceMotion ? 0 : ringTrim)
                .stroke(Color.softTerracotta, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(spin))

            // O ícone orbita o círculo. O contêiner gira `+spin` e o ícone gira `-spin`:
            // a soma é zero, então ele dá voltas sem nunca ficar de cabeça para baixo.
            ZStack {
                iconBadge
                    .rotationEffect(.degrees(-spin))
                    .offset(y: -orbitRadius)
            }
            .rotationEffect(.degrees(spin))
        }
        .frame(width: 150, height: 150)
    }

    private var iconBadge: some View {
        Image(systemName: showWalker ? walkingSymbol : wheelchairSymbol)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Color.softTerracotta)
            // Troca suave de um símbolo para o outro.
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: showWalker)
            .frame(width: 56, height: 56)
            .background(.regularMaterial, in: Circle())
            .background(Color.cream.opacity(0.7), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            .scaleEffect(iconScale)
    }

    // MARK: - Animação

    private func startSpinning() {
        // Com "Reduzir Movimento" ligado, nada gira: o ícone fica no centro e só troca.
        guard !reduceMotion else {
            orbitRadius = 0
            return
        }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            spin = 360
        }
    }

    /// A cadeira espirala até o centro, o arco fecha o círculo e o símbolo vira uma pessoa
    /// caminhando. O giro (`spin`) segue em loop, mas com raio 0 e círculo fechado não se vê.
    @MainActor
    private func playArrival() async {
        if reduceMotion {
            withAnimation(.homeSpring) {
                showWalker = true
                message = Self.readyMessage
            }
            try? await Task.sleep(for: .milliseconds(900))
            return
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            orbitRadius = 0
            ringTrim = 1
            iconScale = 1.45
        }
        try? await Task.sleep(for: .milliseconds(450))

        withAnimation(.homeSpring) {
            showWalker = true
            message = Self.readyMessage
        }
        try? await Task.sleep(for: .milliseconds(950))
    }

    // MARK: - Inicialização

    @MainActor
    private func runStartup() async {
        let started = Date()

        // Dados: garante que o perfil de mobilidade existe antes da primeira rota.
        _ = MemoryPalace(context: modelContext).mobilityProfile()

        // GPS: pede a permissão e começa a ouvir (a primeira posição acelera a Home).
        locationManager.requestPermission()
        locationManager.startUpdating()

        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(started)
            updateLoadingMessage(elapsed: elapsed)

            let status = locationManager.authorizationStatus
            let decided = status != .notDetermined
            let blocked = status == .denied || status == .restricted
            if decided && (locationManager.userLocation != nil || blocked) { break }
            if elapsed > Self.maxWait { break }

            try? await Task.sleep(for: .milliseconds(120))
        }

        // Tempo mínimo na tela, para a animação respirar.
        let remaining = Self.minimumDuration - Date().timeIntervalSince(started)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        guard !Task.isCancelled else { return }

        await playArrival()
        onFinished()
    }

    /// Alterna as frases acolhedoras enquanto carrega.
    private func updateLoadingMessage(elapsed: TimeInterval) {
        let target = Self.loadingMessages[elapsed < 1.5 ? 0 : 1]
        guard message != target, message != Self.readyMessage else { return }
        withAnimation(.homeSpring) { message = target }
    }
}

#Preview {
    SplashScreenView(locationManager: LocationManager()) {}
        .modelContainer(for: AppSchema.models, inMemory: true)
}
