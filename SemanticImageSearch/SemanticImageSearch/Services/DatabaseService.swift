//
//  DatabaseService.swift
//  SemanticImageSearch
//
//  SQLite-based persistent storage service.
//

import Foundation
import SQLite3

/// Database service for persistent storage using SQLite
actor DatabaseService {
    static let shared = DatabaseService()
    
    // MARK: - Properties
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    // MARK: - Initialization
    
    private init() {
        // Get application support directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let appFolder = appSupport.appendingPathComponent("SemanticImageSearch", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        dbPath = appFolder.appendingPathComponent("database.sqlite").path
        
        openDatabase()
        createTables()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Enable WAL mode for better performance
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA synchronous = NORMAL")
        execute("PRAGMA cache_size = -64000") // 64MB cache
    }
    
    private func createTables() {
        // Folders table
        execute("""
            CREATE TABLE IF NOT EXISTS folders (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL,
                bookmark_data BLOB NOT NULL,
                added_at REAL NOT NULL,
                last_scanned_at REAL,
                image_count INTEGER DEFAULT 0
            )
        """)
        
        // Images table
        execute("""
            CREATE TABLE IF NOT EXISTS images (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                folder_id TEXT NOT NULL,
                file_name TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                created_at REAL NOT NULL,
                indexed_at REAL NOT NULL,
                vector BLOB NOT NULL,
                ocr_text TEXT,
                thumbnail_data BLOB,
                FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
            )
        """)
        
        // Create indexes
        execute("CREATE INDEX IF NOT EXISTS idx_images_folder ON images(folder_id)")
        execute("CREATE INDEX IF NOT EXISTS idx_images_path ON images(path)")
        
        // Full-text search for OCR text
        execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS images_fts USING fts5(
                id,
                ocr_text,
                content='images',
                content_rowid='rowid'
            )
        """)
        
        // Triggers to keep FTS in sync
        execute("""
            CREATE TRIGGER IF NOT EXISTS images_ai AFTER INSERT ON images BEGIN
                INSERT INTO images_fts(id, ocr_text) VALUES (new.id, new.ocr_text);
            END
        """)
        
        execute("""
            CREATE TRIGGER IF NOT EXISTS images_ad AFTER DELETE ON images BEGIN
                INSERT INTO images_fts(images_fts, id, ocr_text) VALUES ('delete', old.id, old.ocr_text);
            END
        """)
        
        execute("""
            CREATE TRIGGER IF NOT EXISTS images_au AFTER UPDATE ON images BEGIN
                INSERT INTO images_fts(images_fts, id, ocr_text) VALUES ('delete', old.id, old.ocr_text);
                INSERT INTO images_fts(id, ocr_text) VALUES (new.id, new.ocr_text);
            END
        """)
    }
    
    // MARK: - Helper Methods
    
    private func execute(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQL Error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }
    
    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing statement: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        return statement
    }
    
    // MARK: - Folder Operations
    
    func saveFolder(_ folder: FolderItem) throws {
        let sql = """
            INSERT OR REPLACE INTO folders (id, path, bookmark_data, added_at, last_scanned_at, image_count)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, folder.id.uuidString, -1, nil)
        sqlite3_bind_text(statement, 2, folder.path, -1, nil)
        folder.bookmarkData.withUnsafeBytes { ptr in
            sqlite3_bind_blob(statement, 3, ptr.baseAddress, Int32(folder.bookmarkData.count), nil)
        }
        sqlite3_bind_double(statement, 4, folder.addedAt.timeIntervalSince1970)
        if let lastScanned = folder.lastScannedAt {
            sqlite3_bind_double(statement, 5, lastScanned.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_int(statement, 6, Int32(folder.imageCount))
        
        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.insertFailed
        }
    }
    
    func updateFolder(_ folder: FolderItem) throws {
        try saveFolder(folder)
    }
    
    func loadFolders() throws -> [FolderItem] {
        let sql = "SELECT id, path, bookmark_data, added_at, last_scanned_at, image_count FROM folders"
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        var folders: [FolderItem] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idString = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: idString)),
                  let pathCStr = sqlite3_column_text(statement, 1) else {
                continue
            }
            
            let path = String(cString: pathCStr)
            
            let bookmarkBytes = sqlite3_column_blob(statement, 2)
            let bookmarkLength = sqlite3_column_bytes(statement, 2)
            let bookmarkData = Data(bytes: bookmarkBytes!, count: Int(bookmarkLength))
            
            let addedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            
            let lastScannedAt: Date?
            if sqlite3_column_type(statement, 4) != SQLITE_NULL {
                lastScannedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            } else {
                lastScannedAt = nil
            }
            
            let imageCount = Int(sqlite3_column_int(statement, 5))
            
            let folder = FolderItem(
                id: id,
                path: path,
                bookmarkData: bookmarkData,
                addedAt: addedAt,
                lastScannedAt: lastScannedAt,
                imageCount: imageCount
            )
            
            folders.append(folder)
        }
        
        return folders
    }
    
    func deleteFolder(_ id: UUID) throws {
        let sql = "DELETE FROM folders WHERE id = ?"
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)
        
        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.deleteFailed
        }
    }
    
    // MARK: - Image Operations
    
    func saveImage(_ image: ImageItem) throws {
        let sql = """
            INSERT OR REPLACE INTO images 
            (id, path, folder_id, file_name, file_size, width, height, created_at, indexed_at, vector, ocr_text, thumbnail_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, image.id.uuidString, -1, nil)
        sqlite3_bind_text(statement, 2, image.path, -1, nil)
        sqlite3_bind_text(statement, 3, image.folderId.uuidString, -1, nil)
        sqlite3_bind_text(statement, 4, image.fileName, -1, nil)
        sqlite3_bind_int64(statement, 5, image.fileSize)
        sqlite3_bind_int(statement, 6, Int32(image.width))
        sqlite3_bind_int(statement, 7, Int32(image.height))
        sqlite3_bind_double(statement, 8, image.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 9, image.indexedAt.timeIntervalSince1970)
        
        // Store vector as compressed float array
        let vectorData = image.vector.withUnsafeBytes { Data($0) }
        vectorData.withUnsafeBytes { ptr in
            sqlite3_bind_blob(statement, 10, ptr.baseAddress, Int32(vectorData.count), nil)
        }
        
        if let ocrText = image.ocrText {
            sqlite3_bind_text(statement, 11, ocrText, -1, nil)
        } else {
            sqlite3_bind_null(statement, 11)
        }
        
        if let thumbnailData = image.thumbnailData {
            thumbnailData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 12, ptr.baseAddress, Int32(thumbnailData.count), nil)
            }
        } else {
            sqlite3_bind_null(statement, 12)
        }
        
        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.insertFailed
        }
    }
    
    func loadImage(id: UUID) throws -> ImageItem? {
        let sql = """
            SELECT id, path, folder_id, file_name, file_size, width, height, 
                   created_at, indexed_at, vector, ocr_text, thumbnail_data
            FROM images WHERE id = ?
        """
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return parseImageRow(statement)
    }
    
    func loadImages(ids: [UUID]) throws -> [ImageItem] {
        guard !ids.isEmpty else { return [] }
        
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT id, path, folder_id, file_name, file_size, width, height, 
                   created_at, indexed_at, vector, ocr_text, thumbnail_data
            FROM images WHERE id IN (\(placeholders))
        """
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        for (index, id) in ids.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), id.uuidString, -1, nil)
        }
        
        var images: [ImageItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let image = parseImageRow(statement) {
                images.append(image)
            }
        }
        
        return images
    }
    
    func imageExists(path: String) throws -> Bool {
        let sql = "SELECT 1 FROM images WHERE path = ? LIMIT 1"
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, path, -1, nil)
        
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    func deleteImage(id: UUID) throws {
        let sql = "DELETE FROM images WHERE id = ?"
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)
        
        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.deleteFailed
        }
    }
    
    func deleteImagesInFolder(_ folderId: UUID) throws {
        let sql = "DELETE FROM images WHERE folder_id = ?"
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, folderId.uuidString, -1, nil)
        
        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.deleteFailed
        }
    }
    
    func getImageCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM images"
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        
        return Int(sqlite3_column_int(statement, 0))
    }
    
    func getImageCountInFolder(_ folderId: UUID) throws -> Int {
        let sql = "SELECT COUNT(*) FROM images WHERE folder_id = ?"
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, folderId.uuidString, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        
        return Int(sqlite3_column_int(statement, 0))
    }
    
    // MARK: - Vector Operations
    
    func loadAllVectors() throws -> [(id: UUID, vector: [Float])] {
        let sql = "SELECT id, vector FROM images"
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        var results: [(id: UUID, vector: [Float])] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: idCStr)) else {
                continue
            }
            
            guard let vectorBytes = sqlite3_column_blob(statement, 1) else {
                continue
            }
            
            let vectorLength = Int(sqlite3_column_bytes(statement, 1)) / MemoryLayout<Float>.size
            let vector = Array(UnsafeBufferPointer(
                start: vectorBytes.assumingMemoryBound(to: Float.self),
                count: vectorLength
            ))
            
            results.append((id: id, vector: vector))
        }
        
        return results
    }
    
    // MARK: - Full-Text Search
    
    func searchByText(_ query: String, limit: Int = 50) throws -> [(id: UUID, snippet: String)] {
        let sql = """
            SELECT id, snippet(images_fts, 1, '<b>', '</b>', '...', 32) as snippet
            FROM images_fts
            WHERE ocr_text MATCH ?
            LIMIT ?
        """
        
        guard let statement = prepare(sql) else {
            throw DatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        
        // Prepare FTS5 query
        let ftsQuery = query.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
        sqlite3_bind_text(statement, 1, ftsQuery, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(limit))
        
        var results: [(id: UUID, snippet: String)] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: idCStr)),
                  let snippetCStr = sqlite3_column_text(statement, 1) else {
                continue
            }
            
            let snippet = String(cString: snippetCStr)
            results.append((id: id, snippet: snippet))
        }
        
        return results
    }
    
    // MARK: - Row Parsing
    
    private func parseImageRow(_ statement: OpaquePointer?) -> ImageItem? {
        guard let statement = statement,
              let idCStr = sqlite3_column_text(statement, 0),
              let id = UUID(uuidString: String(cString: idCStr)),
              let pathCStr = sqlite3_column_text(statement, 1),
              let folderIdCStr = sqlite3_column_text(statement, 2),
              let folderId = UUID(uuidString: String(cString: folderIdCStr)),
              let fileNameCStr = sqlite3_column_text(statement, 3) else {
            return nil
        }
        
        let path = String(cString: pathCStr)
        let fileName = String(cString: fileNameCStr)
        let fileSize = sqlite3_column_int64(statement, 4)
        let width = Int(sqlite3_column_int(statement, 5))
        let height = Int(sqlite3_column_int(statement, 6))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        let indexedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
        
        // Parse vector
        guard let vectorBytes = sqlite3_column_blob(statement, 9) else {
            return nil
        }
        let vectorLength = Int(sqlite3_column_bytes(statement, 9)) / MemoryLayout<Float>.size
        let vector = Array(UnsafeBufferPointer(
            start: vectorBytes.assumingMemoryBound(to: Float.self),
            count: vectorLength
        ))
        
        // Parse OCR text
        let ocrText: String?
        if sqlite3_column_type(statement, 10) != SQLITE_NULL,
           let ocrCStr = sqlite3_column_text(statement, 10) {
            ocrText = String(cString: ocrCStr)
        } else {
            ocrText = nil
        }
        
        // Parse thumbnail
        let thumbnailData: Data?
        if sqlite3_column_type(statement, 11) != SQLITE_NULL,
           let thumbBytes = sqlite3_column_blob(statement, 11) {
            let thumbLength = Int(sqlite3_column_bytes(statement, 11))
            thumbnailData = Data(bytes: thumbBytes, count: thumbLength)
        } else {
            thumbnailData = nil
        }
        
        return ImageItem(
            id: id,
            path: path,
            folderId: folderId,
            fileName: fileName,
            fileSize: fileSize,
            width: width,
            height: height,
            createdAt: createdAt,
            indexedAt: indexedAt,
            vector: vector,
            ocrText: ocrText,
            thumbnailData: thumbnailData
        )
    }
}

// MARK: - Errors

enum DatabaseError: Error, LocalizedError {
    case prepareFailed
    case insertFailed
    case deleteFailed
    case queryFailed
    
    var errorDescription: String? {
        switch self {
        case .prepareFailed:
            return "Failed to prepare SQL statement"
        case .insertFailed:
            return "Failed to insert data"
        case .deleteFailed:
            return "Failed to delete data"
        case .queryFailed:
            return "Failed to execute query"
        }
    }
}
