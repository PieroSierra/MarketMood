//
//  ContentView.swift
//  MarketMood
//
//  Created by Piero Sierra on 06/10/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: MarketMoodViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: MarketMoodViewModel())
    }

    @MainActor
    init(viewModel: MarketMoodViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Quotes") {
                    if viewModel.quotes.isEmpty {
                        if viewModel.isLoading {
                            loadingRow
                        } else {
                            placeholderRow
                        }
                    } else {
                        ForEach(viewModel.quotes) { quote in
                            quoteRow(quote)
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Status") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                        Button {
                            Task { await viewModel.loadQuotes() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Market Mood")
            .task {
                if viewModel.quotes.isEmpty {
                    await viewModel.loadQuotes()
                }
            }
            .refreshable {
                await viewModel.loadQuotes()
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
            Spacer()
        }
    }

    private var placeholderRow: some View {
        Text("No market data available yet.")
            .foregroundStyle(.secondary)
    }

    private func quoteRow(_ quote: MarketQuote) -> some View {
        HStack {
            Text(quote.symbol)
                .font(.headline)
            Spacer()
            Text(quote.price, format: .currency(code: "USD"))
                .monospacedDigit()
        }
        .accessibilityLabel("\(quote.symbol) trading at \(quote.price, format: .currency(code: "USD"))")
    }
}

#Preview {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(symbol: "SPY", price: 427.83),
                MarketQuote(symbol: "QQQ", price: 364.12),
                MarketQuote(symbol: "DIA", price: 345.01)
            ]
        )
    )
}
