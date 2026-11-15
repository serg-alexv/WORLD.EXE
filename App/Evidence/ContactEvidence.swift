import WorldCore

extension ContactAction {
    var evidenceName: String {
        switch self {
        case .inspect(let n): return "inspect:\(n)"
        case .power(let n): return "power:\(n)"
        case .tune(let n): return "tune:\(n)"
        case .stabilize(let n): return "stabilize:\(n)"
        case .arm: return "arm"
        case .extract: return "extract"
        }
    }
}
