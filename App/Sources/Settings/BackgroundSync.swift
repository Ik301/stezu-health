import BackgroundTasks
import Foundation
import StezuCore

/// S-033: a BGAppRefreshTask runs S-028's pass when iOS chooses, so Health and the queue reach
/// Hermes on days the app stays closed. The pass stops at 25 s or when iOS expires it (the task
/// is cancelled); what it did not send stays queued (D-088).
enum BackgroundSync {
  /// BGTaskSchedulerPermittedIdentifiers in project.yml.
  static let identifier = "com.ik301.stezuhealth.sync"
  /// About an hour between runs at the earliest; iOS decides when they happen.
  static let interval: TimeInterval = 3600
  static let limit: UInt64 = 25_000_000_000
  /// The `-uitest` scenario whose launch runs the task's handler once (the debug hook).
  static let scenario = "background-sync"
}

extension AppEnvironment {
  /// At launch, before it ends: registers the handler and asks for the first run. Under
  /// `-uitest` nothing is registered; the background-sync scenario queues a synthetic visit as
  /// if it was recorded while the app was closed, then runs the handler's pass once.
  func registerBackgroundSync() {
    guard !isUITest else {
      guard scenario == BackgroundSync.scenario else { return }
      Task {
        await self.places.record(UITestFixtures.backgroundVisit(), into: self.healthSync)
        _ = await self.runBackgroundSync().value
      }
      return
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundSync.identifier, using: nil) {
      nonisolated(unsafe) let task = $0
      let pass = self.runBackgroundSync()
      task.expirationHandler = { pass.cancel() }
      Task {
        let finished = await pass.value
        task.setTaskCompleted(success: finished)
      }
    }
    scheduleBackgroundSync()
  }

  /// Asks for the next run; a new request replaces the waiting one. Not under `-uitest`.
  func scheduleBackgroundSync() {
    guard !isUITest else { return }
    let request = BGAppRefreshTaskRequest(identifier: BackgroundSync.identifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: BackgroundSync.interval)
    try? BGTaskScheduler.shared.submit(request)
  }

  /// One background pass, cancelled after 25 s; true if it ran to the end.
  func runBackgroundSync() -> Task<Bool, Never> {
    let pass = Task.detached(priority: .utility) {
      await self.syncHermes(background: true)
      return !Task.isCancelled
    }
    Task {
      try? await Task.sleep(nanoseconds: BackgroundSync.limit)
      pass.cancel()
    }
    return pass
  }
}
