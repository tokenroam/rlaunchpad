import SwiftUI

enum LaunchPadMotion {
    static let pageSnap = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.9, blendDuration: 0.06)
    static let pageArrowStep = Animation.interactiveSpring(response: 0.2, dampingFraction: 0.9, blendDuration: 0.04)
    static let pageLanding = Animation.interactiveSpring(response: 0.26, dampingFraction: 0.78, blendDuration: 0.08)
    static let pageEdgeIndicator = Animation.easeOut(duration: 0.12)
    static let pageLayerDrift = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.9, blendDuration: 0.06)
    static let folderPageTurn = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.9, blendDuration: 0.06)
    static let folderPagePreview = Animation.easeOut(duration: 0.12)
    static let folderOpen = Animation.interactiveSpring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.08)
    static let folderClose = Animation.easeOut(duration: 0.14)
    static let folderBackdrop = Animation.easeOut(duration: 0.18)
    static let folderSourceRebound = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.8, blendDuration: 0.08)
    static let gridReorder = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.9, blendDuration: 0.03)
    static let folderTargetPulse = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.82, blendDuration: 0.03)
    static let dropCommitFade = Animation.easeOut(duration: 0.06)
    static let indicatorTap = Animation.easeInOut(duration: 0.18)
    static let selectionFocus = Animation.easeOut(duration: 0.14)
    static let editJiggle = Animation.easeInOut(duration: 0.13).repeatForever(autoreverses: true)
}
