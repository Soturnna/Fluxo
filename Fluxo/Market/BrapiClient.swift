import Foundation

/// Uma linha da lista de ativos do brapi. Lista de permissão: só o que a tela usa.
/// O link do logotipo é ignorado de propósito: carregar imagens de fora
/// avisaria terceiros de que o app foi aberto.
struct MarketQuote: Decodable, Identifiable {
    let ticker: String
    let name: String
    let price: Double?
    let changePercent: Double?
    let volume: Double?
    let sector: String?
    let type: String?        // stock, fund, bdr
    let subType: String?     // fii, etf, unit…

    var id: String { ticker }

    private enum CodingKeys: String, CodingKey {
        case stock, name, close, change, volume, sector, type, subType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try c.decode(String.self, forKey: .stock)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ticker
        price = (try? c.decodeIfPresent(Double.self, forKey: .close)) ?? nil
        changePercent = (try? c.decodeIfPresent(Double.self, forKey: .change)) ?? nil
        volume = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? nil
        sector = (try? c.decodeIfPresent(String.self, forKey: .sector)) ?? nil
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        subType = (try? c.decodeIfPresent(String.self, forKey: .subType)) ?? nil
    }

    /// "FII", "Ação", "ETF", "BDR"
    var kindLabel: String {
        switch subType?.lowercased() {
        case "fii": return "FII"
        case "etf": return "ETF"
        case "fi-infra": return "FI-Infra"
        case "fi-agro": return "Fiagro"
        default:
            switch type?.lowercased() {
            case "fund": return "Fundo"
            case "bdr": return "BDR"
            default: return "Ação"
            }
        }
    }

    /// FIIs costumam distribuir rendimento todo mês.
    var paysMonthly: Bool { subType?.lowercased() == "fii" }
}

private struct MarketListResponse: Decodable {
    let stocks: [MarketQuote]
}

enum MarketError: LocalizedError {
    case missingToken, invalidToken, rateLimited, notInPlan, server(Int), network, invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Cadastre a chave gratuita do brapi em Ajustes › Conexões e chaves."
        case .invalidToken: return "O brapi recusou a chave. Confira em Ajustes."
        case .rateLimited: return "Limite de consultas do brapi atingido. Tente mais tarde."
        case .notInPlan: return "Esta lista não está liberada no plano gratuito do brapi."
        case .server(let code): return "O brapi respondeu com erro (\(code))."
        case .network: return "Sem conexão com o brapi."
        case .invalidResponse: return "Resposta inesperada do brapi."
        }
    }
}

/// Cliente do brapi.dev (cotações da B3, com até 30 min de atraso no plano gratuito).
///
/// Mesmas regras dos outros clientes: endereço fixo, sessão efêmera, TLS 1.2+,
/// chave só no cabeçalho (nunca na URL) e nenhum dado seu no pedido.
actor BrapiClient {
    enum Listing: String, CaseIterable, Identifiable {
        case gainers, mostTraded, fiis
        var id: String { rawValue }
        var label: String {
            switch self {
            case .gainers: return "Em alta hoje"
            case .mostTraded: return "Mais negociados"
            case .fiis: return "FIIs (renda mensal)"
            }
        }
    }

    private static let host = "brapi.dev"
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private var cache: [Listing: (at: Date, items: [MarketQuote])] = [:]

    static var hasToken: Bool { KeychainStore.exists(.brapiToken) }

    /// Lista pronta (10 itens). Guarda por 10 minutos para poupar a cota mensal.
    func list(_ listing: Listing) async throws -> [MarketQuote] {
        if let cached = cache[listing], Date().timeIntervalSince(cached.at) < 600 { return cached.items }

        var query: [URLQueryItem]
        switch listing {
        case .gainers:
            // Busca 100 e filtra os com volume relevante: evita "altas" de papéis quase sem negócio.
            query = [.init(name: "sortBy", value: "change"), .init(name: "sortOrder", value: "desc"), .init(name: "limit", value: "100")]
        case .mostTraded:
            query = [.init(name: "sortBy", value: "volume"), .init(name: "sortOrder", value: "desc"), .init(name: "limit", value: "10")]
        case .fiis:
            query = [.init(name: "subType", value: "fii"), .init(name: "sortBy", value: "volume"),
                     .init(name: "sortOrder", value: "desc"), .init(name: "limit", value: "10")]
        }

        let all = try await get(query)
        var items = all
        if listing == .gainers {
            items = all.filter { ($0.volume ?? 0) >= 1_000_000 && ($0.changePercent ?? 0) > 0 }
        }
        items = Array(items.prefix(10))
        cache[listing] = (Date(), items)
        return items
    }

    private func get(_ query: [URLQueryItem]) async throws -> [MarketQuote] {
        guard let token = KeychainStore.read(.brapiToken) else { throw MarketError.missingToken }
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = "/api/quote/list"
        components.queryItems = query
        guard let url = components.url else { throw MarketError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw MarketError.network
        }
        guard let http = result.1 as? HTTPURLResponse, http.url?.host == Self.host else { throw MarketError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            guard let decoded = try? JSONDecoder().decode(MarketListResponse.self, from: result.0) else {
                throw MarketError.invalidResponse
            }
            return decoded.stocks
        case 401: throw MarketError.invalidToken
        case 402, 403: throw MarketError.notInPlan
        case 429: throw MarketError.rateLimited
        default: throw MarketError.server(http.statusCode)
        }
    }
}
