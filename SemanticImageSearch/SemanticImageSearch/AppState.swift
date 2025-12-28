//
//  AppState.swift
//  SemanticImageSearch
//
//  Central application state management.
//

import SwiftUI
import Combine

/// Processing status for the application
enum ProcessingStatus: Equatable {
    case idle
    case scanning(folder: String)
    case processing(current: Int, total: Int)
    case indexing
    case searching
    case error(message: String)
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .scanning(let folder):
            return "Scanning: \(folder)"
        case .processing(let current, let total):
            return "Processing: \(current)/\(total)"
        case .indexing:
            return "Building index..."
        case .searching:
            return "Searching..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .idle, .error:
            return false
        default:
            return true
        }
    }
}

/// Central application state
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    // MARK: - Published Properties
    
    /// Current search query
    @Published var searchQuery: String = ""
    
    /// Search results
    @Published var searchResults: [SearchResult] = []
    
    /// Currently selected image for detail view
    @Published var selectedImage: ImageItem?
    
    /// All monitored folders
    @Published var folders: [FolderItem] = []
    
    /// Processing status
    @Published var status: ProcessingStatus = .idle
    
    /// Show folder picker
    @Published var showFolderPicker: Bool = false
    
    /// Total indexed images count
    @Published var totalIndexedImages: Int = 0
    
    /// Current view mode
    @Published var viewMode: ViewMode = .grid
    
    /// Search mode
    @Published var searchMode: SearchMode = .combined
    
    // MARK: - Services
    
    private(set) lazy var databaseService = DatabaseService.shared
    private(set) lazy var vectorService = VectorService.shared
    private(set) lazy var searchEngine = SearchEngine.shared
    private(set) lazy var folderManager = FolderManager.shared
    private(set) lazy var imageProcessor = ImageProcessingService.shared
    
    // MARK: - Cancellables
    
    private var cancellables = Set<AnyCancellable>()
    private var searchDebouncer: AnyCancellable?
    
    // MARK: - Initialization
    
    private init() {
        setupSearchDebounce()
        Task {
            await loadInitialData()
        }
    }
    
    // MARK: - Setup
    
    private func setupSearchDebounce() {
        searchDebouncer = $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                Task {
                    await self?.performSearch(query: query)
                }
            }
    }
    
    // MARK: - Data Loading
    
    private func loadInitialData() async {
        do {
            folders = try await databaseService.loadFolders()
            totalIndexedImages = try await databaseService.getImageCount()
        } catch {
            status = .error(message: error.localizedDescription)
        }
    }
    
    // MARK: - Folder Management
    
    func addFolder(url: URL) async {
        do {
            // Request security-scoped access
            guard url.startAccessingSecurityScopedResource() else {
                status = .error(message: "Cannot access folder")
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Create bookmark for persistent access
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            let folder = FolderItem(
                id: UUID(),
                path: url.path,
                bookmarkData: bookmarkData,
                addedAt: Date(),
                lastScannedAt: nil,
                imageCount: 0
            )
            
            try await databaseService.saveFolder(folder)
            folders.append(folder)
            
            // Start scanning
            await scanFolder(folder)
        } catch {
            status = .error(message: error.localizedDescription)
        }
    }
    
    func removeFolder(_ folder: FolderItem) async {
        do {
            try await databaseService.deleteFolder(folder.id)
            try await databaseService.deleteImagesInFolder(folder.id)
            folders.removeAll { $0.id == folder.id }
            totalIndexedImages = try await databaseService.getImageCount()
            
            // Rebuild vector index
            await vectorService.rebuildIndex()
        } catch {
            status = .error(message: error.localizedDescription)
        }
    }
    
    func rescanFolder(_ folder: FolderItem) async {
        await scanFolder(folder)
    }
    
    func rescanAllFolders() async {
        for folder in folders {
            await scanFolder(folder)
        }
    }
    
    // MARK: - Scanning
    
    private func scanFolder(_ folder: FolderItem) async {
        status = .scanning(folder: folder.path)
        
        do {
            // Resolve bookmark
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: folder.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                status = .error(message: "Cannot resolve folder bookmark")
                return
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                status = .error(message: "Cannot access folder")
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Find all images
            let imageURLs = try await folderManager.scanForImages(in: url)
            
            // Process images
            let total = imageURLs.count
            for (index, imageURL) in imageURLs.enumerated() {
                status = .processing(current: index + 1, total: total)
                
                // Check if already processed
                let exists = try await databaseService.imageExists(path: imageURL.path)
                if exists {
                    continue
                }
                
                // Process image
                if let imageItem = await imageProcessor.processImage(at: imageURL, folderId: folder.id) {
                    try await databaseService.saveImage(imageItem)
                    await vectorService.addVector(imageItem.vector, id: imageItem.id)
                }
            }
            
            // Update folder stats
            var updatedFolder = folder
            updatedFolder.lastScannedAt = Date()
            updatedFolder.imageCount = try await databaseService.getImageCountInFolder(folder.id)
            try await databaseService.updateFolder(updatedFolder)
            
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index] = updatedFolder
            }
            
            totalIndexedImages = try await databaseService.getImageCount()
            status = .idle
        } catch {
            status = .error(message: error.localizedDescription)
        }
    }
    
    // MARK: - Search
    
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        status = .searching
        
        do {
            searchResults = try await searchEngine.search(
                query: query,
                mode: searchMode,
                limit: 50
            )
            status = .idle
        } catch {
            status = .error(message: error.localizedDescription)
            searchResults = []
        }
    }
    
    func clearSearch() {
        searchQuery = ""
        searchResults = []
    }
}

// MARK: - Enums

enum ViewMode: String, CaseIterable {
    case grid = "Grid"
    case list = "List"
    
    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

enum SearchMode: String, CaseIterable {
    case semantic = "Semantic"
    case text = "Text (OCR)"
    case combined = "Combined"
    
    var description: String {
        switch self {
        case .semantic:
            return "Search by image content using AI"
        case .text:
            return "Search by text found in images"
        case .combined:
            return "Combined semantic and text search"
        }
    }
}
