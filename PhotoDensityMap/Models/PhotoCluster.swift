//
//  PhotoCluster.swift
//  PhotoDensityMap
//
//  Created with Claude
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Photo Location

struct PhotoLocation: Identifiable {
    let id: String // PHAsset localIdentifier
    let coordinate: CLLocationCoordinate2D
    let creationDate: Date?
    
    init(id: String, coordinate: CLLocationCoordinate2D, creationDate: Date? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.creationDate = creationDate
    }
}

// MARK: - Coordinate Region Extension

extension MKCoordinateRegion {
    /// Check if a coordinate is within this region
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latInRange = coordinate.latitude >= center.latitude - span.latitudeDelta / 2 &&
                        coordinate.latitude <= center.latitude + span.latitudeDelta / 2
        let lonInRange = coordinate.longitude >= center.longitude - span.longitudeDelta / 2 &&
                        coordinate.longitude <= center.longitude + span.longitudeDelta / 2
        return latInRange && lonInRange
    }
    
    /// Calculate bounding box from a set of coordinates
    static func boundingBox(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        // Add padding
        let latPadding = (maxLat - minLat) * 0.1
        let lonPadding = (maxLon - minLon) * 0.1
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) + latPadding),
            longitudeDelta: max(0.01, (maxLon - minLon) + lonPadding)
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
}
