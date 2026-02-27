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
    
    private static func executeCapture(deviceId: String?, completion: @escaping (String?) -> Void) {
        // AVCaptureSession.startRunning() MUST NOT run on the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let device: AVCaptureDevice?
            if let deviceId = deviceId, !deviceId.isEmpty {
                device = AVCaptureDevice(uniqueID: deviceId)
            } else {
                device = AVCaptureDevice.default(for: .video)
            }

            guard let captureDevice = device else {
                completion(nil)
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: captureDevice)
                let captureSession = AVCaptureSession()
                captureSession.sessionPreset = .photo

                guard captureSession.canAddInput(input) else { completion(nil); return }
                captureSession.addInput(input)

                let photoOutput = AVCapturePhotoOutput()
                guard captureSession.canAddOutput(photoOutput) else { completion(nil); return }
                captureSession.addOutput(photoOutput)

                let delegate = PhotoCaptureDelegate { data in
                    captureSession.stopRunning()
                    completion(data?.base64EncodedString())
                }

                // Keep session + delegate alive until photo is delivered
                objc_setAssociatedObject(photoOutput, "session",  captureSession, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                objc_setAssociatedObject(photoOutput, "delegate", delegate,       .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

                captureSession.startRunning()

                // Give the camera hardware a moment to warm up, then snap
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
                    let settings = AVCapturePhotoSettings()
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
