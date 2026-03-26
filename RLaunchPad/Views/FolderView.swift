import SwiftUI
import UniformTypeIdentifiers

struct FolderView: View {
    let folder: AppItem
    let metrics: LaunchPadLayout.FolderMetrics
    let containerSize: CGSize
    let sourceRect: CGRect?
    let selectedAppID: UUID?
    let isEditing: Bool
    let onAppTap: (AppItem) -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let canDelete: (AppItem) -> Bool
    let onDeleteRequested: (AppItem) -> Void
    let onMoveApp: (UUID, Int) -> Bool
    let onRemoveFromFolder: (AppItem) -> Void
    let onNameEditingChanged: (Bool) -> Void

    @State private var folderName: String
    @State private var isEditingName = false
    @State private var currentPage = 0
    @State private var isLeftEdgeTargeted = false
    @State private var isRightEdgeTargeted = false
    @State private var previewPageTurnDirection = 0
    @State private var pendingPageTurnDirection = 0
    @State private var pageTurnWorkItem: DispatchWorkItem?
    @StateObject private var trackpadMotion = PageMotionState()
    @State private var accumulatedTrackpadScroll: CGFloat = 0
    @State private var lastTrackpadPageTurnAt: TimeInterval = 0
    @FocusState private var isNameFieldFocused: Bool

    init(
        folder: AppItem,
        metrics: LaunchPadLayout.FolderMetrics,
        containerSize: CGSize,
        sourceRect: CGRect?,
        selectedAppID: UUID?,
        isEditing: Bool,
        onAppTap: @escaping (AppItem) -> Void,
        onClose: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        canDelete: @escaping (AppItem) -> Bool,
        onDeleteRequested: @escaping (AppItem) -> Void,
        onMoveApp: @escaping (UUID, Int) -> Bool,
        onRemoveFromFolder: @escaping (AppItem) -> Void,
        onNameEditingChanged: @escaping (Bool) -> Void
    ) {
        self.folder = folder
        self.metrics = metrics
        self.containerSize = containerSize
        self.sourceRect = sourceRect
        self.selectedAppID = selectedAppID
        self.isEditing = isEditing
        self.onAppTap = onAppTap
        self.onClose = onClose
        self.onRename = onRename
        self.canDelete = canDelete
        self.onDeleteRequested = onDeleteRequested
        self.onMoveApp = onMoveApp
        self.onRemoveFromFolder = onRemoveFromFolder
        self.onNameEditingChanged = onNameEditingChanged
        _folderName = State(initialValue: folder.name)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(
                .fixed(LaunchPadLayout.iconMetrics(scale: metrics.itemScale).contentWidth),
                spacing: metrics.columnSpacing
            ),
            count: metrics.columns
        )
    }

    private var trayFrame: CGRect {
        let originX = (containerSize.width - metrics.width) / 2
        let minTop = metrics.minTopMargin
        let maxTop = max(containerSize.height - metrics.height - metrics.bottomMargin, minTop)
        let defaultTop = min(
            max((containerSize.height - metrics.height) * 0.46, minTop),
            maxTop
        )

        return CGRect(x: originX, y: defaultTop, width: metrics.width, height: metrics.height)
    }

    private var folderItems: [AppItem] {
        folder.folderItems ?? []
    }

    private var itemsPerPage: Int {
        metrics.columns * metrics.rows
    }

    private var folderPages: [[AppItem]] {
        guard !folderItems.isEmpty else { return [[]] }

        return stride(from: 0, to: folderItems.count, by: itemsPerPage).map { start in
            Array(folderItems[start..<min(start + itemsPerPage, folderItems.count)])
        }
    }

    private var pageIndicatorMetrics: LaunchPadLayout.PageIndicatorMetrics {
        .init(dotSize: 5.5, spacing: 9, bottomPadding: 0)
    }

    private var headerHeight: CGFloat {
        metrics.titleTopPadding + metrics.titleBottomPadding + metrics.titleFontSize
    }

    private var pageIndicatorHeight: CGFloat {
        folderPages.count > 1 ? 24 : 0
    }

    private var pageViewportHeight: CGFloat {
        max(metrics.height - headerHeight - pageIndicatorHeight - 12, 180)
    }

    private var pageTurnPreviewProgress: CGFloat {
        guard previewPageTurnDirection != 0 else { return 0 }
        if pendingPageTurnDirection != 0 {
            return 1
        }
        if isLeftEdgeTargeted || isRightEdgeTargeted {
            return 0.82
        }
        return 0.58
    }

    private var pagePreviewOffset: CGFloat {
        let previewDistance = min(metrics.width * 0.055, 34)
        return -CGFloat(previewPageTurnDirection) * previewDistance * pageTurnPreviewProgress
    }

    private var leftPageAvailable: Bool {
        currentPage > 0
    }

    private var rightPageAvailable: Bool {
        currentPage < folderPages.count - 1
    }

    private var edgeTurnOverlayWidth: CGFloat {
        min(max(metrics.width * 0.12, 64), 92)
    }

    private var pageIndicatorPreviewPage: Int? {
        if previewPageTurnDirection != 0 {
            let targetPage = currentPage + previewPageTurnDirection
            guard (0..<folderPages.count).contains(targetPage) else {
                return nil
            }
            return targetPage
        }

        let targetPage = currentPage + trackpadMotion.dragPreviewDirection
        guard trackpadMotion.dragPreviewDirection != 0,
              (0..<folderPages.count).contains(targetPage) else {
            return nil
        }
        return targetPage
    }

    private var pageIndicatorPreviewProgress: CGFloat {
        guard pageIndicatorPreviewPage != nil else { return 0 }
        if previewPageTurnDirection != 0 {
            return pageTurnPreviewProgress
        }
        return min(max(trackpadMotion.dragPreviewProgress, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            folderTitle
                .padding(.top, metrics.titleTopPadding)
                .padding(.bottom, metrics.titleBottomPadding)

            GeometryReader { proxy in
                TrackpadScrollView(
                    accumulatedScroll: $accumulatedTrackpadScroll,
                    pageWidth: proxy.size.width,
                    currentPage: currentPage,
                    totalPages: folderPages.count,
                    isInteractionEnabled: { !isEditingName },
                    onOffsetChanged: { offset in
                        trackpadMotion.offset = offset
                        updateTrackpadPagePreview(offset: offset, pageWidth: proxy.size.width)
                    },
                    onScrollEnded: { totalOffset, velocity in
                        handleTrackpadEnd(totalOffset: totalOffset, velocity: velocity, pageWidth: proxy.size.width)
                    }
                ) {
                    folderPageViewport(viewportSize: proxy.size)
                }
            }
            .frame(height: pageViewportHeight)

            if folderPages.count > 1 {
                PageIndicatorView(
                    totalPages: folderPages.count,
                    currentPage: $currentPage,
                    metrics: pageIndicatorMetrics,
                    previewPage: pageIndicatorPreviewPage,
                    previewProgress: pageIndicatorPreviewProgress
                )
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .background(folderShell)
        .shadow(color: .black.opacity(0.28), radius: 34, x: 0, y: 18)
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
        .position(
            x: trayFrame.midX,
            y: trayFrame.midY
        )
        .onKeyPress(.escape) {
            saveName()
            onClose()
            return .handled
        }
        .onAppear {
            resetTrackpadMotion()
            syncCurrentPage(animated: false)
        }
        .onChange(of: selectedAppID) { _, _ in
            syncCurrentPage(animated: true)
        }
        .onChange(of: folder.id) { _, _ in
            resetTrackpadMotion()
            resetPageTurnPreviewState()
            syncCurrentPage(animated: false)
        }
        .onChange(of: folderItems.count) { _, _ in
            let maxPageIndex = max(folderPages.count - 1, 0)
            if currentPage > maxPageIndex {
                currentPage = maxPageIndex
            }
            if folderPages.count <= 1 {
                resetTrackpadMotion()
            }
            syncCurrentPage(animated: false)
        }
        .onChange(of: isEditingName) { _, newValue in
            onNameEditingChanged(newValue)
        }
        .onChange(of: isLeftEdgeTargeted) { _, _ in
            updatePageTurnTarget()
        }
        .onChange(of: isRightEdgeTargeted) { _, _ in
            updatePageTurnTarget()
        }
        .onDisappear {
            onNameEditingChanged(false)
            resetTrackpadMotion()
            resetPageTurnPreviewState()
        }
    }

    private func folderPageViewport(viewportSize: CGSize) -> some View {
        ZStack {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(folderPages.enumerated()), id: \.offset) { page in
                        folderPageView(
                            items: page.element,
                            pageIndex: page.offset,
                            viewportSize: viewportSize
                        )
                        .frame(width: viewportSize.width, height: viewportSize.height)
                        .scaleEffect(folderPageScale(for: page.offset))
                        .opacity(folderPageOpacity(for: page.offset))
                        .offset(x: folderPageHorizontalOffset(for: page.offset))
                        .offset(y: folderPageVerticalOffset(for: page.offset))
                        .blur(radius: folderPageBlur(for: page.offset))
                        .allowsHitTesting(page.offset == currentPage)
                    }
                }
                .offset(
                    x: -CGFloat(currentPage) * viewportSize.width
                        + pagePreviewOffset
                        + trackpadMotion.offset
                )
                .animation(LaunchPadMotion.folderPageTurn, value: currentPage)
                .animation(LaunchPadMotion.folderPagePreview, value: previewPageTurnDirection)
            }
            .frame(width: viewportSize.width, height: viewportSize.height, alignment: .leading)
            .contentShape(Rectangle())
            .clipped()

            HStack(spacing: 0) {
                folderPageEdgeZone(direction: -1)
                Spacer(minLength: 0)
                folderPageEdgeZone(direction: 1)
            }
            .zIndex(2)
            .allowsHitTesting(false)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: FolderDropDelegate(
                onLocationUpdated: { location in
                    updateDropInteraction(at: location, viewportSize: viewportSize)
                },
                onInteractionEnded: {
                    resetPageTurnPreviewState()
                },
                resolveDestinationIndex: { location in
                    resolveDropDestinationIndex(at: location, viewportSize: viewportSize)
                },
                performMove: { appID, destinationIndex in
                    onMoveApp(appID, destinationIndex)
                }
            )
        )
    }

    private var folderShell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .fill(Color.black.opacity(0.64))

            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.045),
                            Color.white.opacity(0.016),
                            Color.black.opacity(0.09)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .stroke(Color.white.opacity(0.11), lineWidth: 0.9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .stroke(Color.black.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var folderTitle: some View {
        if isEditingName {
            TextField("文件夹", text: $folderName)
                .textFieldStyle(.plain)
                .font(.system(size: metrics.titleFontSize, weight: .medium))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .focused($isNameFieldFocused)
                .frame(maxWidth: metrics.titleMaxWidth)
                .onSubmit {
                    saveName()
                    isEditingName = false
                }
        } else {
            Text(folderName)
                .font(.system(size: metrics.titleFontSize, weight: .medium))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
                .frame(maxWidth: metrics.titleMaxWidth)
                .onTapGesture {
                    onNameEditingChanged(true)
                    isEditingName = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isNameFieldFocused = true
                    }
                }
        }
    }

    private func saveName() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            folderName = folder.name
            return
        }

        if trimmed != folder.name {
            onRename(trimmed)
        }
    }

    @ViewBuilder
    private func folderPageView(items: [AppItem], pageIndex: Int, viewportSize: CGSize) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: metrics.itemSpacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { entry in
                    let app = entry.element

                    DraggableFolderAppIcon(
                        app: app,
                        scale: metrics.itemScale,
                        isSelected: selectedAppID == app.id,
                        isEditing: isEditing,
                        showsDeleteBadge: isEditing && canDelete(app),
                        onDeleteRequested: {
                            onDeleteRequested(app)
                        },
                        onTap: {
                            onAppTap(app)
                        }
                    )
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.topPadding)
            .padding(.bottom, metrics.bottomPadding)
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .top)
        .contentShape(Rectangle())
    }

    private func syncCurrentPage(animated: Bool) {
        guard let selectedAppID,
              let selectedIndex = folderItems.firstIndex(where: { $0.id == selectedAppID }) else {
            return
        }

        let targetPage = min(max(selectedIndex / itemsPerPage, 0), max(folderPages.count - 1, 0))
        guard targetPage != currentPage else { return }

        if animated {
            withAnimation(LaunchPadMotion.folderPageTurn) {
                currentPage = targetPage
            }
        } else {
            currentPage = targetPage
        }
    }

    private func folderPageFocus(for pageIndex: Int) -> CGFloat {
        let previewProgress = pageTurnPreviewProgress

        if pageIndex == currentPage {
            return 1 - 0.12 * previewProgress
        }

        if previewPageTurnDirection != 0, pageIndex == currentPage + previewPageTurnDirection {
            return 0.86 + 0.14 * previewProgress
        }

        if abs(pageIndex - currentPage) == 1 {
            return 0.82
        }

        return 0.76
    }

    private func folderPageScale(for pageIndex: Int) -> CGFloat {
        let focus = folderPageFocus(for: pageIndex)
        return 0.968 + focus * 0.032
    }

    private func folderPageOpacity(for pageIndex: Int) -> CGFloat {
        let focus = folderPageFocus(for: pageIndex)
        return 0.54 + focus * 0.46
    }

    private func folderPageVerticalOffset(for pageIndex: Int) -> CGFloat {
        let focus = folderPageFocus(for: pageIndex)
        return (1 - focus) * 12
    }

    private func folderPageHorizontalOffset(for pageIndex: Int) -> CGFloat {
        let previewProgress = pageTurnPreviewProgress
        guard previewPageTurnDirection != 0, previewProgress > 0.001 else { return 0 }

        if pageIndex == currentPage {
            return CGFloat(previewPageTurnDirection) * 10 * previewProgress
        }

        if pageIndex == currentPage + previewPageTurnDirection {
            return CGFloat(previewPageTurnDirection) * 4 * (1 - previewProgress)
        }

        return 0
    }

    private func folderPageBlur(for pageIndex: Int) -> CGFloat {
        let previewProgress = pageTurnPreviewProgress

        if pageIndex == currentPage {
            return previewProgress * 0.75
        }

        if previewPageTurnDirection != 0, pageIndex == currentPage + previewPageTurnDirection {
            return max(0, 0.28 - previewProgress * 0.2)
        }

        return 0.18
    }

    private func folderPageEdgeZone(direction: Int) -> some View {
        let isAvailable = direction < 0 ? leftPageAvailable : rightPageAvailable
        let isDropHighlighted = (direction < 0 ? isLeftEdgeTargeted : isRightEdgeTargeted) && isAvailable
        let isTrackpadHighlighted = trackpadMotion.dragPreviewDirection == direction
            && trackpadMotion.dragPreviewProgress > 0.01
            && isAvailable
        let isHighlighted = isDropHighlighted || isTrackpadHighlighted

        return Rectangle()
            .fill(Color.clear)
            .frame(width: edgeTurnOverlayWidth)
            .contentShape(Rectangle())
            .overlay(alignment: direction < 0 ? .leading : .trailing) {
                edgeTurnHighlight(direction: direction, isHighlighted: isHighlighted)
            }
    }

    private func updateDropInteraction(at location: CGPoint, viewportSize: CGSize) {
        let direction = resolvePageTurnDirection(at: location, viewportSize: viewportSize)
        let nextLeft = direction == -1
        let nextRight = direction == 1

        if isLeftEdgeTargeted != nextLeft {
            isLeftEdgeTargeted = nextLeft
        }
        if isRightEdgeTargeted != nextRight {
            isRightEdgeTargeted = nextRight
        }
    }

    private func resolvePageTurnDirection(at location: CGPoint, viewportSize: CGSize) -> Int {
        if location.x <= edgeTurnOverlayWidth, leftPageAvailable {
            return -1
        }

        if location.x >= max(viewportSize.width - edgeTurnOverlayWidth, edgeTurnOverlayWidth), rightPageAvailable {
            return 1
        }

        return 0
    }

    private func resolveDropDestinationIndex(at location: CGPoint, viewportSize: CGSize) -> Int {
        let iconMetrics = LaunchPadLayout.iconMetrics(scale: metrics.itemScale)
        let pageStartIndex = currentPage * itemsPerPage
        let itemsOnPage = Array(folderItems.dropFirst(pageStartIndex).prefix(itemsPerPage))
        let cellWidth = iconMetrics.contentWidth
        let cellHeight = iconMetrics.contentHeight
        let gridWidth = CGFloat(metrics.columns) * cellWidth + CGFloat(metrics.columns - 1) * metrics.columnSpacing
        let gridOriginX = max((viewportSize.width - gridWidth) / 2, 0)
        let gridOriginY = metrics.topPadding
        let totalCellWidth = cellWidth + metrics.columnSpacing
        let totalCellHeight = cellHeight + metrics.itemSpacing
        let gridHeight = CGFloat(metrics.rows) * cellHeight + CGFloat(metrics.rows - 1) * metrics.itemSpacing
        let adjustedX = location.x - gridOriginX
        let adjustedY = location.y - gridOriginY

        if adjustedY < 0 {
            return pageStartIndex
        }

        if adjustedY > gridHeight {
            return min(pageStartIndex + itemsOnPage.count, folderItems.count)
        }

        let row = min(max(Int(adjustedY / max(totalCellHeight, 1)), 0), metrics.rows - 1)

        if adjustedX < 0 {
            return min(pageStartIndex + row * metrics.columns, folderItems.count)
        }

        if adjustedX > gridWidth {
            return min(pageStartIndex + row * metrics.columns + metrics.columns, folderItems.count)
        }

        let col = min(max(Int(adjustedX / max(totalCellWidth, 1)), 0), metrics.columns - 1)
        let localIndex = row * metrics.columns + col

        guard localIndex < itemsOnPage.count else {
            return min(pageStartIndex + itemsOnPage.count, folderItems.count)
        }

        let xInCell = adjustedX - CGFloat(col) * totalCellWidth
        let normalizedX = max(0, min(1, xInCell / max(cellWidth, 1)))
        let insertOffset = normalizedX < 0.5 ? localIndex : localIndex + 1
        return min(pageStartIndex + insertOffset, folderItems.count)
    }

    private func updateTrackpadPagePreview(offset: CGFloat, pageWidth: CGFloat) {
        guard pageWidth > 0 else {
            trackpadMotion.dragPreviewDirection = 0
            trackpadMotion.dragPreviewProgress = 0
            return
        }

        let direction = offset > 0 ? -1 : (offset < 0 ? 1 : 0)
        let targetPage = currentPage + direction
        guard direction != 0, (0..<folderPages.count).contains(targetPage) else {
            trackpadMotion.dragPreviewDirection = 0
            trackpadMotion.dragPreviewProgress = 0
            return
        }

        trackpadMotion.dragPreviewDirection = direction
        trackpadMotion.dragPreviewProgress = min(max(abs(offset) / max(pageWidth * 0.24, 1), 0), 1)
    }

    private func handleTrackpadEnd(totalOffset: CGFloat, velocity: CGFloat, pageWidth: CGFloat) {
        let isFastFlick = abs(velocity) > pageWidth * 0.95
        let threshold = pageWidth * (isFastFlick ? 0.062 : 0.1)
        let projectedTravel = totalOffset + velocity * (isFastFlick ? 0.2 : 0.16)
        let now = Date().timeIntervalSinceReferenceDate
        let canFlip = now - lastTrackpadPageTurnAt >= 0.16

        withAnimation(LaunchPadMotion.folderPageTurn) {
            if canFlip, projectedTravel < -threshold {
                if currentPage < folderPages.count - 1 {
                    currentPage += 1
                    lastTrackpadPageTurnAt = now
                }
            } else if canFlip, projectedTravel > threshold {
                if currentPage > 0 {
                    currentPage -= 1
                    lastTrackpadPageTurnAt = now
                }
            }

            trackpadMotion.offset = 0
            trackpadMotion.dragPreviewDirection = 0
            trackpadMotion.dragPreviewProgress = 0
        }
    }

    private func edgeTurnHighlight(direction: Int, isHighlighted: Bool) -> some View {
        ZStack(alignment: direction < 0 ? .leading : .trailing) {
            LinearGradient(
                colors: direction < 0
                    ? [Color.white.opacity(isHighlighted ? 0.14 : 0.0), Color.clear]
                    : [Color.clear, Color.white.opacity(isHighlighted ? 0.14 : 0.0)],
                startPoint: direction < 0 ? .leading : .trailing,
                endPoint: direction < 0 ? .trailing : .leading
            )

            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isHighlighted ? 0.9 : 0.0))
                .padding(direction < 0 ? .leading : .trailing, 12)
        }
        .animation(LaunchPadMotion.folderPagePreview, value: isHighlighted)
    }

    private func updatePageTurnTarget() {
        let direction: Int
        if isLeftEdgeTargeted && leftPageAvailable {
            direction = -1
        } else if isRightEdgeTargeted && rightPageAvailable {
            direction = 1
        } else {
            direction = 0
        }

        if previewPageTurnDirection != direction {
            withAnimation(LaunchPadMotion.folderPagePreview) {
                previewPageTurnDirection = direction
            }
        }

        guard direction != pendingPageTurnDirection else { return }

        cancelPendingPageTurn()
        guard direction != 0 else { return }

        pendingPageTurnDirection = direction
        let workItem = DispatchWorkItem {
            commitPageTurn(direction: direction)
        }
        pageTurnWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: workItem)
    }

    private func commitPageTurn(direction: Int) {
        let targetPage = currentPage + direction
        guard (0..<folderPages.count).contains(targetPage) else {
            cancelPendingPageTurn()
            return
        }

        withAnimation(LaunchPadMotion.folderPageTurn) {
            currentPage = targetPage
        }

        pendingPageTurnDirection = 0
        pageTurnWorkItem = nil

        DispatchQueue.main.async {
            updatePageTurnTarget()
        }
    }

    private func cancelPendingPageTurn() {
        pageTurnWorkItem?.cancel()
        pageTurnWorkItem = nil
        pendingPageTurnDirection = 0
    }

    private func resetPageTurnPreviewState() {
        cancelPendingPageTurn()
        isLeftEdgeTargeted = false
        isRightEdgeTargeted = false
        previewPageTurnDirection = 0
    }

    private func resetTrackpadMotion() {
        accumulatedTrackpadScroll = 0
        trackpadMotion.offset = 0
        trackpadMotion.dragPreviewDirection = 0
        trackpadMotion.dragPreviewProgress = 0
        trackpadMotion.settleDirection = 0
        trackpadMotion.settleProgress = 0
    }
}

private struct FolderDropDelegate: DropDelegate {
    let onLocationUpdated: (CGPoint) -> Void
    let onInteractionEnded: () -> Void
    let resolveDestinationIndex: (CGPoint) -> Int
    let performMove: (UUID, Int) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        onLocationUpdated(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onLocationUpdated(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onInteractionEnded()
    }

    func performDrop(info: DropInfo) -> Bool {
        let destinationIndex = resolveDestinationIndex(info.location)
        let providers = info.itemProviders(for: [UTType.plainText])
        guard let provider = providers.first else {
            onInteractionEnded()
            return false
        }

        onInteractionEnded()
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let value = item as? String ?? (item as? NSString).map(String.init),
                  let uuid = UUID(uuidString: value) else {
                return
            }

            DispatchQueue.main.async {
                _ = performMove(uuid, destinationIndex)
            }
        }
        return true
    }
}

private struct DraggableFolderAppIcon: View {
    let app: AppItem
    let scale: CGFloat
    let isSelected: Bool
    let isEditing: Bool
    let showsDeleteBadge: Bool
    let onDeleteRequested: () -> Void
    let onTap: () -> Void

    var body: some View {
        AppIconView(
            app: app,
            onTap: onTap,
            isSelected: isSelected,
            isEditing: isEditing,
            scale: scale
        )
            .overlay(alignment: .topLeading) {
                if showsDeleteBadge {
                    DeleteBadgeButton(action: onDeleteRequested)
                        .offset(x: 6, y: 2)
                }
            }
            .draggable(app.id.uuidString) {
                DragPreviewView(app: app)
            }
    }
}
