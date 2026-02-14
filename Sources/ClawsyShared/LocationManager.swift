import Foundation
import CoreLocation
import os.log

#if canImport(UIKit)
import UIKit
#endif

public struct ClawsyLocation: Codable {
    public let latitude: Double
    public let longitude: Double
    public let accuracy: Double
    public let altitude: Double?
    public let speed: Double?
    public let timestamp: TimeInterval
    
    // Reverse Geocoding Fields
    public var name: String?         // e.g. "Marktplatz 1"
    public var locality: String?     // e.g. "Bensheim"
    public var country: String?      // e.g. "Germany"
    public var customName: String?   // e.g. "Büro" (User defined)
    
    public init(location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.accuracy = location.horizontalAccuracy
        self.altitude = location.altitude
        self.speed = location.speed >= 0 ? location.speed : nil
        self.timestamp = location.timestamp.timeIntervalSince1970
    }
}

public class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    private let logger = OSLog(subsystem: "ai.clawsy", category: "Location")
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published public var lastLocation: ClawsyLocation?
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    public var onLocationUpdate: ((ClawsyLocation) -> Void)?
    
    // User defined locations (Context logic)
    private var smartLocations: [String: [Double]] {
        SharedConfig.sharedDefaults.dictionary(forKey: "smartLocations") as? [String: [Double]] ?? [:]
    }
    
    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = 100 // kCLLocationAccuracyBalanced (approx 100m)
        self.authorizationStatus = manager.authorizationStatus
    }
    
    public func requestPermission() {
        #if os(iOS)
        manager.requestAlwaysAuthorization()
        #else
        manager.requestWhenInUseAuthorization()
        #endif
    }
    
    public func startUpdating() {
        manager.startUpdatingLocation()
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        #endif
    }
    
    public func stopUpdating() {
        manager.stopUpdatingLocation()
    }
    
    public func addSmartLocation(name: String, lat: Double, lon: Double) {
        var current = smartLocations
        current[name] = [lat, lon]
        SharedConfig.sharedDefaults.set(current, forKey: "smartLocations")
        SharedConfig.sharedDefaults.synchronize()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        var clawsyLocation = ClawsyLocation(location: location)
        
        // 1. Check Smart Locations (On-Device Context)
        for (name, coords) in smartLocations {
            if coords.count == 2 {
                let smartLoc = CLLocation(latitude: coords[0], longitude: coords[1])
                if location.distance(from: smartLoc) < 100 { // 100m radius
                    clawsyLocation.customName = name
                    break
                }
            }
        }
        
        // 2. Perform Reverse Geocoding (On-Device Privacy)
        geocoder.reverseGeocodeLocation(location) { [weak self] (placemarks, err) in
            if let placemark = placemarks?.first {
                clawsyLocation.name = placemark.name
                clawsyLocation.locality = placemark.locality
                clawsyLocation.country = placemark.country
            }
            
            DispatchQueue.main.async {
                self?.lastLocation = clawsyLocation
                self?.onLocationUpdate?(clawsyLocation)
            }
        }
    }
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError err: Error) {
        os_log("Location error: %{public}@", log: logger, type: .error, err.localizedDescription)
    }
}
