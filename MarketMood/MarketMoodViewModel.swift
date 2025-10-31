//
//  MarketMoodViewModel.swift
//  MarketMood
//
//  Created by ChatGPT on 06/10/2025.
//

import Foundation
import Combine

@MainActor
final class MarketMoodViewModel: ObservableObject {
    @Published private(set) var quotes: [MarketQuote]
    @Published private(set) var isLoading: Bool
    @Published private(set) var errorMessage: String?
    @Published private(set) var mood: String?

    private let dataService: MarketDataService

    init(
        dataService: MarketDataService,
        initialQuotes: [MarketQuote] = [],
        initialIsLoading: Bool = false,
        initialErrorMessage: String? = nil,
        initialMood: String? = nil
    ) {
        self.dataService = dataService
        self.quotes = initialQuotes
        self.isLoading = initialIsLoading
        self.errorMessage = initialErrorMessage
        self.mood = initialMood
    }

    convenience init(
        initialQuotes: [MarketQuote] = [],
        initialIsLoading: Bool = false,
        initialErrorMessage: String? = nil,
        initialMood: String? = nil
    ) {
        self.init(
            dataService: MarketDataService(),
            initialQuotes: initialQuotes,
            initialIsLoading: initialIsLoading,
            initialErrorMessage: initialErrorMessage,
            initialMood: initialMood
        )
    }

    func loadQuotes() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        mood = nil

        do {
            let fetchedQuotes = try await dataService.fetchQuotes()
            quotes = fetchedQuotes
            mood = makeMood(from: fetchedQuotes)
        } catch {
            quotes = []
            errorMessage = message(for: error)
            mood = nil
        }

        isLoading = false
    }

    private func message(for error: Error) -> String {
        switch error {
        case MarketDataError.invalidURL:
            return "Unable to build the quote URL. Please try again later."
        case let MarketDataError.invalidResponse(statusCode):
            return "Received an unexpected response (\(statusCode))."
        case let MarketDataError.missingQuote(symbol):
            return "Missing market data for \(symbol)."
        case let MarketDataError.missingPreviousClose(symbol):
            return "Missing prior close data for \(symbol)."
        default:
            return "Something went wrong while fetching the market data."
        }
    }

    private func makeMood(from quotes: [MarketQuote]) -> String? {
        guard !quotes.isEmpty else { return nil }

        let averageChange = quotes.map(\.changePercent).reduce(0, +) / Double(quotes.count)

        switch averageChange {
        case let value where value >= 0.015:
            return "The market is euphoric with strong gains."
        case let value where value >= 0.005:
            return "The market feels upbeat with solid momentum."
        case let value where value <= -0.015:
            return "The market is stressed with sharp losses."
        case let value where value <= -0.005:
            return "The market feels cautious after a pullback."
        default:
            return "The market mood is steady and balanced."
        }
    }
}
