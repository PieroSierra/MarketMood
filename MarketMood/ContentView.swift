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
                if let mood = viewModel.mood {
                    Section("Mood") {
                        Text(mood)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }

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
            VStack(alignment: .trailing, spacing: 4) {
                Text(quote.price, format: .currency(code: "USD"))
                    .monospacedDigit()
                changeLabel(for: quote)
            }
        }
        .accessibilityLabel("\(quote.symbol) trading at \(quote.price, format: .currency(code: "USD"))")
    }

    private func changeLabel(for quote: MarketQuote) -> some View {
        let change = quote.change
        let percent = quote.changePercent
        let changeColor: Color = change >= 0 ? .green : .red
        let sign = change >= 0 ? "+" : "-"
        let formattedChange = abs(change).formatted(.currency(code: "USD"))
        let formattedPercent = abs(percent).formatted(.percent.precision(.fractionLength(2)))
        let accessibilityDirection = change >= 0 ? "up" : "down"
        let accessibilityChange = abs(change).formatted(.currency(code: "USD"))
        let accessibilityPercent = abs(percent).formatted(.percent.precision(.fractionLength(2)))
        let accessibilityText = "\(quote.symbol) is \(accessibilityDirection) \(accessibilityChange) or \(accessibilityPercent) since the prior close."

        return Text("\(sign)\(formattedChange) (\(sign)\(formattedPercent))")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(changeColor)
            .accessibilityLabel(accessibilityText)
    }
}

#Preview {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(symbol: "SPY", price: 427.83, previousClose: 421.00),
                MarketQuote(symbol: "QQQ", price: 364.12, previousClose: 360.50),
                MarketQuote(symbol: "DIA", price: 345.01, previousClose: 349.75)
            ],
            initialMood: "Markets feel steady and balanced."
        )
    )
}
