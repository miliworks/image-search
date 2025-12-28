//
//  SearchResultsView.swift
//  SemanticImageSearch
//
//  Grid view displaying search results.
//

import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: MainViewModel
    
    @State private var showFilters = false
    
    private var results: [SearchResult] {
        let filtered = viewModel.filteredResults(appState.searchResults)
        return viewModel.sortedResults(filtered)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ResultsToolbar(
                resultCount: results.count,
                showFilters: $showFilters
            )
            
            Divider()
            
            // Content
            if appState.status == .searching {
                SearchingView()
            } else if results.isEmpty {
                NoResultsView()
            } else {
                ResultsGrid(results: results)
            }
        }
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Results Toolbar

struct ResultsToolbar: View {
    @EnvironmentObject private var viewModel: MainViewModel
    let resultCount: Int
    @Binding var showFilters: Bool
    
    var body: some View {
        HStack {
            Text("\(resultCount) results")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // View mode
            Picker("View", selection: Binding(
                get: { AppState.shared.viewMode },
                set: { AppState.shared.viewMode = $0 }
            )) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            
            Divider()
                .frame(height: 20)
            
            // Sort
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        HStack {
                            Image(systemName: order.icon)
                            Text(order.rawValue)
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
            
            // Filter
            Button(action: { showFilters.toggle() }) {
                Image(systemName: viewModel.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .popover(isPresented: $showFilters) {
                FilterPopover()
                    .environmentObject(viewModel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Filter Popover

struct FilterPopover: View {
    @EnvironmentObject private var viewModel: MainViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filters")
                .font(.headline)
            
            // Minimum score
            VStack(alignment: .leading, spacing: 4) {
                Text("Minimum Relevance")
                    .font(.subheadline)
                
                HStack {
                    Slider(value: Binding(
                        get: { Double(viewModel.filter.minScore) },
                        set: { viewModel.filter.minScore = Int($0) }
                    ), in: 0...100, step: 5)
                    
                    Text("\(viewModel.filter.minScore)%")
                        .frame(width: 40)
                }
            }
            
            // File types
            VStack(alignment: .leading, spacing: 4) {
                Text("File Types")
                    .font(.subheadline)
                
                HStack {
                    ForEach(["jpg", "png", "gif", "heic"], id: \.self) { type in
                        Toggle(type.uppercased(), isOn: Binding(
                            get: { viewModel.filter.fileTypes.contains(type) },
                            set: { isOn in
                                if isOn {
                                    viewModel.filter.fileTypes.insert(type)
                                } else {
                                    viewModel.filter.fileTypes.remove(type)
                                }
                            }
                        ))
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            Divider()
            
            Button("Reset Filters") {
                viewModel.filter.reset()
            }
            .disabled(!viewModel.filter.isActive)
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Results Grid

struct ResultsGrid: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: MainViewModel
    let results: [SearchResult]
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(results) { result in
                    ImageGridItem(result: result)
                        .onTapGesture {
                            viewModel.selectImage(result.image)
                        }
                        .contextMenu {
                            ImageContextMenu(image: result.image)
                                .environmentObject(viewModel)
                        }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Image Context Menu

struct ImageContextMenu: View {
    @EnvironmentObject private var viewModel: MainViewModel
    let image: ImageItem
    
    var body: some View {
        Group {
            Button("Open") {
                viewModel.openImage(image)
            }
            
            Button("Show in Finder") {
                viewModel.showInFinder(image)
            }
            
            Divider()
            
            Button("Copy Image") {
                viewModel.copyImage(image)
            }
            
            Button("Copy Path") {
                viewModel.copyPath(image)
            }
        }
    }
}

// MARK: - Searching View

struct SearchingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Searching...")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - No Results View

struct NoResultsView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No results found")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Try different search terms or add more folders")
                .foregroundColor(.secondary)
            
            if case .error(let message) = appState.status {
                Text(message)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    SearchResultsView()
        .environmentObject(AppState.shared)
        .environmentObject(MainViewModel())
}
