//
//  SettingsView.swift
//  SemanticImageSearch
//
//  Application settings view.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("thumbnailQuality") private var thumbnailQuality: Double = 0.7
    @AppStorage("semanticWeight") private var semanticWeight: Double = 0.7
    @AppStorage("autoRescan") private var autoRescan: Bool = false
    @AppStorage("rescanInterval") private var rescanInterval: Int = 24
    
    var body: some View {
        TabView {
            GeneralSettingsTab(
                semanticWeight: $semanticWeight,
                autoRescan: $autoRescan,
                rescanInterval: $rescanInterval
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            StorageSettingsTab(
                thumbnailQuality: $thumbnailQuality
            )
            .tabItem {
                Label("Storage", systemImage: "internaldrive")
            }
            
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @Binding var semanticWeight: Double
    @Binding var autoRescan: Bool
    @Binding var rescanInterval: Int
    
    var body: some View {
        Form {
            Section("Search") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Semantic vs Text Weight")
                        Spacer()
                        Text("\(Int(semanticWeight * 100))% / \(Int((1 - semanticWeight) * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $semanticWeight, in: 0...1, step: 0.1)
                    
                    HStack {
                        Text("Semantic")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Automatic Scanning") {
                Toggle("Automatically rescan folders", isOn: $autoRescan)
                
                if autoRescan {
                    Picker("Rescan interval", selection: $rescanInterval) {
                        Text("Every hour").tag(1)
                        Text("Every 6 hours").tag(6)
                        Text("Every 12 hours").tag(12)
                        Text("Daily").tag(24)
                        Text("Weekly").tag(168)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Storage Settings

struct StorageSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @Binding var thumbnailQuality: Double
    
    @State private var databaseSize: String = "Calculating..."
    @State private var indexSize: String = "Calculating..."
    
    var body: some View {
        Form {
            Section("Thumbnail Quality") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Quality")
                        Spacer()
                        Text("\(Int(thumbnailQuality * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $thumbnailQuality, in: 0.3...1.0, step: 0.1)
                    
                    Text("Lower quality reduces storage but may affect thumbnail appearance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Storage Usage") {
                HStack {
                    Text("Database")
                    Spacer()
                    Text(databaseSize)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Vector Index")
                    Spacer()
                    Text(indexSize)
                        .foregroundColor(.secondary)
                }
                
                Button("Clear All Data...") {
                    // Would show confirmation dialog
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            calculateStorageUsage()
        }
    }
    
    private func calculateStorageUsage() {
        Task {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let appFolder = appSupport.appendingPathComponent("SemanticImageSearch")
            
            // Database size
            let dbPath = appFolder.appendingPathComponent("database.sqlite")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath.path),
               let size = attrs[.size] as? Int64 {
                databaseSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            } else {
                databaseSize = "0 bytes"
            }
            
            // Index size
            let indexPath = appFolder.appendingPathComponent("vector_index.plist")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: indexPath.path),
               let size = attrs[.size] as? Int64 {
                indexSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            } else {
                indexSize = "0 bytes"
            }
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Semantic Image Search")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0")
                .foregroundColor(.secondary)
            
            Text("Search your images using natural language descriptions. Powered by local machine learning for complete privacy.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            Text("© 2024 Semantic Image Search")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
