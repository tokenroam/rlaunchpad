import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LaunchPadGridView: View {
    let apps: [AppItem]
    let page: Int
    let onAppTap: (AppItem, CGRect?) -> Void
    let onAppMove: (AppItem, Int, Int) -> Void
    let onCreateFolder: (AppItem, AppItem) -> Void
    let onAddToFolder: (AppItem, AppItem) -> Void
    let onInsertApp: (AppItem, Int, Int) -> Void
    let onHoverPageTurnChanged: (Int, CGFloat) -> Void
    let onHoverPageTurnCommit: (Int) -> Void
    let openFolder: AppItem?
    let selectedAppID: UUID?
    let isEditing: Bool
    let canDelete: (AppItem) -> Bool
    let onDeleteRequested: (AppItem) -> Void
    let onFolderAutoOpen: (AppItem) -> Void
    let dragPreviewMetrics: LaunchPadLayout.DragPreviewMetrics

    @Binding var draggedApp: AppItem?

    private var pageApps: [AppItem] {
        apps
            .filter { $0.page == page }
            .sorted { $0.position < $1.position }
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = LaunchPadLayout.pageGridMetrics(in: geometry.size)

            GridContent(
                pageApps: pageApps,
                page: page,
                columns: LaunchPadLayout.columns,
                rows: LaunchPadLayout.rows,
                cellWidth: metrics.cellWidth,
                cellHeight: metrics.cellHeight,
                horizontalSpacing: metrics.horizontalSpacing,
                verticalSpacing: metrics.verticalSpacing,
                gridWidth: metrics.gridWidth,
                gridHeight: metrics.gridHeight,
                paddingX: metrics.paddingX,
                paddingY: metrics.paddingY,
                viewWidth: geometry.size.width,
                iconScale: metrics.iconScale,
                draggedApp: $draggedApp,
                onAppTap: onAppTap,
                onAppMove: onAppMove,
                onCreateFolder: onCreateFolder,
                onAddToFolder: onAddToFolder,
                onInsertApp: onInsertApp,
                onHoverPageTurnChanged: onHoverPageTurnChanged,
                onHoverPageTurnCommit: onHoverPageTurnCommit,
                openFolder: openFolder,
                selectedAppID: selectedAppID,
                isEditing: isEditing,
                canDelete: canDelete,
                onDeleteRequested: onDeleteRequested,
                onFolderAutoOpen: onFolderAutoOpen,
                dragPreviewMetrics: dragPreviewMetrics
            )
        }
    }
}

private enum GridDropContext {
    case none
    case insert(Int)
    case folder(AppItem)
}

private struct GridVisualState {
    let context: GridDropContext
    let insertProgress: CGFloat
}

private struct PageTurnHoverState {
    let direction: Int
    let progress: CGFloat
}

private struct GridContent: View {
    let pageApps: [AppItem]
    let page: Int
    let columns: Int
    let rows: Int
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let gridWidth: CGFloat
    let gridHeight: CGFloat
    let paddingX: CGFloat
    let paddingY: CGFloat
    let viewWidth: CGFloat
    let iconScale: CGFloat

    @Binding var draggedApp: AppItem?

    let onAppTap: (AppItem, CGRect?) -> Void
    let onAppMove: (AppItem, Int, Int) -> Void
    let onCreateFolder: (AppItem, AppItem) -> Void
    let onAddToFolder: (AppItem, AppItem) -> Void
    let onInsertApp: (AppItem, Int, Int) -> Void
    let onHoverPageTurnChanged: (Int, CGFloat) -> Void
    let onHoverPageTurnCommit: (Int) -> Void
    let openFolder: AppItem?
    let selectedAppID: UUID?
    let isEditing: Bool
    let canDelete: (AppItem) -> Bool
    let onDeleteRequested: (AppItem) -> Void
    let onFolderAutoOpen: (AppItem) -> Void
    let dragPreviewMetrics: LaunchPadLayout.DragPreviewMetrics

    @State private var insertPosition: Int? = nil
    @State private var insertProgress: CGFloat = 1
    @State private var folderTargetID: UUID? = nil
    @State private var dragPreviewLocation: CGPoint? = nil
    @State private var lastPageTurnAt: TimeInterval = 0
    @State private var committingDropAppID: UUID? = nil
    @State private var folderAutoOpenTask: DispatchWorkItem? = nil
    @State private var pendingFolderAutoOpenID: UUID? = nil

    private var capacity: Int { rows * columns }

    var body: some View {
        ZStack(alignment: .topLeading) {
            appLayer
            if let dragged = draggedApp, let location = dragPreviewLocation {
                DragPreviewView(app: dragged, metrics: dragPreviewMetrics)
                    .position(location)
                    .allowsHitTesting(false)
                    .zIndex(1000)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .transaction { transaction in
            if committingDropAppID != nil {
                transaction.animation = nil
            }
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: GridDropDelegate(
                draggedApp: $draggedApp,
                insertPosition: $insertPosition,
                insertProgress: $insertProgress,
                folderTargetID: $folderTargetID,
                dragPreviewLocation: $dragPreviewLocation,
                committingDropAppID: $committingDropAppID,
                resolveVisualState: { location, dragged in
                    resolveVisualState(at: location, dragged: dragged)
                },
                resolvePageTurnState: { location in
                    resolvePageTurnState(at: location)
                },
                onPageTurnPreviewChanged: { direction, progress in
                    onHoverPageTurnChanged(direction, progress)
                },
                onPageTurnRequested: { direction, progress in
                    requestPageTurnIfNeeded(direction: direction, progress: progress)
                },
                onFolderHoverChanged: { target in
                    updateFolderAutoOpenTarget(target)
                },
                performDropAction: { context, dragged in
                    handlePerformDrop(context: context, dragged: dragged)
                }
            )
        )
        .onDisappear {
            cancelFolderAutoOpen()
        }
    }

    private var appLayer: some View {
        ForEach(pageApps, id: \.id) { app in
            let slot = visualSlot(for: app)
            let isCommittingDrop = committingDropAppID == app.id
            let originalSlot = min(max(app.position, 0), capacity - 1)
            let folderOffset = folderRepulsionOffset(for: app, slot: slot)
            let reorderOffset = reorderPreviewOffset(forOriginalSlot: originalSlot, projectedSlot: slot)

            AppCell(
                app: app,
                scale: iconScale,
                isDragged: draggedApp?.id == app.id,
                isCommittingDrop: isCommittingDrop,
                isFolderTarget: folderTargetID == app.id,
                isOpenedFolder: openFolder?.id == app.id,
                isSelected: selectedAppID == app.id,
                isEditing: isEditing,
                showsDeleteBadge: isEditing && canDelete(app),
                isShifted: slot != originalSlot,
                folderOffset: folderOffset,
                reorderOffset: reorderOffset,
                onTap: { rect in onAppTap(app, rect) },
                onDeleteRequested: {
                    onDeleteRequested(app)
                },
                onDragStart: {
                    draggedApp = app
                }
            )
            .equatable()
            .frame(width: cellWidth, height: cellHeight)
            .position(centerFor(slot: slot))
            .animation(
                (draggedApp != nil && !isCommittingDrop) ? LaunchPadMotion.gridReorder : nil,
                value: slot
            )
        }
    }

    private func handlePerformDrop(context: GridDropContext, dragged: AppItem) {
        switch context {
        case .none:
            let fallbackPosition = dragged.page == page ? dragged.position : pageApps.count
            onAppMove(dragged, min(max(fallbackPosition, 0), capacity), page)

        case .insert(let position):
            onInsertApp(dragged, min(max(position, 0), capacity), page)

        case .folder(let target):
            guard target.id != dragged.id else { return }
            if target.type == .folder {
                onAddToFolder(dragged, target)
            } else if dragged.type == .application && target.type == .application {
                onCreateFolder(target, dragged)
            } else {
                onInsertApp(dragged, target.position, page)
            }
        }
    }

    private func resolveVisualState(at location: CGPoint, dragged: AppItem?) -> GridVisualState {
        guard let dragged else {
            return GridVisualState(context: .none, insertProgress: 1)
        }

        let adjustedX = location.x - paddingX
        let adjustedY = location.y - paddingY

        guard adjustedY >= 0, adjustedY <= gridHeight else {
            return GridVisualState(context: .none, insertProgress: 1)
        }

        let totalCellWidth = cellWidth + horizontalSpacing
        let totalCellHeight = cellHeight + verticalSpacing

        let rawRow = Int(adjustedY / totalCellHeight)
        guard rawRow >= 0 && rawRow < rows else {
            return GridVisualState(context: .none, insertProgress: 1)
        }

        let row = rawRow
        let colFloat = adjustedX / totalCellWidth
        let rawCol = Int(colFloat)

        if rawCol < 0 {
            return GridVisualState(context: .insert(row * columns), insertProgress: 1)
        }

        if rawCol >= columns {
            return GridVisualState(context: .insert(min(row * columns + columns, capacity)), insertProgress: 1)
        }

        let col = rawCol
        let index = row * columns + col

        if let target = pageApps.first(where: { $0.position == index }) {
            if target.id == dragged.id {
                return GridVisualState(context: .none, insertProgress: 1)
            }

            let xInCell = adjustedX - CGFloat(col) * totalCellWidth
            let yInCell = adjustedY - CGFloat(row) * totalCellHeight
            let normalizedX = max(0, min(1, xInCell / cellWidth))
            let normalizedY = max(0, min(1, yInCell / cellHeight))

            let isCenterZone = (0.28...0.72).contains(normalizedX) && (0.16...0.84).contains(normalizedY)
            if isCenterZone,
               target.type == .folder || (dragged.type == .application && target.type == .application) {
                return GridVisualState(context: .folder(target), insertProgress: 1)
            }

            let insertPos = normalizedX < 0.5 ? index : index + 1
            let progress = min(max(abs(normalizedX - 0.5) / 0.5, 0), 1)
            return GridVisualState(context: .insert(insertPos), insertProgress: progress)
        }

        return GridVisualState(context: .insert(index), insertProgress: 1)
    }

    private func visualSlot(for app: AppItem) -> Int {
        let index = min(max(app.position, 0), capacity - 1)

        guard let dragged = draggedApp,
              let insertPosition else {
            return index
        }

        // 被拖拽图标保持原位，仅通过 opacity 表示被提起
        if dragged.id == app.id {
            return index
        }

        let sourcePosition: Int? = dragged.page == page ? dragged.position : nil
        return projectedIndex(for: index, sourcePosition: sourcePosition, insertPosition: insertPosition)
    }

    private func projectedIndex(for index: Int, sourcePosition: Int?, insertPosition: Int) -> Int {
        let safeInsert = min(max(insertPosition, 0), capacity)

        guard let sourcePosition else {
            if index >= safeInsert {
                return min(index + 1, capacity - 1)
            }
            return index
        }

        if sourcePosition == safeInsert {
            return index
        }

        if sourcePosition < safeInsert {
            if index > sourcePosition && index <= safeInsert {
                return index - 1
            }
            return index
        }

        if index >= safeInsert && index < sourcePosition {
            return min(index + 1, capacity - 1)
        }

        return index
    }

    private func centerFor(slot: Int) -> CGPoint {
        let clamped = min(max(slot, 0), capacity - 1)
        let row = clamped / columns
        let col = clamped % columns

        let x = paddingX + CGFloat(col) * (cellWidth + horizontalSpacing) + cellWidth / 2
        let y = paddingY + CGFloat(row) * (cellHeight + verticalSpacing) + cellHeight / 2
        return CGPoint(x: x, y: y)
    }

    private func folderRepulsionOffset(for app: AppItem, slot: Int) -> CGSize {
        guard draggedApp == nil,
              let openFolder,
              openFolder.page == page else {
            return .zero
        }

        if app.id == openFolder.id {
            return .zero
        }

        let sourceSlot = min(max(openFolder.position, 0), capacity - 1)
        let sourceRow = sourceSlot / columns
        let sourceCol = sourceSlot % columns
        let row = slot / columns
        let col = slot % columns

        let deltaX = CGFloat(col - sourceCol)
        let deltaY = CGFloat(row - sourceRow)
        let distance = hypot(deltaX, deltaY)

        guard distance > 0, distance < 2.6 else {
            return .zero
        }

        let strength = pow(1 - distance / 2.6, 1.35)
        let scaleBoost = max(iconScale, 1)
        let unitX = deltaX / distance
        let unitY = deltaY / distance

        return CGSize(
            width: unitX * 24 * strength * scaleBoost,
            height: unitY * 18 * strength * scaleBoost
        )
    }

    private func reorderPreviewOffset(forOriginalSlot originalSlot: Int, projectedSlot: Int) -> CGSize {
        guard draggedApp != nil,
              insertPosition != nil,
              projectedSlot != originalSlot else {
            return .zero
        }

        let progress = min(max(insertProgress, 0), 1)
        let remaining = 1 - progress
        guard remaining > 0 else { return .zero }

        let originalCenter = centerFor(slot: originalSlot)
        let projectedCenter = centerFor(slot: projectedSlot)
        return CGSize(
            width: (originalCenter.x - projectedCenter.x) * remaining,
            height: (originalCenter.y - projectedCenter.y) * remaining
        )
    }

    private func resolvePageTurnState(at location: CGPoint) -> PageTurnHoverState {
        guard draggedApp != nil else { return PageTurnHoverState(direction: 0, progress: 0) }

        let edgeWidth = min(max(viewWidth * 0.09, 72), 128)
        if location.x <= edgeWidth {
            let progress = min(max((edgeWidth - location.x) / edgeWidth, 0), 1)
            return PageTurnHoverState(direction: -1, progress: progress)
        }
        if location.x >= max(viewWidth - edgeWidth, edgeWidth) {
            let progress = min(max((location.x - (viewWidth - edgeWidth)) / edgeWidth, 0), 1)
            return PageTurnHoverState(direction: 1, progress: progress)
        }
        return PageTurnHoverState(direction: 0, progress: 0)
    }

    private func requestPageTurnIfNeeded(direction: Int, progress: CGFloat) {
        guard direction != 0, progress >= 0.72 else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let cooldown: TimeInterval = 0.24
        guard now - lastPageTurnAt >= cooldown else { return }
        lastPageTurnAt = now
        onHoverPageTurnCommit(direction)
    }

    private func updateFolderAutoOpenTarget(_ target: AppItem?) {
        guard draggedApp != nil else {
            cancelFolderAutoOpen()
            return
        }

        let newTargetID = target?.id
        guard pendingFolderAutoOpenID != newTargetID else { return }

        cancelFolderAutoOpen()

        guard let target,
              target.type == .folder,
              openFolder?.id != target.id else {
            return
        }

        pendingFolderAutoOpenID = target.id
        let work = DispatchWorkItem { [draggedApp] in
            guard draggedApp != nil else { return }
            onFolderAutoOpen(target)
        }
        folderAutoOpenTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func cancelFolderAutoOpen() {
        folderAutoOpenTask?.cancel()
        folderAutoOpenTask = nil
        pendingFolderAutoOpenID = nil
    }
}

private struct GridDropDelegate: DropDelegate {
    @Binding var draggedApp: AppItem?
    @Binding var insertPosition: Int?
    @Binding var insertProgress: CGFloat
    @Binding var folderTargetID: UUID?
    @Binding var dragPreviewLocation: CGPoint?
    @Binding var committingDropAppID: UUID?

    let resolveVisualState: (CGPoint, AppItem?) -> GridVisualState
    let resolvePageTurnState: (CGPoint) -> PageTurnHoverState
    let onPageTurnPreviewChanged: (Int, CGFloat) -> Void
    let onPageTurnRequested: (Int, CGFloat) -> Void
    let onFolderHoverChanged: (AppItem?) -> Void
    let performDropAction: (GridDropContext, AppItem) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedApp != nil
    }

    func dropEntered(info: DropInfo) {
        updateVisualState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateVisualState(info: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedApp else {
            clearVisualState()
            return false
        }

        let visualState = resolveVisualState(info.location, dragged)
        let context = visualState.context

        // Commit in a single, non-animated transaction to avoid a two-phase visual jump.
        withTransaction(Transaction(animation: nil)) {
            committingDropAppID = dragged.id
            performDropAction(context, dragged)
            clearVisualState()
            draggedApp = nil
            dragPreviewLocation = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            guard committingDropAppID == dragged.id else { return }
            withAnimation(LaunchPadMotion.dropCommitFade) {
                committingDropAppID = nil
            }
        }

        return true
    }

    func dropExited(info: DropInfo) {
        clearVisualState()
    }

    private func updateVisualState(info: DropInfo) {
        dragPreviewLocation = info.location
        let pageTurnState = resolvePageTurnState(info.location)
        onPageTurnPreviewChanged(pageTurnState.direction, pageTurnState.progress)
        onPageTurnRequested(pageTurnState.direction, pageTurnState.progress)

        let visualState = resolveVisualState(info.location, draggedApp)
        insertProgress = visualState.insertProgress

        switch visualState.context {
        case .none:
            onFolderHoverChanged(nil)
            setVisualState(insert: nil, folder: nil)
        case .insert(let position):
            onFolderHoverChanged(nil)
            setVisualState(insert: position, folder: nil)
        case .folder(let target):
            onFolderHoverChanged(target.type == .folder ? target : nil)
            setVisualState(insert: nil, folder: target.id)
        }
    }

    private func clearVisualState() {
        dragPreviewLocation = nil
        insertProgress = 1
        onPageTurnPreviewChanged(0, 0)
        onFolderHoverChanged(nil)
        setVisualState(insert: nil, folder: nil)
    }

    private func setVisualState(insert: Int?, folder: UUID?) {
        if insertPosition != insert {
            insertPosition = insert
        }
        if folderTargetID != folder {
            folderTargetID = folder
        }
    }
}

private struct AppCell: View, Equatable {
    let app: AppItem
    let scale: CGFloat
    let isDragged: Bool
    let isCommittingDrop: Bool
    let isFolderTarget: Bool
    let isOpenedFolder: Bool
    let isSelected: Bool
    let isEditing: Bool
    let showsDeleteBadge: Bool
    let isShifted: Bool
    let folderOffset: CGSize
    let reorderOffset: CGSize
    let onTap: (CGRect?) -> Void
    let onDeleteRequested: () -> Void
    let onDragStart: () -> Void

    static func == (lhs: AppCell, rhs: AppCell) -> Bool {
        lhs.app.id == rhs.app.id &&
        lhs.app.name == rhs.app.name &&
        lhs.app.type == rhs.app.type &&
        lhs.app.position == rhs.app.position &&
        lhs.app.page == rhs.app.page &&
        lhs.app.folderItems?.count == rhs.app.folderItems?.count &&
        lhs.scale == rhs.scale &&
        lhs.isDragged == rhs.isDragged &&
        lhs.isCommittingDrop == rhs.isCommittingDrop &&
        lhs.isFolderTarget == rhs.isFolderTarget &&
        lhs.isOpenedFolder == rhs.isOpenedFolder &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isEditing == rhs.isEditing &&
        lhs.showsDeleteBadge == rhs.showsDeleteBadge &&
        lhs.isShifted == rhs.isShifted &&
        lhs.folderOffset == rhs.folderOffset &&
        lhs.reorderOffset == rhs.reorderOffset
    }

    var body: some View {
        let visualScale: CGFloat = isFolderTarget ? 1.07 : (isOpenedFolder ? 0.92 : 1)
        let visualOpacity: CGFloat = (isDragged || isCommittingDrop) ? 0 : (isOpenedFolder ? 0.05 : 1)
        let sourceSettleOffset = CGSize(width: 0, height: isOpenedFolder ? 8 : 0)
        let sourceBlurRadius: CGFloat = isOpenedFolder ? 2.8 : 0

        return GeometryReader { proxy in
            let sourceRect = proxy.frame(in: .named("launchpadRoot"))

            AppIconView(
                app: app,
                onTap: nil,
                isSelected: isSelected,
                isEditing: isEditing,
                scale: scale
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTap(sourceRect)
            }
            .overlay(alignment: .topLeading) {
                if showsDeleteBadge && !isDragged && !isCommittingDrop {
                    DeleteBadgeButton(action: onDeleteRequested)
                        .offset(x: 6, y: 2)
                }
            }
            .opacity(visualOpacity)
            .scaleEffect(visualScale)
            .offset(folderOffset)
            .offset(reorderOffset)
            .offset(sourceSettleOffset)
            .blur(radius: sourceBlurRadius)
            .animation(LaunchPadMotion.dropCommitFade, value: isCommittingDrop)
            .animation(LaunchPadMotion.folderTargetPulse, value: isFolderTarget)
            .animation(LaunchPadMotion.folderBackdrop, value: folderOffset)
            .animation(LaunchPadMotion.folderSourceRebound, value: isOpenedFolder)
            .onDrag {
                onDragStart()
                return NSItemProvider(object: NSString(string: app.id.uuidString))
            } preview: {
                Color.clear
                    .frame(width: 1, height: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DragPreviewView: View {
    let app: AppItem
    let metrics: LaunchPadLayout.DragPreviewMetrics

    @State private var icon: NSImage?

    init(
        app: AppItem,
        metrics: LaunchPadLayout.DragPreviewMetrics = .init(iconSize: 54, labelWidth: 80, fontSize: 10)
    ) {
        self.app = app
        self.metrics = metrics
    }

    var body: some View {
        VStack(spacing: 5) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: metrics.iconSize, height: metrics.iconSize)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: metrics.iconSize, height: metrics.iconSize)
            }

            Text(app.name)
                .font(.system(size: metrics.fontSize, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: metrics.labelWidth)
        }
        .scaleEffect(1.03)
        .shadow(color: Color.black.opacity(0.3), radius: 7, x: 0, y: 3)
        .task {
            icon = await MainActor.run { app.getIcon() }
        }
    }
}
