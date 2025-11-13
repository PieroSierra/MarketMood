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

    func loadQuotes(for symbols: [String] = [], regenerateMood: Bool = false) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        
        // Only clear mood if we're regenerating it
        if regenerateMood {
            mood = nil
        }

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
            
            // Only regenerate mood if requested
            if regenerateMood {
                // Try to generate mood with LLM, fallback to simple case statement if it fails
                do {
                    let symbolsToUse = symbols.isEmpty ? ["SPY", "QQQ", "DIA"] : symbols
                    mood = try await generateMood(from: fetchedQuotes, symbols: symbolsToUse)
                    print("🔍 DEBUG - Successfully generated mood with LLM: \(mood ?? "nil")")
                } catch {
                    print("🔍 DEBUG - Failed to generate mood with LLM: \(error)")
                    print("🔍 DEBUG - Error details: \(error.localizedDescription)")
                    // Fallback to simple case-statement approach if LLM fails
                    mood = makeMood(from: fetchedQuotes)
                    print("🔍 DEBUG - Using fallback mood: \(mood ?? "nil")")
                }
            }
        } catch {
            print("🔍 DEBUG - Failed to fetch quotes: \(error)")
            print("🔍 DEBUG - Error details: \(error.localizedDescription)")
            quotes = []
            errorMessage = message(for: error)
            // Only clear mood on error if we were regenerating
            if regenerateMood {
                mood = nil
            }
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

    private func generateMood(from quotes: [MarketQuote], symbols: [String]) async throws -> String? {
        guard !quotes.isEmpty else { return nil }

        // Determine if this is the default market set
        let defaultSymbols = Set(["SPY", "QQQ", "DIA"])
        let trackedSymbols = Set(symbols.map { $0.uppercased() })
        let isDefaultSet = trackedSymbols.isSuperset(of: defaultSymbols) && trackedSymbols.count == defaultSymbols.count
        let scopeLabel = isDefaultSet ? "the market" : "your stocks"
        
        // Calculate overall change percentage
        let overallChangePct = quotes.map(\.changePercent).reduce(0, +) / Double(quotes.count)
        
        // Count up and down movers
        let numUp = quotes.filter { $0.changePercent > 0 }.count
        let numDown = quotes.filter { $0.changePercent < 0 }.count
        let total = quotes.count
        
        // Find notable movers (top 2 by absolute percentage change, with threshold)
        let absThreshold = 0.025 // 2.5%
        let notableMovers = quotes
            .filter { abs($0.changePercent) >= absThreshold }
            .sorted { abs($0.changePercent) > abs($1.changePercent) }
            .prefix(2)
            .map { quote in
                let displayName = commonName(for: quote.symbol) ?? quote.name ?? quote.symbol
                return (name: displayName, pct: quote.changePercent)
            }
        
        // Build notable movers JSON array
        let notableMoversJSON: String
        if notableMovers.isEmpty {
            notableMoversJSON = "[]"
        } else {
            let moversArray = notableMovers.map { mover in
                let sign = mover.pct >= 0 ? "+" : ""
                // Escape quotes in the name for JSON safety
                let escapedName = mover.name.replacingOccurrences(of: "\"", with: "\\\"")
                return "{\"name\":\"\(escapedName)\",\"pct\":\(sign)\(String(format: "%.2f", mover.pct * 100))}"
            }.joined(separator: ",")
            notableMoversJSON = "[\(moversArray)]"
        }
        
        // Create the improved prompt following the suggestions
        let systemPrompt = """
        You write one short, witty line that reflects the day's mood for a set of stocks or indices.
        
        Priorities: (1) correct sentiment; (2) concise; (3) lightly witty phrasing—no forced jokes or anthropomorphizing.
        
        Never enumerate all tickers. At most, call out one or two unusually large movers.
        
        Prefer "your stocks" if the user is tracking a custom list; use "the market" if it's the default broad indices set.
        
        Don't explain your reasoning. Output exactly one sentence.
        """
        
        let userPrompt = """
        Context:
        
        scope_label: \(scopeLabel)
        overall_change_pct: \(String(format: "%.2f", overallChangePct * 100))
        num_up: \(numUp), num_down: \(numDown), total: \(total)
        notable_movers: \(notableMoversJSON)
        
        Style: witty, light, human; avoid clichés; 15–28 words; US English names (e.g., "Microsoft," "the Dow").
        
        Rules:
        - Lead with the scope_label ("\(scopeLabel)").
        - Summarize overall mood in one clause.
        - Optionally add a second clause with at most two notable_movers (biggest absolute % moves).
        - No lists, no emojis, no finance slang overload.
        - If overall_change_pct is between -0.15 and +0.15, treat as "flat."
        - If markets are closed and data is stale, say "were" instead of "are."
        
        Output: one sentence only.
        """
        
        // Combine system and user prompts (since we're using a single string API)
        let prompt = """
        \(systemPrompt)
        
        ---
        
        \(userPrompt)
        """
        
        print("🔍 DEBUG - Generating mood with improved prompt (length: \(prompt.count) characters)")
        print("🔍 DEBUG - Scope: \(scopeLabel), Overall change: \(overallChangePct * 100)%, Movers: \(notableMovers.count)")
        
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
    
    /// Maps stock symbols to their common names for display
    private func commonName(for symbol: String) -> String? {
        let symbolUpper = symbol.uppercased()
        switch symbolUpper {
        case "SPY": return "the S&P 500"
        case "QQQ": return "the Nasdaq"
        case "DIA": return "the Dow"
        case "DJI", "DJIA": return "the Dow"
        case "MSFT": return "Microsoft"
        case "AAPL": return "Apple"
        case "GOOGL", "GOOG": return "Google"
        case "AMZN": return "Amazon"
        case "TSLA": return "Tesla"
        case "NVDA": return "Nvidia"
        case "META": return "Meta"
        case "NFLX": return "Netflix"
        case "AMD": return "AMD"
        case "INTC": return "Intel"
        case "JPM": return "JPMorgan"
        case "BAC": return "Bank of America"
        case "WMT": return "Walmart"
        case "V": return "Visa"
        case "MA": return "Mastercard"
        case "DIS": return "Disney"
        default: return nil
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
