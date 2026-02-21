import Foundation

public struct ClawsyEnvelopeBuilder {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Builds a standardized `clawsy_envelope` payload, optionally enriching it with telemetry
    /// and persists the latest JSON string to the shared defaults for later introspection.
    @discardableResult
    public static func build(type: String,
                             content: Any,
                             metadata: [String: Any] = [:],
                             includeTelemetry: Bool = false) -> String? {
        var envelopeData: [String: Any] = [
            "version": SharedConfig.shortVersion,
            "type": type,
            "localTime": isoFormatter.string(from: Date()),
            "tz": TimeZone.current.identifier,
            "content": content
        ]
        
        metadata.forEach { envelopeData[$0.key] = $0.value }
        
        if includeTelemetry {
            envelopeData["telemetry"] = NetworkManager.getTelemetry()
        }
        
        let envelope: [String: Any] = ["clawsy_envelope": envelopeData]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        SharedConfig.lastEnvelopeJSON = jsonString
        return jsonString
    }
    
    /// Returns the last stored envelope content (without the root wrapper) for UI/debug purposes.
    public static func latestEnvelope() -> [String: Any]? {
        guard let data = SharedConfig.lastEnvelopeJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelope = json["clawsy_envelope"] as? [String: Any] else {
            return nil
        }
        return envelope
    }
}
