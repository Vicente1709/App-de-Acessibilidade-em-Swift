import UIKit

enum Keyboard {
    /// Fecha o teclado, esteja o foco onde estiver.
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
