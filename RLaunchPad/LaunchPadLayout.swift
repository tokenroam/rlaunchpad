import CoreGraphics

enum LaunchPadLayout {
    static let columns = 7
    static let rows = 5

    static let pageHorizontalPadding: CGFloat = 10

    static let baseCellWidth: CGFloat = 92
    static let baseCellHeight: CGFloat = 106
    static let baseHorizontalSpacing: CGFloat = 18
    static let baseVerticalSpacing: CGFloat = 26

    static let baseIconSize: CGFloat = 66
    static let baseLabelWidth: CGFloat = 86
    static let baseLabelHeight: CGFloat = 30
    static let baseIconTitleSpacing: CGFloat = 7

    static let gridTargetWidthRatio: CGFloat = 0.92
    static let gridTargetHeightRatio: CGFloat = 0.82
    static let maxIconScale: CGFloat = 1.18

    static func pageGridMetrics(in size: CGSize) -> GridMetrics {
        let baseGridWidth = CGFloat(columns) * baseCellWidth + CGFloat(columns - 1) * baseHorizontalSpacing
        let baseGridHeight = CGFloat(rows) * baseCellHeight + CGFloat(rows - 1) * baseVerticalSpacing

        let iconScale = min(
            max(min(size.width * 0.72 / baseGridWidth, size.height * 0.76 / baseGridHeight), 1),
            maxIconScale
        )

        let cellWidth = baseCellWidth * iconScale
        let cellHeight = baseCellHeight * iconScale
        let minHorizontalSpacing = baseHorizontalSpacing * min(iconScale, 1.08)
        let minVerticalSpacing = baseVerticalSpacing * min(iconScale, 1.08)

        let targetGridWidth = size.width * gridTargetWidthRatio
        let targetGridHeight = size.height * gridTargetHeightRatio

        let widthFromCells = CGFloat(columns) * cellWidth
        let heightFromCells = CGFloat(rows) * cellHeight
        let horizontalSpacing = max(
            (targetGridWidth - widthFromCells) / CGFloat(columns - 1),
            minHorizontalSpacing
        )
        let verticalSpacing = max(
            (targetGridHeight - heightFromCells) / CGFloat(rows - 1),
            minVerticalSpacing
        )

        let gridWidth = widthFromCells + CGFloat(columns - 1) * horizontalSpacing
        let gridHeight = heightFromCells + CGFloat(rows - 1) * verticalSpacing
        let paddingX = max((size.width - gridWidth) / 2, 0)
        let paddingY = max((size.height - gridHeight) / 2, 0)

        return GridMetrics(
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            paddingX: paddingX,
            paddingY: paddingY,
            iconScale: iconScale
        )
    }

    static func sceneMetrics(in size: CGSize) -> SceneMetrics {
        let contentWidth = max(size.width - pageHorizontalPadding * 2, 0)
        let gridMetrics = pageGridMetrics(in: CGSize(width: contentWidth, height: size.height))
        let homeIconMetrics = iconMetrics(scale: gridMetrics.iconScale)

        let searchBarWidth = min(max(contentWidth * 0.34, 420), 560)
        let searchBarHeight: CGFloat = 38

        let searchGridWidth = contentWidth * gridTargetWidthRatio
        let searchGridHeight = size.height * gridTargetHeightRatio
        let searchHorizontalSpacing = max(
            (searchGridWidth - CGFloat(columns) * homeIconMetrics.contentWidth) / CGFloat(columns - 1),
            baseHorizontalSpacing * min(gridMetrics.iconScale, 1.08)
        )
        let searchVerticalSpacing = max(
            (searchGridHeight - CGFloat(rows) * homeIconMetrics.contentHeight) / CGFloat(rows - 1),
            baseVerticalSpacing * min(gridMetrics.iconScale, 1.08)
        )

        let folderScale = min(gridMetrics.iconScale, 1.0)
        let folderIconMetrics = iconMetrics(scale: folderScale)
        let folderWidth = min(max(gridMetrics.gridWidth * 0.84, 680), min(contentWidth * 0.88, 920))
        let folderHeight = min(max(gridMetrics.gridHeight * 0.56, 400), size.height * 0.48)
        let folderColumnSpacing: CGFloat = 28
        let folderHorizontalPadding = max(
            (folderWidth - CGFloat(4) * folderIconMetrics.contentWidth - CGFloat(3) * folderColumnSpacing) / 2,
            56
        )

        return SceneMetrics(
            contentSize: size,
            gridMetrics: gridMetrics,
            iconMetrics: homeIconMetrics,
            searchBar: SearchBarMetrics(
                topPadding: 46,
                width: searchBarWidth,
                height: searchBarHeight,
                cornerRadius: 10
            ),
            pageIndicator: PageIndicatorMetrics(
                dotSize: max(6, min(7.5, 6 * gridMetrics.iconScale)),
                spacing: max(10, min(12, 10 * gridMetrics.iconScale)),
                bottomPadding: 30
            ),
            searchResults: SearchResultsMetrics(
                cellWidth: homeIconMetrics.contentWidth,
                horizontalSpacing: searchHorizontalSpacing,
                verticalSpacing: searchVerticalSpacing
            ),
            folder: FolderMetrics(
                width: folderWidth,
                height: folderHeight,
                cornerRadius: 26,
                minTopMargin: 118,
                bottomMargin: 92,
                sourceSpacing: 26,
                titleTopPadding: 22,
                titleBottomPadding: 16,
                titleFontSize: max(24, min(28, 24 * folderScale)),
                titleMaxWidth: min(folderWidth - 120, 360),
                columns: 4,
                rows: 3,
                itemScale: folderScale,
                itemSpacing: 26,
                columnSpacing: folderColumnSpacing,
                horizontalPadding: folderHorizontalPadding,
                topPadding: 22,
                bottomPadding: 30
            ),
            dragPreview: DragPreviewMetrics(
                iconSize: max(54, min(68, baseIconSize * gridMetrics.iconScale * 0.86)),
                labelWidth: max(80, min(108, baseLabelWidth * gridMetrics.iconScale * 0.9)),
                fontSize: max(10, min(12, 10 * gridMetrics.iconScale))
            )
        )
    }

    static func iconMetrics(scale: CGFloat) -> IconMetrics {
        IconMetrics(
            iconSize: baseIconSize * scale,
            labelWidth: baseLabelWidth * scale,
            labelHeight: baseLabelHeight * scale,
            contentWidth: baseCellWidth * scale,
            contentHeight: baseCellHeight * scale,
            titleSpacing: baseIconTitleSpacing * scale
        )
    }

    struct GridMetrics {
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let gridWidth: CGFloat
        let gridHeight: CGFloat
        let paddingX: CGFloat
        let paddingY: CGFloat
        let iconScale: CGFloat
    }

    struct IconMetrics {
        let iconSize: CGFloat
        let labelWidth: CGFloat
        let labelHeight: CGFloat
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        let titleSpacing: CGFloat
    }

    struct SceneMetrics {
        let contentSize: CGSize
        let gridMetrics: GridMetrics
        let iconMetrics: IconMetrics
        let searchBar: SearchBarMetrics
        let pageIndicator: PageIndicatorMetrics
        let searchResults: SearchResultsMetrics
        let folder: FolderMetrics
        let dragPreview: DragPreviewMetrics
    }

    struct SearchBarMetrics {
        let topPadding: CGFloat
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
    }

    struct PageIndicatorMetrics {
        let dotSize: CGFloat
        let spacing: CGFloat
        let bottomPadding: CGFloat
    }

    struct SearchResultsMetrics {
        let cellWidth: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
    }

    struct FolderMetrics {
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
        let minTopMargin: CGFloat
        let bottomMargin: CGFloat
        let sourceSpacing: CGFloat
        let titleTopPadding: CGFloat
        let titleBottomPadding: CGFloat
        let titleFontSize: CGFloat
        let titleMaxWidth: CGFloat
        let columns: Int
        let rows: Int
        let itemScale: CGFloat
        let itemSpacing: CGFloat
        let columnSpacing: CGFloat
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
    }

    struct DragPreviewMetrics {
        let iconSize: CGFloat
        let labelWidth: CGFloat
        let fontSize: CGFloat
    }
}
