import Foundation
import CoreLocation

// MARK: - Distância (sistema métrico estrito)

/// Formata distâncias SEMPRE em metros ou quilômetros, em pt_BR, sem conversão automática
/// para milhas/pés (independente da região configurada no aparelho).
///
/// `unitOptions = .providedUnit` faz o formatador respeitar a unidade que passamos; por isso a
/// escolha entre m e km é feita aqui: abaixo de 1000 m mostramos metros, a partir daí km.
enum MetricDistance {
    private static func makeFormatter(maxFractionDigits: Int) -> MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.locale = Locale(identifier: "pt_BR")
        formatter.numberFormatter.maximumFractionDigits = maxFractionDigits
        formatter.numberFormatter.minimumFractionDigits = 0
        return formatter
    }

    private static let metersFormatter = makeFormatter(maxFractionDigits: 0)
    private static let kilometersFormatter = makeFormatter(maxFractionDigits: 1)

    /// Ex.: `850 m`, `1,2 km`.
    static func string(from meters: CLLocationDistance) -> String {
        let rounded = max(meters, 0).rounded()
        if rounded < 1000 {
            return metersFormatter.string(from: Measurement(value: rounded, unit: UnitLength.meters))
        }
        return kilometersFormatter.string(from: Measurement(value: rounded / 1000, unit: UnitLength.kilometers))
    }
}
