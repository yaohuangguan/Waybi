import Foundation
import MapLibre

/// Bound Waybi's label candidates before layout, rather than repeatedly indexing
/// every symbol in an overzoomed z14 tile on the UI thread. Geometry and POI hit
/// targets stay intact. The margin lets labels enter smoothly while panning.
final class MapLabelViewportLimiter {
    private var originals: [String: NSPredicate] = [:]
    private var coverage: MLNCoordinateBounds?
    private var zoom: Double = 0
    private var active = false

    func styleLoaded(_ map: MLNMapView) {
        originals.removeAll()
        coverage = nil
        active = map.style?.layer(withIdentifier: "waybi-poi-label") != nil
        update(map)
    }

    func update(_ map: MLNMapView) {
        guard active, let style = map.style, map.bounds.width > 0, map.bounds.height > 0 else { return }
        let layers = style.layers.compactMap { $0 as? MLNSymbolStyleLayer }
            .filter { $0.sourceIdentifier == "openmaptiles" }
        guard map.zoomLevel >= 15 else {
            if coverage != nil {
                for layer in layers { if let original = originals[layer.identifier] { layer.predicate = original } }
                coverage = nil
            }
            return
        }
        let visible = map.visibleCoordinateBounds
        if let coverage, abs(map.zoomLevel - zoom) < 0.75,
           contains(coverage, visible) { return }

        let expanded = map.bounds.insetBy(dx: -map.bounds.width * 0.4, dy: -map.bounds.height * 0.4)
        let bounds = map.convert(expanded, toCoordinateBoundsFrom: map)
        guard bounds.sw.latitude.isFinite, bounds.ne.latitude.isFinite,
              bounds.sw.longitude.isFinite, bounds.ne.longitude.isFinite,
              bounds.sw.latitude < bounds.ne.latitude else { return }
        let geometry: [String: Any]
        if bounds.sw.longitude > bounds.ne.longitude {
            geometry = ["type": "MultiPolygon", "coordinates": [
                [ring(bounds.sw.longitude, 180, bounds.sw.latitude, bounds.ne.latitude)],
                [ring(-180, bounds.ne.longitude, bounds.sw.latitude, bounds.ne.latitude)],
            ]]
        } else {
            geometry = ["type": "Polygon", "coordinates": [
                ring(bounds.sw.longitude, bounds.ne.longitude, bounds.sw.latitude, bounds.ne.latitude)
            ]]
        }
        // Distance includes intersecting roads; `within` would incorrectly drop
        // a long street crossing the viewport with endpoints outside the box.
        let spatial = NSPredicate(mglJSONObject: ["<=", ["distance", geometry], 0])
        for layer in layers {
            let original = originals[layer.identifier] ?? layer.predicate ?? NSPredicate(value: true)
            originals[layer.identifier] = original
            layer.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [original, spatial])
        }
        coverage = bounds
        zoom = map.zoomLevel
    }

    private func contains(_ outer: MLNCoordinateBounds, _ inner: MLNCoordinateBounds) -> Bool {
        func positive(_ value: Double) -> Double { (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
        let outerWidth = positive(outer.ne.longitude - outer.sw.longitude)
        let innerWidth = positive(inner.ne.longitude - inner.sw.longitude)
        let offset = positive(inner.sw.longitude - outer.sw.longitude)
        return offset + innerWidth <= outerWidth &&
               inner.sw.latitude >= outer.sw.latitude && inner.ne.latitude <= outer.ne.latitude
    }

    private func ring(_ west: Double, _ east: Double, _ south: Double, _ north: Double) -> [[Double]] {
        [[west, south], [east, south], [east, north], [west, north], [west, south]]
    }
}
