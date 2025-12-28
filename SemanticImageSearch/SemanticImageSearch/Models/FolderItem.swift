//
//  FolderItem.swift
//  SemanticImageSearch
//
//  Data model representing a monitored folder.
//

import Foundation

/// Represents a folder being monitored for images
struct FolderItem: Identifiable, Codable, Equatable {
    /// Unique identifier
    let id: UUID
    
    /// Full path to the folder
    let path: String
    
    /// Security-scoped bookmark data for persistent access
    let bookmarkData: Data
    
    /// Date when the folder was added
    let addedAt: Date
    
    /// Last scan date
    var lastScannedAt: Date?
    
    /// Number of indexed images in this folder
    var imageCount: Int
    
    // MARK: - Computed Properties
    
    /// Folder name
    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
    
    /// Folder URL
    var url: URL {
        URL(fileURLWithPath: path)
    }
    
    /// Formatted last scan date
    var formattedLastScan: String {
        guard let date = lastScannedAt else {
            return "Never"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Equatable
    
    static func == (lhs: FolderItem, rhs: FolderItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Access

extension FolderItem {
    /// Resolve and access the folder URL with security scope
    func accessURL() throws -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        
        return url
    }
    
    /// Stop accessing the security-scoped resource
    func stopAccess() {
        url.stopAccessingSecurityScopedResource()
    }
}
