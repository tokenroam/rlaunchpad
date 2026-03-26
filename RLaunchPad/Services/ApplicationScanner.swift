//
//  ApplicationScanner.swift
//  RLaunchPad
//
//  Created by luo on 2026/1/14.
//
//  应用扫描服务
//  ============
//  负责扫描系统中安装的应用程序，提取应用信息并分配页面位置。
//  扫描结果通过 @Published 属性发布，供 ViewModel 订阅。
//

import Foundation
import AppKit
import Combine
import Darwin

// MARK: - 应用扫描器

/// 应用程序扫描服务
///
/// 扫描 macOS 系统中的应用程序目录，获取所有已安装的应用信息。
///
/// ## 扫描目录
/// 1. `/Applications` - 用户安装的应用
/// 2. `/System/Applications` - 系统应用
/// 3. `/System/Library/CoreServices/Applications` - 系统核心服务应用
/// 4. `~/Applications` - 用户目录下的应用
///
/// ## 使用示例
/// ```swift
/// let scanner = ApplicationScanner()
/// scanner.scanApplications()
///
/// // 订阅扫描结果
/// scanner.$applications
///     .sink { apps in
///         print("找到 \(apps.count) 个应用")
///     }
/// ```
class ApplicationScanner: ObservableObject {

    /// 扫描到的应用列表
    /// 使用 @Published 使其可被 Combine 订阅
    @Published var applications: [AppItem] = []

    private let scanQueue = DispatchQueue(label: "com.rlaunchpad.scanner.scan", qos: .utility)
    private let watchQueue = DispatchQueue(label: "com.rlaunchpad.scanner.watch", qos: .utility)
    private var directoryWatchers: [DispatchSourceFileSystemObject] = []
    private var pendingWatchNotify: DispatchWorkItem?
    private let watchDebounceInterval: TimeInterval = 0.8

    /// 系统应用程序目录列表
    private let applicationPaths = [
        "/Applications",                                    // 主应用目录
        "/System/Applications",                             // 系统应用
        "/System/Library/CoreServices/Applications"         // 核心服务应用
    ]

    /// 用户应用程序目录
    /// 位于用户主目录下的 Applications 文件夹
    private var userApplicationsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }

    private var scanTargets: [URL] {
        var targets = applicationPaths.map { URL(fileURLWithPath: $0) }
        targets.append(userApplicationsPath)
        return targets
    }

    // MARK: - 扫描方法

    /// 扫描所有应用程序
    ///
    /// 遍历所有配置的应用目录，收集 .app 包信息。
    /// 扫描完成后按名称排序，并自动分配页面和位置。
    ///
    /// ## 扫描流程
    /// 1. 遍历所有应用目录
    /// 2. 查找 .app 后缀的文件
    /// 3. 读取 Bundle 信息获取应用名称
    /// 4. 按名称字母排序
    /// 5. 分配页面和位置索引
    /// 6. 在主线程发布结果
    func scanApplications() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            let apps = self.scanApplicationsSnapshot()
            DispatchQueue.main.async {
                self.applications = apps
            }
        }
    }

    func startDirectoryObservation(onChange: @escaping @Sendable () -> Void) {
        stopDirectoryObservation()

        for target in scanTargets {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            let fd = open(target.path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: watchQueue
            )

            source.setEventHandler { [weak self] in
                self?.scheduleWatchNotify(onChange: onChange)
            }
            source.setCancelHandler {
                close(fd)
            }

            directoryWatchers.append(source)
            source.resume()
        }
    }

    func stopDirectoryObservation() {
        pendingWatchNotify?.cancel()
        pendingWatchNotify = nil

        directoryWatchers.forEach { $0.cancel() }
        directoryWatchers.removeAll()
    }

    // MARK: - 私有方法

    /// 扫描指定目录中的应用
    ///
    /// - Parameters:
    ///   - url: 要扫描的目录 URL
    ///   - position: 当前位置计数器（用于跟踪扫描进度）
    /// - Returns: 扫描到的应用列表
    ///
    /// ## 扫描规则
    /// - 仅扫描第一层目录，不递归进入子目录
    /// - 跳过隐藏文件
    /// - 仅处理 .app 后缀的文件
    private func scanDirectory(at url: URL, position: inout Int) -> [AppItem] {
        var apps: [AppItem] = []

        // 创建目录枚举器
        // - skipsHiddenFiles: 跳过隐藏文件
        // - skipsSubdirectoryDescendants: 不递归子目录
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return apps
        }

        // 遍历目录内容
        for case let fileURL as URL in enumerator {
            // 检查是否是应用程序（.app 后缀）
            if fileURL.pathExtension == "app" {
                // 尝试读取 Bundle 信息
                if let bundle = Bundle(url: fileURL) {
                    // 获取应用显示名称
                    // 优先级: CFBundleDisplayName > CFBundleName > 文件名
                    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? fileURL.deletingPathExtension().lastPathComponent

                    // 获取 Bundle 标识符
                    let bundleId = bundle.bundleIdentifier

                    // 创建 AppItem
                    let app = AppItem(
                        name: name,
                        bundleIdentifier: bundleId,
                        path: fileURL,
                        position: position,
                        page: 0
                    )
                    apps.append(app)
                    position += 1
                }
            }
        }

        return apps
    }

    private func scanApplicationsSnapshot() -> [AppItem] {
        var apps: [AppItem] = []
        var position = 0

        for target in scanTargets {
            apps.append(contentsOf: scanDirectory(at: target, position: &position))
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for (index, var app) in apps.enumerated() {
            app.position = index % itemsPerPage()
            app.page = index / itemsPerPage()
            apps[index] = app
        }

        return apps
    }

    private func scheduleWatchNotify(onChange: @escaping @Sendable () -> Void) {
        pendingWatchNotify?.cancel()

        let work = DispatchWorkItem {
            DispatchQueue.main.async {
                onChange()
            }
        }

        pendingWatchNotify = work
        watchQueue.asyncAfter(deadline: .now() + watchDebounceInterval, execute: work)
    }

    /// 计算每页可容纳的应用数量
    /// - Returns: 每页应用数 (7列 x 5行 = 35)
    private func itemsPerPage() -> Int {
        return 7 * 5  // 35 个应用/页
    }

    // MARK: - 应用启动

    /// 启动指定应用
    ///
    /// 使用 NSWorkspace 打开应用程序
    ///
    /// - Parameter app: 要启动的应用
    func launchApplication(_ app: AppItem) {
        NSWorkspace.shared.openApplication(
            at: app.path,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error = error {
                print("启动应用失败 \(app.name): \(error.localizedDescription)")
            }
        }
    }

    deinit {
        stopDirectoryObservation()
    }
}
