import SwiftUI

/// A patch cable drawn as a sagging cubic Bezier, ported from Modula's
/// `CableShape`. `start`/`end` are deliberately not part of
/// `animatableData` — a cable's ends must snap to a node's current
/// position every frame with zero lag while it's being dragged. Only `sag`
/// is animatable, giving the cable body a little elastic give without the
/// endpoints ever trailing behind the node they're plugged into.
struct CableShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var sag: CGFloat

    var animatableData: CGFloat {
        get { sag }
        set { sag = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let control1 = CGPoint(x: start.x + sag, y: start.y)
        let control2 = CGPoint(x: end.x - sag, y: end.y)
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }
}
