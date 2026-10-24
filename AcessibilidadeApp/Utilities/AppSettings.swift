import SwiftUI

/// Preferências do usuário (UserDefaults). As chaves são usadas com `@AppStorage` nas Views.
enum AppSettings {
    enum Keys {
        static let forceLightMode = "settings.forceLightMode"
        static let showRecentTrips = "settings.showRecentTrips"
        static let profileName = "profile.name"
    }
}

/// Aplica o tema escolhido nas Configurações: "Padrão do sistema" ou "Modo claro" forçado.
/// Aplicado na raiz e em cada sheet/cover, porque apresentações nem sempre herdam a preferência.
private struct AppAppearance: ViewModifier {
    @AppStorage(AppSettings.Keys.forceLightMode) private var forceLightMode = false

    func body(content: Content) -> some View {
        content.preferredColorScheme(forceLightMode ? .light : nil)
    }
}

extension View {
    func appAppearance() -> some View {
        modifier(AppAppearance())
    }
}
