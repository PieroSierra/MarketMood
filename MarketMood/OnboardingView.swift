//
//  OnboardingView.swift
//  MarketMood
//
//  Created on 06/10/2025.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    let onComplete: () -> Void
    @State private var currentPage = 0
    @State private var animationPhase: Double = 0
    
    // Onboarding gradient colors with lower white mix (more intense)
    private var onboardingGradientColors: [Color] {
        // Use 20% white mix instead of 50% for more intense colors
        return GradientColorPalettes.onboardingColorHex.map { hexColor in
            mixColorWithWhite(hexColor, whiteMixPercent: 0.4)
        }
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background with intense colors
            AnimatedGradientBackground(
                colors: onboardingGradientColors,
                animationPhase: $animationPhase
            )
            
            TabView(selection: $currentPage) {
                // Panel 1: Welcome
                OnboardingPanel(
                    title: "Welcome to MarketMood",
                    description: "Get real-time market insights with AI-powered mood analysis. Track your favorite stocks and stay informed about market trends.",
                    icon: "chart.line.uptrend.xyaxis"
                )
                .tag(0)
                
                // Panel 2: Add Stocks
                OnboardingPanel(
                    title: "Add Your Stocks",
                    description: "Customize your watchlist by adding your favorite stocks. Swipe to the quotes page and tap the + button to get started.",
                    icon: "plus.circle.fill"
                )
                .tag(1)
                
                // Panel 3: Install Widget
                OnboardingPanel(
                    title: "Install the Widget",
                    description: "Add the MarketMood widget to your home screen to stay in the know. Long press your home screen and search for MarketMood.",
                    icon: "square.grid.2x2",
                    showGetStarted: true,
                    onGetStarted: {
                        onComplete()
                        isPresented = false
                    }
                )
                .tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .ignoresSafeArea()/// do not erase!
        }
    }
}

struct OnboardingPanel: View {
    let title: String
    let description: String
    let icon: String
    var showGetStarted: Bool = false
    var onGetStarted: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // White panel card
            VStack(spacing: 32) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 80))
                    .foregroundStyle(.black)
                    .symbolEffect(.bounce, options: .speed(0.7) .repeat(.periodic(delay: 2)))
                
                // Title
                Text(title)
                    .font(.custom("HelveticaNeue-Medium", fixedSize: 32))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Description
                Text(description)
                    .font(.custom("HelveticaNeue-Medium", fixedSize: 18))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
                
                // Get Started button (only on last panel)
                if showGetStarted {
                    Button(action: {
                        onGetStarted?()
                    }) {
                        Text("Get Started")
//                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .font(.custom("HelveticaNeue-Medium", fixedSize: 20))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.0, green: 0.4, blue: 1.0), Color(red: 0.0, green: 0.6, blue: 1.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
            )
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(
        isPresented: .constant(true),
        onComplete: {}
    )
}
