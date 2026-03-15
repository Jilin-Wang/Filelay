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
        XCTAssertTrue(item.cloudFilePath.hasPrefix(sharedICloudRoot.appendingPathComponent("Filelay/CloudFiles", isDirectory: true).path))

        let metadata = storage.loadMetadata(for: URL(fileURLWithPath: item.cloudFilePath), cloudFileId: item.cloudFileId).metadata
        XCTAssertEqual(metadata.cloudVersion?.contentHash, item.lastKnownLocalHash)
        XCTAssertNil(metadata.deletedAt)
    }

    func testUploadRejectsExistingUnmanagedCloudFile() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "protect-existing")
        let (_, coordinator) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localURL = try writeLocalFile(deviceKey: "A", fileName: "report.txt", contents: "new content")
        let cloudURL = sharedICloudRoot
            .appendingPathComponent("Filelay/CloudFiles", isDirectory: true)
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

    func testWatcherPromptsLinkedDeviceBeforeApplyingRemoteUpdate() throws {
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
            let localData = try? Data(contentsOf: localB)
            let cloudData = try? Data(contentsOf: URL(fileURLWithPath: uploaded.cloudFilePath))
            return localData == Data("initial".utf8)
                && cloudData == Data("changed from A".utf8)
                && coordinatorB.snapshot().items.first?.status == .conflict
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

    func testUseCloudResolutionRequiresConfirmationForEachFutureRemoteVersion() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "use-cloud-repeat")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localA = try writeLocalFile(deviceKey: "A", fileName: "shared.txt", contents: "initial")
        try coordinatorA.addUploadItem(localPath: localA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localB = try writeLocalFile(deviceKey: "B", fileName: "shared.txt", contents: "initial")
        try coordinatorB.linkExistingItem(localPath: localB.path, cloudFileId: uploaded.cloudFileId)

        try Data("A version 1".utf8).write(to: localA)
        coordinatorA.runManualSyncForTesting()
        coordinatorB.runManualSyncForTesting()

        var conflicted = try XCTUnwrap(coordinatorB.snapshot().items.first)
        XCTAssertEqual(conflicted.status, .conflict)
        XCTAssertEqual(try String(contentsOf: localB), "initial")

        coordinatorB.resolveConflict(itemID: conflicted.id, choice: .useCloud)
        try waitUntil(timeout: 2) {
            coordinatorB.snapshot().items.first?.status == .synced
                && (try? String(contentsOf: localB)) == "A version 1"
        }

        try Data("A version 2".utf8).write(to: localA)
        coordinatorA.runManualSyncForTesting()
        coordinatorB.runManualSyncForTesting()

        conflicted = try XCTUnwrap(coordinatorB.snapshot().items.first)
        XCTAssertEqual(conflicted.status, .conflict)
        XCTAssertEqual(try String(contentsOf: localB), "A version 1")
    }

    func testKeepLocalPromotesLocalVersionAndPeerMustConfirmIt() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "keep-local-peer-conflict")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localA = try writeLocalFile(deviceKey: "A", fileName: "shared.txt", contents: "initial")
        try coordinatorA.addUploadItem(localPath: localA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localB = try writeLocalFile(deviceKey: "B", fileName: "shared.txt", contents: "initial")
        try coordinatorB.linkExistingItem(localPath: localB.path, cloudFileId: uploaded.cloudFileId)

        try Data("A version 1".utf8).write(to: localA)
        coordinatorA.runManualSyncForTesting()
        coordinatorB.runManualSyncForTesting()

        let conflictedB = try XCTUnwrap(coordinatorB.snapshot().items.first)
        XCTAssertEqual(conflictedB.status, .conflict)

        coordinatorB.resolveConflict(itemID: conflictedB.id, choice: .keepLocal)
        try waitUntil(timeout: 2) {
            coordinatorB.snapshot().items.first?.status == .synced
                && (try? String(contentsOf: localB)) == "initial"
                && (try? String(contentsOf: URL(fileURLWithPath: uploaded.cloudFilePath))) == "initial"
        }

        coordinatorA.runManualSyncForTesting()
        var conflictedA = try XCTUnwrap(coordinatorA.snapshot().items.first)
        XCTAssertEqual(conflictedA.status, .conflict)
        XCTAssertEqual(try String(contentsOf: localA), "A version 1")

        coordinatorA.resolveConflict(itemID: conflictedA.id, choice: .useCloud)
        try waitUntil(timeout: 2) {
            coordinatorA.snapshot().items.first?.status == .synced
                && (try? String(contentsOf: localA)) == "initial"
        }

        try Data("B version 2".utf8).write(to: localB)
        coordinatorB.runManualSyncForTesting()
        coordinatorA.runManualSyncForTesting()

        conflictedA = try XCTUnwrap(coordinatorA.snapshot().items.first)
        XCTAssertEqual(conflictedA.status, .conflict)
        XCTAssertEqual(try String(contentsOf: localA), "initial")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: uploaded.cloudFilePath)), "B version 2")
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

    func testLegacyManagedRootMigratesLinkedItemsOnly() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "legacy-root")
        let appSupportDir = tempRoot.appendingPathComponent("legacy-root-app", isDirectory: true)
        let suiteName = "FilelayTests.LegacyRoot.\(UUID().uuidString)"
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

        let legacyRoot = sharedICloudRoot.appendingPathComponent("AutoiCloud", isDirectory: true)
        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        let linkedCloudURL = legacyRoot.appendingPathComponent("report.txt")
        try Data("linked".utf8).write(to: linkedCloudURL)
        let staleCloudURL = legacyRoot.appendingPathComponent("shared.txt")
        try Data("stale".utf8).write(to: staleCloudURL)

        let linkedItem = SyncItem(
            id: UUID().uuidString,
            kind: .file,
            localPath: try writeLocalFile(deviceKey: "A", fileName: "report.txt", contents: "linked").path,
            cloudFilePath: linkedCloudURL.path,
            cloudFileId: UUID().uuidString,
            isEnabled: true,
            status: .synced,
            lastKnownLocalHash: nil,
            lastSeenCloudVersionId: nil,
            conflictState: nil,
            cloudVersion: nil,
            deviceReceipts: [:],
            history: [],
            lastErrorMessage: nil,
            createdAt: Date().filelayString
        )

        let staleMetadata = CloudFileMetadata(
            cloudFileId: UUID().uuidString,
            kind: .file,
            cloudFilePath: staleCloudURL.path,
            cloudVersion: nil,
            deviceReceipts: [:],
            eventLog: [],
            deletedAt: nil,
            deletedByDevice: nil
        )

        storage.saveSettings(AppSettings.default(managedRootPath: legacyRoot.path))
        storage.saveSyncItems([linkedItem])
        try storage.saveMetadata(
            CloudFileMetadata(
                cloudFileId: linkedItem.cloudFileId,
                kind: .file,
                cloudFilePath: linkedCloudURL.path,
                cloudVersion: nil,
                deviceReceipts: [:],
                eventLog: [],
                deletedAt: nil,
                deletedByDevice: nil
            ),
            for: linkedCloudURL
        )
        try storage.saveMetadata(staleMetadata, for: staleCloudURL)

        let coordinator = SyncCoordinator(storage: storage)
        let snapshot = coordinator.snapshot()

        XCTAssertEqual(snapshot.settings.managedRootPath, sharedICloudRoot.appendingPathComponent("Filelay", isDirectory: true).path)
        XCTAssertEqual(snapshot.cloudFiles.count, 1)
        XCTAssertEqual(snapshot.cloudFiles.first?.displayName, "report.txt")
        XCTAssertTrue(snapshot.items.first?.cloudFilePath.hasPrefix(sharedICloudRoot.appendingPathComponent("Filelay/CloudFiles", isDirectory: true).path) ?? false)
        XCTAssertTrue(fm.fileExists(atPath: snapshot.items.first?.cloudFilePath ?? ""))
        XCTAssertTrue(fm.fileExists(atPath: staleCloudURL.path))
    }

    func testFolderUploadAndLinkStaySynced() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "folder-link")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localFolderA = try writeLocalFolder(
            deviceKey: "A",
            folderName: "raycast-data",
            files: [
                "config.json": Data("{\"theme\":\"dark\"}".utf8),
                "nested/state.txt": Data("enabled".utf8)
            ]
        )

        try coordinatorA.addUploadItem(localPath: localFolderA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)
        XCTAssertEqual(uploaded.kind, .folder)
        XCTAssertEqual(uploaded.status, .synced)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localFolderB = try writeLocalFolder(
            deviceKey: "B",
            folderName: "raycast-data",
            files: [
                "config.json": Data("{\"theme\":\"dark\"}".utf8),
                "nested/state.txt": Data("enabled".utf8)
            ]
        )

        try coordinatorB.linkExistingItem(localPath: localFolderB.path, cloudFileId: uploaded.cloudFileId)

        let linked = try XCTUnwrap(coordinatorB.snapshot().items.first)
        XCTAssertEqual(linked.kind, .folder)
        XCTAssertEqual(linked.status, .synced)
        XCTAssertEqual(try Data(contentsOf: localFolderB.appendingPathComponent("nested/state.txt")), Data("enabled".utf8))
    }

    func testFolderSyncMarksRemoteUpdateAsConflictUntilReviewed() throws {
        let sharedICloudRoot = try makeSharedICloudRoot(name: "folder-watch")
        let (_, coordinatorA) = makeCoordinator(deviceKey: "A", sharedICloudRoot: sharedICloudRoot)
        let localFolderA = try writeLocalFolder(
            deviceKey: "A",
            folderName: "cursor-data",
            files: [
                "settings/main.json": Data("{\"fontSize\":14}".utf8)
            ]
        )
        try coordinatorA.addUploadItem(localPath: localFolderA.path, relativeFolder: "")
        coordinatorA.waitForIdleForTesting()
        let uploaded = try XCTUnwrap(coordinatorA.snapshot().items.first)

        let (_, coordinatorB) = makeCoordinator(deviceKey: "B", sharedICloudRoot: sharedICloudRoot)
        let localFolderB = try writeLocalFolder(
            deviceKey: "B",
            folderName: "cursor-data",
            files: [
                "settings/main.json": Data("{\"fontSize\":14}".utf8)
            ]
        )
        try coordinatorB.linkExistingItem(localPath: localFolderB.path, cloudFileId: uploaded.cloudFileId)

        let beforeHash = try folderHash(localFolderA)
        try Data("{\"fontSize\":16}".utf8).write(to: localFolderA.appendingPathComponent("settings/main.json"))
        let afterHash = try folderHash(localFolderA)
        XCTAssertNotEqual(beforeHash, afterHash)
        coordinatorA.runManualSyncForTesting()
        let updatedA = try XCTUnwrap(coordinatorA.snapshot().items.first)
        XCTAssertEqual(updatedA.status, .synced)
        XCTAssertEqual(
            try String(contentsOf: localFolderA.appendingPathComponent("settings/main.json")),
            "{\"fontSize\":16}"
        )
        XCTAssertNotEqual(updatedA.lastSeenCloudVersionId, uploaded.lastSeenCloudVersionId)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: uploaded.cloudFilePath).appendingPathComponent("settings/main.json")),
            "{\"fontSize\":16}"
        )
        coordinatorB.runManualSyncForTesting()

        XCTAssertEqual(
            try String(contentsOf: localFolderB.appendingPathComponent("settings/main.json")),
            "{\"fontSize\":14}"
        )
        XCTAssertEqual(coordinatorB.snapshot().items.first?.status, .conflict)
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

    private func writeLocalFolder(deviceKey: String, folderName: String, files: [String: Data]) throws -> URL {
        let directory = tempRoot
            .appendingPathComponent("local-\(deviceKey)", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        for (relativePath, data) in files {
            let fileURL = directory.appendingPathComponent(relativePath)
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL)
        }

        return directory
    }

    private func folderHash(_ url: URL) throws -> String {
        var rows: [String] = []
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants])!
        for case let childURL as URL in enumerator {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: childURL.path, isDirectory: &isDirectory) else { continue }
            let relative = childURL.path.replacingOccurrences(of: url.path + "/", with: "")
            if isDirectory.boolValue {
                rows.append("dir:\(relative)")
            } else {
                let contents = try Data(contentsOf: childURL).base64EncodedString()
                rows.append("file:\(relative):\(contents)")
            }
        }
        return rows.sorted().joined(separator: "\n")
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
