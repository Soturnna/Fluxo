import Foundation

enum GeminiError: LocalizedError {
    case missingKey
    case invalidKey
    case quotaExceeded
    case badRequest
    case modelUnavailable
    case server(Int)
    case network(String, retryable: Bool)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Cadastre a chave do Gemini em Ajustes › Conexões e chaves."
        case .invalidKey: return "O Google recusou a chave do Gemini. Confira em Ajustes."
        case .quotaExceeded: return "O limite gratuito do Gemini foi atingido. Tente de novo em alguns instantes."
        case .badRequest: return "O Gemini não entendeu o pedido. Tente reformular."
        case .modelUnavailable: return "O modelo do Gemini usado pelo app não está disponível. Ele precisa ser atualizado."
        case .server(let code): return "O Gemini respondeu com erro (\(code))."
        case .network(let detail, _): return detail
        case .invalidResponse: return "Resposta inesperada do Gemini."
        }
    }
}

/// Transporte até a API do Gemini.
///
/// Mesmas regras do cliente do Pluggy:
/// - endereço fixo (generativelanguage.googleapis.com) e conferência do host na resposta;
/// - sessão efêmera, sem cache nem cookies;
/// - a chave sai do Keychain só no momento do envio, num cabeçalho (nunca na URL,
///   onde poderia parar em registros de servidores intermediários).
///
/// Recebe e devolve `Data` já pronto: quem monta o pedido é o AgentEngine.
struct GeminiClient {
    static let model = "gemini-3.8-flash"
    private static let host = "generativelanguage.googleapis.com"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        // O modelo pode "pensar" antes de responder: margem generosa de espera.
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    /// Traduz o código do erro de rede numa mensagem que diz o que aconteceu.
    /// Só o código é usado; nenhum conteúdo da conversa entra na mensagem.
    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "Sem conexão com a internet."
        case .timedOut:
            return "O Gemini demorou demais para responder. Tente de novo."
        case .networkConnectionLost:
            return "A conexão caiu no meio da resposta. Tente de novo."
        case .cannotFindHost, .dnsLookupFailed:
            return "Não foi possível encontrar o servidor do Gemini (DNS). Uma VPN ou um bloqueador pode estar interferindo."
        case .cannotConnectToHost:
            return "O servidor do Gemini recusou a conexão."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return "Falha na conexão segura com o Gemini (código \(error.code.rawValue)). Uma VPN ou um filtro de rede pode estar interceptando."
        case .appTransportSecurityRequiresSecureConnection:
            return "O iOS bloqueou a conexão por segurança (ATS)."
        default:
            return "Erro de rede ao falar com o Gemini (código \(error.code.rawValue))."
        }
    }

    static var hasKey: Bool { KeychainStore.exists(.geminiApiKey) }

    /// Envia o pedido. Falhas passageiras (tempo esgotado, conexão caída)
    /// ganham uma segunda tentativa automática.
    func generate(body: Data) async throws -> Data {
        do {
            return try await attempt(body: body)
        } catch GeminiError.network(_, let retryable) where retryable {
            try await Task.sleep(nanoseconds: 800_000_000)
            return try await attempt(body: body)
        }
    }

    /// Teste de conexão sem nenhum dado seu: só pede ao modelo para responder "ok".
    func ping() async -> String {
        let body = #"{"contents":[{"role":"user","parts":[{"text":"Responda apenas: ok"}]}]}"#
        do {
            _ = try await attempt(body: Data(body.utf8))
            return "Conexão funcionando. A chave e o modelo \(Self.model) estão ok."
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "Falha desconhecida."
        }
    }

    private func attempt(body: Data) async throws -> Data {
        guard let key = KeychainStore.read(.geminiApiKey) else { throw GeminiError.missingKey }
        guard let url = URL(string: "https://\(Self.host)/v1beta/models/\(Self.model):generateContent") else {
            throw GeminiError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = body

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let urlError = error as? URLError {
                let retryable = urlError.code == .timedOut || urlError.code == .networkConnectionLost
                throw GeminiError.network(Self.describe(urlError), retryable: retryable)
            }
            throw GeminiError.network("Erro de rede ao falar com o Gemini.", retryable: false)
        }
        let (data, response) = result

        guard let http = response as? HTTPURLResponse, http.url?.host == Self.host else {
            throw GeminiError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300: return data
        case 400:
            // O Google responde 400 também para chave inválida; o corpo diz qual é o caso.
            // Só procuramos o código do erro; o corpo nunca é exibido nem registrado.
            let text = String(decoding: data.prefix(4000), as: UTF8.self)
            throw text.contains("API_KEY_INVALID") ? GeminiError.invalidKey : GeminiError.badRequest
        case 401, 403: throw GeminiError.invalidKey
        case 404: throw GeminiError.modelUnavailable
        case 429: throw GeminiError.quotaExceeded
        default: throw GeminiError.server(http.statusCode)
        }
    }
}
