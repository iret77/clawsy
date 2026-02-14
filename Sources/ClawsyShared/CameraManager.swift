import Foundation
import AVFoundation
import AppKit

class CameraManager: NSObject {
    
    static func listCameras() -> [[String: Any]] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
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
    
    static func takePhoto(deviceId: String?, completion: @escaping (String?) -> Void) {
        let device: AVCaptureDevice?
        
        if let deviceId = deviceId {
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
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                completion(nil)
                return
            }
            
            let photoOutput = AVCapturePhotoOutput()
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            } else {
                completion(nil)
                return
            }
            
            let delegate = PhotoCaptureDelegate { data in
                captureSession.stopRunning()
                completion(data?.base64EncodedString())
            }
            
            captureSession.startRunning()
            
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: delegate)
            
            // Keep delegate alive
            objc_setAssociatedObject(photoOutput, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
        } catch {
            print("Camera Error: \(error)")
            completion(nil)
        }
    }
}

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void
    
    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            completion(nil)
            return
        }
        
        completion(photo.fileDataRepresentation())
    }
}
