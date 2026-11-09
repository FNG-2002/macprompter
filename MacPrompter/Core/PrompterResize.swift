import Foundation

/// Edges of the prompter that can be dragged. The top stays attached to the
/// notch (docked) or keeps its position (floating).
enum ResizeEdge: CaseIterable, Sendable {
    case left, right, bottom, bottomLeft, bottomRight
    var horizontal: Double {
        switch self { case .left, .bottomLeft: -1; case .right, .bottomRight: 1; case .bottom: 0 }
    }
    var vertical: Bool { self != .left && self != .right }
}

extension Preferences {
    static let widthRange = 400.0...1800.0
    static let heightRange = 220.0...1000.0

    /// Applies a drag of `dx`/`dy` screen points (y up) since the drag began.
    /// A docked prompter stays centred under the notch, so it grows on both sides.
    mutating func resize(from start: Preferences, edge: ResizeEdge, dx: Double, dy: Double) {
        let factor = start.docked ? 2.0 : 1.0
        width = min(Self.widthRange.upperBound, max(Self.widthRange.lowerBound, start.width + edge.horizontal * dx * factor))
        height = edge.vertical ? min(Self.heightRange.upperBound, max(Self.heightRange.lowerBound, start.height - dy)) : start.height
        floatingX = start.floatingX; floatingY = start.floatingY
        guard !start.docked else { return }
        // The opposite edges stay where they are.
        if edge.horizontal < 0, let x = start.floatingX { floatingX = x + start.width - width }
        if edge.vertical, let y = start.floatingY { floatingY = y + start.height - height }
    }
}
