import Foundation

public enum RadialGeometry {
    /// Coordinates use a top-left origin. Sector zero is centered at twelve o'clock.
    public static func sector(x: Double, y: Double, count: Int, inner: Double = 61, outer: Double = 174) -> Int? {
        guard count > 0 else { return nil }
        let distance = hypot(x, y)
        guard distance >= inner, distance <= outer else { return nil }
        let step = 2 * Double.pi / Double(count)
        let angle = atan2(x, -y) + step / 2
        return Int(floor((angle + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi) / step)) % count
    }
}
