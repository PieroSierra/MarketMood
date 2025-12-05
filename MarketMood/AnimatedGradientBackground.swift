//
//  AnimatedGradientBackground.swift
//  MarketMood
//
//  Created on 06/10/2025.
//

import SwiftUI

/// Shared animated gradient background component
/// - Parameters:
///   - colors: Array of 4 colors to use for the gradient zones
///   - animationPhase: Binding to animation phase (for timer updates)
struct AnimatedGradientBackground: View {
    let colors: [Color]
    @Binding var animationPhase: Double
    
    // Gradient animation state
    @State private var gradientCenters: [CGPoint] = []
    @State private var gradientVelocities: [CGPoint] = []
    @State private var pulseSpeeds: [Double] = []
    @State private var pulsePhases: [Double] = []
    @State private var animationTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            let screenSize = max(geometry.size.width, geometry.size.height)
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
                        let centerX = center.x * geometry.size.width
                        let centerY = center.y * geometry.size.height
                        
                        RadialGradient(
                            gradient: Gradient(colors: [
                                color.opacity(currentOpacity),  // Bright at center
                                color.opacity(currentOpacity * 0.6),  // Mid
                                color.opacity(currentOpacity * 0.3),  // Fading
                                Color.clear,  // Transparent at edges
                            ]),
                            center: UnitPoint(x: 0.5, y: 0.5),
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
            .blur(radius: 30)
            .ignoresSafeArea()
        }
        .onAppear {
            initializeGradientCenters()
            
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
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }
    
    // MARK: - Gradient Animation
    
    private func initializeGradientCenters() {
        gradientCenters = (0..<4).map { _ in
            CGPoint(
                x: CGFloat.random(in: 0.1...0.9),
                y: CGFloat.random(in: 0.1...0.9)
            )
        }
        
        // Initialize velocities for smooth motion
        gradientVelocities = (0..<4).map { _ in
            CGPoint(
                x: CGFloat.random(in: -0.00045...0.00045),
                y: CGFloat.random(in: -0.00045...0.00045)
            )
        }
        
        // Initialize individual pulse speeds
        pulseSpeeds = (0..<4).map { _ in
            Double.random(in: 0.0005...0.002)
        }
        
        // Initialize pulse phases
        pulsePhases = (0..<4).map { _ in
            Double.random(in: 0.0...1.0)
        }
    }
    
    private func updateGradientCenters() {
        for i in 0..<gradientCenters.count {
            var center = gradientCenters[i]
            var velocity = gradientVelocities[i]
            
            // Update position
            center.x += velocity.x
            center.y += velocity.y
            
            // Bounce off edges
            if center.x <= 0.05 || center.x >= 0.95 {
                velocity.x *= -1.0
            }
            if center.y <= 0.05 || center.y >= 0.95 {
                velocity.y *= -1.0
            }
            
            // Keep within bounds
            center.x = max(0.05, min(0.95, center.x))
            center.y = max(0.05, min(0.95, center.y))
            
            // Occasionally change direction
            if Int.random(in: 1...300) == 1 {
                velocity.x += CGFloat.random(in: -0.0003...0.0003)
                velocity.y += CGFloat.random(in: -0.0003...0.0003)
                
                // Limit max velocity
                velocity.x = max(-0.00075, min(0.00075, velocity.x))
                velocity.y = max(-0.00075, min(0.00075, velocity.y))
            }
            
            // Update individual pulse phase
            pulsePhases[i] += pulseSpeeds[i]
            if pulsePhases[i] >= 1.0 {
                pulsePhases[i] = 0.0
            }
            
            gradientCenters[i] = center
            gradientVelocities[i] = velocity
        }
    }
}

// MARK: - Color Helpers

/// Mix a hex color with white by a specified percentage
/// - Parameters:
///   - hexColor: The hex color value (e.g., 0xFF0000 for red)
///   - whiteMixPercent: Percentage of white to mix (0.0 = no white, 1.0 = all white)
func mixColorWithWhite(_ hexColor: Int, whiteMixPercent: Double) -> Color {
    let r = ((hexColor & 0xff0000) >> 16)
    let g = ((hexColor & 0xff00) >> 8)
    let b = (hexColor & 0xff)
    
    // Mix with white based on percentage
    let mixedR = Int(Double(r) * (1.0 - whiteMixPercent) + 255.0 * whiteMixPercent)
    let mixedG = Int(Double(g) * (1.0 - whiteMixPercent) + 255.0 * whiteMixPercent)
    let mixedB = Int(Double(b) * (1.0 - whiteMixPercent) + 255.0 * whiteMixPercent)
    
    return Color(hex: (mixedR << 16) | (mixedG << 8) | mixedB)
}

// MARK: - Gradient Color Palettes

/// Color palettes for different market states
struct GradientColorPalettes {
    // Good market colors: green, blue, yellow, aquamarine
    static let goodColorHex = [0x51db51, 0x4169E1, 0xFFD700, 0x7FFFD4]
    
    // Bad market colors: red, purple, orange, fuchsia
    static let badColorHex = [0xfc5858, 0x9932CC, 0xFF8C00, 0xFF00FF]
    
    // Neutral market colors: blue, cyan, teal, aqua
    static let neutralColorHex = [0x0000FF, 0x00FFFF, 0x008080, 0x00FFFF]
    
    // Aggressive onboarding colors: blue, green, red
    static let onboardingColorHex = [0x0000FF, 0x00FFFF, 0x008080, 0x00FFFF]
    ///[0x0066FF, 0x00FF33, 0xFF0033, 0xFF6600]
}

