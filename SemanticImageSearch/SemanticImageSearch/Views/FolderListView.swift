//
//  FolderListView.swift
//  SemanticImageSearch
//
//  View for managing monitored folders.
//

import SwiftUI

struct FolderListView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFolder: FolderItem?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Folders")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Folder list
            if appState.folders.isEmpty {
                EmptyFoldersView()
            } else {
                List(selection: $selectedFolder) {
                    ForEach(appState.folders) { folder in
                        FolderListRow(folder: folder)
                            .tag(folder)
                            .contextMenu {
                                FolderContextMenu(folder: folder)
                            }
                    }
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button(action: {
                    viewModel.openFolderPicker()
                }) {
                    Label("Add Folder", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                if let folder = selectedFolder {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                
                Button(action: {
                    Task {
                        await appState.rescanAllFolders()
                    }
                }) {
                    Label("Rescan All", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(appState.status.isProcessing)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .confirmationDialog(
            "Remove Folder?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let folder = selectedFolder {
                    viewModel.removeFolder(folder)
                    selectedFolder = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let folder = selectedFolder {
                Text("This will remove \"\(folder.name)\" and all its indexed images from the library. The original files will not be deleted.")
            }
        }
    }
}

// MARK: - Folder List Row

struct FolderListRow: View {
    let folder: FolderItem
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            // Folder icon
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)
                
                Text(folder.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 8) {
                    Label("\(folder.imageCount) images", systemImage: "photo")
                    
                    if let lastScanned = folder.lastScannedAt {
                        Text("•")
                        Text("Scanned \(lastScanned, style: .relative)")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status
            if case .scanning(let path) = appState.status, path == folder.path {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if case .processing(let current, let total) = appState.status {
                Text("\(current)/\(total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Folder Context Menu

struct FolderContextMenu: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: MainViewModel
    let folder: FolderItem
    
    var body: some View {
        Button("Rescan") {
            viewModel.rescanFolder(folder)
        }
        
        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
        }
        
        Divider()
        
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(folder.path, forType: .string)
        }
        
        Divider()
        
        Button("Remove", role: .destructive) {
            viewModel.removeFolder(folder)
        }
    }
}

// MARK: - Empty Folders View

struct EmptyFoldersView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Folders Added")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Add folders containing your images to start indexing")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                viewModel.openFolderPicker()
            }) {
                Label("Add Your First Folder", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    FolderListView()
        .environmentObject(AppState.shared)
        .environmentObject(MainViewModel())
}
