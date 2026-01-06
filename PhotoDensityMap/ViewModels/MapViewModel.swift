//
//  MapViewModel.swift
//  PhotoDensityMap
//
//  Created with Claude
//

import Foundation
import MapKit
import Combine

enum MapStyle: Int, CaseIterable {
    case standard
    case satellite
    case hybrid
    
    var mapType: MKMapType {
        switch self {
        case .standard:
            return .standard
        case .satellite:
            return .satellite
        case .hybrid:
            return .hybrid
        }
    }
}

@MainActor
class MapViewModel: ObservableObject {
    @Published var currentRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.4642, longitude: 9.1900), // Milan as default
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
    )
    
    @Published var mapStyle: MapStyle = .standard {
        didSet {
            mapView?.mapType = mapStyle.mapType
        }
    }
    
    @Published var isAnimating: Bool = false
    
    weak var mapView: MKMapView? {
        didSet {
            mapView?.mapType = mapStyle.mapType
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Observe map style changes
        $mapStyle
            .dropFirst() // Skip the initial value since it's already set
            .sink { [weak self] style in
                self?.mapView?.mapType = style.mapType
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Map Controls
    
    func zoomIn() {
        guard let mapView = mapView else { return }
        
        var region = mapView.region
        region.span.latitudeDelta /= 2
        region.span.longitudeDelta /= 2
        
        setRegion(region, animated: true)
    }
    
    func zoomOut() {
        guard let mapView = mapView else { return }
        
        var region = mapView.region
        region.span.latitudeDelta = min(region.span.latitudeDelta * 2, 180)
        region.span.longitudeDelta = min(region.span.longitudeDelta * 2, 360)
        
        setRegion(region, animated: true)
    }
    
    func resetView() {
        // Reset to show entire world
        let worldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 360)
        )
        setRegion(worldRegion, animated: true)
    }
    
    func centerOn(coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil) {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: span ?? MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        setRegion(region, animated: true)
    }
    
    func fitToShow(locations: [PhotoLocation]) {
        guard !locations.isEmpty else { return }
        
        let coordinates = locations.map(\.coordinate)
        if let boundingBox = MKCoordinateRegion.boundingBox(for: coordinates) {
            // Add some padding
            var region = boundingBox
            region.span.latitudeDelta *= 1.3
            region.span.longitudeDelta *= 1.3
            setRegion(region, animated: true)
        }
    }
    
    private func setRegion(_ region: MKCoordinateRegion, animated: Bool) {
        isAnimating = true
        mapView?.setRegion(region, animated: animated)
        
        // Reset animating flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isAnimating = false
        }
    }
    
    // MARK: - Zoom Level Calculation
    
    /// Returns a zoom level from 0 (world) to 20 (building level)
    var currentZoomLevel: Double {
        guard let mapView = mapView else { return 10 }
        
        let longitudeDelta = mapView.region.span.longitudeDelta
        let zoomLevel = log2(360 / longitudeDelta)
        return max(0, min(20, zoomLevel))
    }
    
    /// Clustering radius in meters based on current zoom level
    var clusteringRadius: Double {
        // At zoom level 0 (world view), large radius
        // At zoom level 20 (street level), small radius
        let baseRadius = 50000.0 // 50km at zoom 0
        return baseRadius / pow(2, currentZoomLevel / 2)
    }
}
