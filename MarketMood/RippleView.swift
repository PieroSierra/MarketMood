import SwiftUI
import MetalKit

/// A modifier that applies a ripple effect to its content.
struct RippleModifier: ViewModifier {
    var origin: CGPoint
    
    var elapsedTime: TimeInterval
    
    var duration: TimeInterval
    
    var amplitude: Double
    var frequency: Double
    var decay: Double
    var speed: Double
    
    func body(content: Content) -> some View {
        let shader = ShaderLibrary.Ripple(
            .float2(origin),
            .float(elapsedTime),
            
            // Parameters
            .float(amplitude),
            .float(frequency),
            .float(decay),
            .float(speed)
        )
        
        let maxSampleOffset = maxSampleOffset
        let elapsedTime = elapsedTime
        let duration = duration
        
        content.visualEffect { view, _ in
            view.layerEffect(
                shader,
                maxSampleOffset: maxSampleOffset,
                isEnabled: 0 < elapsedTime && elapsedTime < duration
            )
        }
    }
    
    var maxSampleOffset: CGSize {
        CGSize(width: amplitude, height: amplitude)
    }
}

struct RippleEffect<T: Equatable>: ViewModifier {
    
    private struct ActiveRipple: Identifiable {
        let id = UUID()
        let origin: CGPoint
        let startDate: Date
    }
    
    var origin: CGPoint
    var trigger: T
    var amplitude: Double
    var frequency: Double
    var decay: Double
    var speed: Double
    
    @State private var activeRipples: [ActiveRipple] = []
    
    init(at origin: CGPoint, trigger: T, amplitude: Double = 12, frequency: Double = 15, decay: Double = 8, speed: Double = 1200) {
        self.origin = origin
        self.trigger = trigger
        self.amplitude = amplitude
        self.frequency = frequency
        self.decay = decay
        self.speed = speed
    }
    
    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            
            let validRipples = activeRipples.filter { ripple in
                now.timeIntervalSince(ripple.startDate) < duration
            }
            
            let base = AnyView(content)
            let rippleView = validRipples.reduce(base) { partialView, ripple in
                let elapsedTime = now.timeIntervalSince(ripple.startDate)
                
                return AnyView(
                    partialView.modifier(
                        RippleModifier(
                            origin: ripple.origin,
                            elapsedTime: elapsedTime,
                            duration: duration,
                            amplitude: amplitude,
                            frequency: frequency,
                            decay: decay,
                            speed: speed
                        )
                    )
                )
            }
            
            rippleView
        }
        .onChange(of: trigger) { _, _ in
            let now = Date()
            activeRipples = activeRipples.filter { ripple in
                now.timeIntervalSince(ripple.startDate) < duration
            }
            let newRipple = ActiveRipple(origin: origin, startDate: Date())
            activeRipples.append(newRipple)
        }
    }
    
    var duration: TimeInterval { 3 }
}
