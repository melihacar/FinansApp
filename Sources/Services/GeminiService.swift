import Foundation

class GeminiService {
    static let shared = GeminiService()
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let model = "gemini-2.0-flash-lite"

    private init() {}

    var apiKey: String {
        get {
            if let key = UserDefaults.standard.string(forKey: "aistudio_api_key"), !key.isEmpty {
                return key
            }
            if let legacyGeminiKey = UserDefaults.standard.string(forKey: "gemini_api_key"), !legacyGeminiKey.isEmpty {
                return legacyGeminiKey
            }
            return ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "aistudio_api_key")
        }
    }

    var hasApiKey: Bool { !apiKey.isEmpty }

    // MARK: - Parse PDF Statement
    func parseStatement(pdfData: Data) async throws -> ParsedStatement {
        guard hasApiKey else {
            throw GeminiError.noApiKey
        }

        let base64PDF = pdfData.base64EncodedString()

        let systemPrompt = """
        Kredi kartı ekstresini analiz et. Yalnızca JSON döndür.
        
        JSON formatı:
        {"card_info":{"bank":"X","card_name":"X","last_four":"1234"},"statement_info":{"period_start":"YYYY-MM-DD","period_end":"YYYY-MM-DD","total_amount":0,"min_payment":0,"due_date":"YYYY-MM-DD"},"transactions":[{"date":"YYYY-MM-DD","description":"kısa","merchant":"kısa","amount":0,"category":"X"}]}

        Kurallar:
        - Kategoriler: Market,Restoran,Ulaşım,Giyim,Teknoloji,Sağlık,Eğlence,Fatura,Abonelik,Eşya,Kırtasiye,İade,Diğer
        - description ve merchant kısa olsun (max 20 karakter)
        - Kredi kartı ödemelerini dahil etme
        - Negatif değerleri İade kategorisine ekle
        - Kişisel verileri maskele/çıkar: ad soyad, adres, e-posta, telefon, TC kimlik no, IBAN, tam kart numarası
        - Kart bilgisinde sadece banka adı, kart adı (kişisel isim olmadan) ve son 4 hane döndür
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": systemPrompt],
                        [
                            "inline_data": [
                                "mime_type": "application/pdf",
                                "data": base64PDF
                            ]
                        ],
                        ["text": "Ekstreyi analiz et ve sadece geçerli JSON döndür."]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": 65536
            ]
        ]

        let response: GeminiResponse = try await makeRequest(body: requestBody)
        let content = try extractJSONText(from: response)

        guard let jsonData = content.data(using: .utf8) else {
            throw GeminiError.invalidResponse
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            let array = try JSONDecoder().decode([ParsedStatement].self, from: jsonData)
            guard let first = array.first else {
                throw GeminiError.invalidResponse
            }
            return first
        }

        return try JSONDecoder().decode(ParsedStatement.self, from: jsonData)
    }

    // MARK: - Get AI Insights
    func getInsights(transactions: [Transaction]) async throws -> [AIInsight] {
        guard hasApiKey else {
            throw GeminiError.noApiKey
        }

        guard !transactions.isEmpty else {
            return []
        }

        let transactionSummary = transactions.map { txn in
            [
                "date": ISO8601DateFormatter().string(from: txn.date),
                "merchant": txn.merchant ?? txn.description,
                "amount": txn.amount,
                "category": txn.category ?? "Diğer"
            ] as [String: Any]
        }

        let summaryData = try JSONSerialization.data(withJSONObject: transactionSummary, options: .prettyPrinted)
        let summaryText = String(data: summaryData, encoding: .utf8) ?? "[]"

        let prompt = """
        Sen bir kişisel finans danışmanısın.
        Aşağıdaki harcama verisine göre en fazla 5 adet içgörü üret.
        
        Sadece JSON döndür:
        {
          "insights": [
            {
              "type": "trend | warning | tip | subscription",
              "title": "kısa başlık",
              "description": "açıklama",
              "category": "opsiyonel",
              "amount": 0
            }
          ]
        }

        Türkçe yaz. Kısa ve eyleme dönük öneriler ver.

        Veri:
        \(summaryText)
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": 8192
            ]
        ]

        let response: GeminiResponse = try await makeRequest(body: requestBody)
        let content = try extractJSONText(from: response)

        guard let data = content.data(using: .utf8) else {
            throw GeminiError.invalidResponse
        }

        struct InsightsResponse: Codable {
            let insights: [InsightData]
        }

        struct InsightData: Codable {
            let type: String
            let title: String
            let description: String
            let category: String?
            let amount: Double?
        }

        let insightsResponse = try JSONDecoder().decode(InsightsResponse.self, from: data)

        return insightsResponse.insights.enumerated().map { index, insight in
            AIInsight(
                id: "\(index)-\(Date().timeIntervalSince1970)",
                type: AIInsight.InsightType(rawValue: insight.type) ?? .tip,
                title: insight.title,
                description: insight.description,
                category: insight.category,
                amount: insight.amount
            )
        }
    }

    // MARK: - Network Request
    private func makeRequest<T: Decodable>(body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                throw GeminiError.apiError(errorResponse.error.message)
            }
            throw GeminiError.apiError("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func extractJSONText(from response: GeminiResponse) throws -> String {
        guard let part = response.candidates?.first?.content?.parts?.first,
              var content = part.text else {
            throw GeminiError.invalidResponse
        }

        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasPrefix("```json") {
            content = String(content.dropFirst(7))
        } else if content.hasPrefix("```") {
            content = String(content.dropFirst(3))
        }
        if content.hasSuffix("```") {
            content = String(content.dropLast(3))
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Response Models
struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Codable {
    let content: GeminiContent?
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]?
}

struct GeminiPart: Codable {
    let text: String?
}

struct GeminiErrorResponse: Codable {
    let error: GeminiErrorDetail
}

struct GeminiErrorDetail: Codable {
    let message: String
}

// MARK: - Errors
enum GeminiError: LocalizedError {
    case noApiKey
    case invalidURL
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Google AI Studio API anahtarı ayarlanmamış. Lütfen Ayarlar'dan API key girin."
        case .invalidURL:
            return "Geçersiz URL"
        case .invalidResponse:
            return "AI Studio'dan geçersiz yanıt alındı"
        case .apiError(let message):
            return "API Hatası: \(message)"
        }
    }
}
