import Foundation
import XCTest
@testable import Filelay

final class SyncCoordinatorTests: XCTestCase {
    private var tempRoot: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FilelayTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, fm.fileExists(atPath: tempRoot.path) {
            try? fm.removeItem(at: tempRoot)
        }
    }

    func testUploadCreatesCloudFileAndMetadata() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "upload")
        let (storage, coordinator) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localURL = try writeLocalFile(deviceKey: "A", fileName: "report.txt", contents: "hello upload")

        try coordinator.addUploadItem(localPath: localURL.path, relativeFolder: "")
        coordinator.waitForIdleForTesting()

        let snapshot = coordinator.snapshot()
        let item = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(item.status, .synced)
        XCTAssertTrue(fm.fileExists(atPath: item.cloudFilePath))

        let metadata = storage.loadMetadata(for: URL(fileURLWithPath: item.cloudFilePath), cloudFileId: item.cloudFileId).metadata
        XCTAssertEqual(metadata.cloudVersion?.contentHash, item.lastKnownLocalHash)
        XCTAssertNil(metadata.deletedAt)
    }

    func testUploadRejectsExistingUnmanagedCloudFile() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "protect-existing")
        let (_, coordinator) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localURL = try writeLocalFile(deviceKey: "A", fileName: "report.txt", contents: "new content")
        let cloudURL = sharedICloudRoot
            .appendingPathComponent("Filelay", isDirectory: true)
            .appendingPathComponent("report.txt")
        try fm.createDirectory(at: cloudURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing cloud file".utf8).write(to: cloudURL)

        XCTAssertThrowsError(try coordinator.addUploadItem(localPath: localURL.path, relativeFolder: "")) { error in
            guard case CoordinatorError.cloudTargetAlreadyExists = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testLinkExistingWithMatchingContentStartsSynced() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "link-synced")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localA = try writeLocalFile(deviceKey: "A", fileName: "shared.txt", contents: "same content")
        try coordinatorA.addUploadItem(localPath: localA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localB = try writeLocalFile(deviceKey: "B", fileName: "shared.txt", contents: "same content")
        try coordinatorB.linkExistingItem(localPath: localB.path, cloudFileId: uploaded.cloudFileId)

        let linked = try XCTUnwrap(coordinatorB.snapshot().items.first)
        XCTAssertEqual(linked.status, .synced)
        XCTAssertNil(linked.conflictState)
    }

    func testLinkExistingWithDifferentContentStartsInConflict() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "link-conflict")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localA = try writeLocalFile(deviceKey: "A", fileName: "shared.txt", contents: "cloud content")
        try coordinatorA.addUploadItem(localPath: localA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localB = try writeLocalFile(deviceKey: "B", fileName: "shared.txt", contents: "local changed content")
        try coordinatorB.linkExistingItem(localPath: localB.path, cloudFileId: uploaded.cloudFileId)

        let linked = try XCTUnwrap(coordinatorB.snapshot().items.first)
        XCTAssertEqual(linked.status, .conflict)
        XCTAssertNotNil(linked.conflictState)
    }

    func testDeleteRemovesCloudFileAndStopsRemoteSync() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "delete")
        let (storageA, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localA = try writeLocalFile(deviceKey: "A", fileName: "shared.txt", contents: "shared content")
        try coordinatorA.addUploadItem(localPath: localA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localB = try writeLocalFile(deviceKey: "B", fileName: "shared.txt", contents: "shared content")
        try coordinatorB.linkExistingItem(localPath: localB.path, cloudFileId: uploaded.cloudFileId)

        try coordinatorA.deleteCloudFile(cloudFileId: uploaded.cloudFileId)
        XCTAssertFalse(fm.fileExists(atPath: uploaded.cloudFilePath))

        coordinatorB.runManualSyncForTesting()
        let remoteSnapshot = coordinatorB.snapshot()
        XCTAssertTrue(fm.fileExists(atPath: localB.path))
        XCTAssertTrue(remoteSnapshot.items.isEmpty)
        XCTAssertFalse(remoteSnapshot.cloudFiles.contains { $0.cloudFileId == uploaded.cloudFileId })

        let metadata = storageA.loadMetadata(for: URL(fileURLWithPath: uploaded.cloudFilePath), cloudFileId: uploaded.cloudFileId).metadata
        XCTAssertNotNil(metadata.deletedAt)
    }

    func testDeviceIdentityPersistsAcrossDefaultsDomains() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "device-identity")
        let appSupportDir = tempRoot.appendingPathComponent("device-identity-app", isDirectory: true)

        let suiteNameA = "FilelayTests.DeviceIdentity.A.\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: suiteNameA)!
        defaultsA.removePersistentDomain(forName: suiteNameA)
        let storageA = Storage(
            fileManager: fm,
            userDefaults: defaultsA,
            appSupportDir: appSupportDir,
            iCloudDriveRootURL: sharedICloudRoot
        )
        let deviceA = storageA.currentDevice()

        let suiteNameB = "FilelayTests.DeviceIdentity.B.\(UUID().uuidString)"
        let defaultsB = UserDefaults(suiteName: suiteNameB)!
        defaultsB.removePersistentDomain(forName: suiteNameB)
        let storageB = Storage(
            fileManager: fm,
            userDefaults: defaultsB,
            appSupportDir: appSupportDir,
            iCloudDriveRootURL: sharedICloudRoot
        )
        let deviceB = storageB.currentDevice()

        XCTAssertEqual(deviceA.id, deviceB.id)
    }

    func testAtomicReplaceUpdatesDestinationWithoutTempArtifacts() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "atomic-replace")
        let appSupportDir = tempRoot.appendingPathComponent("atomic-replace-app", isDirectory: true)
        let defaults = UserDefaults(suiteName: "FilelayTests.AtomicReplace.\(UUID().uuidString)")!
        let storage = Storage(
            fileManager: fm,
            userDefaults: defaults,
            appSupportDir: appSupportDir,
            iCloudDriveRootURL: sharedICloudRoot
        )

        let destinationDirectory = tempRoot.appendingPathComponent("atomic-target", isDirectory: true)
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sourceURL = destinationDirectory.appendingPathComponent("source.txt")
        let destinationURL = destinationDirectory.appendingPathComponent("destination.txt")
        try Data("new payload".utf8).write(to: sourceURL)
        try Data("old payload".utf8).write(to: destinationURL)

        try storage.replaceFileAtomically(at: destinationURL, withContentsOf: sourceURL)

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new payload".utf8))
        let directoryContents = try fm.contentsOfDirectory(atPath: destinationDirectory.path)
        XCTAssertFalse(directoryContents.contains(where: { $0.hasPrefix(".tmp.") }))
    }

    func testStructuredLogFileIsWritten() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "structured-log")
        let (storage, coordinator) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localURL = try writeLocalFile(deviceKey: "A", fileName: "report.txt", contents: "log me")

        try coordinator.addUploadItem(localPath: localURL.path, relativeFolder: "")
        coordinator.waitForIdleForTesting()

        let logURL = storage.logsDirectoryURL.appendingPathComponent("sync.log.jsonl")
        let logContents = try String(contentsOf: logURL)
        XCTAssertTrue(logContents.contains("\"category\" : \"item.added\""))
        XCTAssertTrue(logContents.contains("\"category\" : \"sync.push_completed\""))
    }

    func testWatcherPropagatesLocalChangeToLinkedDevice() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "watcher-propagation")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localA = try writeLocalFile(deviceKey: "A", fileName: "shared.txt", contents: "initial")
        try coordinatorA.addUploadItem(localPath: localA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localB = try writeLocalFile(deviceKey: "B", fileName: "shared.txt", contents: "initial")
        try coordinatorB.linkExistingItem(localPath: localB.path, cloudFileId: uploaded.cloudFileId)

        coordinatorA.start()
        coordinatorB.start()
        addTeardownBlock {
            coordinatorA.stop()
            coordinatorB.stop()
        }

        try Data("changed from A".utf8).write(to: localA)

        try waitUntil(timeout: 3) {
            let syncedData = try? Data(contentsOf: localB)
            return syncedData == Data("changed from A".utf8)
                && coordinatorB.snapshot().items.first?.status == .synced
        }
    }

    func testConcurrentEditsProduceConflictAfterBaselineSync() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "baseline-conflict")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localA = try writeLocalFile(deviceKey: "A", fileName: "shared.txt", contents: "initial")
        try coordinatorA.addUploadItem(localPath: localA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localB = try writeLocalFile(deviceKey: "B", fileName: "shared.txt", contents: "initial")
        try coordinatorB.linkExistingItem(localPath: localB.path, cloudFileId: uploaded.cloudFileId)

        try Data("device A update".utf8).write(to: localA)
        try Data("device B update".utf8).write(to: localB)

        coordinatorA.runManualSyncForTesting()
        coordinatorB.runManualSyncForTesting()

        let conflicted = try XCTUnwrap(coordinatorB.snapshot().items.first)
        XCTAssertEqual(conflicted.status, .conflict)
        XCTAssertNotNil(conflicted.conflictState)
    }

    func testLargeFileUploadAndLinkStayStable() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "large-file")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let largeData = Data(repeating: 0x5A, count: 8 * 1024 * 1024)
        let localA = try writeLocalFile(deviceKey: "A", fileName: "archive.bin", data: largeData)

        try coordinatorA.addUploadItem(localPath: localA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)
        XCTAssertEqual(uploaded.status, .synced)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localB = try writeLocalFile(deviceKey: "B", fileName: "archive.bin", data: largeData)
        try coordinatorB.linkExistingItem(localPath: localB.path, cloudFileId: uploaded.cloudFileId)

        let linked = try XCTUnwrap(coordinatorB.snapshot().items.first)
        XCTAssertEqual(linked.status, .synced)
        XCTAssertEqual(try Data(contentsOf: localB), largeData)
    }

    private func makeSharedICloudRoot(name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent("icloud-\(name)", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeCoordinator(deviceKey: String, sharedICloudRoot: URL) -> (Storage, SyncCoordinator) {
        let appSupportDir = tempRoot.appendingPathComponent("app-\(deviceKey)", isDirectory: true)
        let suiteName = "FilelayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = Storage(
            fileManager: fm,
            userDefaults: defaults,
            appSupportDir: appSupportDir,
            iCloudDriveRootURL: sharedICloudRoot
        )
        return (storage, SyncCoordinator(storage: storage))
    }

    private func writeLocalFile(deviceKey: String, fileName: String, contents: String) throws -> URL {
        let directory = tempRoot.appendingPathComponent("local-\(deviceKey)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func writeLocalFile(deviceKey: String, fileName: String, data: Data) throws -> URL {
        let directory = tempRoot.appendingPathComponent("local-\(deviceKey)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }

    private func waitUntil(timeout: TimeInterval, pollInterval: TimeInterval = 0.05, _ condition: @escaping () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        XCTAssertTrue(false, "Timed out waiting for condition")
    }
}
