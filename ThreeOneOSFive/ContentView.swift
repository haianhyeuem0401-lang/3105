import SwiftUI

/// ContentView được rút gọn: chỉ hiển thị PatchProjectsView (gắn patch).
/// Tất cả các tab khác (Repository, Files, Cleaner, Wallpaper, Search) đã bị xoá.
struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @State private var showSettings = false
    @State private var showLogs = false

    var body: some View {
        PatchProjectsView(
            onOpenSettings: { showSettings = true },
            onOpenLogs: { showLogs = true }
        )
        .tint(AppTheme.accent)
        .imageScale(.small)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            // request đến → PatchProjectsView tự handle
            _ = requestID
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            _ = requestID
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .patchStorePresentation(patchStore)
    }
}
