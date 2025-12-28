//
//  MainViewModel.swift
//  SemanticImageSearch
//
//  Main view model for the application.
//

import SwiftUI
import Combine

/// Main view model handling user interactions
@MainActor
final class MainViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// Grid column count
    @Published var gridColumns: Int = 4
    
    /// Show image detail sheet
    @Published var showImageDetail: Bool = false
    
    /// Show folder management sheet
    @Published var showFolderManager: Bool = false
    
    /// Currently hovered image
    @Published var hoveredImage: ImageItem?
    
    /// Sort order for results
    @Published var sortOrder: SortOrder = .relevance
    
    /// Filter options
    @Published var filter: FilterOptions = FilterOptions()
    
    // MARK: - Properties
    
    private var appState: AppState { AppState.shared }
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Respond to window size changes for grid columns
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateGridColumns()
            }
            .store(in: &cancellables)
    }
    
    private func updateGridColumns() {
        // Adjust columns based on window width
        guard let window = NSApp.keyWindow else { return }
        let width = window.frame.width - 250 // Sidebar width
        
        let itemWidth: CGFloat = 180
        let newColumns = max(2, Int(width / itemWidth))
        
        if gridColumns != newColumns {
            withAnimation(.easeInOut(duration: 0.2)) {
                gridColumns = newColumns
            }
        }
    }
    
    // MARK: - Actions
    
    /// Open folder picker
    func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to add to the image library"
        panel.prompt = "Add Folder"
        
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            
            Task { @MainActor in
                await self?.appState.addFolder(url: url)
            }
        }
    }
    
    /// Remove a folder
    func removeFolder(_ folder: FolderItem) {
        Task {
            await appState.removeFolder(folder)
        }
    }
    
    /// Rescan a folder
    func rescanFolder(_ folder: FolderItem) {
        Task {
            await appState.rescanFolder(folder)
        }
    }
    
    /// Open image in Finder
    func showInFinder(_ image: ImageItem) {
        NSWorkspace.shared.selectFile(image.path, inFileViewerRootedAtPath: "")
    }
    
    /// Open image with default app
    func openImage(_ image: ImageItem) {
        NSWorkspace.shared.open(image.url)
    }
    
    /// Copy image path to clipboard
    func copyPath(_ image: ImageItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(image.path, forType: .string)
    }
    
    /// Copy image to clipboard
    func copyImage(_ image: ImageItem) {
        guard let nsImage = image.loadFullImage() else { return }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }
    
    /// Select image for detail view
    func selectImage(_ image: ImageItem) {
        appState.selectedImage = image
        showImageDetail = true
    }
    
    /// Clear selection
    func clearSelection() {
        appState.selectedImage = nil
        showImageDetail = false
    }
    
    // MARK: - Sorting
    
    /// Get sorted results
    func sortedResults(_ results: [SearchResult]) -> [SearchResult] {
        switch sortOrder {
        case .relevance:
            return results.sorted(by: >)
        case .dateNewest:
            return results.sorted { $0.image.createdAt > $1.image.createdAt }
        case .dateOldest:
            return results.sorted { $0.image.createdAt < $1.image.createdAt }
        case .nameAZ:
            return results.sorted { $0.image.fileName.lowercased() < $1.image.fileName.lowercased() }
        case .nameZA:
            return results.sorted { $0.image.fileName.lowercased() > $1.image.fileName.lowercased() }
        case .sizeSmallest:
            return results.sorted { $0.image.fileSize < $1.image.fileSize }
        case .sizeLargest:
            return results.sorted { $0.image.fileSize > $1.image.fileSize }
        }
    }
    
    /// Get filtered results
    func filteredResults(_ results: [SearchResult]) -> [SearchResult] {
        var filtered = results
        
        // Filter by minimum score
        if filter.minScore > 0 {
            filtered = filtered.filter { $0.combinedScore >= Float(filter.minScore) / 100 }
        }
        
        // Filter by file type
        if !filter.fileTypes.isEmpty {
            filtered = filtered.filter { filter.fileTypes.contains($0.image.fileExtension) }
        }
        
        // Filter by date range
        if let startDate = filter.startDate {
            filtered = filtered.filter { $0.image.createdAt >= startDate }
        }
        
        if let endDate = filter.endDate {
            filtered = filtered.filter { $0.image.createdAt <= endDate }
        }
        
        return filtered
    }
}

// MARK: - Supporting Types

enum SortOrder: String, CaseIterable {
    case relevance = "Relevance"
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case nameAZ = "Name (A-Z)"
    case nameZA = "Name (Z-A)"
    case sizeSmallest = "Size (Smallest)"
    case sizeLargest = "Size (Largest)"
    
    var icon: String {
        switch self {
        case .relevance: return "sparkles"
        case .dateNewest, .dateOldest: return "calendar"
        case .nameAZ, .nameZA: return "textformat"
        case .sizeSmallest, .sizeLargest: return "doc"
        }
    }
}

struct FilterOptions {
    var minScore: Int = 0
    var fileTypes: Set<String> = []
    var startDate: Date?
    var endDate: Date?
    
    var isActive: Bool {
        minScore > 0 || !fileTypes.isEmpty || startDate != nil || endDate != nil
    }
    
    mutating func reset() {
        minScore = 0
        fileTypes = []
        startDate = nil
        endDate = nil
    }
}
