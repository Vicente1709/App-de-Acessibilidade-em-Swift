import UIKit
import Observation

/// Foto de perfil escolhida pela pessoa. Fica só no aparelho (arquivo em Application Support),
/// reduzida a no máximo 512 px. Singleton observável: a Home e a tela de perfil leem o mesmo.
@MainActor
@Observable
final class AvatarStore {
    static let shared = AvatarStore()

    private(set) var image: UIImage?

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL) {
            image = UIImage(data: data)
        }
    }

    func save(imageData: Data) {
        guard let original = UIImage(data: imageData) else { return }
        let resized = Self.resized(original, maxSide: 512)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }

        do {
            try jpeg.write(to: Self.fileURL, options: .atomic)
            image = resized
        } catch {
            print("Não foi possível salvar a foto de perfil: \(error.localizedDescription)")
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        image = nil
    }

    // MARK: - Privado

    private static var fileURL: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("profile-avatar.jpg")
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }

        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
