//
//  ImageDetailView.swift
//  SemanticImageSearch
//
//  Detailed view for a single image.
//

import SwiftUI

struct ImageDetailView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    
    let image: ImageItem
    
    @State private var fullImage: NSImage?
    @State private var selectedTab = 0
    @State private var zoomScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(image.fileName)
                    .font(.headline)
                
                Spacer()
                
                // Actions
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.openImage(image)
                    }) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    
                    Button(action: {
                        viewModel.showInFinder(image)
                    }) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    
                    Button(action: {
                        viewModel.copyImage(image)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .buttonStyle(.bordered)
                
                Divider()
                    .frame(height: 20)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // Content
            HSplitView {
                // Image preview
                ZStack {
                    Color(.controlBackgroundColor)
                    
                    if let image = fullImage {
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(zoomScale)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .frame(minWidth: 400)
                .overlay(alignment: .bottom) {
                    // Zoom controls
                    HStack(spacing: 16) {
                        Button(action: { zoomScale = max(0.25, zoomScale - 0.25) }) {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        
                        Text("\(Int(zoomScale * 100))%")
                            .frame(width: 50)
                        
                        Button(action: { zoomScale = min(4.0, zoomScale + 0.25) }) {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        
                        Button(action: { zoomScale = 1.0 }) {
                            Text("100%")
                        }
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding()
                }
                
                // Info panel
                VStack(alignment: .leading, spacing: 0) {
                    // Tabs
                    Picker("", selection: $selectedTab) {
                        Text("Info").tag(0)
                        Text("OCR Text").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    Divider()
                    
                    // Tab content
                    ScrollView {
                        if selectedTab == 0 {
                            ImageInfoPanel(image: image)
                        } else {
                            OCRTextPanel(text: image.ocrText)
                        }
                    }
                }
                .frame(width: 300)
                .background(Color(.windowBackgroundColor))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadFullImage()
        }
    }
    
    private func loadFullImage() {
        Task {
            fullImage = image.loadFullImage()
        }
    }
}

// MARK: - Image Info Panel

struct ImageInfoPanel: View {
    let image: ImageItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // File info
            InfoSection(title: "File") {
                InfoRow(label: "Name", value: image.fileName)
                InfoRow(label: "Size", value: image.formattedSize)
                InfoRow(label: "Type", value: image.fileExtension.uppercased())
                InfoRow(label: "Path", value: image.path, selectable: true)
            }
            
            // Image info
            InfoSection(title: "Image") {
                InfoRow(label: "Dimensions", value: image.dimensionsString)
                InfoRow(label: "Aspect Ratio", value: formatAspectRatio(image.width, image.height))
            }
            
            // Dates
            InfoSection(title: "Dates") {
                InfoRow(label: "Created", value: formatDate(image.createdAt))
                InfoRow(label: "Indexed", value: formatDate(image.indexedAt))
            }
            
            // Vector info
            InfoSection(title: "Index") {
                InfoRow(label: "Vector Dimensions", value: "\(image.vector.count)")
                InfoRow(label: "Has OCR Text", value: image.ocrText != nil ? "Yes" : "No")
            }
        }
        .padding()
    }
    
    private func formatAspectRatio(_ width: Int, _ height: Int) -> String {
        let gcd = gcd(width, height)
        return "\(width/gcd):\(height/gcd)"
    }
    
    private func gcd(_ a: Int, _ b: Int) -> Int {
        return b == 0 ? a : gcd(b, a % b)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Info Section

struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String
    var selectable: Bool = false
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            if selectable {
                Text(value)
                    .textSelection(.enabled)
                    .lineLimit(3)
            } else {
                Text(value)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .font(.callout)
    }
}

// MARK: - OCR Text Panel

struct OCRTextPanel: View {
    let text: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = text, !text.isEmpty {
                HStack {
                    Text("Extracted Text")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Text(text)
                    .textSelection(.enabled)
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No text detected in this image")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    let mockImage = ImageItem(
        id: UUID(),
        path: "/Users/test/Pictures/sample.jpg",
        folderId: UUID(),
        fileName: "sample.jpg",
        fileSize: 2048000,
        width: 1920,
        height: 1080,
        createdAt: Date(),
        indexedAt: Date(),
        vector: Array(repeating: 0.1, count: 512),
        ocrText: "This is some sample OCR text extracted from the image.",
        thumbnailData: nil
    )
    
    ImageDetailView(image: mockImage)
        .environmentObject(MainViewModel())
}
