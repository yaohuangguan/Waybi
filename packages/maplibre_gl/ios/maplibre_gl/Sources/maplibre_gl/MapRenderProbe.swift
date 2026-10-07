import Foundation
import UIKit
import MapLibre
import QuartzCore

/// Explicit device-tooling probe. Never runs during a normal app launch.
/// Launch with WAYBI_MAP_PERFORMANCE_PROBE=1; results stay in this app's Documents.
final class MapRenderProbe {
    private weak var map: MLNMapView?
    private var started = false
    private var recording = false
    private var previousFrame: CFTimeInterval?
    private var intervals: [Double] = []
    private var encoding: [Double] = []
    private var rendering: [Double] = []
    private var results: [[String: Any]] = []
    private var originalCamera: MLNMapCamera?
    private let mode = ProcessInfo.processInfo.environment["WAYBI_MAP_PERFORMANCE_PROBE"]
    static func make() -> MapRenderProbe? {
        ProcessInfo.processInfo.environment["WAYBI_MAP_PERFORMANCE_PROBE"] == nil ? nil : MapRenderProbe()
    }
    func start(_ map: MLNMapView) {
        guard !started else { return }
        started = true
        self.map = map
        originalCamera = map.camera
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.phase(0) }
    }
    func frame(encodingTime: Double, renderingTime: Double) {
        guard recording else { return }
        let now = CACurrentMediaTime()
        if let previousFrame { intervals.append((now - previousFrame) * 1000) }
        previousFrame = now
        encoding.append(encodingTime * 1000)
        rendering.append(renderingTime * 1000)
    }
    private func phase(_ index: Int) {
        guard let map else { return }
        let phases: [(String, Double)] = [("street", 16), ("near", 18), ("very-near", 19), ("near-poi-off", 18), ("near-labels-off", 18)]
        guard index < phases.count else {
            save()
            for layer in map.style?.layers ?? [] { if layer is MLNSymbolStyleLayer { layer.isVisible = true } }
            if let originalCamera { map.setCamera(originalCamera, animated: false) }
            return
        }
        let (name, zoom) = phases[index]
        for layer in map.style?.layers ?? [] {
            if layer is MLNSymbolStyleLayer {
                layer.isVisible = index != 4 && !(index == 3 && layer.identifier == "waybi-poi-label")
            }
        }
        map.setCenter(CLLocationCoordinate2D(latitude: -36.852, longitude: 174.766),
                      zoomLevel: zoom, direction: 0, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            self.intervals = []; self.encoding = []; self.rendering = []
            self.previousFrame = nil; self.recording = true
            self.pan(0, phase: index, name: name, zoom: zoom)
        }
    }
    private func pan(_ iteration: Int, phase index: Int, name: String, zoom: Double) {
        guard let map else { return }
        if iteration == 4 {
            recording = false
            results.append([
                "name": name, "zoom": zoom, "frames": encoding.count,
                "interval_p50_ms": percentile(intervals, 0.5),
                "interval_p95_ms": percentile(intervals, 0.95),
                "encoding_p95_ms": percentile(encoding, 0.95),
                "rendering_p95_ms": percentile(rendering, 0.95),
                "over_33ms": intervals.filter { $0 > 33.4 }.count,
            ])
            phase(index + 1)
            return
        }
        let camera = map.camera
        let delta = 360 / pow(2, zoom) * 0.55
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: -36.852,
                          longitude: 174.766 + (iteration % 2 == 0 ? delta : -delta))
        map.setCamera(camera, withDuration: 2, animationTimingFunction: CAMediaTimingFunction(name: .linear),
                      completionHandler: { [weak self] in
            self?.pan(iteration + 1, phase: index, name: name, zoom: zoom)
        })
    }
    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
    }
    private func save() {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: [
                "device": UIDevice.current.model, "os": UIDevice.current.systemVersion,
                "probe": mode ?? "", "phases": results,
              ], options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("waybi-map-performance.json"), options: .atomic)
    }
}
