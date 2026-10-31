import SwiftUI

struct KeyVerificationView: View {
    @EnvironmentObject private var keyService: KeyVerificationService
    @State private var keyInput: String = ""
    @State private var isSecure: Bool = true
    @FocusState private var keyFocused: Bool

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    AppTheme.accent.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Logo & branding ──────────────────────────────────
                    VStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.14))
                                .frame(width: 80, height: 80)

                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                        }

                        VStack(spacing: 6) {
                            Text("3105")
                                .font(.title.bold())
                                .foregroundStyle(.primary)

                            Text("by \(keyService.adminName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 36)

                    // ── Card nhập key ────────────────────────────────────
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Nhập Key Kích Hoạt")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        // Input field với toggle show/hide
                        HStack(spacing: 0) {
                            Group {
                                if isSecure {
                                    SecureField("Dán key vào đây…", text: $keyInput)
                                } else {
                                    TextField("Dán key vào đây…", text: $keyInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                            }
                            .font(.system(.body, design: .monospaced))
                            .padding(.leading, 14)
                            .padding(.vertical, 14)
                            .focused($keyFocused)
                            .onSubmit { Task { await keyService.verify(key: keyInput) } }

                            Button {
                                isSecure.toggle()
                            } label: {
                                Image(systemName: isSecure ? "eye" : "eye.slash")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    keyService.errorMessage != nil
                                        ? Color.red.opacity(0.6)
                                        : Color(uiColor: .separator).opacity(0.3),
                                    lineWidth: 1
                                )
                        )

                        // Thông báo lỗi
                        if let error = keyService.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold))
                                Text(error)
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Nút xác thực
                        Button {
                            Task { await keyService.verify(key: keyInput) }
                        } label: {
                            Group {
                                if keyService.isChecking {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                        Text("Đang kiểm tra…")
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.shield.fill")
                                        Text("Xác Thực Key")
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || keyService.isChecking
                                    ? AppTheme.accent.opacity(0.4)
                                    : AppTheme.accent
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(
                            keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || keyService.isChecking
                        )
                        .animation(.easeInOut(duration: 0.2), value: keyService.isChecking)

                        // Paste từ clipboard
                        Button {
                            if let clip = UIPasteboard.general.string {
                                keyInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.caption.weight(.medium))
                                Text("Dán từ clipboard")
                                    .font(.caption.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
                    )
                    .padding(.horizontal, 20)
                    .animation(.easeInOut(duration: 0.2), value: keyService.errorMessage)

                    // ── Footer ───────────────────────────────────────────
                    VStack(spacing: 8) {
                        Text("Liên hệ admin để nhận key")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(keyService.adminName)
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                }
            }
        }
        .onTapGesture { keyFocused = false }
    }
}

#if DEBUG
#Preview {
    KeyVerificationView()
        .environmentObject(KeyVerificationService())
}
#endif
