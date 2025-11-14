//
//  AppState.swift
//  MarketMood
//
//  Created on 31/10/2025.
//

import Foundation
import Combine

/// Manages the app's persistent state, including the user's favorite stock symbols.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var favoriteSymbols: [String]
    
    private let userDefaults: UserDefaults
    private let favoritesKey = "favoriteSymbols"
    
    /// Default symbols if none are stored
    private let defaultSymbols = ["SPY", "QQQ", "DIA"]
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        // Load saved favorites or use defaults
        if let saved = userDefaults.stringArray(forKey: favoritesKey), !saved.isEmpty {
            // Normalize and deduplicate symbols (case-insensitive)
            var seen = Set<String>()
            self.favoriteSymbols = saved.compactMap { symbol in
                let normalized = symbol.uppercased().trimmingCharacters(in: .whitespaces)
                guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
                seen.insert(normalized)
                return normalized
            }
            
            // Save deduplicated list back if it changed
            if self.favoriteSymbols.count != saved.count {
                saveFavorites()
            }
        } else {
            self.favoriteSymbols = defaultSymbols
            // Save defaults so they persist
            userDefaults.set(defaultSymbols, forKey: favoritesKey)
        }
    }
    
    /// Add a symbol to favorites if not already present
    func addFavorite(_ symbol: String) {
        let normalizedSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalizedSymbol.isEmpty, !favoriteSymbols.contains(normalizedSymbol) else {
            return
        }
        favoriteSymbols.append(normalizedSymbol)
        saveFavorites()
    }
    
    /// Remove a symbol from favorites
    func removeFavorite(_ symbol: String) {
        let normalizedSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        favoriteSymbols.removeAll { $0 == normalizedSymbol }
        saveFavorites()
    }
    
    private func saveFavorites() {
        userDefaults.set(favoriteSymbols, forKey: favoritesKey)
    }
}

