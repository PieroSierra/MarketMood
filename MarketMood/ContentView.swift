//
//  ContentView.swift
//  MarketMood
//
//  Created by Piero Sierra on 06/10/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: MarketMoodViewModel
    @State private var animationPhase: Double = 0

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: MarketMoodViewModel())
    }

    @MainActor
    init(viewModel: MarketMoodViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // Determine gradient colors based on market state
    private var gradientColors: (Color, Color) {
        if viewModel.errorMessage != nil || viewModel.quotes.isEmpty {
            // No data or error - white to light gray
            return (Color.white, Color(white: 0.85))
        }
        
        guard !viewModel.quotes.isEmpty else {
            return (Color.white, Color(white: 0.85))
        }
        
        let averageChange = viewModel.quotes.map(\.changePercent).reduce(0, +) / Double(viewModel.quotes.count)
        
        switch averageChange {
        case let value where value >= 0.015:
            // Market up a lot - light green to green
            return (Color(red: 0.7, green: 0.95, blue: 0.7), Color(red: 0.2, green: 0.8, blue: 0.2))
        case let value where value >= 0.005:
            // Market up a bit - white to light green
            return (Color.white, Color(red: 0.85, green: 0.95, blue: 0.85))
        case let value where value <= -0.015:
            // Market down a lot - light red to red
            return (Color(red: 0.95, green: 0.7, blue: 0.7), Color(red: 0.8, green: 0.2, blue: 0.2))
        case let value where value <= -0.005:
            // Market down a bit - white to light red
            return (Color.white, Color(red: 0.95, green: 0.85, blue: 0.85))
        default:
            // Steady - white to light gray
            return (Color.white, Color(white: 0.85))
        }
    }

    var body: some View {
        NavigationStack {
            TabView {
                // Page 1: Mood page
                moodPage
                
                // Page 2: Quotes page
                quotesPage
            }
            .tabViewStyle(.page)
           // .navigationTitle("Market Mood")
            .task {
                if viewModel.quotes.isEmpty {
                    await viewModel.loadQuotes()
                }
            }
        }
    }
    
    // Page 1: Centered mood text
    private var moodPage: some View {
        ZStack {
            // Animated gradient background
            animatedGradientBackground
            
            VStack {
                Spacer()
                
                if let mood = viewModel.mood {
                    Text(mood)
                        .font(.system(size: 24, weight: .medium, design: .default))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 32)
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Text(errorMessage)
                            .font(.system(size: 22, weight: .regular, design: .default))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 32)
                        
                        Button {
                            Task { await viewModel.loadQuotes() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Text("Pull to refresh to load market mood")
                        .font(.system(size: 22, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                Spacer()
            }
        }
        .refreshable {
            await viewModel.loadQuotes()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        }
    }
    
    // Page 2: Quotes list
    private var quotesPage: some View {
        ZStack {
            // Animated gradient background
            animatedGradientBackground
            
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
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .refreshable {
            await viewModel.loadQuotes()
        }
        .onAppear {
            // Start continuous pulsing animation
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
        .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: animationPhase)
    }
    
    // Animated gradient background with multiple pulsing radial zones
    private var animatedGradientBackground: some View {
        GeometryReader { geometry in
            let colors = gradientColors
            let baseSize = max(geometry.size.width, geometry.size.height) * 1.5
            let pulsePhase = sin(animationPhase * .pi * 2) * 0.5 + 0.5 // Convert to 0-1 range
            
            ZStack {
                // Zone 1 - Top left
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.0.opacity(0.5 + pulsePhase * 0.15),
                        colors.1.opacity(0.25 + pulsePhase * 0.1)
                    ]),
                    center: UnitPoint(x: 0.2, y: 0.2),
                    startRadius: baseSize * (0.25 + pulsePhase * 0.1),
                    endRadius: baseSize * (0.55 + pulsePhase * 0.15)
                )
                .offset(
                    x: -geometry.size.width * 0.15 * pulsePhase * 0.1,
                    y: -geometry.size.height * 0.15 * pulsePhase * 0.1
                )
                
                // Zone 2 - Top right
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.1.opacity(0.35 + pulsePhase * 0.12),
                        colors.0.opacity(0.45 + pulsePhase * 0.1)
                    ]),
                    center: UnitPoint(x: 0.8, y: 0.25),
                    startRadius: baseSize * (0.22 + pulsePhase * 0.12),
                    endRadius: baseSize * (0.52 + pulsePhase * 0.12)
                )
                .offset(
                    x: geometry.size.width * 0.15 * pulsePhase * 0.1,
                    y: -geometry.size.height * 0.12 * pulsePhase * 0.1
                )
                
                // Zone 3 - Bottom left
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.0.opacity(0.45 + pulsePhase * 0.1),
                        colors.1.opacity(0.3 + pulsePhase * 0.12)
                    ]),
                    center: UnitPoint(x: 0.3, y: 0.75),
                    startRadius: baseSize * (0.24 + pulsePhase * 0.1),
                    endRadius: baseSize * (0.54 + pulsePhase * 0.15)
                )
                .offset(
                    x: -geometry.size.width * 0.12 * pulsePhase * 0.1,
                    y: geometry.size.height * 0.15 * pulsePhase * 0.1
                )
                
                // Zone 4 - Bottom right
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.1.opacity(0.4 + pulsePhase * 0.12),
                        colors.0.opacity(0.35 + pulsePhase * 0.1)
                    ]),
                    center: UnitPoint(x: 0.75, y: 0.8),
                    startRadius: baseSize * (0.28 + pulsePhase * 0.1),
                    endRadius: baseSize * (0.58 + pulsePhase * 0.15)
                )
                .offset(
                    x: geometry.size.width * 0.12 * pulsePhase * 0.1,
                    y: geometry.size.height * 0.12 * pulsePhase * 0.1
                )
            }
            .blur(radius: 50)
            .ignoresSafeArea()
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
    // Preview will automatically load live data via the .task modifier in ContentView
    ContentView()
}
