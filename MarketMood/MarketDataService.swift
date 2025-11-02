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
    private let baseURL = URL(string: "https://financialmodelingprep.com")!
    private let apiKey: String
    private let logger = Logger(subsystem: "com.marketmood", category: "MarketDataService")
    
    init() {
        // Try to get API key from Info.plist first
        if let apiKey = Bundle.main.infoDictionary?["API_KEY"] as? String {
            self.apiKey = apiKey
        } else {
            // Fallback: Use hardcoded key for now (in production, this should be in a secure config)
            self.apiKey = "jSidYa38QniqVGfDASVPuiAB1OIaM1kl"
            logger.warning("API_KEY not found in Info.plist, using fallback")
        }
    }

    func fetchQuotes(for symbols: [String] = ["SPY", "QQQ", "DIA"]) async throws -> [MarketQuote] {
        print("🔍 DEBUG - Fetching quotes for symbols: \(symbols.joined(separator: ", "))")
        
        // FMP /quote accepts one symbol at a time, so fetch them in parallel
        return try await withThrowingTaskGroup(of: (String, Result<MarketQuote, Error>).self) { group in
            for symbol in symbols {
                group.addTask {
                    do {
                        let quote = try await self.fetchQuote(for: symbol)
                        return (symbol, .success(quote))
                    } catch {
                        // Return failure result instead of throwing
                        print("🔍 DEBUG - Failed to fetch \(symbol): \(error)")
                        return (symbol, .failure(error))
                    }
                }
            }
            
            var quotes: [MarketQuote] = []
            var errorsBySymbol: [String: Error] = [:]
            
            for try await (symbol, result) in group {
                switch result {
                case .success(let quote):
                    quotes.append(quote)
                    print("🔍 DEBUG - Successfully collected quote for \(symbol)")
                case .failure(let error):
                    errorsBySymbol[symbol] = error
                    // If it's a cancellation error, just log it (common in previews)
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        print("🔍 DEBUG - Request cancelled for \(symbol) (this is normal in previews)")
                    } else {
                        print("🔍 DEBUG - Error fetching \(symbol): \(error)")
                    }
                }
            }
            
            // If we got at least some quotes, return them (partial success)
            // Otherwise throw the first error
            if quotes.isEmpty {
                if let firstSymbol = symbols.first, let firstError = errorsBySymbol[firstSymbol] {
                    throw firstError
                } else {
                    throw MarketDataError.missingQuote(symbol: symbols.first ?? "UNKNOWN")
                }
            }
            
            print("🔍 DEBUG - Collected \(quotes.count) quotes out of \(symbols.count) requested")
            print("🔍 DEBUG - Collected quote symbols: \(quotes.map { $0.symbol })")
            print("🔍 DEBUG - Looking for symbols: \(symbols)")
            
            // Sort quotes to match the input symbol order
            // Use case-insensitive comparison for symbol matching
            let result = symbols.compactMap { requestedSymbol in
                quotes.first { quote in
                    quote.symbol.caseInsensitiveCompare(requestedSymbol) == .orderedSame
                }
            }
            
            print("🔍 DEBUG - Final result count: \(result.count), symbols: \(result.map { $0.symbol })")
            
            return result
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

        // Debug: Log raw response first
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔍 DEBUG - Raw JSON response for \(symbol): \(responseString)")
        }
        
        // Debug: Try to decode and log success
        let decoded: [FMPQuote]
        do {
            decoded = try JSONDecoder().decode([FMPQuote].self, from: data)
            print("🔍 DEBUG - Successfully decoded JSON response for \(symbol)")
            print("🔍 DEBUG - Decoded array length: \(decoded.count)")
        } catch {
            // Log the raw response if decoding fails
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 DEBUG - Failed to decode JSON for \(symbol). Response body: \(responseString)")
                logger.error("JSON decode failed for \(symbol): \(error.localizedDescription)")
            }
            throw error
        }
        
        guard let quote = decoded.first else {
            print("🔍 DEBUG - Empty array returned for \(symbol), throwing missingQuote error")
            logger.warning("Empty response array for symbol: \(symbol)")
            throw MarketDataError.missingQuote(symbol: symbol)
        }
        
        print("🔍 DEBUG - quote found for \(symbol): symbol=\(quote.symbol), price=\(quote.price), previousClose=\(quote.previousClose)")

        guard let price = quote.price else {
            logger.warning("Missing or invalid price for symbol: \(symbol)")
            throw MarketDataError.missingQuote(symbol: symbol)
        }

        guard let previousClose = quote.previousClose else {
            logger.warning("Missing or invalid previous close for symbol: \(symbol)")
            throw MarketDataError.missingPreviousClose(symbol: symbol)
        }

        let returnedSymbol = quote.symbol ?? symbol
        let quoteResult = MarketQuote(symbol: returnedSymbol, price: price, previousClose: previousClose)
        print("🔍 DEBUG - Parsed quote: \(symbol) -> returned symbol: '\(returnedSymbol)' = $\(price) (prev: $\(previousClose))")
        return quoteResult
    }

    private func url(for symbol: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/stable/quote"
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        return components?.url
    }
}

// Financial Modeling Prep Quote response structure
private struct FMPQuote: Decodable {
    let symbol: String?
    let name: String?
    let price: Double?
    let changePercentage: Double?
    let change: Double?
    let volume: Int64?
    let dayLow: Double?
    let dayHigh: Double?
    let yearHigh: Double?
    let yearLow: Double?
    let marketCap: Int64?
    let priceAvg50: Double?
    let priceAvg200: Double?
    let exchange: String?
    let open: Double?
    let previousClose: Double?
    let timestamp: Int64?
    
    enum CodingKeys: String, CodingKey {
        case symbol, name, price, changePercentage, change, volume, dayLow, dayHigh, yearHigh, yearLow, marketCap, priceAvg50, priceAvg200, exchange, open, previousClose, timestamp
    }
}
