import Contacts
import CoreBluetooth
import CoreLocation
import EventKit
import Foundation
import UIKit

/// Calendars, reminders, contacts, location, Bluetooth accessories and files —
/// each behind the user's permission prompt.
@MainActor
final class PersonalDataTools: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate {
    private let events = EKEventStore()
    private let contacts = CNContactStore()
    private let location = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var central: CBCentralManager?
    private var discovered: [String: Int] = [:]
    private var bluetoothReady: CheckedContinuation<Void, Never>?

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    // MARK: Calendar

    func calendar(action: String, title: String, start: String, minutes: Int) async -> (Bool, String) {
        guard (try? await events.requestFullAccessToEvents()) == true else { return (false, "Calendar access was denied.") }
        if action == "create" {
            guard let date = Self.parseDate(start) else { return (false, "I need a valid start time.") }
            let event = EKEvent(eventStore: events)
            event.title = title.isEmpty ? "Jarvis" : title
            event.startDate = date
            event.endDate = date.addingTimeInterval(TimeInterval(max(15, minutes) * 60))
            event.calendar = events.defaultCalendarForNewEvents
            do {
                try events.save(event, span: .thisEvent)
                return (true, "Created “\(event.title ?? "")” at \(start).")
            } catch {
                return (false, error.localizedDescription)
            }
        }
        let now = Date()
        let predicate = events.predicateForEvents(withStart: now, end: now.addingTimeInterval(7 * 86_400), calendars: nil)
        let upcoming = events.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(10)
        if upcoming.isEmpty { return (true, "No events in the next seven days.") }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM HH:mm"
        return (true, upcoming.map { "\(f.string(from: $0.startDate)) — \($0.title ?? "")" }.joined(separator: "\n"))
    }

    // MARK: Reminders

    func reminders(action: String, title: String, due: String) async -> (Bool, String) {
        guard (try? await events.requestFullAccessToReminders()) == true else { return (false, "Reminders access was denied.") }
        if action == "add" {
            let r = EKReminder(eventStore: events)
            r.title = title.isEmpty ? "Jarvis reminder" : title
            r.calendar = events.defaultCalendarForNewReminders()
            if let d = Self.parseDate(due) {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
                r.addAlarm(EKAlarm(absoluteDate: d))
            }
            do {
                try events.save(r, commit: true)
                return (true, "Added reminder “\(r.title ?? "")”.")
            } catch {
                return (false, error.localizedDescription)
            }
        }
        let predicate = events.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let titles: [String] = await withCheckedContinuation { c in
            events.fetchReminders(matching: predicate) { list in
                c.resume(returning: (list ?? []).prefix(15).compactMap { $0.title })
            }
        }
        return (true, titles.isEmpty ? "No open reminders." : titles.joined(separator: "\n"))
    }

    // MARK: Contacts

    struct ContactMatch {
        var name: String
        var phones: [String]
        var emails: [String]
    }

    func lookupContact(_ name: String) async -> [ContactMatch] {
        let granted = (try? await contacts.requestAccess(for: .contacts)) ?? false
        guard granted else { return [] }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let found = (try? contacts.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return found.prefix(5).map { c in
            ContactMatch(name: [c.familyName, c.givenName].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces),
                         phones: c.phoneNumbers.map { $0.value.stringValue },
                         emails: c.emailAddresses.map { String($0.value) })
        }
    }

    // MARK: Calls & messages

    func call(_ contact: String) async -> (Bool, String) {
        var number = contact.filter { $0.isNumber || $0 == "+" }
        if number.count < 3 {
            guard let match = await lookupContact(contact).first, let phone = match.phones.first else {
                return (false, "I couldn't find a phone number for \(contact).")
            }
            number = phone.filter { $0.isNumber || $0 == "+" }
        }
        guard let url = URL(string: "tel:\(number)") else { return (false, "Invalid number.") }
        let ok = await UIApplication.shared.open(url)
        return (ok, ok ? number : "This device cannot place calls.")
    }

    func message(_ contact: String?, body: String?) async -> (Bool, String) {
        var number = ""
        if let contact {
            number = contact.filter { $0.isNumber || $0 == "+" }
            if number.count < 3, let phone = await lookupContact(contact).first?.phones.first {
                number = phone.filter { $0.isNumber || $0 == "+" }
            }
        }
        let text = (body ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "sms:\(number)&body=\(text)") else { return (false, "Invalid message.") }
        let ok = await UIApplication.shared.open(url)
        return (ok, ok ? "Opened Messages" : "Messages is unavailable.")
    }

    // MARK: Location

    func currentLocation() async -> CLLocation? {
        location.delegate = self
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        return await withCheckedContinuation { c in
            locationContinuation = c
            location.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            self.locationContinuation?.resume(returning: last)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }

    // MARK: Bluetooth accessories

    func scanBluetooth(seconds: Double = 4) async -> [String] {
        discovered.removeAll()
        if central == nil {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                bluetoothReady = c
                central = CBCentralManager(delegate: self, queue: .main)
            }
        }
        guard central?.state == .poweredOn else { return [] }
        central?.scanForPeripherals(withServices: nil, options: nil)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        central?.stopScan()
        return discovered.sorted { $0.value > $1.value }.map(\.key)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothReady?.resume()
            self.bluetoothReady = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        guard let name, !name.isEmpty else { return }
        let rssi = RSSI.intValue
        Task { @MainActor in self.discovered[name] = max(self.discovered[name] ?? -200, rssi) }
    }

    // MARK: Files (Documents/Jarvis/Files — visible in the Files app)

    static var filesDirectory: URL { JarvisPaths.ensure(JarvisPaths.root.appendingPathComponent("Files")) }

    func files(action: String, filename: String, content: String, runID: String?) -> (Bool, String) {
        let safe = filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
        switch action {
        case "write":
            guard !safe.isEmpty else { return (false, "A file name is required.") }
            guard let data = content.data(using: .utf8) else { return (false, "Invalid text.") }
            let url = Self.filesDirectory.appendingPathComponent(safe)
            do {
                try data.write(to: url, options: .atomic)
                RecordKeeper.shared.registerArtifact(at: url, runID: runID, description: "Text file written by Jarvis")
                return (true, "Saved \(safe) (\(data.count) bytes).")
            } catch {
                return (false, error.localizedDescription)
            }
        case "read":
            let url = Self.filesDirectory.appendingPathComponent(safe)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return (false, "Couldn't read \(safe).") }
            return (true, String(text.prefix(3000)))
        default:
            let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.filesDirectory.path)) ?? []
            return (true, names.isEmpty ? "The Jarvis Files folder is empty." : names.sorted().joined(separator: "\n"))
        }
    }
}
