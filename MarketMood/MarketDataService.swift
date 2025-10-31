//
//  MarketDataService.swift
//  MarketMood
//
//  Created by ChatGPT on 06/10/2025.
//

import Foundation
import OSLog

struct MarketQuote: Identifiable, Equatable {
    let symbol: String
    let price: Double
    let previousClose: Double

    var id: String { symbol }

    /// Raw dollar change from the prior close.
    var change: Double {
        price - previousClose
    }

    /// Percentage move from the prior close (0 if the prior close is zero).
    var changePercent: Double {
        guard previousClose != 0 else { return 0 }
        return change / previousClose
    }
}

enum MarketDataError: Error {
    case invalidURL
    case invalidResponse(statusCode: Int)
    case missingQuote(symbol: String)
    case missingPreviousClose(symbol: String)
}

struct MarketDataService {
    private let baseURL = URL(string: "https://www.alphavantage.co/query")!
    private let apiKey = "FJY3KQ4JO44PVJVG"
    private let logger = Logger(subsystem: "com.marketmood", category: "MarketDataService")

    func fetchQuotes(for symbols: [String] = ["SPY", "QQQ", "DIA"]) async throws -> [MarketQuote] {
        print("🔍 DEBUG - Fetching quotes for symbols: \(symbols.joined(separator: ", "))")
        
        // Alpha Vantage GLOBAL_QUOTE only accepts one symbol at a time, so fetch them in parallel
        return try await withThrowingTaskGroup(of: MarketQuote.self) { group in
            for symbol in symbols {
                group.addTask {
                    try await self.fetchQuote(for: symbol)
                }
            }
            
            var quotes: [MarketQuote] = []
            for try await quote in group {
                quotes.append(quote)
            }
            
            // Sort quotes to match the input symbol order
            return symbols.compactMap { symbol in
                quotes.first { $0.symbol == symbol }
            }
        }
    }
    
    private func fetchQuote(for symbol: String) async throws -> MarketQuote {
        guard let url = url(for: symbol) else {
            logger.error("Failed to generate URL for symbol: \(symbol)")
            throw MarketDataError.invalidURL
        }

        // Debug: Log the generated URL
        logger.info("Fetching quote from URL: \(url.absoluteString)")
        print("🔍 DEBUG - Generated URL for \(symbol): \(url.absoluteString)")

        let request = URLRequest(url: url)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Network request failed for \(symbol): \(error.localizedDescription)")
            print("🔍 DEBUG - Network error for \(symbol): \(error)")
            throw error
        }

        // Debug: Log response details
        if let httpResponse = response as? HTTPURLResponse {
            print("🔍 DEBUG - Response status code for \(symbol): \(httpResponse.statusCode)")
            
            // Log response body for error cases
            if !(200..<300).contains(httpResponse.statusCode) {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🔍 DEBUG - Response body for \(symbol): \(responseString)")
                    logger.error("Received error response for \(symbol) (\(httpResponse.statusCode)): \(responseString.prefix(200))")
                } else {
                    print("🔍 DEBUG - Response body for \(symbol): <unable to decode as UTF-8, \(data.count) bytes>")
                }
                throw MarketDataError.invalidResponse(statusCode: httpResponse.statusCode)
            }
        }

        print("🔍 DEBUG - Received \(data.count) bytes of data for \(symbol)")

        // Debug: Try to decode and log success
        let decoded: AlphaVantageQuoteResponse
        do {
            decoded = try JSONDecoder().decode(AlphaVantageQuoteResponse.self, from: data)
            print("🔍 DEBUG - Successfully decoded JSON response for \(symbol)")
        } catch {
            // Log the raw response if decoding fails
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 DEBUG - Failed to decode JSON for \(symbol). Response body: \(responseString)")
                logger.error("JSON decode failed for \(symbol): \(error.localizedDescription)")
            }
            throw error
        }
        
        guard let globalQuote = decoded.globalQuote else {
            // Check for API error messages
            if let errorMessage = decoded.errorMessage, let note = decoded.note {
                print("🔍 DEBUG - Alpha Vantage API error: \(errorMessage), Note: \(note)")
                logger.error("Alpha Vantage API error for \(symbol): \(errorMessage)")
                throw MarketDataError.missingQuote(symbol: symbol)
            }
            logger.warning("Missing Global Quote data for symbol: \(symbol)")
            throw MarketDataError.missingQuote(symbol: symbol)
        }

        guard let priceString = globalQuote.price,
              let price = Double(priceString) else {
            logger.warning("Missing or invalid price for symbol: \(symbol)")
            throw MarketDataError.missingQuote(symbol: symbol)
        }

        guard let previousCloseString = globalQuote.previousClose,
              let previousClose = Double(previousCloseString) else {
            logger.warning("Missing or invalid previous close for symbol: \(symbol)")
            throw MarketDataError.missingPreviousClose(symbol: symbol)
        }

        let quoteResult = MarketQuote(symbol: globalQuote.symbol ?? symbol, price: price, previousClose: previousClose)
        print("🔍 DEBUG - Parsed quote: \(symbol) = $\(price) (prev: $\(previousClose))")
        return quoteResult
    }

    private func url(for symbol: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "function", value: "GLOBAL_QUOTE"),
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        return components?.url
    }
}

// Alpha Vantage GLOBAL_QUOTE response structure
private struct AlphaVantageQuoteResponse: Decodable {
    let globalQuote: GlobalQuote?
    let errorMessage: String?
    let note: String?
    
    enum CodingKeys: String, CodingKey {
        case globalQuote = "Global Quote"
        case errorMessage = "Error Message"
        case note = "Note"
    }
    
    struct GlobalQuote: Decodable {
        let symbol: String?
        let price: String?
        let previousClose: String?
        
        enum CodingKeys: String, CodingKey {
            case symbol = "01. symbol"
            case price = "05. price"
            case previousClose = "08. previous close"
        }
    }
}
