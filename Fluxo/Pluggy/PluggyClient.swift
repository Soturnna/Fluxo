import Foundation

enum PluggyError: LocalizedError {
    case missingCredentials
    case invalidCredentials
    case unauthorized
    case notFound
    case rateLimited
    case server(Int)
    case network
    case invalidResponse

    /// Mensagens próprias, curtas. O corpo da resposta do servidor nunca é
    /// mostrado nem registrado, porque pode conter dados da conta.
    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Cadastre as credenciais do Pluggy em Ajustes."
        case .invalidCredentials: return "O Pluggy recusou o Client ID ou o Client Secret."
        case .unauthorized: return "O acesso ao Pluggy expirou. Tente de novo."
        case .notFound: return "Conexão não encontrada. Confira o ID no dashboard do Pluggy."
        case .rateLimited: return "Muitas consultas seguidas. Aguarde um pouco."
        case .server(let code): return "O Pluggy respondeu com erro (\(code))."
        case .network: return "Sem conexão com a internet ou o Pluggy não respondeu."
        case .invalidResponse: return "Resposta inesperada do Pluggy."
        }
    }
}

/// Cliente da API do Pluggy, somente leitura.
///
/// Decisões de segurança:
/// - `actor`: só uma tarefa por vez mexe no token, evitando pedidos duplicados.
/// - Endereço fixo: o cliente só fala com https://api.pluggy.ai.
/// - Sessão "efêmera": nada de cache, cookies ou respostas gravadas em disco.
/// - Token de acesso só na memória, com validade curta, renovado quando vence.
/// - Apenas GET de dados. Não existe aqui nenhuma chamada de pagamento.
actor PluggyClient {
    private static let host = "api.pluggy.ai"
    private static let baseURL = URL(string: "https://api.pluggy.ai")!

    private let session: URLSession
    private let decoder = PluggyDates.makeDecoder()
    private var apiKey: String?
    private var apiKeyExpiresAt: Date?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: Consultas

    func item(id: String) async throws -> PluggyItem {
        try await get("items/\(id)", query: [], as: PluggyItem.self)
    }

    func accounts(itemId: String) async throws -> [PluggyAccount] {
        let query = [URLQueryItem(name: "itemId", value: itemId)]
        return try await get("accounts", query: query, as: PluggyPage<PluggyAccount>.self).results
    }

    /// Transações desde uma data, pela rota com cursor (/v2/transactions).
    /// `maxPages` limita o laço: mesmo que o servidor devolva cursores sem fim,
    /// o app nunca entra em repetição infinita.
    func transactions(accountId: String, since: Date, maxPages: Int = 20) async throws -> [PluggyTransaction] {
        var all: [PluggyTransaction] = []
        var cursor: String?

        for _ in 0..<maxPages {
            var query = [
                URLQueryItem(name: "accountId", value: accountId),
                URLQueryItem(name: "dateFrom", value: Self.dayString(since))
            ]
            if let cursor { query.append(URLQueryItem(name: "after", value: cursor)) }

            let page = try await get("v2/transactions", query: query, as: PluggyCursorPage<PluggyTransaction>.self)
            all += page.results

            // O servidor devolve um link para a próxima página. Não seguimos o link:
            // extraímos só o cursor e montamos o pedido no nosso endereço fixo.
            guard let next = page.next,
                  let nextCursor = URLComponents(string: next)?.queryItems?.first(where: { $0.name == "after" })?.value,
                  !nextCursor.isEmpty
            else { break }
            cursor = nextCursor
        }
        return all
    }

    /// Descarta o token da memória (chamado ao bloquear o app ou trocar credenciais).
    func reset() {
        apiKey = nil
        apiKeyExpiresAt = nil
    }

    // MARK: Autenticação

    private func validApiKey() async throws -> String {
        if let apiKey, let expiresAt = apiKeyExpiresAt, expiresAt.timeIntervalSinceNow > 60 {
            return apiKey
        }
        guard let clientId = KeychainStore.read(.pluggyClientId),
              let clientSecret = KeychainStore.read(.pluggyClientSecret)
        else { throw PluggyError.missingCredentials }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("auth"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // nonExpiring: false pede um token de vida curta.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "clientId": clientId,
            "clientSecret": clientSecret,
            "nonExpiring": false
        ])

        let data = try await send(request, isAuthRequest: true)
        guard let response = try? decoder.decode(PluggyAuthResponse.self, from: data) else {
            throw PluggyError.invalidResponse
        }
        apiKey = response.apiKey
        apiKeyExpiresAt = Self.expiration(ofJWT: response.apiKey) ?? Date().addingTimeInterval(30 * 60)
        return response.apiKey
    }

    /// O token é um JWT: três partes em Base64 separadas por ponto. A do meio
    /// traz o campo `exp` (validade). Lemos só isso, para saber quando renovar.
    static func expiration(ofJWT token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: Transporte

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem], as type: T.Type) async throws -> T {
        // Duas tentativas: se o token vencer no meio do caminho, pede outro uma vez.
        for attempt in 0..<2 {
            let key = try await validApiKey()

            guard var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            else { throw PluggyError.invalidResponse }
            components.queryItems = query.isEmpty ? nil : query
            guard let url = components.url else { throw PluggyError.invalidResponse }

            var request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "X-API-KEY")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let data = try await send(request, isAuthRequest: false)
                guard let value = try? decoder.decode(T.self, from: data) else {
                    throw PluggyError.invalidResponse
                }
                return value
            } catch PluggyError.unauthorized where attempt == 0 {
                reset()
                continue
            }
        }
        throw PluggyError.unauthorized
    }

    private func send(_ request: URLRequest, isAuthRequest: Bool) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            // Cancelamento não é falha de rede: quem chamou desistiu do pedido.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw PluggyError.network
        }
        let (data, response) = result

        guard let http = response as? HTTPURLResponse,
              http.url?.host == Self.host // a resposta veio mesmo do Pluggy
        else { throw PluggyError.invalidResponse }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw isAuthRequest ? PluggyError.invalidCredentials : PluggyError.unauthorized
        case 404:
            throw PluggyError.notFound
        case 429:
            throw PluggyError.rateLimited
        default:
            throw PluggyError.server(http.statusCode)
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
