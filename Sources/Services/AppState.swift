import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedNav: NavigationItem = .dashboard
    @Published var cards: [Card] = []
    @Published var statements: [Statement] = []
    @Published var transactions: [Transaction] = []
    @Published var categories: [Category] = []
    @Published var dashboardStats: DashboardStats?
    @Published var insights: [AIInsight] = []
    @Published var selectedDateFilter: DateFilter = .lastMonth

    @Published var isLoading = false
    @Published var error: String?

    @Published var searchQuery = ""
    @Published var selectedCategory: String?
    @Published var selectedCardId: String?

    // MARK: - AI Provider Selection
    @Published var selectedAIProvider: AIProvider = {
        if let saved = UserDefaults.standard.string(forKey: "selected_ai_provider"),
           let provider = AIProvider(rawValue: saved) {
            return provider
        }
        return .aiStudio
    }()
    @Published var shouldFilterPersonalData: Bool = UserDefaults.standard.object(forKey: "filter_personal_data_enabled") as? Bool ?? true

    // MARK: - Services
    private let db = DatabaseService.shared
    private let aiStudio = GeminiService.shared

    // MARK: - Initialization
    init() {
        loadInitialData()
    }

    func loadInitialData() {
        loadCards()
        loadStatements()
        loadTransactions()
        loadCategories()
        loadDashboardStats()
    }

    // MARK: - Card Operations
    func loadCards() {
        cards = db.getCards()
    }

    func addCard(name: String, bank: String?, lastFour: String?) {
        let card = Card(name: name, bank: bank, lastFour: lastFour)
        db.createCard(card)
        loadCards()
    }

    func updateCard(_ card: Card) {
        db.updateCard(card)
        loadCards()
    }

    func deleteCard(_ id: String) {
        db.deleteCard(id)
        loadCards()
        loadStatements()
        loadTransactions()
        loadDashboardStats()
    }

    // MARK: - Statement Operations
    func loadStatements() {
        statements = db.getStatements()
    }

    func deleteStatement(_ id: String) {
        db.deleteStatement(id)
        loadStatements()
        loadTransactions()
        loadDashboardStats()
    }

    // MARK: - Transaction Operations
    func loadTransactions() {
        transactions = db.getTransactions(
            cardId: selectedCardId,
            category: selectedCategory,
            searchQuery: searchQuery.isEmpty ? nil : searchQuery
        )
    }

    func filterTransactions(category: String?) {
        selectedCategory = category
        loadTransactions()
    }

    func filterByCard(_ cardId: String?) {
        selectedCardId = cardId
        loadTransactions()
    }

    func searchTransactions(_ query: String) {
        searchQuery = query
        loadTransactions()
    }

    func getCardName(for transaction: Transaction) -> String? {
        guard let statement = statements.first(where: { $0.id == transaction.statementId }),
              let card = cards.first(where: { $0.id == statement.cardId }) else {
            return nil
        }
        return card.name
    }

    func updateTransactionCategory(transactionId: String, category: String?) {
        db.updateTransactionCategory(transactionId: transactionId, category: category)
        loadTransactions()
        loadDashboardStats()
    }

    func updateTransactionsCategoryBulk(transactionIds: Set<String>, category: String?) {
        db.updateTransactionsCategoryBulk(transactionIds: Array(transactionIds), category: category)
        loadTransactions()
        loadDashboardStats()
    }

    func deleteTransaction(_ transactionId: String) {
        db.deleteTransaction(transactionId)
        loadTransactions()
        loadDashboardStats()
    }

    func deleteTransactionsBulk(transactionIds: Set<String>) {
        db.deleteTransactionsBulk(transactionIds: Array(transactionIds))
        loadTransactions()
        loadDashboardStats()
    }

    // MARK: - Category Operations
    func loadCategories() {
        categories = db.getCategories()
    }

    func addCategory(name: String, icon: String, color: String) {
        let category = Category(name: name, icon: icon, color: color, isCustom: true)
        db.createCategory(category)
        loadCategories()
    }

    func deleteCategory(_ id: String) {
        db.deleteCategory(id)
        loadCategories()
    }

    // MARK: - Dashboard
    func loadDashboardStats() {
        let range = selectedDateFilter.dateRange
        dashboardStats = db.getDashboardStats(from: range.start, to: range.end)
    }

    func setDateFilter(_ filter: DateFilter) {
        selectedDateFilter = filter
        loadDashboardStats()
    }

    // MARK: - PDF Upload & Parse
    func uploadAndParseStatement(pdfURL: URL) async {
        isLoading = true
        error = nil

        do {
            let pdfData = try Data(contentsOf: pdfURL)

            // Use selected AI provider
            let parsed: ParsedStatement
            switch selectedAIProvider {
            case .aiStudio:
                parsed = try await aiStudio.parseStatement(pdfData: pdfData)
            }
            let sanitizedParsed = sanitizeParsedStatement(parsed)

            // Find or create card automatically
            let cardId: String
            if let lastFour = sanitizedParsed.cardInfo.lastFour,
               let existingCard = db.findCardByLastFour(lastFour) {
                cardId = existingCard.id
            } else {
                // Create new card from parsed info
                let newCard = Card(
                    name: sanitizedParsed.cardInfo.cardName ?? "Bilinmeyen Kart",
                    bank: sanitizedParsed.cardInfo.bank,
                    lastFour: sanitizedParsed.cardInfo.lastFour
                )
                db.createCard(newCard)
                cardId = newCard.id
                loadCards() // Refresh cards list
            }

            // Create statement
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            let statement = Statement(
                cardId: cardId,
                periodStart: sanitizedParsed.statementInfo.periodStart.flatMap { dateFormatter.date(from: $0) },
                periodEnd: sanitizedParsed.statementInfo.periodEnd.flatMap { dateFormatter.date(from: $0) },
                totalAmount: sanitizedParsed.statementInfo.totalAmount,
                minPayment: sanitizedParsed.statementInfo.minPayment,
                dueDate: sanitizedParsed.statementInfo.dueDate.flatMap { dateFormatter.date(from: $0) },
                pdfPath: pdfURL.path,
                rawJson: try? String(data: JSONEncoder().encode(sanitizedParsed), encoding: .utf8)
            )

            db.createStatement(statement)

            // Create transactions
            let transactions = sanitizedParsed.transactions.map { txn in
                Transaction(
                    statementId: statement.id,
                    date: dateFormatter.date(from: txn.date) ?? Date(),
                    description: txn.description,
                    merchant: txn.merchant,
                    amount: txn.amount,
                    category: txn.category
                )
            }

            db.createTransactions(transactions)

            // Reload data
            loadCards()
            loadStatements()
            loadTransactions()
            loadDashboardStats()

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - AI Insights
    func loadInsights() async {
        guard aiStudio.hasApiKey else {
            error = "Google AI Studio API anahtarı gerekli"
            return
        }

        isLoading = true
        error = nil

        do {
            insights = try await aiStudio.getInsights(transactions: transactions)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Settings
    var aiStudioApiKey: String {
        get { aiStudio.apiKey }
        set { aiStudio.apiKey = newValue }
    }

    var hasApiKey: Bool {
        switch selectedAIProvider {
        case .aiStudio: return aiStudio.hasApiKey
        }
    }

    func setAIProvider(_ provider: AIProvider) {
        selectedAIProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "selected_ai_provider")
    }

    func setPersonalDataFiltering(_ enabled: Bool) {
        shouldFilterPersonalData = enabled
        UserDefaults.standard.set(enabled, forKey: "filter_personal_data_enabled")
    }

    // MARK: - Clear All Data
    func clearAllData() {
        db.clearAllData()
        loadCards()
        loadStatements()
        loadTransactions()
        loadDashboardStats()
        insights = []
    }

    // MARK: - Export
    func exportTransactionsCSV() -> String {
        var csv = "Tarih,Açıklama,İşyeri,Kategori,Tutar,Para Birimi\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for txn in transactions {
            let date = dateFormatter.string(from: txn.date)
            let desc = txn.description.replacingOccurrences(of: ",", with: ";")
            let merchant = (txn.merchant ?? "").replacingOccurrences(of: ",", with: ";")
            let category = txn.category ?? ""
            csv += "\(date),\(desc),\(merchant),\(category),\(txn.amount),\(txn.currency)\n"
        }

        return csv
    }

    // MARK: - Privacy Filtering
    private func sanitizeParsedStatement(_ parsed: ParsedStatement) -> ParsedStatement {
        guard shouldFilterPersonalData else { return parsed }

        let sanitizedCardInfo = CardInfo(
            bank: sanitizeText(parsed.cardInfo.bank),
            cardName: sanitizeText(parsed.cardInfo.cardName),
            lastFour: sanitizeLastFour(parsed.cardInfo.lastFour)
        )

        let sanitizedTransactions = parsed.transactions.map { txn in
            ParsedTransaction(
                date: txn.date,
                description: sanitizeText(txn.description) ?? txn.description,
                merchant: sanitizeText(txn.merchant),
                amount: txn.amount,
                category: txn.category
            )
        }

        return ParsedStatement(
            cardInfo: sanitizedCardInfo,
            statementInfo: parsed.statementInfo,
            transactions: sanitizedTransactions
        )
    }

    private func sanitizeText(_ text: String?) -> String? {
        guard var value = text, !value.isEmpty else { return text }

        let patterns: [(String, String)] = [
            (#"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, "[E-POSTA]"),
            (#"\bTR\d{2}[0-9A-Z]{22}\b"#, "[IBAN]"),
            (#"\b\d{11}\b"#, "[KIMLIK]"),
            (#"\b(?:\d[ -]?){12,19}\b"#, "[KART]"),
            (#"(?:\+?90[\s-]?)?(?:5\d{2}|[2-4]\d{2})[\s-]?\d{3}[\s-]?\d{2}[\s-]?\d{2}"#, "[TELEFON]")
        ]

        for (pattern, replacement) in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeLastFour(_ value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        if digits.count >= 4 {
            return String(digits.suffix(4))
        }
        return digits.isEmpty ? nil : digits
    }
}
