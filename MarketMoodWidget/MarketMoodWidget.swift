import WidgetKit
import SwiftUI
import AppIntents
import os

// MARK: - Shared Keys/Group
private let cachedMoodKey = "MarketMood.cachedMoodText"
private let cachedMoodDateKey = "MarketMood.cachedMoodDateISO8601"
private let cachedMarketStateKey = "MarketMood.cachedMarketState" // "good", "bad", or "neutral"
// Must match the App Group enabled for both App and Widget targets
private let appGroupId = "group.com.pieroco.MarketMood"
private let refreshingUntilKey = "MarketMood.refreshingUntilISO8601"

// Market state colors (matching ContentView)
private let goodColorHex = [0x51db51, 0x4169E1, 0xFFD700, 0x7FFFD4]
private let badColorHex = [0xfc5858, 0x9932CC, 0xFF8C00, 0xFF00FF]
private let neutralColorHex = [0x0000FF, 0x00FFFF, 0x008080, 0x00FFFF]

// Helper to convert hex to Color
private extension Color {
    init(hex: Int) {
        let red = Double((hex & 0xff0000) >> 16) / 255.0
        let green = Double((hex & 0xff00) >> 8) / 255.0
        let blue = Double((hex & 0xff) >> 0) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}

// Helper to mix color with white (50/50 blend)
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

// MARK: - AppIntent: Refresh
struct RefreshMarketMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Market Mood"
    static var description = IntentDescription("Refreshes the Market Mood widget")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Mark a short-lived refreshing phase in App Group defaults
        let until = Date().addingTimeInterval(1.5) // make phase noticeable
        let formatter = ISO8601DateFormatter()
        if let groupDefaults = UserDefaults(suiteName: appGroupId) {
            groupDefaults.set(formatter.string(from: until), forKey: refreshingUntilKey)
            groupDefaults.set(formatter.string(from: Date()), forKey: "MarketMood.lastRefreshTappedISO8601")
            // Signal the app to perform a full refresh when it opens
            groupDefaults.set(formatter.string(from: Date()), forKey: "MarketMood.refreshRequestedISO8601")
        }
        os.Logger(subsystem: "MarketMoodWidget", category: "Intent").info("RefreshMarketMoodIntent tapped; refreshing until \(until, privacy: .public)")
        // Trigger a reload of timelines so the widget reflects the refreshing phase
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Entry
struct MarketMoodEntry: TimelineEntry {
    let date: Date
    let moodText: String?
    let moodDate: Date?
    let isRefreshing: Bool
    let marketState: String? // "good", "bad", or "neutral"
}

// MARK: - Provider
struct MarketMoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> MarketMoodEntry {
        MarketMoodEntry(date: Date(), moodText: "Thinking...", moodDate: nil, isRefreshing: true, marketState: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MarketMoodEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MarketMoodEntry>) -> Void) {
        let now = Date()
        let entry = loadEntry()
        var entries: [MarketMoodEntry] = [entry]
        
        // If we are in the refreshing phase, schedule an immediate follow-up entry when it ends
        if let groupDefaults = UserDefaults(suiteName: appGroupId),
           let iso = groupDefaults.string(forKey: refreshingUntilKey) {
            let formatter = ISO8601DateFormatter()
            if let until = formatter.date(from: iso), until > now {
                // Add an entry that ends the refreshing phase
                let endEntry = MarketMoodEntry(
                    date: until,
                    moodText: entry.moodText,
                    moodDate: entry.moodDate,
                    isRefreshing: false,
                    marketState: entry.marketState
                )
                entries.append(endEntry)
            }
        }
        
        // Refresh once a day after last entry
        let lastDate = entries.last?.date ?? now
        let nextDaily = Calendar.current.date(byAdding: .day, value: 1, to: lastDate) ?? lastDate.addingTimeInterval(86400)
        completion(Timeline(entries: entries, policy: .after(nextDaily)))
    }

    private func loadEntry() -> MarketMoodEntry {
        var mood: String?
        var moodDate: Date?
        var marketState: String?
        let formatter = ISO8601DateFormatter()
        let now = Date()
        var isRefreshing = false
        // Prefer App Group defaults, fallback to standard
        if let groupDefaults = UserDefaults(suiteName: appGroupId) {
            mood = groupDefaults.string(forKey: cachedMoodKey)
            if let iso = groupDefaults.string(forKey: cachedMoodDateKey) {
                moodDate = formatter.date(from: iso)
            }
            marketState = groupDefaults.string(forKey: cachedMarketStateKey)
            if let refreshingISO = groupDefaults.string(forKey: refreshingUntilKey),
               let until = formatter.date(from: refreshingISO) {
                isRefreshing = until > now
            }
        }
        if mood == nil {
            let std = UserDefaults.standard
            mood = std.string(forKey: cachedMoodKey)
            if let iso = std.string(forKey: cachedMoodDateKey) {
                moodDate = formatter.date(from: iso)
            }
            if marketState == nil {
                marketState = std.string(forKey: cachedMarketStateKey)
            }
        }
        return MarketMoodEntry(date: Date(), moodText: mood, moodDate: moodDate, isRefreshing: isRefreshing, marketState: marketState)
    }
}

// MARK: - View
struct MarketMoodWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: MarketMoodEntry

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
            
            if let range = part.range(of: upArrow) {
                part[range].foregroundColor = .green
            }
            if let range = part.range(of: downArrow) {
                part[range].foregroundColor = .red
            }
            
            attributed.append(part)
        }
        
        return Text(attributed)
            .foregroundStyle(color) // default color for non-arrow text
            .font(.system(size: fontSize, weight: .regular))
            .multilineTextAlignment(.center)
    }

    private var fontSizes: (mood: CGFloat, date: Font) {
        switch family {
        case .systemSmall:
            return (mood: 14, date: .caption2)
        case .systemMedium:
            return (mood: 18, date: .caption2)
        default:
            // Large uses same as app
            return (mood: 25, date: .caption2)
        }
    }

    // Generate deterministic random positions from mood text hash
    private func generateGradientCenters(from moodText: String) -> [CGPoint] {
        // Use mood text hash as seed for deterministic randomness
        var hasher = Hasher()
        hasher.combine(moodText)
        let seed = hasher.finalize()
        var generator = SeededRandomNumberGenerator(seed: UInt64(abs(Int64(seed))))
        
        return (0..<4).map { _ in
            CGPoint(
                x: Double.random(in: 0.1...0.9, using: &generator),
                y: Double.random(in: 0.1...0.9, using: &generator)
            )
        }
    }
    
    // Simple seeded random number generator for deterministic randomness
    private struct SeededRandomNumberGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) {
            state = seed
        }
        mutating func next() -> UInt64 {
            state = state &* 1103515245 &+ 12345
            return state
        }
    }
    
    // Static gradient background matching the app
    private func staticGradientBackground(geometry: GeometryProxy) -> some View {
        let marketState = entry.marketState ?? "neutral"
        let moodText = entry.moodText ?? ""
        
        // Select colors based on market state
        let colorHexes: [Int]
        switch marketState {
        case "good":
            colorHexes = goodColorHex
        case "bad":
            colorHexes = badColorHex
        default:
            colorHexes = neutralColorHex
        }
        
        // Convert to colors (half-mixed with white like in app for consistency)
        let colors = colorHexes.map { halfMixWithWhite($0) }
        
        // Generate deterministic positions from mood text
        let centers = generateGradientCenters(from: moodText)
        let screenSize = max(geometry.size.width, geometry.size.height)
        let baseCircleSize = screenSize * 0.9
        
        // Use static radius and opacity (no animation)
        let radius = baseCircleSize * 0.45 // Average of min/max from app
        let opacity = 0.4 // Average of min/max from app
        
        return ZStack {
            ForEach(0..<4, id: \.self) { index in
                if index < centers.count && index < colors.count {
                    let center = centers[index]
                    let color = colors[index]
                    
                    let centerX = center.x * geometry.size.width
                    let centerY = center.y * geometry.size.height
                    
                    RadialGradient(
                        gradient: Gradient(colors: [
                            color.opacity(opacity),
                            color.opacity(opacity * 0.6),
                            color.opacity(opacity * 0.3),
                            Color.clear,
                        ]),
                        center: UnitPoint(x: 0.5, y: 0.5),
                        startRadius: 0,
                        endRadius: radius
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: centerX, y: centerY)
                }
            }
        }
        .blur(radius: 30)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Static gradient background
                staticGradientBackground(geometry: geometry)

                // Main content
                VStack {
                    Spacer()
                    if let mood = entry.moodText {
                        coloredMoodText(mood, fontSize: fontSizes.mood, color: .primary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 0)
                            .padding(.vertical, 0)
                    } else {
                        Text("Thinking...")
                            .font(.system(size: fontSizes.mood, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 0)
                    }
                    Spacer()
                }
            }
            // Date overlay (center-bottom)
            .overlay(alignment: .bottom) {
                if (family != .systemSmall) {
                    if entry.isRefreshing {
                        Text("Thinking...")
                            .font(fontSizes.date)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 0)
                    } else if let d = entry.moodDate {
                        Text(d.formatted(.dateTime.month(.wide).day().year()))
                            .font(fontSizes.date)
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 0)
                    } else {
                        Text("Thinking...")
                            .font(fontSizes.date)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 0)
                    }
                }
            }
            // Refresh button overlay (top-right) that doesn't affect layout
            .overlay(alignment: .topTrailing) {
                if let url = URL(string: "marketmood://refresh") {
                    Link(destination: url) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(0)
                }
            }
            // Tapping the tile opens the app
            .widgetURL(URL(string: "marketmood://open"))
        }
        .containerBackground(Color.white.opacity(0.5), for: .widget)
    }
}

// MARK: - Widget
@main
struct MarketMoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MarketMoodWidget", provider: MarketMoodProvider()) { entry in
            MarketMoodWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Market Mood")
        .description("Shows the latest market mood and date.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews
#if DEBUG
#Preview("Small", as: .systemSmall) {
    MarketMoodWidget()
} timeline: {
    MarketMoodEntry(date: .now, moodText: "Market feels upbeat with Nvidia up (▲3.15%) with solid momentum. What a time to be alive.", moodDate: .now, isRefreshing: false, marketState: "bad")
}

#Preview("Medium", as: .systemMedium) {
    MarketMoodWidget()
} timeline: {
    MarketMoodEntry(date: .now, moodText: "Market feels upbeat with Nvidia up (▲3.15%) with solid momentum. What a time to be alive.", moodDate: .now, isRefreshing: false, marketState: "good")
}

#Preview("Large", as: .systemLarge) {
    MarketMoodWidget()
} timeline: {
    MarketMoodEntry(date: .now, moodText: "Market feels upbeat with Nvidia up (▲3.15%) with solid momentum! What a time to be alive.", moodDate: .now, isRefreshing: false, marketState: "neutral")
}
#endif

