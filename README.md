# RLaunchPad

A native-feeling macOS Launchpad clone built with SwiftUI.

RLaunchPad recreates the classic full-screen Launchpad experience on macOS, with search, folders, paging, drag-and-drop reordering, keyboard navigation, and a resident menu bar launcher.

中文说明见下方的 `中文` 章节。

## Features

- Full-screen Launchpad-style grid layout
- Search with live filtering
- Drag-and-drop reordering across pages
- Folder creation, rename, open, and drag-in management
- Keyboard navigation and quick launching
- Menu bar integration and global hotkey toggle
- Persistent layout storage
- DMG packaging script for release builds

## Requirements

- macOS 26.1+
- Xcode 17+
- Swift 5.9+

## Getting Started

### Xcode

```bash
open RLaunchPad.xcodeproj
```

Build and run the `RLaunchPad` scheme.

### SwiftPM

```bash
swift build
./.build/arm64-apple-macosx/debug/RLaunchPad
```

## Packaging

Create a signed Release app bundle and DMG:

```bash
./scripts/make_dmg.sh
```

The script outputs a DMG to `dist/`.

If you want to test packaging without bumping the build number:

```bash
AUTO_BUMP_BUILD=0 ./scripts/make_dmg.sh
```

## Project Structure

```text
RLaunchPad/
├── RLaunchPad/              # SwiftUI app source
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   ├── Views/
│   └── Assets.xcassets/
├── RLaunchPad.xcodeproj/    # Xcode project
├── scripts/                 # Build and release helpers
├── Package.swift            # SwiftPM manifest
└── LICENSE
```

## Notes

- RLaunchPad is an independent project and is not affiliated with Apple.
- Release builds rely on the signing configuration in your local Xcode environment.

## 中文

RLaunchPad 是一个使用 SwiftUI 构建的 macOS Launchpad 风格启动器，目标是尽可能还原经典 Launchpad 的交互和视觉体验，包括分页、搜索、文件夹、拖拽整理、键盘导航和常驻菜单栏入口。

### 功能特性

- 全屏 Launchpad 风格网格布局
- 实时搜索过滤
- 支持跨页拖拽排序
- 支持创建、重命名和管理文件夹
- 支持键盘导航和快速启动
- 支持菜单栏入口和全局快捷键呼出
- 自动保存布局状态
- 附带 DMG 打包脚本

### 运行要求

- macOS 26.1+
- Xcode 17+
- Swift 5.9+

### 快速开始

#### 使用 Xcode

```bash
open RLaunchPad.xcodeproj
```

打开后直接运行 `RLaunchPad` scheme。

#### 使用 SwiftPM

```bash
swift build
./.build/arm64-apple-macosx/debug/RLaunchPad
```

### 打包

生成签名的 Release app 和 DMG：

```bash
./scripts/make_dmg.sh
```

如果只想验证打包流程而不自动递增构建号：

```bash
AUTO_BUMP_BUILD=0 ./scripts/make_dmg.sh
```

打包产物会输出到 `dist/`。

## License

MIT. See [LICENSE](LICENSE).
