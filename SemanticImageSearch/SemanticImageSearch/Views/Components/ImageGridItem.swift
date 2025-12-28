//
//  ImageGridItem.swift
//  SemanticImageSearch
//
//  Grid item component for displaying image thumbnails.
//

import SwiftUI

struct ImageGridItem: View {
    let result: SearchResult
    
    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.controlBackgroundColor))
                        .frame(width: 160, height: 120)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                }
                
                // Hover overlay
                if isHovered {
                    Color.black.opacity(0.3)
                    
                    VStack {
                        Spacer()
                        HStack {
                            // Relevance badge
                            RelevanceBadge(score: result.combinedScore)
                            
                            Spacer()
                            
                            // Quick actions
                            HStack(spacing: 4) {
                                QuickActionButton(icon: "eye.fill") {
                                    // Preview handled by parent
                                }
                                
                                QuickActionButton(icon: "folder") {
                                    NSWorkspace.shared.selectFile(
                                        result.image.path,
                                        inFileViewerRootedAtPath: ""
                                    )
                                }
                            }
                        }
                        .padding(8)
                    }
                }
                
                // Text indicator
                if result.image.ocrText != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "text.viewfinder")
                                .font(.caption)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .frame(width: 160, height: 120)
            .cornerRadius(8)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(result.image.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 4) {
                    Text(result.image.formattedSize)
                    Text("•")
                    Text(result.image.dimensionsString)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
        }
        .frame(width: 160)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task {
            thumbnail = result.image.loadThumbnail()
        }
    }
}

// MARK: - Relevance Badge

struct RelevanceBadge: View {
    let score: Float
    
    private var color: Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.5 {
            return .orange
        } else {
            return .gray
        }
    }
    
    var body: some View {
        Text("\(Int(score * 100))%")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.white)
                .padding(4)
                .background(.ultraThinMaterial)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    // Create a mock result for preview
    let mockImage = ImageItem(
        id: UUID(),
        path: "/test/image.jpg",
        folderId: UUID(),
        fileName: "sample_image.jpg",
        fileSize: 1024000,
        width: 1920,
        height: 1080,
        createdAt: Date(),
        indexedAt: Date(),
        vector: [],
        ocrText: "Sample text",
        thumbnailData: nil
    )
    
    let mockResult = SearchResult.semantic(mockImage, score: 0.85)
    
    ImageGridItem(result: mockResult)
        .padding()
}
