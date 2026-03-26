import SwiftUI
import AppKit

struct AppIconView: View {
    let app: AppItem
    let onTap: (() -> Void)?
    var isSelected: Bool = false
    var isEditing: Bool = false
    var scale: CGFloat = 1

    @State private var icon: NSImage?
    @State private var isJiggling = false

    var body: some View {
        if let onTap {
            decoratedContent
                .onTapGesture(perform: onTap)
                .onAppear {
                    loadIconIfNeeded()
                    updateJiggleState()
                }
                .onChange(of: isEditing) { _, _ in
                    updateJiggleState()
                }
        } else {
            decoratedContent
                .onAppear {
                    loadIconIfNeeded()
                    updateJiggleState()
                }
                .onChange(of: isEditing) { _, _ in
                    updateJiggleState()
                }
        }
    }

    private var content: some View {
        let metrics = LaunchPadLayout.iconMetrics(scale: scale)

        return VStack(spacing: metrics.titleSpacing) {
            iconView
                .frame(width: metrics.iconSize, height: metrics.iconSize)
                .shadow(color: Color.black.opacity(0.32), radius: 5, x: 0, y: 3)

            Text(app.name)
                .font(.system(size: 12 * scale, weight: .regular))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: metrics.labelWidth, height: metrics.labelHeight)
                .shadow(color: Color.black.opacity(0.75), radius: 1, x: 0, y: 1)
        }
        .frame(width: metrics.contentWidth, height: metrics.contentHeight)
        .contentShape(Rectangle())
    }

    private var decoratedContent: some View {
        content
            .background(selectionBackdrop)
            .scaleEffect(isSelected ? 1.035 : 1)
            .rotationEffect(isEditing ? Angle.degrees(isJiggling ? 1.2 : -1.2) : .zero)
            .animation(LaunchPadMotion.selectionFocus, value: isSelected)
    }

    @ViewBuilder
    private var selectionBackdrop: some View {
        RoundedRectangle(cornerRadius: 18 * scale)
            .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 18 * scale)
                    .stroke(isSelected ? Color.white.opacity(0.34) : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal, 4 * scale)
            .padding(.vertical, 2 * scale)
    }

    @ViewBuilder
    private var iconView: some View {
        if app.type == .folder {
            FolderIconView(items: app.folderItems ?? [], scale: scale)
        } else if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.18))
        }
    }

    private func loadIconIfNeeded() {
        guard app.type != .folder, icon == nil else { return }
        icon = app.getIcon()
    }

    private func updateJiggleState() {
        guard isEditing else {
            isJiggling = false
            return
        }

        isJiggling = false
        DispatchQueue.main.async {
            withAnimation(LaunchPadMotion.editJiggle) {
                isJiggling = true
            }
        }
    }
}

private struct FolderIconView: View {
    let items: [AppItem]
    let scale: CGFloat

    var body: some View {
        let miniIconSize = 15 * scale
        let miniIconSpacing = 2 * scale

        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.26), lineWidth: 0.8)
                )

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(miniIconSize), spacing: miniIconSpacing), count: 3),
                spacing: miniIconSpacing
            ) {
                ForEach(Array(items.prefix(9))) { item in
                    MiniAppIcon(app: item, scale: scale)
                }
            }
            .padding(7 * scale)
        }
    }
}

private struct MiniAppIcon: View {
    let app: AppItem
    let scale: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.22))
            }
        }
        .frame(width: 15 * scale, height: 15 * scale)
        .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
        .onAppear {
            if icon == nil {
                icon = app.getIcon()
            }
        }
    }
}

struct DeleteBadgeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.red.opacity(0.95))
                .shadow(color: .black.opacity(0.24), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
