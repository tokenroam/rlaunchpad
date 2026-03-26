import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @StateObject private var viewModel = LaunchPadViewModel()
    @StateObject private var pageMotion = PageMotionState()
    @State private var accumulatedScroll: CGFloat = 0
    @State private var lastTrackpadPageTurnAt: TimeInterval = 0
    @State private var folderSourceRect: CGRect?
    @State private var folderTransitionReplica: AppItem?
    @State private var selectedAppID: UUID?
    @State private var isFolderNameEditing = false
    @State private var pendingUninstallApp: AppItem?
    @State private var uninstallErrorMessage: String?

    var body: some View {
        GeometryReader { geometry in
            let layout = LaunchPadLayout.sceneMetrics(in: geometry.size)

            ZStack {
                WindowReporterView()
                    .frame(width: 0, height: 0)

                BlurredBackgroundView()
                    .ignoresSafeArea()
                DarkOverlayView()
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard viewModel.openFolder == nil else { return }
                        NotificationCenter.default.post(name: .rLaunchPadHideRequested, object: nil)
                    }

                VStack(spacing: 0) {
                    SearchBarView(
                        searchText: $viewModel.searchText,
                        isEditing: viewModel.isEditing,
                        onToggleEditing: toggleEditingMode,
                        metrics: layout.searchBar
                    )
                        .padding(.top, layout.searchBar.topPadding)

                    Spacer(minLength: 24)

                    Group {
                        if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            pageView(layout: layout)
                        } else {
                            searchResultsView(layout: layout)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.totalPages > 1 {
                        PageIndicatorView(
                            totalPages: viewModel.totalPages,
                            currentPage: $viewModel.currentPage,
                            metrics: layout.pageIndicator,
                            previewPage: topLevelPreviewPage,
                            previewProgress: topLevelPreviewProgress,
                            settleProgress: pageMotion.settleProgress
                        )
                        .padding(.bottom, layout.pageIndicator.bottomPadding)
                    } else {
                        Spacer().frame(height: 34)
                    }
                }
                .padding(.horizontal, LaunchPadLayout.pageHorizontalPadding)
                .blur(radius: viewModel.openFolder == nil ? 0 : 1.5)
                .scaleEffect(viewModel.openFolder == nil ? 1 : 0.982)
                .opacity(viewModel.openFolder == nil ? 1 : 0.94)
                .saturation(viewModel.openFolder == nil ? 1 : 0.93)
                .offset(backgroundRetreatOffset(in: geometry.size))
                .allowsHitTesting(viewModel.openFolder == nil)
                .animation(LaunchPadMotion.folderBackdrop, value: viewModel.openFolder != nil)

                if viewModel.openFolder == nil,
                   let folderTransitionReplica,
                   let folderSourceRect
                {
                    FolderSourceHaloView(
                        sourceRect: folderSourceRect,
                        isExpanded: viewModel.openFolder?.id == folderTransitionReplica.id
                    )
                    .allowsHitTesting(false)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.9))
                    )
                    .zIndex(viewModel.openFolder != nil ? 9.35 : 2.1)

                    FolderSourceReplicaView(
                        app: folderTransitionReplica,
                        sourceRect: folderSourceRect,
                        scale: layout.gridMetrics.iconScale,
                        isExpanded: viewModel.openFolder?.id == folderTransitionReplica.id
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(viewModel.openFolder != nil ? 9.45 : 2.2)
                }

                if let folder = viewModel.openFolder {
                    let folderFrame = folderTrayFrame(metrics: layout.folder, in: geometry.size)

                    Color.black.opacity(0.34)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(9)

                    ForEach(Array(outsideFolderRegions(around: folderFrame, in: geometry.size).enumerated()), id: \.offset) { entry in
                        let region = entry.element

                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: region.width, height: region.height)
                            .position(x: region.midX, y: region.midY)
                            .contentShape(Rectangle())
                            .zIndex(9.1)
                            .onTapGesture {
                                closeOpenFolder()
                            }
                            .dropDestination(for: String.self) { items, _ in
                                return handleOutsideFolderDrop(items: items, from: folder)
                            }
                    }

                    FolderView(
                        folder: folder,
                        metrics: layout.folder,
                        containerSize: geometry.size,
                        sourceRect: folderSourceRect,
                        selectedAppID: selectedAppID,
                        isEditing: viewModel.isEditing,
                        onAppTap: { app in
                            selectedAppID = app.id
                            if viewModel.isEditing {
                                return
                            }
                            launchApplicationAndHide(app)
                            closeOpenFolder()
                        },
                        onClose: {
                            closeOpenFolder()
                        },
                        onRename: { newName in
                            viewModel.renameFolder(folder, to: newName)
                        },
                        canDelete: { app in
                            viewModel.canUninstall(app)
                        },
                        onDeleteRequested: { app in
                            requestUninstall(app)
                        },
                        onMoveApp: { appID, destinationIndex in
                            viewModel.reorderApp(withID: appID, inFolder: folder.id, to: destinationIndex)
                            if let moved = viewModel.app(withID: appID) {
                                selectedAppID = moved.id
                                return true
                            }
                            return false
                        },
                        onRemoveFromFolder: { app in
                            viewModel.removeFromFolder(app, from: folder)
                            closeOpenFolder()
                        },
                        onNameEditingChanged: { isEditing in
                            isFolderNameEditing = isEditing
                            if isEditing {
                                selectedAppID = nil
                            }
                        }
                    )
                    .transition(folderTransition(in: geometry.size))
                    .zIndex(10)
                }
            }
            .coordinateSpace(name: "launchpadRoot")
        }
        .onAppear {
            pageMotion.offset = 0
            pageMotion.dragPreviewDirection = 0
            pageMotion.dragPreviewProgress = 0
            viewModel.ensureLayoutIntegrity(resetToFirstPage: true)
            syncSelection()
        }
        .onChange(of: viewModel.currentPage) { oldPage, newPage in
            pageMotion.offset = 0
            pageMotion.dragPreviewDirection = 0
            pageMotion.dragPreviewProgress = 0
            triggerPageLanding(from: oldPage, to: newPage)
            syncSelection()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            syncSelection()
        }
        .onChange(of: viewModel.openFolder?.id) { _, _ in
            syncSelection()
        }
        .onChange(of: viewModel.applications) { _, _ in
            syncSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rLaunchPadWillHide)) { _ in
            resetTransientPresentationState()
        }
        .confirmationDialog(
            "卸载应用",
            isPresented: Binding(
                get: { pendingUninstallApp != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingUninstallApp = nil
                    }
                }
            ),
            presenting: pendingUninstallApp
        ) { app in
            Button("移到废纸篓", role: .destructive) {
                confirmUninstall(app)
            }
            Button("取消", role: .cancel) {}
        } message: { app in
            Text("会尝试将“\(app.name)”移到废纸篓。")
        }
        .alert(
            "无法卸载",
            isPresented: Binding(
                get: { uninstallErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        uninstallErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {}
        } message: {
            Text(uninstallErrorMessage ?? "")
        }
        .onKeyPress(.escape) {
            if isFolderNameEditing {
                return .ignored
            }
            if viewModel.openFolder != nil {
                closeOpenFolder()
                return .handled
            }

            NotificationCenter.default.post(name: .rLaunchPadHideRequested, object: nil)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if isFolderNameEditing {
                return .ignored
            }
            moveSelection(.left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if isFolderNameEditing {
                return .ignored
            }
            moveSelection(.right)
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isFolderNameEditing {
                return .ignored
            }
            moveSelection(.up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            if isFolderNameEditing {
                return .ignored
            }
            moveSelection(.down)
            return .handled
        }
        .onKeyPress(.return) {
            if isFolderNameEditing {
                return .ignored
            }
            activateSelection()
            return .handled
        }
    }

    private func pageView(layout: LaunchPadLayout.SceneMetrics) -> some View {
        GeometryReader { geometry in
            TrackpadScrollView(
                accumulatedScroll: $accumulatedScroll,
                pageWidth: geometry.size.width,
                currentPage: viewModel.currentPage,
                totalPages: viewModel.totalPages,
                isInteractionEnabled: { viewModel.draggedApp == nil },
                onOffsetChanged: { offset in
                    pageMotion.offset = offset
                    updateTrackpadPagePreview(offset: offset, pageWidth: geometry.size.width)
                },
                onScrollEnded: { totalOffset, velocity in
                    handleTrackpadEnd(
                        totalOffset: totalOffset,
                        velocity: velocity,
                        screenWidth: geometry.size.width
                    )
                }
            ) {
                PagedGridContent(
                    viewModel: viewModel,
                    pageWidth: geometry.size.width,
                    motion: pageMotion,
                    onAppTap: handleAppTap,
                    openFolder: viewModel.openFolder,
                    selectedAppID: selectedAppID,
                    onDeleteRequested: requestUninstall,
                    onFolderAutoOpen: openFolderFromHover,
                    dragPreviewMetrics: layout.dragPreview
                )
            }
            .clipped()
        }
    }

    private func handleTrackpadEnd(totalOffset: CGFloat, velocity: CGFloat, screenWidth: CGFloat) {
        guard viewModel.draggedApp == nil else {
            pageMotion.offset = 0
            return
        }

        let isFastFlick = abs(velocity) > screenWidth * 0.95
        let threshold = screenWidth * (isFastFlick ? 0.062 : 0.1)
        let projectedTravel = totalOffset + velocity * (isFastFlick ? 0.2 : 0.16)
        let now = Date().timeIntervalSinceReferenceDate
        let canFlip = now - lastTrackpadPageTurnAt >= 0.16

        withAnimation(LaunchPadMotion.pageSnap) {
            if canFlip, projectedTravel < -threshold {
                if viewModel.currentPage < viewModel.totalPages - 1 {
                    viewModel.currentPage += 1
                    lastTrackpadPageTurnAt = now
                }
            } else if canFlip, projectedTravel > threshold {
                if viewModel.currentPage > 0 {
                    viewModel.currentPage -= 1
                    lastTrackpadPageTurnAt = now
                }
            }
            pageMotion.offset = 0
            pageMotion.dragPreviewDirection = 0
            pageMotion.dragPreviewProgress = 0
        }
    }

    private func searchResultsView(layout: LaunchPadLayout.SceneMetrics) -> some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(layout.searchResults.cellWidth), spacing: layout.searchResults.horizontalSpacing),
                    count: LaunchPadLayout.columns
                ),
                spacing: layout.searchResults.verticalSpacing
            ) {
                ForEach(viewModel.searchResults) { app in
                    AppIconView(
                        app: app,
                        onTap: {
                            handleAppTap(app, sourceRect: nil)
                        },
                        isSelected: selectedAppID == app.id,
                        scale: layout.gridMetrics.iconScale
                    )
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private func handleAppTap(_ app: AppItem, sourceRect: CGRect?) {
        selectedAppID = app.id
        if viewModel.isEditing, app.type == .application {
            return
        }
        folderSourceRect = app.type == .folder ? sourceRect : nil
        if app.type == .folder {
            folderTransitionReplica = app
            viewModel.launchApplication(app)
        } else {
            folderTransitionReplica = nil
            launchApplicationAndHide(app)
        }
    }

    private func closeOpenFolder() {
        let closingFolderID = viewModel.openFolder?.id
        let closingSourceRect = folderSourceRect
        isFolderNameEditing = false
        if let openFolder = viewModel.openFolder {
            folderTransitionReplica = openFolder
        }
        viewModel.draggedApp = nil
        withAnimation(LaunchPadMotion.folderClose) {
            viewModel.openFolder = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard viewModel.openFolder == nil, folderSourceRect == closingSourceRect else { return }
            folderSourceRect = nil
            folderTransitionReplica = nil
        }
        syncSelection(preferredID: closingFolderID)
    }

    private func openFolderFromHover(_ folder: AppItem) {
        guard viewModel.draggedApp != nil else { return }
        isFolderNameEditing = false
        folderSourceRect = nil
        folderTransitionReplica = nil
        withAnimation(LaunchPadMotion.folderOpen) {
            viewModel.openFolder = folder
        }
        selectedAppID = nil
    }

    private func toggleEditingMode() {
        withAnimation(LaunchPadMotion.selectionFocus) {
            let nextEditing = !viewModel.isEditing
            viewModel.setEditing(nextEditing)
            if nextEditing {
                viewModel.searchText = ""
            }
        }
    }

    private func requestUninstall(_ app: AppItem) {
        selectedAppID = app.id
        pendingUninstallApp = app
    }

    private func launchApplicationAndHide(_ app: AppItem) {
        viewModel.launchApplication(app)
        NotificationCenter.default.post(name: .rLaunchPadHideRequested, object: nil)
    }

    private func updateTrackpadPagePreview(offset: CGFloat, pageWidth: CGFloat) {
        guard pageWidth > 0 else {
            pageMotion.dragPreviewDirection = 0
            pageMotion.dragPreviewProgress = 0
            return
        }

        let direction = offset > 0 ? -1 : (offset < 0 ? 1 : 0)
        let targetPage = viewModel.currentPage + direction
        guard direction != 0, (0..<viewModel.totalPages).contains(targetPage) else {
            pageMotion.dragPreviewDirection = 0
            pageMotion.dragPreviewProgress = 0
            return
        }

        pageMotion.dragPreviewDirection = direction
        pageMotion.dragPreviewProgress = min(max(abs(offset) / max(pageWidth * 0.24, 1), 0), 1)
    }

    private func triggerPageLanding(from oldPage: Int, to newPage: Int) {
        guard oldPage != newPage else {
            pageMotion.settleDirection = 0
            pageMotion.settleProgress = 0
            return
        }

        pageMotion.settleDirection = newPage > oldPage ? 1 : -1
        pageMotion.settleProgress = 1

        withAnimation(LaunchPadMotion.pageLanding) {
            pageMotion.settleProgress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            guard pageMotion.settleProgress < 0.01 else { return }
            pageMotion.settleDirection = 0
        }
    }

    private func confirmUninstall(_ app: AppItem) {
        pendingUninstallApp = nil
        do {
            try viewModel.uninstallApplication(app)
            if selectedAppID == app.id {
                selectedAppID = nil
            }
            pendingUninstallApp = nil
            syncSelection()
        } catch {
            uninstallErrorMessage = error.localizedDescription
        }
    }

    private func syncSelection(preferredID: UUID? = nil) {
        let context = currentSelectionContext()
        guard !context.items.isEmpty else {
            selectedAppID = nil
            return
        }

        if let preferredID,
           context.items.contains(where: { $0.id == preferredID }) {
            selectedAppID = preferredID
            return
        }

        if let selectedAppID,
           context.items.contains(where: { $0.id == selectedAppID }) {
            return
        }

        selectedAppID = nil
    }

    private func moveSelection(_ direction: KeyboardNavigationDirection) {
        let context = currentSelectionContext()
        guard !context.items.isEmpty else { return }

        guard let currentIndex = context.items.firstIndex(where: { $0.id == selectedAppID }) else {
            selectedAppID = context.items.first?.id
            return
        }

        switch direction {
        case .left:
            if currentIndex > 0 {
                selectedAppID = context.items[currentIndex - 1].id
            } else if context.scope == .page {
                moveSelectionAcrossPages(direction: -1)
            }

        case .right:
            if currentIndex < context.items.count - 1 {
                selectedAppID = context.items[currentIndex + 1].id
            } else if context.scope == .page {
                moveSelectionAcrossPages(direction: 1)
            }

        case .up:
            let targetIndex = max(currentIndex - context.columns, 0)
            selectedAppID = context.items[targetIndex].id

        case .down:
            let targetIndex = min(currentIndex + context.columns, context.items.count - 1)
            selectedAppID = context.items[targetIndex].id
        }
    }

    private func moveSelectionAcrossPages(direction: Int) {
        let targetPage = viewModel.currentPage + direction
        guard (0..<viewModel.totalPages).contains(targetPage) else { return }

        let targetItems = viewModel.applications(onPage: targetPage)
        guard let target = direction < 0 ? targetItems.last : targetItems.first else { return }

        withAnimation(LaunchPadMotion.pageArrowStep) {
            viewModel.currentPage = targetPage
        }
        selectedAppID = target.id
    }

    private func activateSelection() {
        let context = currentSelectionContext()
        guard let selected = context.items.first(where: { $0.id == selectedAppID }) else {
            return
        }

        handleAppTap(selected, sourceRect: nil)
        if viewModel.openFolder != nil, selected.type == .application, !viewModel.isEditing {
            closeOpenFolder()
        }
    }

    private func currentSelectionContext() -> KeyboardSelectionContext {
        if let folder = viewModel.openFolder {
            return KeyboardSelectionContext(
                items: folder.folderItems ?? [],
                columns: 4,
                scope: .folder
            )
        }

        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return KeyboardSelectionContext(
                items: viewModel.searchResults,
                columns: LaunchPadLayout.columns,
                scope: .search
            )
        }

        return KeyboardSelectionContext(
            items: viewModel.applications(onPage: viewModel.currentPage),
            columns: LaunchPadLayout.columns,
            scope: .page
        )
    }

    private var topLevelPreviewPage: Int? {
        let targetPage = viewModel.currentPage + pageMotion.dragPreviewDirection
        guard pageMotion.dragPreviewDirection != 0,
              (0..<viewModel.totalPages).contains(targetPage) else {
            return nil
        }
        return targetPage
    }

    private var topLevelPreviewProgress: CGFloat {
        min(max(pageMotion.dragPreviewProgress, 0), 1)
    }

    private func resetTransientPresentationState() {
        pageMotion.offset = 0
        pageMotion.dragPreviewDirection = 0
        pageMotion.dragPreviewProgress = 0
        pageMotion.settleDirection = 0
        pageMotion.settleProgress = 0
        accumulatedScroll = 0
        viewModel.draggedApp = nil
        viewModel.openFolder = nil
        folderSourceRect = nil
        folderTransitionReplica = nil
        viewModel.searchText = ""
        pendingUninstallApp = nil
        uninstallErrorMessage = nil
        isFolderNameEditing = false
        syncSelection()
    }

    private func folderTransition(in containerSize: CGSize) -> AnyTransition {
        let geometry = folderTransitionGeometry(in: containerSize)
        return .asymmetric(
            insertion: .modifier(
                active: FolderPresentationModifier(
                    geometry: geometry,
                    progress: 0,
                    entryScale: 0.9,
                    blurRadius: 8,
                    saturation: 0.82,
                    extraLift: 14
                ),
                identity: FolderPresentationModifier(
                    geometry: geometry,
                    progress: 1,
                    entryScale: 0.9,
                    blurRadius: 8,
                    saturation: 0.82,
                    extraLift: 14
                )
            ),
            removal: .modifier(
                active: FolderPresentationModifier(
                    geometry: geometry,
                    progress: 0,
                    entryScale: 0.975,
                    blurRadius: 4,
                    saturation: 0.9,
                    extraLift: 8
                ),
                identity: FolderPresentationModifier(
                    geometry: geometry,
                    progress: 1,
                    entryScale: 0.975,
                    blurRadius: 4,
                    saturation: 0.9,
                    extraLift: 8
                )
            )
        )
    }

    private func folderTransitionGeometry(in containerSize: CGSize) -> FolderTransitionGeometry {
        guard let rect = folderSourceRect, containerSize.width > 0, containerSize.height > 0 else {
            return FolderTransitionGeometry(anchor: .center, offset: CGSize(width: 0, height: 10))
        }

        let sourceCenter = CGPoint(x: rect.midX, y: rect.midY)
        let anchor = UnitPoint(
            x: min(max(sourceCenter.x / containerSize.width, 0), 1),
            y: min(max(sourceCenter.y / containerSize.height, 0), 1)
        )
        let offset = CGSize(
            width: (sourceCenter.x - containerSize.width / 2) * 0.08,
            height: (sourceCenter.y - containerSize.height / 2) * 0.08
        )
        return FolderTransitionGeometry(anchor: anchor, offset: offset)
    }

    private func backgroundRetreatOffset(in containerSize: CGSize) -> CGSize {
        guard viewModel.openFolder != nil else { return .zero }
        let geometry = folderTransitionGeometry(in: containerSize)
        return CGSize(
            width: -geometry.offset.width * 0.26,
            height: -geometry.offset.height * 0.22 + 4
        )
    }

    private func folderTrayFrame(metrics: LaunchPadLayout.FolderMetrics, in containerSize: CGSize) -> CGRect {
        let originX = (containerSize.width - metrics.width) / 2
        let minTop = metrics.minTopMargin
        let maxTop = max(containerSize.height - metrics.height - metrics.bottomMargin, minTop)
        let defaultTop = min(
            max((containerSize.height - metrics.height) * 0.46, minTop),
            maxTop
        )

        return CGRect(x: originX, y: defaultTop, width: metrics.width, height: metrics.height)
    }

    private func outsideFolderRegions(around folderFrame: CGRect, in containerSize: CGSize) -> [CGRect] {
        let fullFrame = CGRect(origin: .zero, size: containerSize)
        let top = CGRect(x: 0, y: 0, width: fullFrame.width, height: max(folderFrame.minY, 0))
        let bottom = CGRect(
            x: 0,
            y: max(folderFrame.maxY, 0),
            width: fullFrame.width,
            height: max(fullFrame.maxY - folderFrame.maxY, 0)
        )
        let left = CGRect(
            x: 0,
            y: max(folderFrame.minY, 0),
            width: max(folderFrame.minX, 0),
            height: max(folderFrame.height, 0)
        )
        let right = CGRect(
            x: max(folderFrame.maxX, 0),
            y: max(folderFrame.minY, 0),
            width: max(fullFrame.maxX - folderFrame.maxX, 0),
            height: max(folderFrame.height, 0)
        )

        return [top, bottom, left, right].filter { $0.width > 0.5 && $0.height > 0.5 }
    }

    private func handleOutsideFolderDrop(items: [String], from folder: AppItem) -> Bool {
        guard let idString = items.first,
              let uuid = UUID(uuidString: idString),
              let app = folder.folderItems?.first(where: { $0.id == uuid }) else {
            return false
        }

        viewModel.removeFromFolder(app, from: folder)
        closeOpenFolder()
        return true
    }
}

private struct PagedGridContent: View {
    @ObservedObject var viewModel: LaunchPadViewModel
    let pageWidth: CGFloat
    @ObservedObject var motion: PageMotionState
    let onAppTap: (AppItem, CGRect?) -> Void
    let openFolder: AppItem?
    let selectedAppID: UUID?
    let onDeleteRequested: (AppItem) -> Void
    let onFolderAutoOpen: (AppItem) -> Void
    let dragPreviewMetrics: LaunchPadLayout.DragPreviewMetrics

    var body: some View {
        let totalPages = max(viewModel.totalPages, 1)

        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(0..<totalPages, id: \.self) { page in
                    pageContent(page)
                        .frame(width: pageWidth)
                        .scaleEffect(scale(for: page))
                        .opacity(opacity(for: page))
                        .offset(x: horizontalOffset(for: page))
                        .offset(y: verticalOffset(for: page))
                        .rotation3DEffect(
                            .degrees(rotation(for: page)),
                            axis: (x: 0, y: 1, z: 0),
                            anchor: page <= viewModel.currentPage ? .trailing : .leading,
                            perspective: 0.78
                        )
                        .animation(LaunchPadMotion.pageLayerDrift, value: viewModel.currentPage)
                        .animation(LaunchPadMotion.pageLanding, value: motion.settleProgress)
                }
            }
            .frame(width: pageWidth * CGFloat(totalPages), alignment: .leading)
            .offset(x: -CGFloat(viewModel.currentPage) * pageWidth + motion.offset)

            PageTurnPreviewOverlay(
                currentPage: viewModel.currentPage,
                totalPages: totalPages,
                pageWidth: pageWidth,
                motion: motion
            )
        }
        .frame(width: pageWidth, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func pageContent(_ page: Int) -> some View {
        let shouldRenderGrid = abs(page - viewModel.currentPage) <= 1

        if shouldRenderGrid {
            LaunchPadGridView(
                apps: viewModel.applications,
                page: page,
                onAppTap: onAppTap,
                onAppMove: { app, position, targetPage in
                    viewModel.moveApplication(from: app, to: position, page: targetPage)
                },
                onCreateFolder: { app1, app2 in
                    viewModel.createFolder(with: [app1, app2])
                },
                onAddToFolder: { app, folder in
                    viewModel.addToFolder(app, folder: folder)
                },
                onInsertApp: { app, position, targetPage in
                    viewModel.insertApplication(app, at: position, page: targetPage)
                },
                onHoverPageTurnChanged: { direction, progress in
                    updateDragPageTurnPreview(direction: direction, progress: progress)
                },
                onHoverPageTurnCommit: { direction in
                    requestDragPageTurn(direction: direction)
                },
                openFolder: openFolder,
                selectedAppID: selectedAppID,
                isEditing: viewModel.isEditing,
                canDelete: { app in
                    viewModel.canUninstall(app)
                },
                onDeleteRequested: onDeleteRequested,
                onFolderAutoOpen: onFolderAutoOpen,
                dragPreviewMetrics: dragPreviewMetrics,
                draggedApp: $viewModel.draggedApp
            )
            .disabled(page != viewModel.currentPage)
        } else {
            Color.clear
        }
    }

    private func requestDragPageTurn(direction: Int) {
        guard viewModel.draggedApp != nil else { return }
        let nextPage = viewModel.currentPage + direction
        guard (0..<viewModel.totalPages).contains(nextPage) else { return }

        withAnimation(LaunchPadMotion.pageSnap) {
            motion.offset = 0
            motion.dragPreviewDirection = 0
            motion.dragPreviewProgress = 0
            viewModel.currentPage = nextPage
        }
    }

    private func updateDragPageTurnPreview(direction: Int, progress: CGFloat) {
        guard viewModel.draggedApp != nil else {
            motion.offset = 0
            motion.dragPreviewDirection = 0
            motion.dragPreviewProgress = 0
            return
        }

        let clampedProgress = min(max(progress, 0), 1)
        let previewDistance = pageWidth * 0.24 * clampedProgress
        let targetOffset = direction == 0 ? 0 : -CGFloat(direction) * previewDistance
        motion.dragPreviewDirection = direction
        motion.dragPreviewProgress = clampedProgress

        if direction == 0 {
            withAnimation(LaunchPadMotion.pageEdgeIndicator) {
                motion.offset = 0
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                motion.offset = targetOffset
            }
        }
    }

    private func swipeDirection() -> Int {
        motion.offset > 0 ? -1 : (motion.offset < 0 ? 1 : 0)
    }

    private func swipeProgress() -> CGFloat {
        min(max(abs(motion.offset) / max(pageWidth * 0.96, 1), 0), 1)
    }

    private func prominence(for page: Int) -> CGFloat {
        let direction = swipeDirection()
        let progress = swipeProgress()
        let landingProgress = min(max(motion.settleProgress, 0), 1)

        if page == viewModel.currentPage {
            return min(1.12, 1 - 0.38 * progress + 0.14 * landingProgress)
        }

        if direction != 0, page == viewModel.currentPage + direction {
            return 0.62 + 0.38 * progress
        }

        if motion.settleDirection != 0, page == viewModel.currentPage - motion.settleDirection {
            return max(0.42, 0.58 - 0.12 * landingProgress)
        }

        if abs(page - viewModel.currentPage) == 1 {
            return 0.56
        }

        return 0.5
    }

    private func scale(for page: Int) -> CGFloat {
        let prominence = prominence(for: page)
        return 0.972 + prominence * 0.028
    }

    private func opacity(for page: Int) -> CGFloat {
        let prominence = prominence(for: page)
        return 0.56 + prominence * 0.44
    }

    private func verticalOffset(for page: Int) -> CGFloat {
        let prominence = prominence(for: page)
        let landingProgress = min(max(motion.settleProgress, 0), 1)

        if page == viewModel.currentPage {
            return (1 - prominence) * 12 - landingProgress * 5
        }

        if motion.settleDirection != 0, page == viewModel.currentPage - motion.settleDirection {
            return (1 - prominence) * 12 + landingProgress * 3
        }

        return (1 - prominence) * 12
    }

    private func horizontalOffset(for page: Int) -> CGFloat {
        let landingProgress = min(max(motion.settleProgress, 0), 1)
        guard motion.settleDirection != 0, landingProgress > 0.001 else { return 0 }

        if page == viewModel.currentPage {
            return -CGFloat(motion.settleDirection) * 12 * landingProgress
        }

        if page == viewModel.currentPage - motion.settleDirection {
            return -CGFloat(motion.settleDirection) * 7 * landingProgress
        }

        return 0
    }

    private func rotation(for page: Int) -> Double {
        let direction = swipeDirection()
        let progress = swipeProgress()
        let landingProgress = min(max(motion.settleProgress, 0), 1)
        var degrees: Double = 0

        if page == viewModel.currentPage {
            degrees += Double(direction) * 2.2 * Double(progress)
            degrees += Double(motion.settleDirection) * 1.2 * Double(landingProgress)
        } else if direction != 0, page == viewModel.currentPage + direction {
            degrees += Double(direction) * 2.8 * Double(1 - progress)
        } else if motion.settleDirection != 0, page == viewModel.currentPage - motion.settleDirection {
            degrees += Double(motion.settleDirection) * 0.9 * Double(landingProgress)
        }

        return degrees
    }
}

final class PageMotionState: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var dragPreviewDirection: Int = 0
    @Published var dragPreviewProgress: CGFloat = 0
    @Published var settleDirection: Int = 0
    @Published var settleProgress: CGFloat = 0
}

private enum KeyboardNavigationDirection {
    case left
    case right
    case up
    case down
}

private enum KeyboardSelectionScope {
    case page
    case search
    case folder
}

private struct KeyboardSelectionContext {
    let items: [AppItem]
    let columns: Int
    let scope: KeyboardSelectionScope
}

private struct FolderTransitionGeometry {
    let anchor: UnitPoint
    let offset: CGSize
}

private struct FolderPresentationModifier: ViewModifier {
    let geometry: FolderTransitionGeometry
    let progress: CGFloat
    let entryScale: CGFloat
    let blurRadius: CGFloat
    let saturation: CGFloat
    let extraLift: CGFloat

    func body(content: Content) -> some View {
        let clampedProgress = min(max(progress, 0), 1)
        let scale = entryScale + (1 - entryScale) * clampedProgress
        let offset = CGSize(
            width: geometry.offset.width * (1 - clampedProgress),
            height: geometry.offset.height * (1 - clampedProgress) + (1 - clampedProgress) * extraLift
        )

        content
            .scaleEffect(scale, anchor: geometry.anchor)
            .offset(offset)
            .opacity(max(0.001, pow(clampedProgress, 0.88)))
            .blur(radius: blurRadius * (1 - clampedProgress))
            .saturation(saturation + (1 - saturation) * clampedProgress)
            .brightness(0.035 * (1 - clampedProgress))
    }
}

private struct FolderSourceHaloView: View {
    let sourceRect: CGRect
    let isExpanded: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: max(sourceRect.width * 1.16, 110),
                    height: max(sourceRect.height * 1.08, 92)
                )
                .blur(radius: 18)

            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.9)
                .frame(
                    width: max(sourceRect.width * 0.92, 84),
                    height: max(sourceRect.height * 0.72, 68)
                )
        }
        .scaleEffect(isExpanded ? 1.08 : 1)
        .opacity(isExpanded ? 0.95 : 0.52)
        .position(x: sourceRect.midX, y: sourceRect.midY - 4)
        .animation(LaunchPadMotion.folderSourceRebound, value: isExpanded)
    }
}

private struct FolderSourceReplicaView: View {
    let app: AppItem
    let sourceRect: CGRect
    let scale: CGFloat
    let isExpanded: Bool

    var body: some View {
        AppIconView(
            app: app,
            onTap: nil,
            scale: scale
        )
        .scaleEffect(isExpanded ? 0.8 : 1)
        .opacity(isExpanded ? 0.14 : 1)
        .blur(radius: isExpanded ? 3.6 : 0)
        .offset(y: isExpanded ? 10 : 0)
        .position(x: sourceRect.midX, y: sourceRect.midY)
        .compositingGroup()
        .animation(LaunchPadMotion.folderSourceRebound, value: isExpanded)
    }
}

private struct PageTurnPreviewOverlay: View {
    let currentPage: Int
    let totalPages: Int
    let pageWidth: CGFloat
    @ObservedObject var motion: PageMotionState

    var body: some View {
        HStack(spacing: 0) {
            edgeIndicator(direction: -1)
            Spacer(minLength: 0)
            edgeIndicator(direction: 1)
        }
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func edgeIndicator(direction: Int) -> some View {
        let canTurn = direction < 0 ? currentPage > 0 : currentPage < totalPages - 1
        let progress = previewProgress(for: direction)
        let isVisible = progress > 0.01

        Rectangle()
            .fill(Color.clear)
            .frame(width: min(max(pageWidth * 0.12, 76), 116))
            .overlay(alignment: direction < 0 ? .leading : .trailing) {
                if isVisible {
                    ZStack(alignment: direction < 0 ? .leading : .trailing) {
                        LinearGradient(
                            colors: direction < 0
                                ? [Color.white.opacity((canTurn ? 0.18 : 0.1) * progress), Color.clear]
                                : [Color.clear, Color.white.opacity((canTurn ? 0.18 : 0.1) * progress)],
                            startPoint: direction < 0 ? .leading : .trailing,
                            endPoint: direction < 0 ? .trailing : .leading
                        )

                        Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(canTurn ? 0.86 * progress : 0))
                            .padding(direction < 0 ? .leading : .trailing, 12)
                    }
                    .transition(.opacity)
                }
            }
            .animation(LaunchPadMotion.pageEdgeIndicator, value: progress)
    }

    private func previewProgress(for direction: Int) -> CGFloat {
        let dragProgress = motion.dragPreviewDirection == direction ? motion.dragPreviewProgress : 0
        let trackpadDirection = motion.offset > 0 ? -1 : (motion.offset < 0 ? 1 : 0)
        let trackpadProgress = trackpadDirection == direction
            ? min(max(abs(motion.offset) / max(pageWidth * 0.24, 1), 0), 1)
            : 0
        return max(dragProgress, trackpadProgress)
    }
}

private struct WindowReporterView: NSViewRepresentable {
    final class Coordinator {
        weak var reportedWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            reportWindow(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            reportWindow(from: nsView, coordinator: context.coordinator)
        }
    }

    private func reportWindow(from view: NSView?, coordinator: Coordinator) {
        guard let window = view?.window else { return }
        guard coordinator.reportedWindow !== window else { return }
        coordinator.reportedWindow = window
        NotificationCenter.default.post(name: .rLaunchPadWindowDiscovered, object: window)
    }
}

struct TrackpadScrollView<Content: View>: NSViewRepresentable {
    @Binding var accumulatedScroll: CGFloat
    let pageWidth: CGFloat
    let currentPage: Int
    let totalPages: Int
    let isInteractionEnabled: () -> Bool
    let onOffsetChanged: (CGFloat) -> Void
    let onScrollEnded: (CGFloat, CGFloat) -> Void
    let content: () -> Content

    func makeNSView(context: Context) -> TrackpadScrollNSView<Content> {
        let view = TrackpadScrollNSView<Content>()
        view.accumulatedScroll = accumulatedScroll
        view.pageWidth = pageWidth
        view.currentPage = currentPage
        view.totalPages = totalPages
        view.isInteractionEnabled = isInteractionEnabled
        view.onOffsetChanged = onOffsetChanged
        view.onScrollEnded = onScrollEnded
        view.hostingView = NSHostingView(rootView: content())
        view.addSubview(view.hostingView!)
        return view
    }

    func updateNSView(_ nsView: TrackpadScrollNSView<Content>, context: Context) {
        nsView.pageWidth = pageWidth
        nsView.currentPage = currentPage
        nsView.totalPages = totalPages
        nsView.isInteractionEnabled = isInteractionEnabled
        nsView.onOffsetChanged = onOffsetChanged
        nsView.onScrollEnded = onScrollEnded
        nsView.hostingView?.rootView = content()
        nsView.hostingView?.frame = nsView.bounds
    }
}

class TrackpadScrollNSView<Content: View>: NSView {
    var accumulatedScroll: CGFloat = 0
    var pageWidth: CGFloat = 0
    var currentPage: Int = 0
    var totalPages: Int = 1
    var isInteractionEnabled: (() -> Bool)?
    var onOffsetChanged: ((CGFloat) -> Void)?
    var onScrollEnded: ((CGFloat, CGFloat) -> Void)?
    var hostingView: NSHostingView<Content>?

    private var hasActiveScroll = false
    private var smoothedVelocityX: CGFloat = 0
    private var lastEventTimestamp: TimeInterval?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    override func layout() {
        super.layout()
        if hostingView?.frame != bounds {
            hostingView?.frame = bounds
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard isInteractionEnabled?() ?? true else { return }
        guard abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) else { return }

        if event.phase == .began {
            hasActiveScroll = true
            accumulatedScroll = 0
            smoothedVelocityX = 0
            lastEventTimestamp = event.timestamp
            onOffsetChanged?(0)
            return
        }

        if event.phase == .changed {
            applyDelta(event.scrollingDeltaX, timestamp: event.timestamp)
            return
        }

        if event.phase == .ended || event.phase == .cancelled {
            finishScrollIfNeeded()
            return
        }

        if event.phase == [] {
            if event.momentumPhase == .began {
                finishScrollIfNeeded()
                return
            }
            if event.momentumPhase == .changed {
                return
            }
            if event.momentumPhase == .ended {
                finishScrollIfNeeded()
            }
        }
    }

    private func applyDelta(_ deltaX: CGFloat, timestamp: TimeInterval) {
        hasActiveScroll = true

        if let lastEventTimestamp {
            let deltaTime = max(timestamp - lastEventTimestamp, 1.0 / 240.0)
            let instantVelocity = deltaX / CGFloat(deltaTime)
            smoothedVelocityX = smoothedVelocityX == 0
                ? instantVelocity
                : smoothedVelocityX * 0.64 + instantVelocity * 0.36
        }

        lastEventTimestamp = timestamp
        accumulatedScroll += deltaX
        let displayedOffset = resolvedDisplayedOffset(for: accumulatedScroll)
        onOffsetChanged?(displayedOffset)
    }

    private func finishScrollIfNeeded() {
        guard hasActiveScroll else { return }
        hasActiveScroll = false

        onScrollEnded?(accumulatedScroll, smoothedVelocityX)
        accumulatedScroll = 0
        smoothedVelocityX = 0
        lastEventTimestamp = nil
        onOffsetChanged?(0)
    }

    private func resolvedDisplayedOffset(for rawOffset: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return rawOffset }

        let canMoveToPrevious = currentPage > 0
        let canMoveToNext = currentPage < max(totalPages - 1, 0)

        if (rawOffset > 0 && !canMoveToPrevious) || (rawOffset < 0 && !canMoveToNext) {
            let edgeLimit = pageWidth * 0.18
            let normalized = min(abs(rawOffset) / max(pageWidth * 0.32, 1), 1.6)
            let resisted = edgeLimit * (1 - exp(-normalized))
            return rawOffset.sign == .minus ? -resisted : resisted
        }

        let travelLimit = max(pageWidth * 0.94, 1)
        let normalized = abs(rawOffset) / travelLimit
        let softened = travelLimit * tanh(normalized * 0.9)
        return rawOffset.sign == .minus ? -softened : softened
    }

    override var acceptsFirstResponder: Bool { true }
}

#Preview {
    ContentView()
}
