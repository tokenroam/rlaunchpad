import Foundation
import SwiftUI
import Combine

enum LaunchPadUninstallError: LocalizedError {
    case unsupportedLocation
    case folderUnsupported
    case trashFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLocation:
            return "这个应用不适合通过 RLaunchPad 直接卸载。"
        case .folderUnsupported:
            return "文件夹不能卸载。"
        case .trashFailed(let message):
            return message
        }
    }
}

@MainActor
class LaunchPadViewModel: ObservableObject {
    @Published var applications: [AppItem] = []
    @Published var currentPage: Int = 0
    @Published var searchText: String = ""
    @Published var draggedApp: AppItem? = nil
    @Published var openFolder: AppItem? = nil
    @Published var isEditing: Bool = false

    private let scanner = ApplicationScanner()
    private let persistenceManager = PersistenceManager()
    private var cancellables = Set<AnyCancellable>()
    private var pendingSaveWork: DispatchWorkItem?

    private let columns = 7
    private let rows = 5
    private var itemsPerPage: Int { columns * rows }

    var totalPages: Int {
        let maxPage = applications.map(\.page).max() ?? 0
        return max(maxPage + 1, 1)
    }

    private var searchableApps: [AppItem] {
        var combined = applications
        for folder in applications where folder.type == .folder {
            combined.append(contentsOf: folder.folderItems ?? [])
        }
        return combined
    }

    var filteredApplications: [AppItem] {
        if searchText.isEmpty {
            return applications
        }

        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return applications }

        return searchableApps.filter { app in
            app.name.localizedCaseInsensitiveContains(keyword)
        }
    }

    var searchResults: [AppItem] {
        var seen = Set<UUID>()
        return filteredApplications
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    init() {
        bindScanner()
        loadApplications()
        startApplicationObservation()
    }

    func applications(onPage page: Int) -> [AppItem] {
        applications
            .filter { $0.page == page }
            .sorted { $0.position < $1.position }
    }

    func folderItems(for folderID: UUID) -> [AppItem] {
        applications.first(where: { $0.id == folderID && $0.type == .folder })?.folderItems ?? []
    }

    func app(withID id: UUID) -> AppItem? {
        if let topLevel = applications.first(where: { $0.id == id }) {
            return topLevel
        }

        for folder in applications where folder.type == .folder {
            if let item = folder.folderItems?.first(where: { $0.id == id }) {
                return item
            }
        }

        return nil
    }

    func setEditing(_ editing: Bool) {
        isEditing = editing
    }

    func loadApplications() {
        if let saved = persistenceManager.loadApplications(), !saved.isEmpty {
            applications = saved
            validateApplications()
            normalizeLayout()
            saveApplications()
            scanner.scanApplications()
        } else {
            scanner.scanApplications()
        }
    }

    private func bindScanner() {
        scanner.$applications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scanned in
                guard let self = self else { return }
                guard !scanned.isEmpty else { return }
                self.mergeScannedApplications(scanned)
            }
            .store(in: &cancellables)
    }

    private func startApplicationObservation() {
        scanner.startDirectoryObservation { [weak self] in
            Task { @MainActor [weak self] in
                self?.scanner.scanApplications()
            }
        }
    }

    private func validateApplications() {
        applications = applications.compactMap { app in
            switch app.type {
            case .application:
                return FileManager.default.fileExists(atPath: app.path.path) ? app : nil
            case .folder:
                var folder = app
                let items = (folder.folderItems ?? []).filter {
                    FileManager.default.fileExists(atPath: $0.path.path)
                }
                folder.folderItems = items
                return items.isEmpty ? nil : folder
            }
        }
    }

    func launchApplication(_ app: AppItem) {
        if app.type == .folder {
            withAnimation(LaunchPadMotion.folderOpen) {
                openFolder = app
            }
            return
        }

        scanner.launchApplication(app)
    }

    func moveApplication(from sourceApp: AppItem, to position: Int, page: Int) {
        insertApplication(sourceApp, at: position, page: page)
    }

    func insertApplication(_ app: AppItem, at insertPosition: Int, page: Int) {
        var ordered = topLevelOrderedApps()
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == app.id }) else {
            return
        }

        let movingApp = ordered.remove(at: sourceIndex)
        let targetIndex = max(0, min(page * itemsPerPage + insertPosition, ordered.count))
        ordered.insert(movingApp, at: targetIndex)

        applyTopLevelOrder(ordered)
        saveApplications()
    }

    func addToFolder(_ app: AppItem, folder: AppItem) {
        guard app.id != folder.id, app.type == .application else { return }

        var ordered = topLevelOrderedApps()
        guard let appIndex = ordered.firstIndex(where: { $0.id == app.id }),
              let folderIndex = ordered.firstIndex(where: { $0.id == folder.id }) else {
            return
        }

        let appToMove = ordered.remove(at: appIndex)
        let adjustedFolderIndex = appIndex < folderIndex ? folderIndex - 1 : folderIndex

        guard ordered.indices.contains(adjustedFolderIndex),
              ordered[adjustedFolderIndex].type == .folder else {
            return
        }

        var targetFolder = ordered[adjustedFolderIndex]
        var items = targetFolder.folderItems ?? []

        if items.contains(where: { $0.id == appToMove.id }) {
            return
        }

        items.append(appToMove)
        targetFolder.folderItems = items
        ordered[adjustedFolderIndex] = targetFolder

        applyTopLevelOrder(ordered)
        syncOpenFolderIfNeeded(folderID: targetFolder.id)
        saveApplications()
    }

    func moveApp(withID appID: UUID, toFolder folderID: UUID, at destinationIndex: Int? = nil) {
        reorderApp(withID: appID, inFolder: folderID, to: destinationIndex ?? folderItems(for: folderID).count)
    }

    func createFolder(with apps: [AppItem], name: String = "新建文件夹") {
        let uniqueIDs = Array(Set(apps.map(\.id)))
        guard uniqueIDs.count >= 2 else { return }

        var ordered = topLevelOrderedApps()

        // apps[0] 作为锚点位置（目标图标）
        guard let anchorID = apps.first?.id,
              let anchorIndex = ordered.firstIndex(where: { $0.id == anchorID }) else {
            return
        }

        let folderItems = apps.compactMap { app in
            ordered.first(where: { $0.id == app.id })
        }

        guard folderItems.count >= 2 else { return }

        let idsToFold = Set(folderItems.map(\.id))
        ordered.removeAll { idsToFold.contains($0.id) }

        let folder = AppItem(
            name: name,
            bundleIdentifier: nil,
            path: URL(fileURLWithPath: "/"),
            type: .folder,
            position: 0,
            page: 0,
            folderItems: folderItems
        )

        let insertIndex = min(anchorIndex, ordered.count)
        ordered.insert(folder, at: insertIndex)

        applyTopLevelOrder(ordered)
        saveApplications()
    }

    func renameFolder(_ folder: AppItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = applications.firstIndex(where: { $0.id == folder.id }) else {
            return
        }

        applications[index].name = trimmed
        syncOpenFolderIfNeeded(folderID: folder.id)
        saveApplications()
    }

    func reorderApp(withID appID: UUID, inFolder folderID: UUID, to destinationIndex: Int) {
        var ordered = topLevelOrderedApps()
        guard let folderIndex = ordered.firstIndex(where: { $0.id == folderID && $0.type == .folder }) else {
            return
        }

        if let sourceIndex = ordered[folderIndex].folderItems?.firstIndex(where: { $0.id == appID }) {
            var folder = ordered[folderIndex]
            guard var items = folder.folderItems else { return }
            let movingApp = items.remove(at: sourceIndex)
            let targetIndex = min(max(destinationIndex, 0), items.count)
            items.insert(movingApp, at: targetIndex)
            folder.folderItems = items
            ordered[folderIndex] = folder
            applyTopLevelOrder(ordered)
            syncOpenFolderIfNeeded(folderID: folderID)
            saveApplications()
            return
        }

        guard let movingApp = extractApplication(withID: appID, from: &ordered),
              movingApp.type == .application else {
            return
        }

        guard let refreshedFolderIndex = ordered.firstIndex(where: { $0.id == folderID && $0.type == .folder }) else {
            return
        }

        var folder = ordered[refreshedFolderIndex]
        var items = folder.folderItems ?? []
        let targetIndex = min(max(destinationIndex, 0), items.count)
        items.insert(movingApp, at: targetIndex)
        folder.folderItems = items
        ordered[refreshedFolderIndex] = folder

        applyTopLevelOrder(ordered)
        syncOpenFolderIfNeeded(folderID: folderID)
        saveApplications()
    }

    func removeFromFolder(_ app: AppItem, from folder: AppItem) {
        var ordered = topLevelOrderedApps()
        guard let folderIndex = ordered.firstIndex(where: { $0.id == folder.id }),
              ordered[folderIndex].type == .folder else {
            return
        }

        var targetFolder = ordered[folderIndex]
        guard var folderItems = targetFolder.folderItems,
              let removeIndex = folderItems.firstIndex(where: { $0.id == app.id }) else {
            return
        }

        let removedApp = folderItems.remove(at: removeIndex)

        if folderItems.count <= 1 {
            ordered.remove(at: folderIndex)

            var insertApps = [removedApp]
            if let survivor = folderItems.first {
                insertApps.append(survivor)
            }

            ordered.insert(contentsOf: insertApps, at: min(folderIndex, ordered.count))
            applyTopLevelOrder(ordered)
            openFolder = nil
            saveApplications()
            return
        }

        targetFolder.folderItems = folderItems
        ordered[folderIndex] = targetFolder
        ordered.insert(removedApp, at: min(folderIndex + 1, ordered.count))

        applyTopLevelOrder(ordered)
        syncOpenFolderIfNeeded(folderID: targetFolder.id)
        saveApplications()
    }

    func canUninstall(_ app: AppItem) -> Bool {
        guard app.type == .application else { return false }

        let standardizedPath = app.path.standardizedFileURL.path
        let userApplicationsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .path

        if standardizedPath.hasPrefix("/System/") {
            return false
        }

        return standardizedPath.hasPrefix("/Applications/")
            || standardizedPath.hasPrefix(userApplicationsRoot + "/")
    }

    func uninstallApplication(_ app: AppItem) throws {
        guard app.type == .application else {
            throw LaunchPadUninstallError.folderUnsupported
        }

        guard canUninstall(app) else {
            throw LaunchPadUninstallError.unsupportedLocation
        }

        do {
            _ = try FileManager.default.trashItem(at: app.path, resultingItemURL: nil)
            removeApplication(withID: app.id)
            scanner.scanApplications()
        } catch {
            throw LaunchPadUninstallError.trashFailed(error.localizedDescription)
        }
    }

    func saveApplications() {
        pendingSaveWork?.cancel()
        let snapshot = applications
        let work = DispatchWorkItem { [persistenceManager] in
            persistenceManager.saveApplications(snapshot)
        }
        pendingSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    func refreshApplications() {
        pendingSaveWork?.cancel()
        pendingSaveWork = nil
        applications = []
        scanner.scanApplications()
    }

    func resetLayout() {
        pendingSaveWork?.cancel()
        pendingSaveWork = nil
        persistenceManager.clearApplications()
        applications = []
        scanner.scanApplications()
    }

    func ensureLayoutIntegrity(resetToFirstPage: Bool = false) {
        normalizeLayout()
        if resetToFirstPage {
            currentPage = 0
        }
        saveApplications()
    }

    func debugPrintPageInfo(forPage page: Int) {
        let pageApps = applications
            .filter { $0.page == page }
            .sorted { $0.position < $1.position }

        print("===== PAGE \(page) =====")
        print("totalApps: \(applications.count), totalPages: \(totalPages)")
        for app in pageApps {
            print("[\(app.position)] \(app.name) (\(app.type))")
        }
    }

    private func normalizeLayout() {
        let ordered = topLevelOrderedApps()
        applyTopLevelOrder(ordered)
    }

    private func topLevelOrderedApps() -> [AppItem] {
        applications
    }

    private func applyTopLevelOrder(_ ordered: [AppItem]) {
        applications = ordered.enumerated().map { index, app in
            var updated = app
            updated.page = index / itemsPerPage
            updated.position = index % itemsPerPage
            return updated
        }

        let maxPageIndex = max(0, totalPages - 1)
        if currentPage > maxPageIndex {
            currentPage = maxPageIndex
        }

        if let openFolderID = openFolder?.id {
            syncOpenFolder(folderID: openFolderID)
        }
    }

    private func syncOpenFolder(folderID: UUID) {
        openFolder = applications.first {
            $0.id == folderID && $0.type == .folder
        }
    }

    private func syncOpenFolderIfNeeded(folderID: UUID) {
        guard openFolder?.id == folderID else { return }
        syncOpenFolder(folderID: folderID)
    }

    private func removeApplication(withID appID: UUID) {
        var ordered = topLevelOrderedApps()
        guard extractApplication(withID: appID, from: &ordered) != nil else { return }

        applyTopLevelOrder(ordered)
        saveApplications()
    }

    private func extractApplication(withID appID: UUID, from ordered: inout [AppItem]) -> AppItem? {
        if let index = ordered.firstIndex(where: { $0.id == appID }) {
            guard ordered[index].type == .application else { return nil }
            return ordered.remove(at: index)
        }

        for folderIndex in ordered.indices {
            guard ordered[folderIndex].type == .folder else { continue }
            var folder = ordered[folderIndex]
            guard var items = folder.folderItems,
                  let itemIndex = items.firstIndex(where: { $0.id == appID }) else {
                continue
            }

            let removed = items.remove(at: itemIndex)

            if items.count <= 1 {
                ordered.remove(at: folderIndex)
                if let survivor = items.first {
                    ordered.insert(survivor, at: min(folderIndex, ordered.count))
                }
            } else {
                folder.folderItems = items
                ordered[folderIndex] = folder
            }

            return removed
        }

        return nil
    }

    private func mergeScannedApplications(_ scannedApps: [AppItem]) {
        let scannedByKey = Dictionary(
            scannedApps.map { (appIdentityKey(for: $0), $0) },
            uniquingKeysWith: { current, _ in current }
        )

        var consumedKeys = Set<String>()
        var mergedTopLevel: [AppItem] = []
        var changed = false

        for item in topLevelOrderedApps() {
            switch item.type {
            case .application:
                let key = appIdentityKey(for: item)
                guard let scanned = scannedByKey[key] else {
                    changed = true
                    continue
                }
                consumedKeys.insert(key)

                let rebuilt = rebuildApplication(existing: item, scanned: scanned)
                if !sameApplicationMetadata(lhs: item, rhs: rebuilt) {
                    changed = true
                }
                mergedTopLevel.append(rebuilt)

            case .folder:
                let oldItems = item.folderItems ?? []
                var newItems: [AppItem] = []

                for folderItem in oldItems {
                    let key = appIdentityKey(for: folderItem)
                    guard let scanned = scannedByKey[key] else {
                        changed = true
                        continue
                    }
                    consumedKeys.insert(key)

                    let rebuilt = rebuildApplication(existing: folderItem, scanned: scanned)
                    if !sameApplicationMetadata(lhs: folderItem, rhs: rebuilt) {
                        changed = true
                    }
                    newItems.append(rebuilt)
                }

                if newItems.count != oldItems.count {
                    changed = true
                }

                if newItems.isEmpty {
                    changed = true
                    continue
                }

                if newItems.count == 1 {
                    changed = true
                    mergedTopLevel.append(newItems[0])
                    continue
                }

                var updatedFolder = item
                updatedFolder.folderItems = newItems
                mergedTopLevel.append(updatedFolder)
            }
        }

        let newApps = scannedApps.filter { !consumedKeys.contains(appIdentityKey(for: $0)) }
        if !newApps.isEmpty {
            changed = true
            mergedTopLevel.append(contentsOf: newApps)
        }

        if applications.isEmpty && !scannedApps.isEmpty {
            mergedTopLevel = scannedApps
            changed = true
        }

        guard changed else { return }

        applyTopLevelOrder(mergedTopLevel)
        saveApplications()
    }

    private func appIdentityKey(for app: AppItem) -> String {
        app.path.standardizedFileURL.path.lowercased()
    }

    private func rebuildApplication(existing: AppItem, scanned: AppItem) -> AppItem {
        AppItem(
            id: existing.id,
            name: scanned.name,
            bundleIdentifier: scanned.bundleIdentifier,
            path: scanned.path,
            type: .application,
            position: existing.position,
            page: existing.page
        )
    }

    private func sameApplicationMetadata(lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.name == rhs.name &&
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.path == rhs.path
    }

    deinit {
        pendingSaveWork?.cancel()
        let scanner = scanner
        Task { @MainActor in
            scanner.stopDirectoryObservation()
        }
    }
}
