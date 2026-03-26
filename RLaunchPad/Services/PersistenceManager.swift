//
//  PersistenceManager.swift
//  RLaunchPad
//
//  Created by luo on 2026/1/14.
//
//  数据持久化服务
//  ==============
//  使用 UserDefaults 存储应用配置数据。
//  支持应用位置、页面、文件夹等信息的持久化保存。
//

import Foundation

// MARK: - 持久化管理器

/// 数据持久化管理器
///
/// 负责将应用配置数据保存到 UserDefaults，并在启动时恢复。
/// 使用 JSON 编码格式存储 AppItem 数组。
///
/// ## 存储位置
/// 数据存储在 UserDefaults 中，键名为 `com.rlaunchpad.applications`
///
/// ## 数据格式
/// ```json
/// [
///     {
///         "id": "uuid-string",
///         "name": "App Name",
///         "bundleIdentifier": "com.example.app",
///         "path": "file:///Applications/App.app",
///         "type": "application",
///         "position": 0,
///         "page": 0,
///         "folderItems": null
///     }
/// ]
/// ```
///
/// ## 使用示例
/// ```swift
/// let manager = PersistenceManager()
///
/// // 保存
/// manager.saveApplications(apps)
///
/// // 加载
/// if let apps = manager.loadApplications() {
///     // 使用加载的应用列表
/// }
///
/// // 清除
/// manager.clearApplications()
/// ```
class PersistenceManager {

    /// UserDefaults 实例
    private let userDefaults = UserDefaults.standard
    private let saveQueue = DispatchQueue(label: "com.rlaunchpad.persistence.save", qos: .utility)
    private var pendingWrite: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.08

    /// 存储键名
    /// 用于在 UserDefaults 中标识应用配置数据
    private let applicationsKey = "com.rlaunchpad.applications"

    // MARK: - 保存

    /// 保存应用配置
    ///
    /// 将应用列表编码为 JSON 数据并存储到 UserDefaults。
    ///
    /// - Parameter apps: 要保存的应用列表
    ///
    /// ## 注意事项
    /// - 保存在后台队列执行，并做短时间防抖，减少频繁拖拽时主线程抖动
    /// - 编码失败时会打印错误信息但不会抛出异常
    func saveApplications(_ apps: [AppItem]) {
        let snapshot = apps
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(snapshot)
                self.scheduleWrite(data: data)
            } catch {
                print("保存应用配置失败: \(error)")
            }
        }
    }

    // MARK: - 加载

    /// 加载应用配置
    ///
    /// 从 UserDefaults 读取 JSON 数据并解码为应用列表。
    ///
    /// - Returns: 应用列表，如果没有保存的数据或解码失败则返回 nil
    ///
    /// ## 返回值说明
    /// - 首次运行时返回 nil（无保存数据）
    /// - 数据损坏或格式不兼容时返回 nil
    func loadApplications() -> [AppItem]? {
        // 尝试获取存储的数据
        guard let data = userDefaults.data(forKey: applicationsKey) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let apps = try decoder.decode([AppItem].self, from: data)
            return apps
        } catch {
            print("加载应用配置失败: \(error)")
            return nil
        }
    }

    // MARK: - 清除

    /// 清除应用配置
    ///
    /// 从 UserDefaults 中删除保存的应用配置数据。
    /// 下次启动时将重新扫描系统应用。
    ///
    /// ## 调试用途
    /// 可通过命令行清除：
    /// ```bash
    /// defaults delete com.superposer.RLaunchPad.RLaunchPad com.rlaunchpad.applications
    /// ```
    func clearApplications() {
        saveQueue.sync {
            pendingWrite?.cancel()
            pendingWrite = nil
        }
        userDefaults.removeObject(forKey: applicationsKey)
    }

    private func scheduleWrite(data: Data) {
        pendingWrite?.cancel()

        let writeWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.userDefaults.set(data, forKey: self.applicationsKey)
        }

        pendingWrite = writeWork
        saveQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: writeWork)
    }
}
