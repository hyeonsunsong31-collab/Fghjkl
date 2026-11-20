import Foundation

/// A vectorised population of synaptic perceptrons (structure-of-arrays layout).
///
/// Each member is the same unit as `SynapticPerceptron` — synapses with
/// short-term plasticity and eligibility traces, dendritic branches, leaky
/// soma, adaptive threshold — but stored contiguously so whole regions run in
/// well under a millisecond per tick on an iPad/iPhone CPU.
final class PerceptronPopulation {
    enum Connectivity {
        /// Every neuron receives every input.
        case dense
        /// Each neuron receives `fanIn` distinct random inputs.
        case random(fanIn: Int)
        /// Neuron i receives the inputs listed in `lists[i]`.
        case explicit([[Int]])
    }

    let name: String
    let size: Int
    let inputSize: Int
    /// Lattice IDs of the members (their physical location in the 3D brain).
    private(set) var ids: [NeuronID]

    // MARK: Synapses (CSR)
    private(set) var rowStart: [Int32]
    private(set) var column: [Int32]
    var weight: [Float]
    private(set) var sign: [Int8]
    private(set) var release: [Float]
    private(set) var resources: [Float]
    private(set) var eligibility: [Float]

    // MARK: Neurons
    var bias: [Float]
    var threshold: [Float]
    private(set) var potential: [Float]
    private(set) var output: [Float]
    private(set) var preActivation: [Float]
    private var averageRate: [Float]
    private var lastInput: [Float]

    // MARK: Parameters
    var activation: ActivationKind
    var leak: Float
    var targetRate: Float
    var homeostasisRate: Float
    var learningRate: Float
    var rule: PlasticityRule
    var receptors: ModulatorReceptors
    var traceDecay: Float = 0.6
    /// Short-term plasticity (Tsodyks–Markram) parameters.
    var stpEnabled: Bool
    var baselineRelease: Float = 0.5
    var tauFacilitation: Float = 6
    var tauDepression: Float = 15
    /// Dendritic branches per neuron (synapse k of a row belongs to branch k % branchCount).
    var branchCount: Int
    var branchSlope: Float = 4
    var branchThreshold: Float = 0.5
    /// Lateral inhibition: only the top-k neurons stay active (nil = off).
    var kWinners: Int?
    /// Bounds on the signed weight.
    var weightLimit: Float = 4

    init(name: String,
         ids: [NeuronID],
         inputSize: Int,
         connectivity: Connectivity,
         weightScale: Float,
         inhibitoryFraction: Float = 0,
         activation: ActivationKind = .sigmoid,
         leak: Float = 0,
         targetRate: Float = 0.1,
         homeostasisRate: Float = 0,
         learningRate: Float = 0.02,
         rule: PlasticityRule = .threeFactor,
         receptors: ModulatorReceptors = .standard,
         stpEnabled: Bool = false,
         branchCount: Int = 1,
         kWinners: Int? = nil,
         seed: UInt64) {
        precondition(!ids.isEmpty && inputSize > 0)
        self.name = name
        self.size = ids.count
        self.inputSize = inputSize
        self.ids = ids
        self.activation = activation
        self.leak = leak
        self.targetRate = targetRate
        self.homeostasisRate = homeostasisRate
        self.learningRate = learningRate
        self.rule = rule
        self.receptors = receptors
        self.stpEnabled = stpEnabled
        self.branchCount = max(1, branchCount)
        self.kWinners = kWinners

        var rng = SplitMix64(seed: seed)
        var rows: [Int32] = [0]
        var cols: [Int32] = []
        rows.reserveCapacity(ids.count + 1)
        for i in 0..<ids.count {
            switch connectivity {
            case .dense:
                cols.append(contentsOf: (0..<inputSize).map { Int32($0) })
            case .random(let fanIn):
                let k = min(fanIn, inputSize)
                var chosen = Set<Int>()
                while chosen.count < k { chosen.insert(Int(rng.next() % UInt64(inputSize))) }
                cols.append(contentsOf: chosen.sorted().map { Int32($0) })
            case .explicit(let lists):
                cols.append(contentsOf: lists[i].map { Int32($0) })
            }
            rows.append(Int32(cols.count))
        }
        rowStart = rows
        column = cols
        let n = cols.count
        var w = [Float](repeating: 0, count: n)
        var s = [Int8](repeating: 1, count: n)
        for k in 0..<n {
            w[k] = abs(rng.nextGaussian()) * weightScale
            if rng.nextUnit() < inhibitoryFraction { s[k] = -1 }
        }
        weight = w
        sign = s
        release = [Float](repeating: 0.5, count: n)
        resources = [Float](repeating: 1, count: n)
        eligibility = [Float](repeating: 0, count: n)
        bias = [Float](repeating: 0, count: ids.count)
        threshold = [Float](repeating: 0, count: ids.count)
        potential = [Float](repeating: 0, count: ids.count)
        output = [Float](repeating: 0, count: ids.count)
        preActivation = [Float](repeating: 0, count: ids.count)
        averageRate = [Float](repeating: targetRate, count: ids.count)
        lastInput = [Float](repeating: 0, count: inputSize)
    }

    var synapseCount: Int { column.count }

    /// One forward tick. Returns the population output vector.
    @discardableResult
    func step(_ input: [Float], modulators: NeuromodulatorState = NeuromodulatorState(), extraDrive: [Float]? = nil) -> [Float] {
        precondition(input.count == inputSize, "\(name): input \(input.count) ≠ \(inputSize)")
        lastInput = input
        let gain = modulators.outputGain / NeuromodulatorState().outputGain
        var branchSums = [Float](repeating: 0, count: branchCount)

        input.withUnsafeBufferPointer { x in
            weight.withUnsafeBufferPointer { w in
                for i in 0..<size {
                    let start = Int(rowStart[i]), end = Int(rowStart[i + 1])
                    for b in 0..<branchCount { branchSums[b] = 0 }
                    var k = start
                    var local = 0
                    while k < end {
                        let pre = x[Int(column[k])]
                        var eff: Float = 1
                        if stpEnabled {
                            release[k] += (baselineRelease - release[k]) / tauFacilitation
                            resources[k] += (1 - resources[k]) / tauDepression
                            eff = (release[k] * resources[k]) / baselineRelease
                            let used = release[k] * resources[k] * pre
                            release[k] += baselineRelease * (1 - release[k]) * pre
                            resources[k] = max(0, resources[k] - used)
                        }
                        branchSums[local % branchCount] += Float(sign[k]) * w[k] * eff * pre
                        k += 1
                        local += 1
                    }
                    var drive: Float = 0
                    if branchCount == 1 {
                        drive = branchSums[0]
                    } else {
                        for b in 0..<branchCount {
                            drive += NeuroMath.sigmoid(branchSlope * (branchSums[b] - branchThreshold))
                        }
                    }
                    if let extra = extraDrive { drive += extra[i] }
                    potential[i] = leak * potential[i] + drive + bias[i]
                    let pre = potential[i] - threshold[i]
                    preActivation[i] = pre
                    var y = activation.apply(pre) * gain
                    if activation == .spiking && y > 0 { potential[i] = 0 }
                    if y.isNaN { y = 0 }
                    output[i] = y
                }
            }
        }

        if let k = kWinners, k < size {
            applyKWinners(k)
        }

        // Homeostasis + eligibility.
        for i in 0..<size {
            averageRate[i] = averageRate[i] * 0.95 + output[i] * 0.05
            if homeostasisRate > 0 {
                threshold[i] += homeostasisRate * (averageRate[i] - targetRate)
            }
            let post = activation.derivative(preActivation[i], output: output[i])
            let start = Int(rowStart[i]), end = Int(rowStart[i + 1])
            if rule == .hebbian {
                continue
            }
            for k in start..<end {
                eligibility[k] = eligibility[k] * traceDecay + input[Int(column[k])] * post
            }
        }
        return output
    }

    private func applyKWinners(_ k: Int) {
        guard k > 0 else {
            for i in 0..<size { output[i] = 0 }
            return
        }
        // Partial selection of the k-th largest value.
        var values = output
        let kth = Self.kthLargest(&values, k)
        var kept = 0
        for i in 0..<size {
            if output[i] >= kth && output[i] > 0 && kept < k {
                kept += 1
            } else {
                output[i] = 0
            }
        }
    }

    /// Quickselect for the k-th largest element (1-based k).
    static func kthLargest(_ a: inout [Float], _ k: Int) -> Float {
        var lo = 0, hi = a.count - 1
        let target = k - 1
        var rng = SplitMix64(seed: UInt64(a.count &* 2654435761))
        while lo < hi {
            let pivotIndex = lo + Int(rng.next() % UInt64(hi - lo + 1))
            let pivot = a[pivotIndex]
            a.swapAt(pivotIndex, hi)
            var store = lo
            for i in lo..<hi where a[i] > pivot {
                a.swapAt(store, i)
                store += 1
            }
            a.swapAt(store, hi)
            if store == target { return a[store] }
            if store < target { lo = store + 1 } else { hi = store - 1 }
        }
        return a[lo]
    }

    /// Indices of currently active neurons (output above `level`).
    func activeIndices(level: Float = 0.5) -> [Int] {
        (0..<size).filter { output[$0] > level }
    }

    /// Three-factor learning with an optional per-neuron teaching signal
    /// (supervised error, climbing-fibre error…).
    func learn(modulators: NeuromodulatorState, teaching: [Float]? = nil, rateScale: Float = 1) {
        let eta = learningRate * rateScale * modulators.learningGain
        for i in 0..<size {
            let t = teaching?[i] ?? 0
            let start = Int(rowStart[i]), end = Int(rowStart[i + 1])
            switch rule {
            case .none:
                continue
            case .hebbian:
                let y = output[i]
                guard y > 0 else { continue }
                for k in start..<end {
                    let pre = lastInput[Int(column[k])]
                    let signed = Float(sign[k]) * weight[k]
                    let updated = signed + eta * y * (pre - y * signed)
                    setSigned(k, updated)
                }
            case .threeFactor, .stdp:
                let m = receptors.thirdFactor(modulators, teaching: t)
                if m == 0 { continue }
                for k in start..<end where eligibility[k] != 0 {
                    let signed = Float(sign[k]) * weight[k]
                    setSigned(k, signed + eta * m * eligibility[k])
                }
                bias[i] += eta * m * activation.derivative(preActivation[i], output: output[i]) * 0.5
            case .cerebellarLTD:
                // Microzones without a climbing-fibre signal are left untouched.
                guard t != 0 else { continue }
                for k in start..<end {
                    let pre = lastInput[Int(column[k])]
                    guard pre != 0 else { continue }
                    let signed = Float(sign[k]) * weight[k]
                    // error > 0 (climbing fibre fired) → LTD on active parallel fibres; error < 0 → LTP.
                    setSigned(k, signed - eta * t * pre)
                }
            }
        }
    }

    /// Normalise each neuron's afferent weight vector (synaptic scaling).
    func synapticScaling(targetNorm: Float) {
        for i in 0..<size {
            let start = Int(rowStart[i]), end = Int(rowStart[i + 1])
            var norm: Float = 0
            for k in start..<end { norm += weight[k] * weight[k] }
            norm = norm.squareRoot()
            guard norm > 1e-6 else { continue }
            let scale = targetNorm / norm
            for k in start..<end { weight[k] *= scale }
        }
    }

    @inline(__always)
    private func setSigned(_ k: Int, _ value: Float) {
        let v = NeuroMath.clamp(value, -weightLimit, weightLimit)
        sign[k] = v < 0 ? -1 : 1
        weight[k] = abs(v)
    }

    /// Signed weight from neuron `row` to input `col` (linear scan of the row).
    func signedWeight(row: Int, input col: Int) -> Float? {
        guard let k = synapseIndex(row: row, input: col) else { return nil }
        return Float(sign[k]) * weight[k]
    }

    func synapseIndex(row: Int, input col: Int) -> Int? {
        let start = Int(rowStart[row]), end = Int(rowStart[row + 1])
        for k in start..<end where Int(column[k]) == col { return k }
        return nil
    }

    func assignSigned(_ k: Int, _ value: Float) { setSigned(k, value) }

    /// Signed dense weight row (for inspection/visualisation).
    func signedRow(_ row: Int) -> [Float] {
        var out = [Float](repeating: 0, count: inputSize)
        let start = Int(rowStart[row]), end = Int(rowStart[row + 1])
        for k in start..<end { out[Int(column[k])] = Float(sign[k]) * weight[k] }
        return out
    }

    func resetDynamics() {
        for i in 0..<size { potential[i] = 0; output[i] = 0 }
        for k in 0..<column.count { release[k] = baselineRelease; resources[k] = 1; eligibility[k] = 0 }
    }

    // MARK: Persistence

    func archive(into w: inout BinaryWriter) {
        w.write(name)
        w.write(UInt32(size))
        w.write(UInt32(inputSize))
        w.write(ids)
        w.write(rowStart)
        w.write(column)
        w.write(weight)
        w.write(sign)
        w.write(bias)
        w.write(threshold)
    }

    /// Restore learned parameters. Topology must match (same name/size/inputs/synapse count).
    func restore(from r: inout BinaryReader) throws {
        let storedName = try r.readString()
        let storedSize = Int(try r.read(UInt32.self))
        let storedInputs = Int(try r.read(UInt32.self))
        let storedIDs = try r.readUInt64s()
        let storedRows = try r.readInt32s()
        let storedCols = try r.readInt32s()
        let storedWeights = try r.readFloats()
        let storedSigns = try r.readInt8s()
        let storedBias = try r.readFloats()
        let storedThreshold = try r.readFloats()
        guard storedName == name, storedSize == size, storedInputs == inputSize,
              storedCols.count == column.count, storedWeights.count == weight.count else {
            throw BinaryArchiveError.versionMismatch
        }
        ids = storedIDs
        rowStart = storedRows
        column = storedCols
        weight = storedWeights
        sign = storedSigns
        bias = storedBias
        threshold = storedThreshold
    }
}
