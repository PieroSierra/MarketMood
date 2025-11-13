import Foundation
import CoreMotion
import Combine

@MainActor
final class MotionManager: ObservableObject {
    @Published var gravity: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    
    private let motionManager = CMMotionManager()
    
    init() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            self?.gravity = motion.gravity
        }
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

