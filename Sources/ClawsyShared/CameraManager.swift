import Foundation
import AVFoundation

#if os(macOS)
import AppKit
#endif

public class CameraManager: NSObject {
    
    public static func listCameras() -> [[String: Any]] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        
        return discoverySession.devices.map { device in
            return [
                "id": device.uniqueID,
                "name": device.localizedName,
                "position": positionToString(device.position)
            ]
        }
    }
    
    private static func positionToString(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: return "front"
        case .back: return "back"
        case .unspecified: return "unspecified"
        @unknown default: return "unknown"
        }
    }
    
    public static func takePhoto(deviceId: String?, completion: @escaping (String?) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.executeCapture(deviceId: deviceId, completion: completion)
                } else {
                    completion(nil)
                }
            }
        } else if status == .authorized {
            self.executeCapture(deviceId: deviceId, completion: completion)
        } else {
            completion(nil)
        }
    }
    
    // Stable keys for objc_setAssociatedObject (string literals are NOT stable pointers in Swift)
    private static var activeSessions: [String: (AVCaptureSession, PhotoCaptureDelegate)] = [:]
    private static let sessionsLock = NSLock()

    private static func executeCapture(deviceId: String?, completion: @escaping (String?) -> Void) {
        // AVCaptureSession.startRunning() MUST NOT run on the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let device: AVCaptureDevice?
            if let deviceId = deviceId, !deviceId.isEmpty {
                device = AVCaptureDevice(uniqueID: deviceId)
            } else {
                // Use first discovered camera as fallback (AVCaptureDevice.default(for:) is deprecated
                // and may return nil on macOS 14+ when no built-in camera is active)
                let discovered = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .external],
                    mediaType: .video,
                    position: .unspecified
                ).devices
                device = discovered.first
            }

            guard let captureDevice = device else {
                completion(nil)
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: captureDevice)
                let captureSession = AVCaptureSession()
                // .photo is not supported by all cameras (e.g. external/Continuity) — check first
                if captureSession.canSetSessionPreset(.photo) {
                    captureSession.sessionPreset = .photo
                } else if captureSession.canSetSessionPreset(.high) {
                    captureSession.sessionPreset = .high
                }

                guard captureSession.canAddInput(input) else { completion(nil); return }
                captureSession.addInput(input)

                let photoOutput = AVCapturePhotoOutput()
                guard captureSession.canAddOutput(photoOutput) else { completion(nil); return }
                captureSession.addOutput(photoOutput)

                let captureId = UUID().uuidString
                let delegate = PhotoCaptureDelegate { data in
                    captureSession.stopRunning()
                    sessionsLock.lock()
                    activeSessions.removeValue(forKey: captureId)
                    sessionsLock.unlock()
                    completion(data?.base64EncodedString())
                }

                // Keep session + delegate alive in a stable dictionary until photo is delivered
                sessionsLock.lock()
                activeSessions[captureId] = (captureSession, delegate)
                sessionsLock.unlock()

                captureSession.startRunning()

                // Give the camera hardware a moment to warm up, then snap
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
                    // Always request JPEG explicitly — default AVCapturePhotoSettings() may
                    // pick HEVC or a codec the camera doesn't support → crash
                    let settings: AVCapturePhotoSettings
                    if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                        settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                    } else {
                        settings = AVCapturePhotoSettings()
                    }
                    photoOutput.capturePhoto(with: settings, delegate: delegate)
                }

            } catch {
                print("Camera Error: \(error)")
                completion(nil)
            }
        }
    }
}

public class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void
    
    public init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }
    
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            completion(nil)
            return
        }
        
        completion(photo.fileDataRepresentation())
    }
}
