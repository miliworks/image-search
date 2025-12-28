//
//  ContentView.swift
//  SemanticImageSearch
//
//  Main content view with navigation structure.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = MainViewModel()
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(viewModel)
        } detail: {
            VStack(spacing: 0) {
                // Search bar
                SearchBar()
                
                Divider()
                
                // Main content
                if appState.searchQuery.isEmpty {
                    WelcomeView()
                        .environmentObject(viewModel)
                } else {
                    SearchResultsView()
                        .environmentObject(viewModel)
                }
                
                // Status bar
                StatusBarView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $viewModel.showImageDetail) {
            if let image = appState.selectedImage {
                ImageDetailView(image: image)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $appState.showFolderPicker) {
            FolderListView()
                .environmentObject(viewModel)
        }
        .onAppear {
            Task {
                try? await appState.vectorService.initialize()
            }
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search images...", text: $appState.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                
                if !appState.searchQuery.isEmpty {
                    Button(action: {
                        appState.clearSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(.textBackgroundColor))
            .cornerRadius(10)
            
            // Search mode picker
            Picker("Mode", selection: $appState.searchMode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .help("Search mode: \(appState.searchMode.description)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App icon and title
            VStack(spacing: 16) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Semantic Image Search")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Search your images using natural language")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            // Quick stats
            if appState.totalIndexedImages > 0 {
                HStack(spacing: 40) {
                    StatCard(
                        icon: "photo.fill",
                        value: "\(appState.totalIndexedImages)",
                        label: "Images Indexed"
                    )
                    
                    StatCard(
                        icon: "folder.fill",
                        value: "\(appState.folders.count)",
                        label: "Folders"
                    )
                }
            }
            
            // Actions
            VStack(spacing: 16) {
                if appState.folders.isEmpty {
                    Button(action: {
                        viewModel.openFolderPicker()
                    }) {
                        Label("Add Your First Folder", systemImage: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("Type in the search box above to find images")
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 20) {
                    SearchSuggestion(text: "sunset on beach")
                    SearchSuggestion(text: "people smiling")
                    SearchSuggestion(text: "documents with text")
                }
            }
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct SearchSuggestion: View {
    @EnvironmentObject private var appState: AppState
    let text: String
    
    var body: some View {
        Button(action: {
            appState.searchQuery = text
        }) {
            Text("\"\(text)\"")
                .font(.callout)
                .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
