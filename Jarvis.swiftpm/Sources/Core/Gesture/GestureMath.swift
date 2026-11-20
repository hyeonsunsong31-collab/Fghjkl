import Foundation

/// Platform-independent 2D point (normalised image coordinates, origin top-left).
struct Point2: Equatable, Codable {
    var x: Double
    var y: Double

    static func + (a: Point2, b: Point2) -> Point2 { Point2(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Point2, b: Point2) -> Point2 { Point2(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Point2, s: Double) -> Point2 { Point2(x: a.x * s, y: a.y * s) }
    var length: Double { (x * x + y * y).squareRoot() }
    func distance(to o: Point2) -> Double { (self - o).length }
    static func midpoint(_ a: Point2, _ b: Point2) -> Point2 { Point2(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
}

/// One-Euro filter (Casiez et al. 2012): low jitter at rest, low lag in motion.
struct OneEuroFilter {
    var minCutoff: Double = 1.2
    var beta: Double = 0.02
    var derivativeCutoff: Double = 1.0
    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTime: Double?

    init(minCutoff: Double = 1.2, beta: Double = 0.02, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    mutating func filter(_ value: Double, time: Double) -> Double {
        guard let prev = lastValue, let t0 = lastTime, time > t0 else {
            lastValue = value; lastTime = time
            return value
        }
        let dt = time - t0
        let derivative = (value - prev) / dt
        let aD = Self.alpha(cutoff: derivativeCutoff, dt: dt)
        lastDerivative = aD * derivative + (1 - aD) * lastDerivative
        let cutoff = minCutoff + beta * abs(lastDerivative)
        let a = Self.alpha(cutoff: cutoff, dt: dt)
        let filtered = a * value + (1 - a) * prev
        lastValue = filtered
        lastTime = time
        return filtered
    }

    mutating func reset() { lastValue = nil; lastTime = nil; lastDerivative = 0 }
}

struct OneEuroFilter2D {
    var fx = OneEuroFilter()
    var fy = OneEuroFilter()
    mutating func filter(_ p: Point2, time: Double) -> Point2 {
        Point2(x: fx.filter(p.x, time: time), y: fy.filter(p.y, time: time))
    }
    mutating func reset() { fx.reset(); fy.reset() }
}

/// Key landmarks of one detected hand (from Vision's hand-pose request).
struct HandLandmarks: Equatable {
    var thumbTip: Point2
    var indexTip: Point2
    var wrist: Point2
    var middleMCP: Point2
    var confidence: Double
    /// "left"/"right" if known.
    var chirality: String?

    /// Size reference: wrist → middle knuckle.
    var scale: Double { max(0.02, wrist.distance(to: middleMCP)) }
    var pinchDistance: Double { thumbTip.distance(to: indexTip) / scale }
    var pinchPoint: Point2 { Point2.midpoint(thumbTip, indexTip) }
}

enum HandGestureEvent: Equatable {
    case pointer(Point2)
    case grabBegan(Point2)
    case grabMoved(Point2)
    case grabEnded(Point2)
    case twoHandBegan
    /// Ratio of current to initial distance between the two pinch points.
    case twoHandScale(Double)
    /// Rotation (radians) relative to the initial two-hand angle.
    case twoHandRotate(Double)
    case twoHandEnded
    case handsLost
}

/// Turns per-frame hand landmarks into Iron-Man-style manipulation events:
/// index–thumb pinch grabs and drags; pinching with both hands and moving
/// them apart/together scales; twisting the pair rotates.
struct HandGestureInterpreter {
    var pinchOn: Double = 0.32
    var pinchOff: Double = 0.48
    var mirrored = true

    private var pinching: [Bool] = [false, false]
    private var filters = [OneEuroFilter2D(), OneEuroFilter2D()]
    private var twoHandActive = false
    private var startDistance: Double = 1
    private var startAngle: Double = 0
    private var lastPointer: Point2?
    private var missingFrames = 0

    init(mirrored: Bool = true) { self.mirrored = mirrored }

    mutating func process(_ hands: [HandLandmarks], time: Double) -> [HandGestureEvent] {
        var events: [HandGestureEvent] = []
        let visible = hands.filter { $0.confidence > 0.3 }.prefix(2)
            .sorted { $0.wrist.x < $1.wrist.x } // stable left→right order
        if visible.isEmpty {
            missingFrames += 1
            if missingFrames == 6 {
                if twoHandActive { events.append(.twoHandEnded); twoHandActive = false }
                for i in 0..<2 where pinching[i] {
                    pinching[i] = false
                    events.append(.grabEnded(lastPointer ?? Point2(x: 0.5, y: 0.5)))
                }
                filters = [OneEuroFilter2D(), OneEuroFilter2D()]
                events.append(.handsLost)
            }
            return events
        }
        missingFrames = 0

        var points: [Point2] = []
        for (i, hand) in visible.enumerated() {
            let d = hand.pinchDistance
            if !pinching[i] && d < pinchOn { pinching[i] = true }
            else if pinching[i] && d > pinchOff { pinching[i] = false; events.append(.grabEnded(lastPointer ?? hand.pinchPoint)) }
            var p = pinching[i] ? hand.pinchPoint : hand.indexTip
            if mirrored { p.x = 1 - p.x }
            points.append(filters[i].filter(p, time: time))
        }
        if visible.count < 2 { pinching[1] = false }

        let bothPinching = visible.count == 2 && pinching[0] && pinching[1]
        if bothPinching {
            let d = max(0.01, points[0].distance(to: points[1]))
            let angle = atan2(points[1].y - points[0].y, points[1].x - points[0].x)
            if !twoHandActive {
                twoHandActive = true
                startDistance = d
                startAngle = angle
                events.append(.twoHandBegan)
            } else {
                events.append(.twoHandScale(d / startDistance))
                var delta = angle - startAngle
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                events.append(.twoHandRotate(delta))
            }
            previousPinchState = false
            return events
        } else if twoHandActive {
            twoHandActive = false
            events.append(.twoHandEnded)
        }

        // Single-hand pointer / grab using the first visible hand.
        let p = points[0]
        if pinching[0] {
            events.append(previousPinchState ? .grabMoved(p) : .grabBegan(p))
        } else {
            events.append(.pointer(p))
        }
        previousPinchState = pinching[0]
        lastPointer = p
        return events
    }

    private var previousPinchState = false
}
