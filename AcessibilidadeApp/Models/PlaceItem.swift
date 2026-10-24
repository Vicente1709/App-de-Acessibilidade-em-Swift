import Foundation
import MapKit
import UIKit

enum PlaceKind: String, Hashable {
    case pharmacy
    case shopping

    var label: String {
        switch self {
        case .pharmacy: return "Farmácia"
        case .shopping: return "Shopping"
        }
    }

    var systemImage: String {
        switch self {
        case .pharmacy: return "pill.fill"
        case .shopping: return "bag.fill"
        }
    }

    /// Consulta enviada ao `MKLocalSearch`.
    var query: String {
        switch self {
        case .pharmacy: return "farmácia"
        case .shopping: return "shopping"
        }
    }

    /// Categorias nativas do MapKit usadas como filtro.
    /// Não existe categoria de shopping center no MapKit, então para shoppings o filtro é
    /// omitido e a busca depende só da consulta de texto.
    var categories: [MKPointOfInterestCategory]? {
        switch self {
        case .pharmacy: return [.pharmacy]
        case .shopping: return nil
        }
    }

    /// Aviso exibido no banner do local. Este texto é uma afirmação GERAL (não verificada
    /// por local) — se preferir, troque por algo como "Costuma oferecer… confirme na chegada".
    var accessibilityNotice: String? {
        switch self {
        case .pharmacy: return nil
        case .shopping: return "Este shopping possui cadeiras de rodas e infraestrutura acessível disponíveis para uso."
        }
    }
}

/// Local encontrado pela busca de POIs (farmácia ou shopping).
struct PlaceItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let kind: PlaceKind
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Ícone por categoria

/// Símbolo (SF Symbols) e tema de cor que representam uma categoria de local.
/// Usado nos resultados da busca; a cor concreta é aplicada em `GlassComponents.swift`.
struct PlaceCategoryStyle: Equatable {
    enum Theme: Equatable {
        case green, orange, red, blue, purple, indigo, teal, gray
    }

    let systemImage: String
    let theme: Theme

    static let generic = PlaceCategoryStyle(systemImage: "mappin.and.ellipse", theme: .gray)

    /// "hospital.fill" só existe nos SF Symbols mais recentes; sem ele, cai em "cross.case.fill".
    private static var hospitalSymbol: String {
        UIImage(systemName: "hospital.fill") != nil ? "hospital.fill" : "cross.case.fill"
    }

    /// Estilo para uma categoria nativa do MapKit. `nil` quando não há mapeamento.
    static func style(for category: MKPointOfInterestCategory?) -> PlaceCategoryStyle? {
        guard let category else { return nil }
        switch category {
        case .pharmacy: return PlaceCategoryStyle(systemImage: "pill.fill", theme: .green)
        case .restaurant: return PlaceCategoryStyle(systemImage: "fork.knife", theme: .orange)
        case .foodMarket: return PlaceCategoryStyle(systemImage: "cart.fill", theme: .orange)
        case .cafe, .bakery: return PlaceCategoryStyle(systemImage: "cup.and.saucer.fill", theme: .orange)
        case .hospital: return PlaceCategoryStyle(systemImage: hospitalSymbol, theme: .red)
        case .school, .university: return PlaceCategoryStyle(systemImage: "book.fill", theme: .blue)
        case .store: return PlaceCategoryStyle(systemImage: "bag.fill", theme: .purple)
        case .park, .nationalPark: return PlaceCategoryStyle(systemImage: "tree.fill", theme: .green)
        case .publicTransport: return PlaceCategoryStyle(systemImage: "bus.fill", theme: .indigo)
        case .hotel: return PlaceCategoryStyle(systemImage: "bed.double.fill", theme: .indigo)
        case .bank, .atm: return PlaceCategoryStyle(systemImage: "banknote.fill", theme: .teal)
        case .parking: return PlaceCategoryStyle(systemImage: "parkingsign.circle.fill", theme: .blue)
        case .gasStation: return PlaceCategoryStyle(systemImage: "fuelpump.fill", theme: .gray)
        default: return nil
        }
    }

    /// Palpite pelo NOME do local, usado enquanto a categoria real ainda não foi resolvida
    /// (o autocompletar do MapKit não informa categoria) ou quando ela não vem.
    static func guess(fromTitle title: String) -> PlaceCategoryStyle? {
        let text = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        for rule in guessRules where rule.keywords.contains(where: { text.contains($0) }) {
            return rule.style
        }
        return nil
    }

    private static let guessRules: [(keywords: [String], style: PlaceCategoryStyle)] = [
        (["farmacia", "drogaria", "drogasil", "droga raia", "drogaraia", "pague menos", "pacheco", "ultrafarma"],
         PlaceCategoryStyle(systemImage: "pill.fill", theme: .green)),
        (["hospital", "pronto socorro", "pronto-socorro", "policlinica", "clinica", "posto de saude"],
         PlaceCategoryStyle(systemImage: hospitalSymbol, theme: .red)),
        (["restaurante", "pizzaria", "lanchonete", "churrascaria", "hamburgueria"],
         PlaceCategoryStyle(systemImage: "fork.knife", theme: .orange)),
        (["supermercado", "hipermercado", "atacadao", "atacarejo", "mercado"],
         PlaceCategoryStyle(systemImage: "cart.fill", theme: .orange)),
        (["escola", "colegio", "universidade", "faculdade"],
         PlaceCategoryStyle(systemImage: "book.fill", theme: .blue)),
        (["shopping"],
         PlaceCategoryStyle(systemImage: "bag.fill", theme: .purple)),
        (["parque"],
         PlaceCategoryStyle(systemImage: "tree.fill", theme: .green)),
        (["metro", "estacao", "rodoviaria", "terminal"],
         PlaceCategoryStyle(systemImage: "bus.fill", theme: .indigo))
    ]
}
