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
        case .server(let code) where code == 503:
            return "O Gemini está sobrecarregado agora (503). Já tentei de novo e com modelos reserva; aguarde um pouco."
        case .server(let code): return "O Gemini respondeu com erro (\(code))."
        case .network(let detail, _): return detail
        case .invalidResponse: return "Resposta inesperada do Gemini."
        }
    }

    /// Falhas passageiras: vale esperar e tentar de novo.
    var isTransient: Bool {
        switch self {
        case .server(let code): return [500, 502, 503, 504].contains(code)
        case .network(_, let retryable): return retryable
        default: return false
        }
    }

    /// Servidor indisponível ou sobrecarregado: vale trocar para um modelo reserva.
    var isOverloaded: Bool {
        if case .server(let code) = self { return [500, 503, 504].contains(code) }
        return false
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
    /// Modelo principal e reservas (todos com plano gratuito), em ordem de preferência.
    static let primaryModel = "gemini-3.8-flash"
    static let fallbackModels = ["gemini-3.6-flash", "gemini-3.5-flash-lite"]
    static var model: String { primaryModel }
    static var allModels: [String] { [primaryModel] + fallbackModels }
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

    /// Envia o pedido a um modelo. Falhas passageiras (sobrecarga, tempo
    /// esgotado, conexão caída) ganham até duas novas tentativas, com espera
    /// crescente (1 s, depois 2,5 s): o "recuo exponencial" recomendado para
    /// não sobrecarregar ainda mais um servidor que já está no limite.
    func generate(model: String, body: Data) async throws -> Data {
        var delay: UInt64 = 1_000_000_000
        for attemptNumber in 0..<3 {
            do {
                return try await attempt(model: model, body: body)
            } catch let error as GeminiError where error.isTransient && attemptNumber < 2 {
                try await Task.sleep(nanoseconds: delay)
                delay = delay * 5 / 2
            }
        }
        throw GeminiError.invalidResponse // inalcançável: o laço sempre retorna ou lança
    }

    /// Teste de conexão sem nenhum dado seu: só pede ao modelo para responder "ok".
    func ping() async -> String {
        let body = Data(#"{"contents":[{"role":"user","parts":[{"text":"Responda apenas: ok"}]}]}"#.utf8)
        var lastError: Error?
        for model in Self.allModels {
            do {
                _ = try await attempt(model: model, body: body)
                return model == Self.primaryModel
                    ? "Conexão funcionando com o modelo \(model)."
                    : "O modelo principal está indisponível agora, mas a chave funciona com o reserva \(model)."
            } catch let error as GeminiError where error.isOverloaded {
                lastError = error
                continue
            } catch {
                return (error as? LocalizedError)?.errorDescription ?? "Falha desconhecida."
            }
        }
        return (lastError as? LocalizedError)?.errorDescription ?? "Falha desconhecida."
    }

    private func attempt(model: String, body: Data) async throws -> Data {
        guard let key = KeychainStore.read(.geminiApiKey) else { throw GeminiError.missingKey }
        guard Self.allModels.contains(model),
              let url = URL(string: "https://\(Self.host)/v1beta/models/\(model):generateContent") else {
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
