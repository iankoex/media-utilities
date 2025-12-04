//
//  CameraService+Permissions.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import Foundation

// MARK: - Permission Handling

@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Check camera authorization status (from provided code with print integration)
    func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                print("Camera access authorized.")
                return true
            case .notDetermined:
                print("Camera access not determined.")
                sessionQueue.suspend()
                let status = await AVCaptureDevice.requestAccess(for: .video)
                sessionQueue.resume()
                if !status {
                    print("Camera access is required to take photos and videos")
                }
                return status
            case .denied:
                print("Camera access denied.")
                print("Camera access denied. Please enable in Settings")
                return false
            case .restricted:
                print("Camera library access restricted.")
                print("Camera access restricted")
                return false
            @unknown default:
                print("Unknown camera authorization status.")
                return false
        }
    }

    /// Request camera access permission
    @concurrent
    public func requestCameraAccess() async {
        guard authorizationStatus != .authorized else {
            print("Camera access already authorized")
            return
        }

        let authorized = await checkAuthorization()
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        if authorized {
            print("Camera access successfully granted")
        } else {
            print("Camera access denied or restricted")
        }
    }

    /// Check if camera is available and authorized
    @concurrent
    public func checkCameraAvailability() async -> Bool {
        // Update authorization status
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        // Check device availability
        let devicesAvailable = !availableCaptureDevices.isEmpty
        isCameraAvailable = devicesAvailable && authorizationStatus == .authorized

        if !devicesAvailable {
            print("No camera devices available")
        } else if authorizationStatus != .authorized {
            print("Camera access not authorized")
        } else {
            print("Camera is available and authorized")
        }

        return isCameraAvailable
    }

    /// Get current authorization status
    public func getAuthorizationStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("Current camera authorization status: \(authorizationStatus.rawValue)")
    }
}
