//
//  StatusBarView.swift
//  SemanticImageSearch
//
//  Status bar showing processing status.
//

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 6) {
                statusIcon
                
                Text(appState.status.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Progress bar (if processing)
            if case .processing(let current, let total) = appState.status {
                ProgressView(value: Double(current), total: Double(total))
                    .frame(width: 100)
            }
            
            Spacer()
            
            // Stats
            HStack(spacing: 16) {
                Label("\(appState.totalIndexedImages) images", systemImage: "photo")
                Label("\(appState.folders.count) folders", systemImage: "folder")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch appState.status {
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .scanning, .processing, .indexing, .searching:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        StatusBarView()
            .environmentObject(AppState.shared)
    }
}
