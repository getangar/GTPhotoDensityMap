//
//  ContentView.swift
//  PhotoDensityMap
//
//  Created with Claude
//

import SwiftUI
import MapKit
import Photos

struct ContentView: View {
    @EnvironmentObject var photoManager: PhotoLocationManager
    @StateObject private var mapViewModel = MapViewModel()
    
    var body: some View {
        ZStack {
            // Main Map View with Heatmap
            HeatmapMapView(
                mapViewModel: mapViewModel,
                photoLocations: photoManager.photoLocations,
                heatmapData: photoManager.heatmapData
            )
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top bar with status and controls
                HStack {
                    StatusBarView(photoManager: photoManager)
                    Spacer()
                    MapControlsView(mapViewModel: mapViewModel, photoManager: photoManager)
                }
                .padding()
                
                Spacer()
                
                // Bottom legend
                if !photoManager.photoLocations.isEmpty {
                    HeatmapLegendView(maxDensity: photoManager.heatmapData?.maxDensity ?? 1)
                        .padding()
                }
            }
            
            // Loading/Authorization overlay
            if photoManager.authorizationStatus == .notDetermined ||
               photoManager.authorizationStatus == .denied ||
               photoManager.isLoading {
                AuthorizationOverlay(photoManager: photoManager)
            }
        }
        .onAppear {
            photoManager.requestAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            mapViewModel.zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            mapViewModel.zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetView)) { _ in
            mapViewModel.resetView()
        }
    }
}

// MARK: - Heatmap Map View (AppKit wrapper)

struct HeatmapMapView: NSViewRepresentable {
    @ObservedObject var mapViewModel: MapViewModel
    let photoLocations: [PhotoLocation]
    let heatmapData: HeatmapData?
    
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        mapView.showsCompass = true
        mapView.showsZoomControls = true
        mapView.showsScale = true
        
        mapViewModel.mapView = mapView
        
        return mapView
    }
    
    func updateNSView(_ mapView: MKMapView, context: Context) {
        // Remove existing heatmap overlay
        let existingOverlays = mapView.overlays.filter { $0 is HeatmapOverlay }
        mapView.removeOverlays(existingOverlays)
        
        // Add new heatmap overlay if we have data
        if let heatmapData = heatmapData, !photoLocations.isEmpty {
            let overlay = HeatmapOverlay(heatmapData: heatmapData)
            mapView.addOverlay(overlay, level: .aboveRoads)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: HeatmapMapView
        
        init(_ parent: HeatmapMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heatmapOverlay = overlay as? HeatmapOverlay {
                return HeatmapOverlayRenderer(overlay: heatmapOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Dispatch updates asynchronously to avoid publishing changes during view updates
            DispatchQueue.main.async {
                self.parent.mapViewModel.currentRegion = mapView.region
                
                // Trigger heatmap recalculation based on new zoom level
                NotificationCenter.default.post(
                    name: .mapRegionChanged,
                    object: mapView.region
                )
            }
        }
    }
}

// MARK: - Heatmap Overlay

class HeatmapOverlay: NSObject, MKOverlay {
    let heatmapData: HeatmapData
    
    var coordinate: CLLocationCoordinate2D {
        heatmapData.boundingBox.center
    }
    
    var boundingMapRect: MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: heatmapData.boundingBox.center.latitude + heatmapData.boundingBox.span.latitudeDelta / 2,
            longitude: heatmapData.boundingBox.center.longitude - heatmapData.boundingBox.span.longitudeDelta / 2
        ))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: heatmapData.boundingBox.center.latitude - heatmapData.boundingBox.span.latitudeDelta / 2,
            longitude: heatmapData.boundingBox.center.longitude + heatmapData.boundingBox.span.longitudeDelta / 2
        ))
        return MKMapRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }
    
    init(heatmapData: HeatmapData) {
        self.heatmapData = heatmapData
        super.init()
    }
}

// MARK: - Heatmap Overlay Renderer

class HeatmapOverlayRenderer: MKOverlayRenderer {
    
    private var cachedImage: CGImage?
    private var cachedRect: MKMapRect?
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heatmapOverlay = overlay as? HeatmapOverlay else { return }
        
        let heatmapData = heatmapOverlay.heatmapData
        let overlayRect = overlay.boundingMapRect
        
        // Calculate the drawing rect
        let drawRect = rect(for: overlayRect)
        
        // Generate or use cached heatmap image
        let image = generateHeatmapImage(
            data: heatmapData,
            size: CGSize(width: max(1, drawRect.width), height: max(1, drawRect.height)),
            zoomScale: zoomScale
        )
        
        // Draw the heatmap
        context.saveGState()
        context.setAlpha(0.7) // Semi-transparent overlay
        
        if let image = image {
            context.draw(image, in: drawRect)
        }
        
        context.restoreGState()
    }
    
    private func generateHeatmapImage(data: HeatmapData, size: CGSize, zoomScale: MKZoomScale) -> CGImage? {
        let width = Int(max(1, min(size.width, 2048)))
        let height = Int(max(1, min(size.height, 2048)))
        
        guard width > 0, height > 0 else { return nil }
        
        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Clear background
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        let gridWidth = data.grid.count
        let gridHeight = data.grid.first?.count ?? 0
        
        guard gridWidth > 0, gridHeight > 0 else { return nil }
        
        let cellWidth = CGFloat(width) / CGFloat(gridWidth)
        let cellHeight = CGFloat(height) / CGFloat(gridHeight)
        
        // Draw each cell with interpolated colors
        for x in 0..<gridWidth {
            for y in 0..<gridHeight {
                let density = data.grid[x][y]
                if density > 0 {
                    let color = colorForDensity(density / data.maxDensity)
                    context.setFillColor(color)
                    
                    // Draw cell with slight overlap for smoother appearance
                    let rect = CGRect(
                        x: CGFloat(x) * cellWidth - 1,
                        y: CGFloat(gridHeight - 1 - y) * cellHeight - 1,
                        width: cellWidth + 2,
                        height: cellHeight + 2
                    )
                    context.fillEllipse(in: rect.insetBy(dx: -cellWidth * 0.5, dy: -cellHeight * 0.5))
                }
            }
        }
        
        // Apply Gaussian blur for smooth gradient effect
        if let image = context.makeImage() {
            return applyBlur(to: image, radius: max(cellWidth, cellHeight) * 1.5)
        }
        
        return context.makeImage()
    }
    
    private func applyBlur(to image: CGImage, radius: CGFloat) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        
        guard let outputImage = filter?.outputImage else { return image }
        
        let ciContext = CIContext()
        let extent = ciImage.extent
        
        return ciContext.createCGImage(outputImage, from: extent)
    }
    
    private func colorForDensity(_ normalizedDensity: Double) -> CGColor {
        // Google Photos style gradient: transparent -> blue -> cyan -> green -> yellow -> orange -> red
        let density = max(0, min(1, normalizedDensity))
        
        // Color stops matching Google Photos heatmap
        let colors: [(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)] = [
            (0.0, 0.0, 1.0, 0.0),    // Transparent blue (density = 0)
            (0.0, 0.4, 1.0, 0.4),    // Light blue
            (0.0, 0.8, 1.0, 0.5),    // Cyan
            (0.0, 1.0, 0.5, 0.6),    // Green-cyan
            (0.5, 1.0, 0.0, 0.7),    // Yellow-green
            (1.0, 1.0, 0.0, 0.75),   // Yellow
            (1.0, 0.6, 0.0, 0.8),    // Orange
            (1.0, 0.0, 0.0, 0.85)    // Red (density = 1)
        ]
        
        let scaledDensity = density * Double(colors.count - 1)
        let index = min(Int(scaledDensity), colors.count - 2)
        let fraction = CGFloat(scaledDensity - Double(index))
        
        let c1 = colors[index]
        let c2 = colors[index + 1]
        
        let r = c1.r + (c2.r - c1.r) * fraction
        let g = c1.g + (c2.g - c1.g) * fraction
        let b = c1.b + (c2.b - c1.b) * fraction
        let a = c1.a + (c2.a - c1.a) * fraction
        
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Status Bar View

struct StatusBarView: View {
    @ObservedObject var photoManager: PhotoLocationManager
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundColor(.secondary)
            
            if photoManager.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading photos...")
                    .foregroundColor(.secondary)
            } else {
                Text("\(photoManager.totalPhotosWithLocation) photos with location")
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Map Controls View

struct MapControlsView: View {
    @ObservedObject var mapViewModel: MapViewModel
    @ObservedObject var photoManager: PhotoLocationManager
    
    var body: some View {
        HStack(spacing: 8) {
            // Heatmap intensity slider
            HStack(spacing: 4) {
                Image(systemName: "circle.dotted")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Slider(value: $photoManager.heatmapRadius, in: 10...100)
                    .frame(width: 80)
                Image(systemName: "circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            
            Divider()
                .frame(height: 20)
            
            Button(action: { mapViewModel.zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            
            Button(action: { mapViewModel.zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            
            Divider()
                .frame(height: 20)
            
            Picker("Map Style", selection: $mapViewModel.mapStyle) {
                Image(systemName: "map").tag(MapStyle.standard)
                Image(systemName: "globe.americas").tag(MapStyle.satellite)
                Image(systemName: "map.fill").tag(MapStyle.hybrid)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Heatmap Legend View

struct HeatmapLegendView: View {
    let maxDensity: Double
    
    var body: some View {
        HStack(spacing: 16) {
            Text("Photo density:")
                .foregroundColor(.secondary)
                .font(.caption)
            
            // Gradient bar
            HeatmapGradientBar()
                .frame(width: 150, height: 12)
                .clipShape(Capsule())
            
            HStack(spacing: 4) {
                Text("Low")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("—")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("High")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HeatmapGradientBar: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.0, green: 0.4, blue: 1.0),
                Color(red: 0.0, green: 0.8, blue: 1.0),
                Color(red: 0.0, green: 1.0, blue: 0.5),
                Color(red: 0.5, green: 1.0, blue: 0.0),
                Color(red: 1.0, green: 1.0, blue: 0.0),
                Color(red: 1.0, green: 0.6, blue: 0.0),
                Color(red: 1.0, green: 0.0, blue: 0.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Authorization Overlay

struct AuthorizationOverlay: View {
    @ObservedObject var photoManager: PhotoLocationManager
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                if photoManager.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Loading photo locations...")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("\(photoManager.loadedPhotosCount) of \(photoManager.totalPhotosCount) photos processed")
                            .foregroundColor(.white.opacity(0.7))
                        
                        ProgressView(value: Double(photoManager.loadedPhotosCount), total: Double(max(1, photoManager.totalPhotosCount)))
                            .progressViewStyle(.linear)
                            .frame(width: 300)
                        
                        if photoManager.totalPhotosWithLocation > 0 {
                            Text("\(photoManager.totalPhotosWithLocation) photos with GPS data found")
                                .foregroundColor(.green.opacity(0.8))
                                .font(.caption)
                        }
                    }
                } else if photoManager.authorizationStatus == .denied {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)
                        
                        Text("Photo Access Required")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Text("Please allow access to your photos in System Settings to use this app.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: 400)
                        
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Requesting photo access...")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let mapRegionChanged = Notification.Name("mapRegionChanged")
}

#Preview {
    ContentView()
        .environmentObject(PhotoLocationManager())
}
