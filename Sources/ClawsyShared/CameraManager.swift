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
    
    // Keep session + delegate alive until photo is delivered
    private static var activeSessions: [String: (AVCaptureSession, PhotoCaptureDelegate, NSObjectProtocol)] = [:]
    private static let sessionsLock = NSLock()
    // Dedicated serial queue for ALL AVCaptureSession operations (Apple requirement)
    private static let sessionQueue = DispatchQueue(label: "com.clawsy.camera.session", qos: .userInitiated)

    private static func executeCapture(deviceId: String?, completion: @escaping (String?) -> Void) {
        // All AVCaptureSession work MUST happen on a single serial queue — never on
        // DispatchQueue.global (concurrent) or main.  Using a concurrent queue causes
        // cross-thread access on the session's internal state which triggers an
        // EXC_BAD_ACCESS / assertion on modern macOS.
        sessionQueue.async {
            let device: AVCaptureDevice?
            if let deviceId = deviceId, !deviceId.isEmpty {
                device = AVCaptureDevice(uniqueID: deviceId)
            } else {
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
                    // Stop session on the same serial queue to avoid threading issues
                    sessionQueue.async {
                        captureSession.stopRunning()
                        sessionsLock.lock()
                        if let (_, _, observer) = activeSessions[captureId] {
                            NotificationCenter.default.removeObserver(observer)
                        }
                        activeSessions.removeValue(forKey: captureId)
                        sessionsLock.unlock()
                    }
                    completion(data?.base64EncodedString())
                }

                // Observe didStartRunning instead of using a fragile timer delay.
                // The notification fires once the session is fully running and the
                // camera hardware is ready to deliver frames.
                let observer = NotificationCenter.default.addObserver(
                    forName: .AVCaptureSessionDidStartRunning,
                    object: captureSession,
                    queue: nil     // delivered on posting thread
                ) { _ in
                    // Capture on the serial queue to guarantee thread safety
                    sessionQueue.async {
                        guard captureSession.isRunning else { return }
                        let settings: AVCapturePhotoSettings
                        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                        } else {
                            settings = AVCapturePhotoSettings()
                        }
                        photoOutput.capturePhoto(with: settings, delegate: delegate)
                    }
                }

                sessionsLock.lock()
                activeSessions[captureId] = (captureSession, delegate, observer)
                sessionsLock.unlock()

                // startRunning is blocking — that's fine on our dedicated serial queue
                captureSession.startRunning()

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
