import Foundation
import UIKit
import WoosmapGeofencing

extension Notification.Name {
  static let updateRegions = Notification.Name("updateRegions")
  static let didEventPOIRegion = Notification.Name("didEventPOIRegion")
}

/// Listens for Woosmap geofence region events on iOS and forwards them to the
/// customer's back-office via a REST call (replacing the Batch SDK call from
/// the Woosmap Batch connector sample).
@objc(GeofencingEventsReceiver)
class GeofencingEventsReceiver: NSObject {

  // TODO: point these at the customer's back-office.
  private let backOfficeURL = URL(string: "https://api.customer-backoffice.example.com/geofence-events")!
  private let apiKey = "CUSTOMER_API_KEY"

  @objc public func startReceivingEvent() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(POIRegionReceivedNotification),
      name: .didEventPOIRegion,
      object: nil)
  }

  @objc func POIRegionReceivedNotification(notification: Notification) {
    guard let region = notification.userInfo?["Region"] as? Region else { return }

    // Event name convention matches the Woosmap connectors.
    let eventName = region.didEnter
      ? "woos_geofence_entered_event"
      : "woos_geofence_exited_event"

    // Base payload — always present.
    var payload: [String: Any] = [
      "date": ISO8601DateFormatter().string(from: region.date),
      "eventName": eventName,
      "id": region.identifier,
      "latitude": region.latitude,
      "longitude": region.longitude,
      "radius": region.radius,
      "didEnter": region.didEnter,
      "origin": region.origin
    ]

    // Enrich with POI attributes when the region originates from a POI.
    if region.origin == "POI",
       let poi = POIs.getPOIbyIdStore(idstore: region.identifier) as POI? {
      payload["idStore"]     = poi.idstore ?? ""
      payload["name"]        = poi.name ?? ""
      payload["city"]        = poi.city ?? ""
      payload["zipCode"]     = poi.zipCode ?? ""
      payload["distance"]    = poi.distance
      payload["countryCode"] = poi.countryCode ?? ""
      payload["address"]     = poi.address ?? ""
      payload["tags"]        = poi.tags ?? ""
      payload["types"]       = poi.types ?? ""
    }

    postEvent(payload)
  }

  private func postEvent(_ payload: [String: Any]) {
    // Keep the app alive long enough to finish the request when the event is
    // triggered while the app is in the background.
    var bgTask: UIBackgroundTaskIdentifier = .invalid
    bgTask = UIApplication.shared.beginBackgroundTask(withName: "WoosGeofenceEvent") {
      UIApplication.shared.endBackgroundTask(bgTask)
      bgTask = .invalid
    }

    var request = URLRequest(url: backOfficeURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
    } catch {
      NSLog("Woos: failed to serialize payload: \(error)")
      UIApplication.shared.endBackgroundTask(bgTask)
      return
    }

    let task = URLSession.shared.dataTask(with: request) { _, response, error in
      if let error = error {
        NSLog("Woos: back-office POST error: \(error.localizedDescription)")
      } else if let http = response as? HTTPURLResponse {
        NSLog("Woos: back-office responded \(http.statusCode)")
      }
      if bgTask != .invalid {
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
      }
    }
    task.resume()
  }

  @objc public func stopReceivingEvent() {
    NotificationCenter.default.removeObserver(self, name: .didEventPOIRegion, object: nil)
  }
}
