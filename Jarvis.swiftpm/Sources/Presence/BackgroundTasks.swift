import BackgroundTasks
import Foundation

/// Background work: brain persistence, hippocampal replay/consolidation (when
/// charging), housekeeping of learned synapses. iOS schedules these at its
/// discretion; they also relaunch Jarvis in the background after a reboot once
/// the device has been unlocked.
enum BackgroundTasks {
    static let refreshID = "com.jarvis.local.assistant.refresh"
    static let consolidateID = "com.jarvis.local.assistant.consolidate"

    /// IDs must be declared in Info.plist (Info-Extra.plist); registering an
    /// undeclared ID would crash, so check first.
    private static var permitted: Set<String> {
        Set((Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]) ?? [])
    }

    static func register() {
        let ids = permitted
        if ids.contains(refreshID) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
                handle(task, consolidate: false)
            }
        }
        if ids.contains(consolidateID) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: consolidateID, using: nil) { task in
                handle(task, consolidate: true)
            }
        }
    }

    static func schedule() {
        let ids = permitted
        if ids.contains(refreshID) {
            let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
            refresh.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
            try? BGTaskScheduler.shared.submit(refresh)
        }
        if ids.contains(consolidateID) {
            let processing = BGProcessingTaskRequest(identifier: consolidateID)
            processing.requiresExternalPower = true
            processing.requiresNetworkConnectivity = false
            try? BGTaskScheduler.shared.submit(processing)
        }
    }

    private static func handle(_ task: BGTask, consolidate: Bool) {
        schedule()
        let work = Task { @MainActor in
            let jarvis = JarvisController.shared
            if consolidate {
                _ = jarvis.brain.consolidate(replays: 32)
                jarvis.brain.connectome.plasticity.decay(factor: 0.999)
            }
            jarvis.saveBrain()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
