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

    private let dataService: MarketDataService

    init(
        dataService: MarketDataService,
        initialQuotes: [MarketQuote] = [],
        initialIsLoading: Bool = false,
        initialErrorMessage: String? = nil
    ) {
        self.dataService = dataService
        self.quotes = initialQuotes
        self.isLoading = initialIsLoading
        self.errorMessage = initialErrorMessage
    }

    convenience init(
        initialQuotes: [MarketQuote] = [],
        initialIsLoading: Bool = false,
        initialErrorMessage: String? = nil
    ) {
        self.init(
            dataService: MarketDataService(),
            initialQuotes: initialQuotes,
            initialIsLoading: initialIsLoading,
            initialErrorMessage: initialErrorMessage
        )
    }

    func loadQuotes() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let fetchedQuotes = try await dataService.fetchQuotes()
            quotes = fetchedQuotes
        } catch {
            quotes = []
            errorMessage = message(for: error)
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
        default:
            return "Something went wrong while fetching the market data."
        }
    }
}
