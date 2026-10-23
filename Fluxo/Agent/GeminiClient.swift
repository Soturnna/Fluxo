import Foundation

enum GeminiError: LocalizedError {
    case missingKey
    case invalidKey
    case quotaExceeded
    case badRequest
    case modelUnavailable
    case server(Int)
    case network
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Cadastre a chave do Gemini em Ajustes › Conexões e chaves."
        case .invalidKey: return "O Google recusou a chave do Gemini. Confira em Ajustes."
        case .quotaExceeded: return "O limite gratuito do Gemini foi atingido. Tente de novo em alguns instantes."
        case .badRequest: return "O Gemini não entendeu o pedido. Tente reformular."
        case .modelUnavailable: return "O modelo do Gemini usado pelo app não está disponível. Ele precisa ser atualizado."
        case .server(let code): return "O Gemini respondeu com erro (\(code))."
        case .network: return "Sem conexão com a internet ou o Gemini não respondeu."
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
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    static var hasKey: Bool { KeychainStore.exists(.geminiApiKey) }

    func generate(body: Data) async throws -> Data {
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
            throw GeminiError.network
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
