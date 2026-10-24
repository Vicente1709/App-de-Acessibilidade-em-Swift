import SwiftUI

/// Fundo padrão do app: degradê `linen` → `cream` com dois halos suaves (nude e terracota).
/// Usado na Home, nas sheets e nos formulários, para tudo parecer a mesma superfície.
struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Color.linen, Color.cream], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.warmNude.opacity(0.55))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .offset(x: 110, y: -110)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color.softTerracotta.opacity(0.14))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: -110, y: 110)
            }
            .clipped()
            .ignoresSafeArea()
    }
}

/// Fundo de cada linha de um `Form`: lavagem quente + vidro fino.
struct ThemedRowBackground: View {
    var body: some View {
        ZStack {
            Color.cream.opacity(0.6)
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

/// Cabeçalho de seção no design system (arredondado, grafite suave, sem caixa-alta).
struct ThemedHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.warmGraphite.opacity(0.7))
            .textCase(nil)
    }
}

/// Título da barra de navegação no design system.
struct ThemedTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.warmGraphite)
    }
}

extension View {
    /// Estilo padrão de telas em formulário: fundo do app, tipografia arredondada, texto grafite,
    /// destaque terracota e barra de navegação transparente.
    func themedForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .fontDesign(.rounded)
            .foregroundStyle(Color.warmGraphite)
            .tint(Color.softTerracotta)
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Fundo e cantos de uma sheet no design system.
    func themedSheet() -> some View {
        self
            .presentationBackground { AppBackground() }
            .presentationCornerRadius(28)
    }
}
