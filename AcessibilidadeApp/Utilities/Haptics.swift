import UIKit

/// Feedbacks táteis usados fora das Views (ex.: chegada automática ao destino).
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
