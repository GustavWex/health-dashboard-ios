import Foundation
import Testing
@testable import HealthCore

func close(_ a: Double?, _ b: Double, tol: Double = 1e-9) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tol
}

@Suite struct StatsTests {
    @Test func meanAndSampleSD() {
        let x: [Double] = [2, 4, 4, 4, 5, 5, 7, 9]
        #expect(Stats.mean(x) == 5)
        #expect(close(Stats.sd(x), 2.138089935299395))
        #expect(Stats.mean([]) == nil)
        #expect(Stats.sd([3]) == nil)
    }

    @Test(arguments: [
        (0.0, 1.0), (0.1, 1.0), (0.25, 1.75), (0.5, 3.5), (0.9, 6.8999999999999995), (1.0, 9.0)
    ])
    func percentileMatchesNumpy(p: Double, expected: Double) {
        let q: [Double] = [3, 1, 4, 1, 5, 9, 2, 6]
        #expect(close(Stats.percentile(q, p), expected))
    }

    @Test(arguments: [
        (0.0, 0.5), (1.0, 0.8413447460685429), (-1.96, 0.024997895148220435), (2.5, 0.9937903346742238)
    ])
    func normalCDFMatchesScipy(z: Double, expected: Double) {
        #expect(close(Stats.normalCDF(z), expected, tol: 1e-12))
    }

    @Test func slopeOfExactLine() {
        let pts = Fixture.series(0...9) { 1 + 2 * Double($0) }
        #expect(close(Stats.slopePerDay(pts), 2))
        #expect(Stats.slopePerDay(Array(pts.prefix(2))) == nil)
    }

    @Test func emaSeededWithFirstValue() {
        let out = BodyEngine.ema(Fixture.series(0...2) { 70 + Double($0) })
        #expect(close(out[0].value, 70))
        #expect(close(out[1].value, 70.2))
        #expect(close(out[2].value, 70.56))
    }
}
