//
//  AppItem.swift
//  RLaunchPad
//
//  Created by luo on 2026/1/14.
//
//  应用项数据模型
//  ============
//  定义应用程序和文件夹的数据结构，是整个应用的核心数据模型。
//  遵循 Codable 协议以支持 JSON 序列化持久化存储。
//

import Foundation
import AppKit

// MARK: - 应用项类型枚举

/// 应用项的类型
/// - application: 普通应用程序
/// - folder: 文件夹（包含多个应用）
enum AppItemType: Codable, Sendable {
    case application
    case folder
}

// MARK: - 应用项模型

/// 应用项模型
/// 表示 Launchpad 中的一个应用程序或文件夹
///
/// ## 属性说明
/// - `id`: 唯一标识符，用于 SwiftUI 列表识别
/// - `name`: 显示名称，来自 Bundle 的 CFBundleDisplayName 或 CFBundleName
/// - `bundleIdentifier`: 应用的 Bundle ID，用于唯一标识应用（文件夹为 nil）
/// - `path`: 应用的文件系统路径
/// - `type`: 类型（应用或文件夹）
/// - `position`: 在当前页面的位置索引 (0 到 itemsPerPage-1)
/// - `page`: 所在页码（从 0 开始）
/// - `folderItems`: 文件夹内的应用列表（仅文件夹类型有值）
///
/// ## 页面位置计算
/// ```
/// 第 0 页: position 0-34
/// 第 1 页: position 0-34
/// ...
/// ```
///
/// ## 使用示例
/// ```swift
/// // 创建应用
/// let app = AppItem(
///     name: "Safari",
///     bundleIdentifier: "com.apple.Safari",
///     path: URL(fileURLWithPath: "/Applications/Safari.app"),
///     position: 0,
///     page: 0
/// )
///
/// // 创建文件夹
/// let folder = AppItem(
///     name: "工具",
///     bundleIdentifier: nil,
///     path: URL(fileURLWithPath: "/"),
///     type: .folder,
///     position: 5,
///     page: 0,
///     folderItems: [app1, app2]
/// )
/// ```
struct AppItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    private static let iconCache = NSCache<NSString, NSImage>()

    /// 唯一标识符
    let id: UUID

    /// 显示名称
    var name: String

    /// 应用 Bundle 标识符（文件夹为 nil）
    let bundleIdentifier: String?

    /// 应用路径
    let path: URL

    /// 类型（应用或文件夹）
    let type: AppItemType

    /// 在当前页面的位置索引（0 到 34，基于 7x5 网格）
    var position: Int

    /// 所在页码（从 0 开始）
    var page: Int

    /// 文件夹内的应用列表（仅文件夹类型有值）
    var folderItems: [AppItem]?

    /// 初始化方法
    /// - Parameters:
    ///   - id: 唯一标识符，默认自动生成
    ///   - name: 显示名称
    ///   - bundleIdentifier: Bundle ID
    ///   - path: 应用路径
    ///   - type: 类型，默认为 .application
    ///   - position: 位置索引，默认为 0
    ///   - page: 页码，默认为 0
    ///   - folderItems: 文件夹内应用，默认为 nil
    init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String?,
        path: URL,
        type: AppItemType = .application,
        position: Int = 0,
        page: Int = 0,
        folderItems: [AppItem]? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.type = type
        self.position = position
        self.page = page
        self.folderItems = folderItems
    }

    // MARK: - 图标获取

    /// 获取应用图标
    /// - Returns: 应用图标的 NSImage
    ///
    /// 对于普通应用，使用 NSWorkspace 从应用路径获取图标
    /// 对于文件夹，返回系统文件夹图标
    ///
    /// - Note: 此方法标记为 @MainActor，必须在主线程调用
    @MainActor
    func getIcon() -> NSImage {
        switch type {
        case .application:
            let cacheKey = path.path as NSString
            if let cached = Self.iconCache.object(forKey: cacheKey) {
                return cached
            }
            let icon = NSWorkspace.shared.icon(forFile: path.path)
            Self.iconCache.setObject(icon, forKey: cacheKey)
            return icon
        case .folder:
            // 使用系统文件夹图标
            return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage()
        }
    }

    // MARK: - Equatable & Hashable

    /// 相等性比较（仅比较 ID）
    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.id == rhs.id
    }

    /// 哈希值计算（仅使用 ID）
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
