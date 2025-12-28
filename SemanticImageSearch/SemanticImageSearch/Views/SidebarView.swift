//
//  SidebarView.swift
//  SemanticImageSearch
//
//  Sidebar navigation view.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: MainViewModel
    
    @State private var selectedFolder: FolderItem?
    
    var body: some View {
        List(selection: $selectedFolder) {
            // Library Section
            Section("Library") {
                NavigationLink(value: "all") {
                    Label {
                        HStack {
                            Text("All Images")
                            Spacer()
                            Text("\(appState.totalIndexedImages)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
            }
            
            // Folders Section
            Section {
                ForEach(appState.folders) { folder in
                    FolderRow(folder: folder)
                        .contextMenu {
                            Button("Rescan Folder") {
                                viewModel.rescanFolder(folder)
                            }
                            
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                            }
                            
                            Divider()
                            
                            Button("Remove Folder", role: .destructive) {
                                viewModel.removeFolder(folder)
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Folders")
                    Spacer()
                    Button(action: {
                        viewModel.openFolderPicker()
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Quick Actions Section
            Section("Actions") {
                Button(action: {
                    appState.showFolderPicker = true
                }) {
                    Label("Manage Folders", systemImage: "folder.badge.gear")
                }
                
                Button(action: {
                    Task {
                        await appState.rescanAllFolders()
                    }
                }) {
                    Label("Rescan All", systemImage: "arrow.clockwise")
                }
                .disabled(appState.status.isProcessing)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 250)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }) {
                    Image(systemName: "sidebar.left")
                }
            }
        }
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: FolderItem
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text("\(folder.imageCount) images")
                    
                    if let lastScanned = folder.lastScannedAt {
                        Text("•")
                        Text(lastScanned, style: .relative)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Show processing indicator
            if case .scanning(let path) = appState.status, path == folder.path {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationSplitView {
        SidebarView()
            .environmentObject(AppState.shared)
            .environmentObject(MainViewModel())
    } detail: {
        Text("Detail")
    }
}
