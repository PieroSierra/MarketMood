//
//  MarketDataService.swift
//  MarketMood
//
//  Created by ChatGPT on 06/10/2025.
//

import Foundation

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
    private let baseURL = URL(string: "https://query1.finance.yahoo.com/v7/finance/quote")!

    func fetchQuotes(for symbols: [String] = ["SPY", "QQQ", "DIA"]) async throws -> [MarketQuote] {
        guard let url = url(for: symbols) else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw MarketDataError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(YahooQuoteEnvelope.self, from: data)
        let results = decoded.quoteResponse.result

        let quotes = try symbols.map { symbol -> MarketQuote in
            guard let quote = results.first(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }),
                  let price = quote.regularMarketPrice else {
                throw MarketDataError.missingQuote(symbol: symbol)
            }

            guard let previousClose = quote.regularMarketPreviousClose else {
                throw MarketDataError.missingPreviousClose(symbol: symbol)
            }

            return MarketQuote(symbol: quote.symbol, price: price, previousClose: previousClose)
        }

        return quotes
    }

    private func url(for symbols: [String]) -> URL? {
        guard !symbols.isEmpty else { return nil }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))
        ]

        return components?.url
    }
}

private struct YahooQuoteEnvelope: Decodable {
    let quoteResponse: QuoteResponse

    struct QuoteResponse: Decodable {
        let result: [Quote]
    }
}

private struct Quote: Decodable {
    let symbol: String
    let regularMarketPrice: Double?
    let regularMarketPreviousClose: Double?
}
