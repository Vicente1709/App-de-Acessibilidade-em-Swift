import SwiftUI

/// Avatar circular: mostra a foto escolhida ou, sem foto, um avatar genérico de acessibilidade
/// (a cadeira de rodas sobre um degradê terroso).
struct ProfileAvatarView: View {
    let image: UIImage?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.warmNude, Color.softTerracotta.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "figure.roll")
                        .font(.system(size: size * 0.48, weight: .semibold))
                        .foregroundStyle(Color.cream)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}
