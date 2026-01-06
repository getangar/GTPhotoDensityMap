//
//  PhotoLocationManager.swift
//  PhotoDensityMap
//
//  Created with Claude
//

import Foundation
import Photos
import CoreLocation
import Combine
import MapKit

// MARK: - Heatmap Data Model

struct HeatmapData {
    let grid: [[Double]]           // 2D grid of density values
    let gridWidth: Int
    let gridHeight: Int
    let boundingBox: MKCoordinateRegion
    let maxDensity: Double
    let cellSizeDegrees: Double
    
    static func empty() -> HeatmapData {
        HeatmapData(
            grid: [],
            gridWidth: 0,
            gridHeight: 0,
            boundingBox: MKCoordinateRegion(),
            maxDensity: 0,
            cellSizeDegrees: 0
        )
    }
}

@MainActor
class PhotoLocationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var photoLocations: [PhotoLocation] = []
    @Published private(set) var heatmapData: HeatmapData?
    
    @Published private(set) var totalPhotosCount: Int = 0
    @Published private(set) var loadedPhotosCount: Int = 0
    @Published private(set) var totalPhotosWithLocation: Int = 0
    
    /// Controls the radius/spread of heat points (adjustable via UI)
    @Published var heatmapRadius: Double = 50 {
        didSet {
            regenerateHeatmap()
        }
    }
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var currentHeatmapTask: Task<Void, Never>?
    private var currentMapRegion: MKCoordinateRegion?
    
    // MARK: - Initialization
    
    init() {
        // Listen for map region changes to regenerate heatmap
        NotificationCenter.default.publisher(for: .mapRegionChanged)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] notification in
                if let region = notification.object as? MKCoordinateRegion {
                    self?.currentMapRegion = region
                    self?.regenerateHeatmap()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = currentStatus
        
        switch currentStatus {
        case .authorized, .limited:
            loadPhotoLocations()
        case .notDetermined:
            Task {
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                await MainActor.run {
                    self.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        self.loadPhotoLocations()
                    }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }
    
    // MARK: - Load Photos
    
    private func loadPhotoLocations() {
        guard !isLoading else { return }
        isLoading = true
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            // Fetch all image assets
            let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            
            await MainActor.run {
                self.totalPhotosCount = assets.count
            }
            
            var locations: [PhotoLocation] = []
            var processedCount = 0
            
            // Process in batches for better performance
            let batchSize = 500
            
            assets.enumerateObjects { asset, index, _ in
                if let location = asset.location {
                    let photoLocation = PhotoLocation(
                        id: asset.localIdentifier,
                        coordinate: location.coordinate,
                        creationDate: asset.creationDate
                    )
                    locations.append(photoLocation)
                }
                
                processedCount += 1
                
                // Update UI periodically
                if processedCount % batchSize == 0 {
                    let currentCount = processedCount
                    let currentLocations = locations.count
                    Task { @MainActor in
                        self.loadedPhotosCount = currentCount
                        self.totalPhotosWithLocation = currentLocations
                    }
                }
            }
            
            // Final update
            await MainActor.run {
                self.loadedPhotosCount = processedCount
                self.totalPhotosWithLocation = locations.count
                self.photoLocations = locations
                self.generateInitialHeatmap()
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Heatmap Generation
    
    private func generateInitialHeatmap() {
        guard !photoLocations.isEmpty else { return }
        
        // Calculate bounding box for all photos
        let coordinates = photoLocations.map(\.coordinate)
        if let boundingBox = MKCoordinateRegion.boundingBox(for: coordinates) {
            currentMapRegion = boundingBox
            generateHeatmap(for: boundingBox)
        }
    }
    
    private func regenerateHeatmap() {
        guard let region = currentMapRegion else { return }
        generateHeatmap(for: region)
    }
    
    private func generateHeatmap(for region: MKCoordinateRegion) {
        // Cancel any pending heatmap generation
        currentHeatmapTask?.cancel()
        
        currentHeatmapTask = Task {
            let data = await calculateHeatmapData(
                locations: photoLocations,
                region: region,
                radius: heatmapRadius
            )
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.heatmapData = data
            }
        }
    }
    
    private func calculateHeatmapData(
        locations: [PhotoLocation],
        region: MKCoordinateRegion,
        radius: Double
    ) async -> HeatmapData {
        
        guard !locations.isEmpty else { return .empty() }
        
        // Grid resolution based on view size (higher = more detail, slower)
        let gridSize = 150
        
        // Calculate cell size in degrees
        let cellSizeLat = region.span.latitudeDelta / Double(gridSize)
        let cellSizeLon = region.span.longitudeDelta / Double(gridSize)
        
        // Create density grid
        var grid = Array(repeating: Array(repeating: 0.0, count: gridSize), count: gridSize)
        
        // Bounds of the region
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        
        // Radius in grid cells (affected by the slider)
        let radiusCells = Int(radius / 10) + 1
        
        // For each photo location, add heat to nearby cells
        for location in locations {
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude
            
            // Convert to grid coordinates
            let gridX = Int((lon - minLon) / cellSizeLon)
            let gridY = Int((lat - minLat) / cellSizeLat)
            
            // Skip if outside grid
            guard gridX >= 0 && gridX < gridSize && gridY >= 0 && gridY < gridSize else {
                continue
            }
            
            // Add heat with Gaussian falloff
            for dx in -radiusCells...radiusCells {
                for dy in -radiusCells...radiusCells {
                    let nx = gridX + dx
                    let ny = gridY + dy
                    
                    guard nx >= 0 && nx < gridSize && ny >= 0 && ny < gridSize else {
                        continue
                    }
                    
                    // Gaussian falloff based on distance
                    let distance = sqrt(Double(dx * dx + dy * dy))
                    let sigma = Double(radiusCells) / 2.5
                    let weight = exp(-(distance * distance) / (2 * sigma * sigma))
                    
                    grid[nx][ny] += weight
                }
            }
        }
        
        // Find maximum density for normalization
        var maxDensity = 0.0
        for row in grid {
            for value in row {
                maxDensity = max(maxDensity, value)
            }
        }
        
        return HeatmapData(
            grid: grid,
            gridWidth: gridSize,
            gridHeight: gridSize,
            boundingBox: region,
            maxDensity: maxDensity,
            cellSizeDegrees: cellSizeLat
        )
    }
    
    // MARK: - Statistics
    
    var dateRange: (earliest: Date, latest: Date)? {
        let dates = photoLocations.compactMap(\.creationDate)
        guard let earliest = dates.min(), let latest = dates.max() else {
            return nil
        }
        return (earliest, latest)
    }
}
