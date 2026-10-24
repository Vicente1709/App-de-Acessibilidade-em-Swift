import SwiftUI

/// Raiz do app: mostra a `SplashScreenView` e, quando a inicialização termina, passa para a
/// `HomeView`. O `LocationManager` é criado aqui e compartilhado entre as duas telas, então o
/// GPS que a Splash já começou a ouvir continua valendo na Home.
struct RootView: View {
    @State private var locationManager = LocationManager()
    @State private var isReady = false

    var body: some View {
        ZStack {
            if isReady {
                HomeView(locationManager: locationManager)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                SplashScreenView(locationManager: locationManager) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        isReady = true
                    }
                }
                .transition(.opacity)
            }
        }
        .appAppearance()
        // Design system global: tipografia arredondada e destaque terracota em todo o app
        // (o ambiente também chega às sheets e ao mapa).
        .fontDesign(.rounded)
        .tint(Color.softTerracotta)
    }
}
