import Foundation

/// One sample along a stroke.
///
/// This is the atom of Invariant 2: ordered points carrying pressure, tilt,
/// azimuth, and time. Everything else about ink — the rendered bitmap, the
/// PencilKit `PKDrawing`, the smoothed Bézier the GPU actually draws — is a
/// derivative that can be thrown away and recomputed. This cannot.
///
/// The tutor loop depends on more of this than rendering does. Timing is how a
/// stall is detected and how a ninety-second pause on one line becomes visible;
/// pressure and tilt are how "written firmly" is distinguished from "trailed
/// off uncertainly". Discarding them at capture time to save space would be
/// throwing away the signal the product is built on.
public struct InkPoint: Hashable, Sendable, Codable {

    /// Position in canvas coordinates.
    public var position: CanvasPoint

    /// Seconds since the first point of the stroke that contains this point.
    ///
    /// Relative rather than absolute so that a stroke is self-contained and
    /// unaffected by the clock changing between capture and save. The stroke's
    /// own `createdAt` anchors it to wall time.
    public var timeOffset: TimeInterval

    /// Normalized pressure, 0...1, where 1 is the maximum the input device
    /// reports.
    ///
    /// Devices without pressure — a mouse, a finger on hardware with no force
    /// sensing — report a constant. That is a legitimate value and not a
    /// missing one, so this is not optional; `hasPressure` on the stroke says
    /// whether it means anything.
    public var pressure: Double

    /// Rotation of the stylus around the canvas normal, in radians, 0...2π.
    ///
    /// Meaningless for input devices that cannot report it.
    public var azimuth: Double

    /// Angle of the stylus from the canvas plane, in radians, where π/2 is
    /// perpendicular. This is what "tilt" means in the invariant.
    public var altitude: Double

    /// The width of the mark at this point in canvas units, as the capturing
    /// platform computed it.
    ///
    /// Retained alongside pressure rather than derived from it because each
    /// platform's pressure-to-width curve differs, and reproducing the original
    /// look on the platform that drew it matters more than recomputing a width
    /// we think is equivalent.
    public var width: Double

    public init(
        position: CanvasPoint,
        timeOffset: TimeInterval,
        pressure: Double,
        azimuth: Double,
        altitude: Double,
        width: Double
    ) {
        self.position = position
        self.timeOffset = timeOffset
        self.pressure = pressure
        self.azimuth = azimuth
        self.altitude = altitude
        self.width = width
    }

    /// A point with no stylus data, for input devices that report only position
    /// — a mouse, a trackpad, a finger on a screen without force sensing.
    ///
    /// Invariant 5: these are sources of the same normalized stroke events as
    /// an Apple Pencil, with the optional channels absent rather than faked.
    public static func positionOnly(
        _ position: CanvasPoint,
        timeOffset: TimeInterval,
        width: Double
    ) -> InkPoint {
        InkPoint(
            position: position,
            timeOffset: timeOffset,
            pressure: 1,
            azimuth: 0,
            altitude: .pi / 2,
            width: width
        )
    }

    /// Returns a copy moved and scaled by the given transform.
    ///
    /// Width scales by the transform's uniform scale; pressure, azimuth, and
    /// altitude are properties of the hand that drew the stroke and are not
    /// affected by where the stroke was subsequently placed.
    public func transformed(by transform: CanvasTransform) -> InkPoint {
        InkPoint(
            position: transform.apply(to: position),
            timeOffset: timeOffset,
            pressure: pressure,
            azimuth: azimuth,
            altitude: altitude,
            width: width * transform.uniformScale
        )
    }
}
