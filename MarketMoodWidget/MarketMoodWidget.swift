import WidgetKit
import SwiftUI
import AppIntents
import os

// MARK: - Shared Keys/Group
private let cachedMoodKey = "MarketMood.cachedMoodText"
private let cachedMoodDateKey = "MarketMood.cachedMoodDateISO8601"
// Must match the App Group enabled for both App and Widget targets
private let appGroupId = "group.com.pieroco.MarketMood"
private let refreshingUntilKey = "MarketMood.refreshingUntilISO8601"

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
}

// MARK: - Provider
struct MarketMoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> MarketMoodEntry {
        MarketMoodEntry(date: Date(), moodText: "Thinking...", moodDate: nil, isRefreshing: true)
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
                    isRefreshing: false
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
        let formatter = ISO8601DateFormatter()
        let now = Date()
        var isRefreshing = false
        // Prefer App Group defaults, fallback to standard
        if let groupDefaults = UserDefaults(suiteName: appGroupId) {
            mood = groupDefaults.string(forKey: cachedMoodKey)
            if let iso = groupDefaults.string(forKey: cachedMoodDateKey) {
                moodDate = formatter.date(from: iso)
            }
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
        }
        return MarketMoodEntry(date: Date(), moodText: mood, moodDate: moodDate, isRefreshing: isRefreshing)
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

    var body: some View {
        ZStack {
            // Background
            Color.clear

            // Main content
            VStack {
                Spacer()
                if let mood = entry.moodText {
                    coloredMoodText(mood, fontSize: fontSizes.mood, color: .primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 0)
                        .padding(.vertical, 0)
                    if entry.isRefreshing {
                        Text("\nThinking...")
                            .font(fontSizes.date)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let d = entry.moodDate {
                        Text("\n\(d.formatted(.dateTime.month(.wide).day().year()))")
                            .font(fontSizes.date)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("\nThinking...")
                            .font(fontSizes.date)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
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
        // Refresh button overlay (top-right) that doesn't affect layout
        .overlay(alignment: .topTrailing) {
            if let url = URL(string: "marketmood://refresh") {
                Link(destination: url) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(0)
            }
        }
        // Tapping the tile opens the app
        .widgetURL(URL(string: "marketmood://open"))
        .containerBackground(.fill.tertiary, for: .widget)
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
    MarketMoodEntry(date: .now, moodText: "Market feels upbeat with Nvidia up (▲3.15%) with solid momentum. What a time to be alive.", moodDate: .now, isRefreshing: false)
}

#Preview("Medium", as: .systemMedium) {
    MarketMoodWidget()
} timeline: {
    MarketMoodEntry(date: .now, moodText: "Market feels upbeat with Nvidia up (▲3.15%) with solid momentum. What a time to be alive.", moodDate: .now, isRefreshing: false)
}

#Preview("Large", as: .systemLarge) {
    MarketMoodWidget()
} timeline: {
    MarketMoodEntry(date: .now, moodText: "Market feels upbeat with Nvidia up (▲3.15%) with solid momentum! What a time to be alive.", moodDate: .now, isRefreshing: false)
}
#endif

