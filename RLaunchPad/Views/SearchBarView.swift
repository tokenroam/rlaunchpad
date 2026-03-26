import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    let isEditing: Bool
    let onToggleEditing: () -> Void
    let metrics: LaunchPadLayout.SearchBarMetrics

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            TextField("搜索应用程序", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.white)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.66))
                }
                .buttonStyle(.plain)
            }

            Button(action: onToggleEditing) {
                Text(isEditing ? "完成" : "编辑")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isEditing ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(width: metrics.width, height: metrics.height)
        .background(
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cornerRadius)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}
