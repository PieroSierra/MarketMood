//
//  ContentView.swift
//  MarketMood
//
//  Created by Piero Sierra on 06/10/2025.
//

import SwiftUI
import WidgetKit
import UIKit

// UIKit-based tap gesture recognizer that provides location and allows simultaneous recognition
struct TapLocationView: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    
    func makeUIView(context: Context) -> TapLocationUIView {
        let view = TapLocationUIView()
        view.onTap = onTap
        return view
    }
    
    func updateUIView(_ uiView: TapLocationUIView, context: Context) {
        uiView.onTap = onTap
    }
}

class TapLocationUIView: UIView {
    var onTap: ((CGPoint) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTapGesture()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTapGesture()
    }
    
    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        onTap?(location)
    }
}

extension TapLocationUIView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow simultaneous recognition with TabView's pan gesture
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't require failure of pan gestures (TabView swipes)
        if otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        return false
    }
}

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
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: MarketMoodViewModel
    @State private var animationPhase: Double = 0
    @State private var animationTimer: Timer?

    // Random center points for gradient zones (0.0 to 1.0 for UnitPoint)
    @State private var gradientCenters: [CGPoint] = []
    @State private var gradientVelocities: [CGPoint] = []
    @State private var pulseSpeeds: [Double] = []  // Individual pulse speed for each dot
    @State private var pulsePhases: [Double] = []  // Individual pulse phase for each dot

    // Add stock dialog state
    @State private var showAddDialog = false
    @State private var newSymbolText = ""
    @State private var searchResults: [StockSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    
    // Ripple effect trigger
    @State private var rippleTrigger = UUID()
    @State private var rippleCenter = CGPoint(x: 200, y: 400)
    
    // Track initial load state
    @State private var hasCompletedInitialLoad = false
    
    // Cached mood & date (persisted across launches)
    @State private var cachedMood: String?
    @State private var cachedMoodDate: Date?
    
    // Cache keys
    private let cachedMoodKey = "MarketMood.cachedMoodText"
    private let cachedMoodDateKey = "MarketMood.cachedMoodDateISO8601"
    private let cachedMarketStateKey = "MarketMood.cachedMarketState" // "good", "bad", or "neutral"
    // App Group (must match the App Group enabled for both app and widget)
    private let appGroupId = "group.com.pieroco.MarketMood"
    private let refreshRequestedKey = "MarketMood.refreshRequestedISO8601"
    
    private func loadCachedMood() {
        let defaults = UserDefaults.standard
        if let mood = defaults.string(forKey: cachedMoodKey) {
            cachedMood = mood
        }
        if let dateISO = defaults.string(forKey: cachedMoodDateKey) {
            let formatter = ISO8601DateFormatter()
            cachedMoodDate = formatter.date(from: dateISO)
        }
    }
    
    // Determine market state from quotes ("good", "bad", or "neutral")
    private func determineMarketState(from quotes: [MarketQuote]) -> String {
        guard !quotes.isEmpty else {
            return "neutral"
        }
        
        let averageChange = quotes.map(\.changePercent).reduce(0, +) / Double(quotes.count)
        
        switch averageChange {
        case let value where value >= 0.005:
            return "good"
        case let value where value <= -0.005:
            return "bad"
        default:
            return "neutral"
        }
    }
    
    private func saveCachedMood(mood: String, date: Date) {
        let defaults = UserDefaults.standard
        defaults.set(mood, forKey: cachedMoodKey)
        let formatter = ISO8601DateFormatter()
        defaults.set(formatter.string(from: date), forKey: cachedMoodDateKey)
        cachedMood = mood
        cachedMoodDate = date
        
        // Determine and save market state from quotes
        let marketState = determineMarketState(from: viewModel.quotes)
        defaults.set(marketState, forKey: cachedMarketStateKey)
        
        // Also write to App Group so the widget can read it
        if let groupDefaults = UserDefaults(suiteName: appGroupId) {
            groupDefaults.set(mood, forKey: cachedMoodKey)
            groupDefaults.set(formatter.string(from: date), forKey: cachedMoodDateKey)
            groupDefaults.set(marketState, forKey: cachedMarketStateKey)
        }
        
        // Request widget timeline reload so it shows the latest cache
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Define 8 complementary colors as hex values
    // Good market colors: green, blue, yellow, aquamarine
    private static let goodColorHex = [0x51db51, 0x4169E1, 0xFFD700, 0x7FFFD4]

    // Bad market colors: red, purple, orange, fuchsia
    private static let badColorHex = [0xfc5858, 0x9932CC, 0xFF8C00, 0xFF00FF]
    
    // Neutral market colors: blue, cyan, teal, aqua
    private static let neutralColorHex = [0x0000FF, 0x00FFFF, 0x008080, 0x00FFFF]

    // Helper to mix color with white (50/50 blend) using hex arithmetic
    private func halfMixWithWhite(_ hexColor: Int) -> Color {
        let r = ((hexColor & 0xff0000) >> 16)
        let g = ((hexColor & 0xff00) >> 8)
        let b = (hexColor & 0xff)
        // Mix 50/50 with white (255, 255, 255)
        let mixedR = (r + 255) / 2
        let mixedG = (g + 255) / 2
        let mixedB = (b + 255) / 2
        return Color(hex: (mixedR << 16) | (mixedG << 8) | mixedB)
    }

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: MarketMoodViewModel())

        // Customize page indicator dots to be visible
        UIPageControl.appearance().currentPageIndicatorTintColor = .black
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.black
            .withAlphaComponent(0.3)
    }

    @MainActor
    init(viewModel: MarketMoodViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)

        // Customize page indicator dots to be visible
        UIPageControl.appearance().currentPageIndicatorTintColor = .black
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.black
            .withAlphaComponent(0.3)
    }

    // Determine gradient colors based on market state - returns 4 colors
    private var gradientColors: [Color] {
        // Show neutral colors during initial load or when no data
        if !hasCompletedInitialLoad || viewModel.errorMessage != nil || viewModel.quotes.isEmpty {
            // No data or initial load - use neutral colors half-mixed with white
            return Self.neutralColorHex.map { halfMixWithWhite($0) }
        }

        guard !viewModel.quotes.isEmpty else {
            return Self.neutralColorHex.map { halfMixWithWhite($0) }
        }

        let averageChange =
            viewModel.quotes.map(\.changePercent).reduce(0, +)
            / Double(viewModel.quotes.count)

        switch averageChange {
        case let value where value >= 0.015:
            // Market up a lot - use full good colors
            return Self.goodColorHex.map { Color(hex: $0) }
        case let value where value >= 0.005:
            // Market up a bit - use good colors half-mixed with white
            return Self.goodColorHex.map { halfMixWithWhite($0) }
        case let value where value <= -0.015:
            // Market down a lot - use full bad colors
            return Self.badColorHex.map { Color(hex: $0) }
        case let value where value <= -0.005:
            // Market down a bit - use bad colors half-mixed with white
            return Self.badColorHex.map { halfMixWithWhite($0) }
        default:
            // Steady / neutral - use neutral colors half-mixed with white
            return Self.neutralColorHex.map { halfMixWithWhite($0) }
        }
    }

    var body: some View {
        
        TabView {
            // Page 1: Mood page
            moodPage
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showAddDialog = true
                        }) {
                            Label("Info", systemImage: "info")
                        }
                    }
                }
                

            // Page 2: Quotes page
            quotesPage
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showAddDialog = true
                        }) {
                            Label("Add Stock", systemImage: "plus")
                        }
                    }
                }
        }
        .tabViewStyle(.page)

        // .navigationTitle("Market Mood")
        .task {
            // Only fetch if we have no quotes at all (initial load)
            // Previews with hardcoded data already have quotes, so they won't trigger this
            if viewModel.quotes.isEmpty {
                await viewModel.loadQuotes(for: appState.favoriteSymbols, regenerateMood: true)
                // Mark initial load as complete after loading
                if !viewModel.quotes.isEmpty || viewModel.errorMessage != nil {
                    hasCompletedInitialLoad = true
                }
            } else {
                // If we already have quotes (e.g., from preview), mark as completed
                hasCompletedInitialLoad = true
            }
        }
        .ignoresSafeArea()/// do not erase!
    }

    // Page 1: Centered mood text
    private var moodPage: some View {
        
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Animated gradient background
                    animatedGradientBackground

                    VStack {
                        Spacer()

                        if !hasCompletedInitialLoad && viewModel.isLoading {
                            // During initial load on subsequent runs: show cached mood if available
                            if let cachedMood {                  
                                coloredMoodText(cachedMood, fontSize: 25, color: .secondary)
                                    .padding(.horizontal, 32)
                                Text("\nThinking...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                // First run with no cache yet
                                Text("Thinking...")
                                    .font(.custom("HelveticaNeue-Medium", fixedSize: 25))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 32)
                            }
                        } else if let mood = viewModel.mood {
                            // Show fresh mood and current date
                            let now = Date()
                            let dayOnly = now.formatted(.dateTime.month(.wide).day().year())
                            coloredMoodText(mood, fontSize: 25, color: .primary)
                                .padding(.horizontal, 32)
                            Text("\n\(dayOnly)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if let errorMessage = viewModel.errorMessage {
                            // If we have cached content, show it in gray with red "Last: <date>"
                            if let cachedMood {
                                coloredMoodText(cachedMood, fontSize: 25, color: .secondary)
                                    .padding(.horizontal, 32)
                                if let cachedMoodDate {
                                    let dayOnly = cachedMoodDate.formatted(.dateTime.month(.wide).day().year())
                                    Text("\nLast: \(dayOnly)")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            } else {
                                // No cache to show; fall back to error UI with retry
                                VStack(spacing: 16) {
                                    Text(errorMessage)
                                        .font(
                                            .system(
                                                size: 22,
                                                weight: .regular,
                                                design: .default
                                            )
                                        )
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 32)
                                    
                                    Button {
                                        Task {
                                            await viewModel.loadQuotes(
                                                for: appState.favoriteSymbols,
                                                regenerateMood: true
                                            )
                                        }
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                }
                            }
                        } else if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(1.5)
                        } else {
                            Text("Pull to refresh to load market mood")
                                .font(
                                    .system(
                                        size: 22,
                                        weight: .regular,
                                        design: .default
                                    )
                                )
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        Spacer()
                    }
                }
                .modifier(RippleEffect(
                    at: rippleCenter,
                    trigger: rippleTrigger,
                    amplitude: -22,
                    frequency: 15,
                    decay: 4,
                    speed: 600
                ))
                .overlay {
                    // UIKit-based tap gesture that allows simultaneous recognition with TabView swipes
                    TapLocationView { location in
                        rippleCenter = location
                        rippleTrigger = UUID()
                    }
                }
            }

        }
        .refreshable {
            await viewModel.loadQuotes(for: appState.favoriteSymbols, regenerateMood: true)
        }
        .onChange(of: viewModel.mood) { _, newMood in
            // Only trigger ripple after initial load completes and when mood changes
            if hasCompletedInitialLoad && newMood != nil {
                // Center the ripple on initial mood load
                rippleCenter = CGPoint(x: 200, y: 400)
                rippleTrigger = UUID()
                
                // Save latest mood to cache with current date
                if let moodToSave = newMood {
                    saveCachedMood(mood: moodToSave, date: Date())
                }
            }
        }
        .onChange(of: hasCompletedInitialLoad) { _, completed in
            // Trigger ripple when initial load completes with mood data
            if completed && viewModel.mood != nil {
                // Center the ripple on initial load
                rippleCenter = CGPoint(x: 200, y: 400)
                rippleTrigger = UUID()
            }
        }
        .onAppear {
            // Load cached mood/date for immediate display on subsequent runs
            loadCachedMood()
            // Initialize random gradient centers and velocities if not already set
            if gradientCenters.isEmpty {
                initializeGradientCenters()
            }

            // Start continuous pulsing animation using Timer
            animationTimer = Timer.scheduledTimer(
                withTimeInterval: 0.016,
                repeats: true
            ) { _ in
                withAnimation(.linear(duration: 0.016)) {
                    animationPhase += 0.01
                    if animationPhase >= 1.0 {
                        animationPhase = 0.0
                    }
                    updateGradientCenters()
                }
            }
            
            // Trigger ripple on appear if mood is already present and initial load is complete
            // (This handles page transitions between Quotes and Mood pages)
            if hasCompletedInitialLoad && viewModel.mood != nil {
                // Center the ripple on page transition
                rippleCenter = CGPoint(x: 200, y: 400)
                rippleTrigger = UUID()
            }
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        // When app becomes active (e.g., from widget refresh action), check for refresh request
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                handlePendingRefreshRequestIfAny()
            }
        }
        // Handle deep links (from widget refresh link)
        .onOpenURL { url in
            if url.scheme == "marketmood", url.host == "refresh" {
                Task {
                    await viewModel.loadQuotes(for: appState.favoriteSymbols, regenerateMood: true)
                }
            }
        }

    }
    
    @Environment(\.scenePhase) private var scenePhase
    
    private func handlePendingRefreshRequestIfAny() {
        guard let groupDefaults = UserDefaults(suiteName: appGroupId) else { return }
        let formatter = ISO8601DateFormatter()
        if let iso = groupDefaults.string(forKey: refreshRequestedKey),
           let when = formatter.date(from: iso) {
            // If the request is recent, perform a full refresh, then clear the flag
            if Date().timeIntervalSince(when) < 60 {
                groupDefaults.removeObject(forKey: refreshRequestedKey)
                Task {
                    await viewModel.loadQuotes(for: appState.favoriteSymbols, regenerateMood: true)
                }
            } else {
                groupDefaults.removeObject(forKey: refreshRequestedKey)
            }
        }
    }

    // Page 2: Quotes list
    private var quotesPage: some View {
        NavigationStack {
            ZStack {
                // Animated gradient background
                animatedGradientBackground

                // Quotes list
                VStack {
                    Spacer()
                    List {
                        // Blank space via a header spacer
                        Section(header:
                            // Adjust height to taste
                            Color.clear
                                .frame(height: 50)
                        ) {
                            // Keep section empty to only create space
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
                                .onDelete(perform: deleteQuotes)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            EditButton()
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showAddDialog = true
                            }) {
                                Label("Add Stock", systemImage: "plus")
                            }
                        }
                    }
      
                }
            }
        }
        .refreshable {
            // Regenerate mood when pulling to refresh on quotes page
            await viewModel.loadQuotes(for: appState.favoriteSymbols, regenerateMood: true)
        }
        .onAppear {
            // Initialize random gradient centers and velocities if not already set
            if gradientCenters.isEmpty {
                initializeGradientCenters()
            }

            // Start continuous pulsing animation using Timer (reuse same timer)
            if animationTimer == nil {
                animationTimer = Timer.scheduledTimer(
                    withTimeInterval: 0.016,
                    repeats: true
                ) { _ in
                    withAnimation(.linear(duration: 0.016)) {
                        animationPhase += 0.01
                        if animationPhase >= 1.0 {
                            animationPhase = 0.0
                        }
                        updateGradientCenters()
                    }
                }
            }
        }
        .sheet(isPresented: $showAddDialog) {
            addStockDialog
        }
    }

    // Delete quotes using native swipe-to-delete with IndexSet
    private func deleteQuotes(offsets: IndexSet) {
        withAnimation {
            let symbolsToDelete = offsets.map { viewModel.quotes[$0].symbol }
            for symbol in symbolsToDelete {
                appState.removeFavorite(symbol)
            }
            Task {
                // Regenerate mood when deleting quotes
                await viewModel.loadQuotes(for: appState.favoriteSymbols, regenerateMood: true)
            }
        }
    }

    // Add stock dialog
    private var addStockDialog: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Search field
                TextField("Stock Symbol or Company Name", text: $newSymbolText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding()
                    .onChange(of: newSymbolText) { _, newValue in
                        performSearch(query: newValue)
                    }
                
                // Search results or loading/error state
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
                        Spacer()
                    }
                    .padding()
                } else if let error = searchError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                } else if !searchResults.isEmpty {
                    List(searchResults) { result in
                        Button {
                            selectSearchResult(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.symbol)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(result.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let exchange = result.exchangeFullName ?? result.exchange {
                                    Text(exchange)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                } else if !newSymbolText.isEmpty && !isSearching {
                    Text("No results found")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding()
                }
                Spacer()
            }
            .navigationTitle("Add Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelSearch()
                        showAddDialog = false
                        newSymbolText = ""
                        searchResults = []
                        searchError = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            cancelSearch()
        }
    }
    
    private func performSearch(query: String) {
        // Cancel previous search task
        searchTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clear results if query is empty or less than 3 characters
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }
        
        // Don't search until at least 3 characters are entered
        guard trimmedQuery.count >= 3 else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }
        
        // Debounce search: wait 0.5 seconds after user stops typing
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await performSearchRequest(query: trimmedQuery)
        }
    }
    
    @MainActor
    private func performSearchRequest(query: String) async {
        isSearching = true
        searchError = nil
        
        do {
            let service = MarketDataService()
            let results = try await service.searchStocks(query: query, limit: 20)
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            searchResults = results
            isSearching = false
        } catch {
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            searchError = "Search failed: \(error.localizedDescription)"
            searchResults = []
            isSearching = false
        }
    }
    
    private func selectSearchResult(_ result: StockSearchResult) {
        appState.addFavorite(result.symbol)
        Task {
            // Regenerate mood when adding quotes
            await viewModel.loadQuotes(
                for: appState.favoriteSymbols,
                regenerateMood: true
            )
        }
        cancelSearch()
        showAddDialog = false
        newSymbolText = ""
        searchResults = []
        searchError = nil
    }
    
    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    // Initialize random gradient center positions and velocities
    private func initializeGradientCenters() {
        gradientCenters = (0..<4).map { _ in
            CGPoint(
                x: CGFloat.random(in: 0.1...0.9),
                y: CGFloat.random(in: 0.1...0.9)
            )
        }

        // Initialize velocities for smooth motion - 50% faster than before
        gradientVelocities = (0..<4).map { _ in
            CGPoint(
                x: CGFloat.random(in: -0.00045...0.00045),  // 1.5x faster
                y: CGFloat.random(in: -0.00045...0.00045)  // 1.5x faster
            )
        }

        // Initialize individual pulse speeds (random speeds for each dot)
        pulseSpeeds = (0..<4).map { _ in
            Double.random(in: 0.0005...0.002)  // Different speeds per dot
        }

        // Initialize pulse phases (random starting phases)
        pulsePhases = (0..<4).map { _ in
            Double.random(in: 0.0...1.0)
        }
    }

    // Update gradient center positions with smooth motion
    private func updateGradientCenters() {
        for i in 0..<gradientCenters.count {
            var center = gradientCenters[i]
            var velocity = gradientVelocities[i]

            // Update position
            center.x += velocity.x
            center.y += velocity.y

            // Bounce off edges (smooth reflection)
            if center.x <= 0.05 || center.x >= 0.95 {
                velocity.x *= -1.0
            }
            if center.y <= 0.05 || center.y >= 0.95 {
                velocity.y *= -1.0
            }

            // Keep within bounds
            center.x = max(0.05, min(0.95, center.x))
            center.y = max(0.05, min(0.95, center.y))

            // Occasionally change direction for more interesting paths (about every 3-5 seconds)
            if Int.random(in: 1...300) == 1 {
                velocity.x += CGFloat.random(in: -0.0003...0.0003)  // 1.5x faster
                velocity.y += CGFloat.random(in: -0.0003...0.0003)  // 1.5x faster

                // Limit max velocity (50% faster)
                velocity.x = max(-0.00075, min(0.00075, velocity.x))
                velocity.y = max(-0.00075, min(0.00075, velocity.y))
            }

            // Update individual pulse phase for this dot
            pulsePhases[i] += pulseSpeeds[i]
            if pulsePhases[i] >= 1.0 {
                pulsePhases[i] = 0.0
            }

            gradientCenters[i] = center
            gradientVelocities[i] = velocity
        }
    }

    // Animated gradient background with multiple pulsing radial zones
    private var animatedGradientBackground: some View {
        GeometryReader { geometry in
            let colors = gradientColors
            let screenSize = max(geometry.size.width, geometry.size.height)
            // Each gradient circle should be a reasonable size (about 30-50% of screen)
            let baseCircleSize = screenSize * 0.9

            ZStack {
                // Create 4 gradient zones with random, moving centers
                ForEach(0..<4, id: \.self) { index in
                    if index < gradientCenters.count && index < colors.count {
                        let center = gradientCenters[index]
                        let color = colors[index]

                        // Use individual pulse phase for this dot
                        let individualPulsePhase =
                            index < pulsePhases.count
                            ? (sin(pulsePhases[index] * .pi * 2) + 1.0) / 2.0  // Convert to 0-1 range
                            : 0.5

                        // Pulse the size: small to large circle
                        let minRadius = baseCircleSize * 0.3
                        let maxRadius = baseCircleSize * 0.6
                        let currentRadius =
                            minRadius + (maxRadius - minRadius)
                            * individualPulsePhase

                        // Pulse the brightness: dimmer to brighter
                        let minOpacity = 0.2
                        let maxOpacity = 0.6
                        let currentOpacity =
                            minOpacity + (maxOpacity - minOpacity)
                            * individualPulsePhase

                        // Create gradient from color (center) to transparent (edges)
                        // Position the gradient circle at the dot's location
                        let centerX = center.x * geometry.size.width
                        let centerY = center.y * geometry.size.height

                        RadialGradient(
                            gradient: Gradient(colors: [
                                color.opacity(currentOpacity),  // Bright at center
                                color.opacity(currentOpacity * 0.6),  // Mid
                                color.opacity(currentOpacity * 0.3),  // Fading
                                Color.clear,  // Transparent at edges
                            ]),
                            center: UnitPoint(x: 0.5, y: 0.5),  // Center of the circle itself
                            startRadius: 0,
                            endRadius: currentRadius
                        )
                        .frame(
                            width: currentRadius * 2,
                            height: currentRadius * 2
                        )
                        .position(x: centerX, y: centerY)
                    }
                }
            }
            .blur(radius: 30)  // Less blur for more visibility
            .ignoresSafeArea()
                .overlay {
                    // Black dots at center for visibility (comment out later)
                 /*   GeometryReader { overlayGeometry in
                        ZStack {
                            ForEach(0..<4, id: \.self) { index in
                                if index < gradientCenters.count {
                                    let center = gradientCenters[index]
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 8, height: 8)
                                        .position(
                                            x: center.x * overlayGeometry.size.width,
                                            y: center.y * overlayGeometry.size.height
                                        )
                                }
                            }
                        }
                    }*/
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
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.symbol)
                    .font(.headline)
                if let name = quote.name {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(quote.price, format: .currency(code: "USD"))
                    .monospacedDigit()
                changeLabel(for: quote)
            }
        }
        .accessibilityLabel(
            "\(quote.symbol)\(quote.name.map { " \($0)" } ?? "") trading at \(quote.price, format: .currency(code: "USD"))"
        )
    }

    private func changeLabel(for quote: MarketQuote) -> some View {
        let change = quote.change
        let percent = quote.changePercent
        let changeColor: Color = change >= 0 ? .green : .red
        let sign = change >= 0 ? "+" : "-"
        let formattedChange = abs(change).formatted(.currency(code: "USD"))
        let formattedPercent = abs(percent).formatted(
            .percent.precision(.fractionLength(2))
        )
        let accessibilityDirection = change >= 0 ? "up" : "down"
        let accessibilityChange = abs(change).formatted(.currency(code: "USD"))
        let accessibilityPercent = abs(percent).formatted(
            .percent.precision(.fractionLength(2))
        )
        let accessibilityText =
            "\(quote.symbol) is \(accessibilityDirection) \(accessibilityChange) or \(accessibilityPercent) since the prior close."

        return Text("\(sign)\(formattedChange) (\(sign)\(formattedPercent))")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(changeColor)
            .accessibilityLabel(accessibilityText)
    }
    
    /// Creates a Text view with colored arrows (▲ green, ▼ red)
    private func coloredMoodText(_ mood: String, fontSize: CGFloat, color: Color) -> some View {
        // Build a single AttributedString, colorizing only the arrows
        let upArrow = "▲"
        let downArrow = "▼"

        var attributed = AttributedString()
        let tokens = mood.split(separator: " ")

        for (index, token) in tokens.enumerated() {
            if index > 0 {
                attributed.append(AttributedString(" "))
            }

            var part = AttributedString(String(token))

            // Colorize any up arrows within this token
            if let range = part.range(of: upArrow) {
                part[range].foregroundColor = .green
            }

            // Colorize any down arrows within this token
            if let range = part.range(of: downArrow) {
                part[range].foregroundColor = .red
            }

            attributed.append(part)
        }

        return Text(attributed)
            // Default color for non-arrow text
            .foregroundStyle(color)
            .font(.system(size: fontSize, weight: .regular))
            .multilineTextAlignment(.center)
    }
}

// Preview: Market Up Slightly (0.5% - 1.5%)
#Preview("Market Up Slightly") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(
                    symbol: "SPY",
                    name: "SPDR S&P 500 ETF Trust",
                    price: 450.00,
                    previousClose: 446.50
                ),  // +0.78%
                MarketQuote(
                    symbol: "QQQ",
                    name: "Invesco QQQ Trust",
                    price: 380.00,
                    previousClose: 377.50
                ),  // +0.66%
                MarketQuote(
                    symbol: "DIA",
                    name: "SPDR Dow Jones Industrial Average ETF",
                    price: 350.00,
                    previousClose: 347.50
                ),  // +0.72%
            ],
            initialMood: "The market feels upbeat with solid momentum."
        )
    )
    .environmentObject(AppState())
}

// Preview: Market Up A Lot (>1.5%)
#Preview("Market Up A Lot") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(
                    symbol: "SPY",
                    name: "SPDR S&P 500 ETF Trust",
                    price: 460.00,
                    previousClose: 445.00
                ),  // +3.37%
                MarketQuote(
                    symbol: "QQQ",
                    name: "Invesco QQQ Trust",
                    price: 390.00,
                    previousClose: 375.00
                ),  // +4.00%
                MarketQuote(
                    symbol: "DIA",
                    name: "SPDR Dow Jones Industrial Average ETF",
                    price: 360.00,
                    previousClose: 345.00
                ),  // +4.35%
            ],
            initialMood: "The market is euphoric with strong gains."
        )
    )
    .environmentObject(AppState())
}

// Preview: Market Neutral (-0.5% to +0.5%)
#Preview("Market Neutral") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(
                    symbol: "SPY",
                    name: "SPDR S&P 500 ETF Trust",
                    price: 449.00,
                    previousClose: 448.00
                ),  // +0.22%
                MarketQuote(
                    symbol: "QQQ",
                    name: "Invesco QQQ Trust",
                    price: 378.50,
                    previousClose: 379.00
                ),  // -0.13%
                MarketQuote(
                    symbol: "DIA",
                    name: "SPDR Dow Jones Industrial Average ETF",
                    price: 347.00,
                    previousClose: 346.50
                ),  // +0.14%
            ],
            initialMood: "The market is holding steady, waiting for direction."
        )
    )
    .environmentObject(AppState())
}

// Preview: Market Down Slightly (-0.5% to -1.5%)
#Preview("Market Down Slightly") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(
                    symbol: "SPY",
                    name: "SPDR S&P 500 ETF Trust",
                    price: 443.00,
                    previousClose: 446.50
                ),  // -0.78%
                MarketQuote(
                    symbol: "QQQ",
                    name: "Invesco QQQ Trust",
                    price: 374.50,
                    previousClose: 377.50
                ),  // -0.79%
                MarketQuote(
                    symbol: "DIA",
                    name: "SPDR Dow Jones Industrial Average ETF",
                    price: 345.00,
                    previousClose: 347.50
                ),  // -0.72%
            ],
            initialMood: "The market feels cautious after a pullback."
        )
    )
    .environmentObject(AppState())
}

// Preview: Market Down A Lot (<-1.5%)
#Preview("Market Down A Lot") {
    ContentView(
        viewModel: MarketMoodViewModel(
            initialQuotes: [
                MarketQuote(
                    symbol: "SPY",
                    name: "SPDR S&P 500 ETF Trust",
                    price: 435.00,
                    previousClose: 450.00
                ),  // -3.33%
                MarketQuote(
                    symbol: "QQQ",
                    name: "Invesco QQQ Trust",
                    price: 360.00,
                    previousClose: 375.00
                ),  // -4.00%
                MarketQuote(
                    symbol: "DIA",
                    name: "SPDR Dow Jones Industrial Average ETF",
                    price: 335.00,
                    previousClose: 350.00
                ),  // -4.29%
            ],
            initialMood: "The market is stressed with sharp losses."
        )
    )
    .environmentObject(AppState())
}

// Preview: Live Market Data (hardcoded to default market indices)
// This preview fetches live data for SPY, QQQ, and DIA
#Preview("Live: Market") {
    // Create a UserDefaults suite and pre-populate with default market symbols
    let previewDefaults = UserDefaults(suiteName: "preview.market") ?? .standard
    let defaultSymbols = ["SPY", "QQQ", "DIA"]
    
    // Clear any existing values and set fresh
    previewDefaults.removeObject(forKey: "favoriteSymbols")
    previewDefaults.set(defaultSymbols, forKey: "favoriteSymbols")
    previewDefaults.synchronize()
    
    // Create AppState with the pre-populated UserDefaults
    let marketAppState = AppState(userDefaults: previewDefaults)
    
    // Ensure all three symbols are present by adding any that might be missing
    // This handles cases where UserDefaults might not have loaded correctly
    for symbol in defaultSymbols {
        if !marketAppState.favoriteSymbols.contains(symbol) {
            marketAppState.addFavorite(symbol)
        }
    }
    
    // Also remove any symbols that aren't in our default set
    let symbolsToRemove = marketAppState.favoriteSymbols.filter { !defaultSymbols.contains($0) }
    for symbol in symbolsToRemove {
        marketAppState.removeFavorite(symbol)
    }
    
    return ContentView()
        .environmentObject(marketAppState)
}

// Preview: Live Custom Stocks Data (uses locally stored favorites)
// This preview fetches live data for whatever stocks are saved in UserDefaults
#Preview("Live: Custom Stocks") {
    // Use regular AppState which loads from UserDefaults
    // This will use whatever custom stocks the user has saved
    ContentView()
        .environmentObject(AppState())
}
