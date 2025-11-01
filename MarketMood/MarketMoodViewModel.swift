//
//  MarketMoodViewModel.swift
//  MarketMood
//
//  Created by ChatGPT on 06/10/2025.
//

import Foundation
import Combine
import FoundationModels

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

    func loadQuotes(for symbols: [String] = []) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        mood = nil

        do {
            // Use provided symbols or let dataService use defaults
            let fetchedQuotes: [MarketQuote]
            if symbols.isEmpty {
                fetchedQuotes = try await dataService.fetchQuotes()
            } else {
                fetchedQuotes = try await dataService.fetchQuotes(for: symbols)
            }
            print("🔍 DEBUG - Successfully fetched \(fetchedQuotes.count) quotes")
            quotes = fetchedQuotes
            
            // Try to generate mood with LLM, fallback to simple case statement if it fails
            do {
                mood = try await generateMood(from: fetchedQuotes)
                print("🔍 DEBUG - Successfully generated mood with LLM: \(mood ?? "nil")")
            } catch {
                print("🔍 DEBUG - Failed to generate mood with LLM: \(error)")
                print("🔍 DEBUG - Error details: \(error.localizedDescription)")
                // Fallback to simple case-statement approach if LLM fails
                mood = makeMood(from: fetchedQuotes)
                print("🔍 DEBUG - Using fallback mood: \(mood ?? "nil")")
            }
        } catch {
            print("🔍 DEBUG - Failed to fetch quotes: \(error)")
            print("🔍 DEBUG - Error details: \(error.localizedDescription)")
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

    private func generateMood(from quotes: [MarketQuote]) async throws -> String? {
        guard !quotes.isEmpty else { return nil }

        let averageChange = quotes.map(\.changePercent).reduce(0, +) / Double(quotes.count)
        
        // Build a description of individual quote changes
        let individualChanges = quotes.map { quote in
            let percentStr = quote.changePercent.formatted(.percent.precision(.fractionLength(2)))
            let direction = quote.changePercent >= 0 ? "up" : "down"
            return "\(quote.symbol) is \(direction) \(percentStr)"
        }.joined(separator: ", ")
        
        // Create the prompt for the LLM
        let prompt = """
        Write a humorous, witty sentence about the stock market's mood today. 
        
        Here's the context:
        - Average market change: \(averageChange.formatted(.percent.precision(.fractionLength(2))))
        - Individual changes: \(individualChanges)
        
        The sentence should be funny and entertaining, like "The market has a major hangover today from last week's binging" or similar humorous observations. 
        Keep it to one sentence, be creative, and make it reflect the overall market sentiment while noting any interesting individual stock performance if relevant.
        
        Refer to stocks by their common name, e.g. DJI as "the Dow", or MSFT as "Microsoft"
        """
        
        print("🔍 DEBUG - Generating mood with prompt (length: \(prompt.count) characters)")
        
        // Use Foundation Models to generate the mood
        do {
            print("🔍 DEBUG - Creating LanguageModelSession...")
            let session = try LanguageModelSession()
            print("🔍 DEBUG - Calling session.respond(to:)...")
            let response = try await session.respond(to: prompt)
            print("🔍 DEBUG - Got response, extracting content...")
            
            // Extract text from the response
            // response.content is the generated text string
            let moodText = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            print("🔍 DEBUG - Generated mood text: \(moodText)")
            return moodText
        } catch {
            print("🔍 DEBUG - LLM error: \(error)")
            print("🔍 DEBUG - LLM error type: \(type(of: error))")
            throw error
        }
    }
    
    // Fallback mood generation using simple case statement
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
