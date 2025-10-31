//
//  ContentView.swift
//  MarketMood
//
//  Created by Piero Sierra on 06/10/2025.
//

import SwiftUI

// HEX color code extension
extension Color {
    init(hex: Int, opacity: Double = 1.0) {
        let red = Double((hex & 0xff0000) >> 16) / 255.0
        let green = Double((hex & 0xff00) >> 8) / 255.0
        let blue = Double((hex & 0xff) >> 0) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct ContentView: View {
    @StateObject private var viewModel: MarketMoodViewModel
    @State private var animationPhase: Double = 0
    @State private var animationTimer: Timer?

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
            return (Color(hex: 0xFFFFFF), Color(hex: 0xD3D3D3))
        }
        
        guard !viewModel.quotes.isEmpty else {
            return (Color(hex: 0xFFFFFF), Color(hex: 0xD3D3D3))
        }
        
        let averageChange = viewModel.quotes.map(\.changePercent).reduce(0, +) / Double(viewModel.quotes.count)
        
        switch averageChange {
        case let value where value >= 0.015:
            // Market up a lot - bright light green to vibrant green
            return (Color(hex: 0x90EE90), Color(hex: 0x51db51))  // LightGreen to Lime
        case let value where value >= 0.005:
            // Market up a bit - white to light green
            return (Color(hex: 0xFFFFFF), Color(hex: 0xD4F5D4))  // White to pale green
        case let value where value <= -0.015:
            // Market down a lot - bright light red to vibrant red
            return (Color(hex: 0xFFB6C1), Color(hex: 0xfc5858))  // LightPink to Red
        case let value where value <= -0.005:
            // Market down a bit - white to light red
            return (Color(hex: 0xFA9F98), Color(hex: 0xfaacb8))  // pink to misty rose
        default:
            // Steady - white to light gray
            return (Color(hex: 0xFFFFFF), Color(hex: 0xD3D3D3))
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
                // Only fetch if we have no quotes at all
                // Previews with hardcoded data already have quotes, so they won't trigger this
                if viewModel.quotes.isEmpty {
                    await viewModel.loadQuotes()
                }
            }
            .ignoresSafeArea() /// do not erase!
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
//                        .font(.system(size: 24, weight: .medium, design: .default))
                        .font(.custom("Avenir Next Demi Bold", fixedSize: 25))
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
            // Start continuous pulsing animation using Timer
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
                withAnimation(.linear(duration: 0.016)) {
                    animationPhase += 0.01
                    if animationPhase >= 1.0 {
                        animationPhase = 0.0
                    }
                }
            }
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }
    
    // Page 2: Quotes list
    private var quotesPage: some View {
        ZStack {
            // Animated gradient background
            animatedGradientBackground
            
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    
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
                    .frame(height: min(geometry.size.height * 0.6, CGFloat(viewModel.quotes.count * 60 + 100))) // Adjust height based on content
                    
                    Spacer()
                }
            }
        }
        .refreshable {
            await viewModel.loadQuotes()
        }
        .onAppear {
            // Start continuous pulsing animation using Timer (reuse same timer)
            if animationTimer == nil {
                animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
                    withAnimation(.linear(duration: 0.016)) {
                        animationPhase += 0.01
                        if animationPhase >= 1.0 {
                            animationPhase = 0.0
                        }
                    }
                }
            }
        }
    }
    
    // Animated gradient background with multiple pulsing radial zones
    private var animatedGradientBackground: some View {
        GeometryReader { geometry in
            let colors = gradientColors
            let baseSize = max(geometry.size.width, geometry.size.height) * 1.5
            // Use animationPhase directly for continuous animation (0 to 1, wrapping)
            let pulsePhase = (sin(animationPhase * .pi * 2) + 1.0) / 2.0 // Convert to 0-1 range
            
            ZStack {
                // Zone 1 - Top left - much more visible with larger opacity range
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.0.opacity(0.4 + pulsePhase * 0.4),  // 0.4 to 0.8
                        colors.1.opacity(0.3 + pulsePhase * 0.5)    // 0.3 to 0.8
                    ]),
                    center: UnitPoint(x: 0.2, y: 0.2),
                    startRadius: baseSize * (0.2 + pulsePhase * 0.2),  // More movement
                    endRadius: baseSize * (0.5 + pulsePhase * 0.3)
                )
                .offset(
                    x: -geometry.size.width * 0.2 * (pulsePhase - 0.5) * 0.3,  // More movement
                    y: -geometry.size.height * 0.2 * (pulsePhase - 0.5) * 0.3
                )
                
                // Zone 2 - Top right
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.1.opacity(0.35 + pulsePhase * 0.45),
                        colors.0.opacity(0.5 + pulsePhase * 0.3)
                    ]),
                    center: UnitPoint(x: 0.8, y: 0.25),
                    startRadius: baseSize * (0.18 + pulsePhase * 0.18),
                    endRadius: baseSize * (0.48 + pulsePhase * 0.25)
                )
                .offset(
                    x: geometry.size.width * 0.2 * (pulsePhase - 0.5) * 0.3,
                    y: -geometry.size.height * 0.15 * (pulsePhase - 0.5) * 0.3
                )
                
                // Zone 3 - Bottom left
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.0.opacity(0.45 + pulsePhase * 0.35),
                        colors.1.opacity(0.3 + pulsePhase * 0.5)
                    ]),
                    center: UnitPoint(x: 0.3, y: 0.75),
                    startRadius: baseSize * (0.2 + pulsePhase * 0.2),
                    endRadius: baseSize * (0.5 + pulsePhase * 0.3)
                )
                .offset(
                    x: -geometry.size.width * 0.15 * (pulsePhase - 0.5) * 0.3,
                    y: geometry.size.height * 0.2 * (pulsePhase - 0.5) * 0.3
                )
                
                // Zone 4 - Bottom right
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.1.opacity(0.4 + pulsePhase * 0.45),
                        colors.0.opacity(0.4 + pulsePhase * 0.35)
                    ]),
                    center: UnitPoint(x: 0.75, y: 0.8),
                    startRadius: baseSize * (0.25 + pulsePhase * 0.2),
                    endRadius: baseSize * (0.55 + pulsePhase * 0.3)
                )
                .offset(
                    x: geometry.size.width * 0.15 * (pulsePhase - 0.5) * 0.3,
                    y: geometry.size.height * 0.15 * (pulsePhase - 0.5) * 0.3
                )
            }
            .blur(radius: 40)  // Less blur for more visibility
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

// Preview: Market Up Slightly (0.5% - 1.5%)
#Preview("Market Up Slightly") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(symbol: "SPY", price: 450.00, previousClose: 446.50),  // +0.78%
                MarketQuote(symbol: "QQQ", price: 380.00, previousClose: 377.50),  // +0.66%
                MarketQuote(symbol: "DIA", price: 350.00, previousClose: 347.50)  // +0.72%
            ],
            initialMood: "The market feels upbeat with solid momentum."
        )
    )
}

// Preview: Market Up A Lot (>1.5%)
#Preview("Market Up A Lot") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(symbol: "SPY", price: 460.00, previousClose: 445.00),  // +3.37%
                MarketQuote(symbol: "QQQ", price: 390.00, previousClose: 375.00),  // +4.00%
                MarketQuote(symbol: "DIA", price: 360.00, previousClose: 345.00)  // +4.35%
            ],
            initialMood: "The market is euphoric with strong gains."
        )
    )
}

// Preview: Market Down Slightly (-0.5% to -1.5%)
#Preview("Market Down Slightly") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(symbol: "SPY", price: 443.00, previousClose: 446.50),  // -0.78%
                MarketQuote(symbol: "QQQ", price: 374.50, previousClose: 377.50),  // -0.79%
                MarketQuote(symbol: "DIA", price: 345.00, previousClose: 347.50)  // -0.72%
            ],
            initialMood: "The market feels cautious after a pullback."
        )
    )
}

// Preview: Market Down A Lot (<-1.5%)
#Preview("Market Down A Lot") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(symbol: "SPY", price: 435.00, previousClose: 450.00),  // -3.33%
                MarketQuote(symbol: "QQQ", price: 360.00, previousClose: 375.00),  // -4.00%
                MarketQuote(symbol: "DIA", price: 335.00, previousClose: 350.00)  // -4.29%
            ],
            initialMood: "The market is stressed with sharp losses."
        )
    )
}

// Preview: Live Data (actual API call)
// NOTE: This preview will attempt to fetch real data, but may hit Alpha Vantage's rate limit (25 requests/day)
// If you see rate limit errors, use one of the hardcoded previews above instead
#Preview("Live Data") {
    ContentView()
}
