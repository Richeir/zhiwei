import os
import PhotosUI
import SwiftUI

// MARK: - 发布编辑器（M3 落地；M0 只立字段结构与草稿接线，不接通发送）

struct ComposeView: View {
    @Binding var isPresented: Bool
    @Environment(AppContainer.self) private var container

    @State private var text = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var draft = Draft(text: "")
    @FocusState private var editorFocused: Bool

    /// 微博正文上限：Web 端 140 字（超出走长文，提示由 `overSoftLimit` 驱动）
    private static let softLimit = 140
    private static let hardLimit = 2000

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                editor
                Divider()
                toolbar
            }
            .navigationTitle("微博")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { saveDraftIfNeeded()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") { Task { await publish() } }
                        .disabled(!canPublish)
                }
            }
            .onAppear { text = draft.text }
            .onDisappear { saveDraftIfNeeded() }
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .frame(minHeight: 120, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("有什么新鲜事？")
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 8)
                        .padding(.leading, Theme.gutter + 5)
                        .allowsHitTesting(false)
                }
            }
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                Image(systemName: "photo.on.rectangle")
            }
            Menu {
                // 话题插入（M3：`#xx#`）；热搜建议由 APIWeb 端点供给
                Button("插入话题") { text += "##"
                    editorFocused = false
                }
            } label: {
                Image(systemName: "number")
            }
            Spacer()
            Text("\(text.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(counterColor)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var counterColor: Color {
        if text.count > Self.hardLimit {
            return Theme.destructive
        }
        if text.count > Self.softLimit {
            return Theme.accent
        }
        return Theme.muted
    }

    private var canPublish: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= Self.hardLimit
    }

    private func saveDraftIfNeeded() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        DraftStore(store: container.store).save(Draft(text: text))
    }

    /// M3 接通：车道② 上传（`APIWebEndpoint.uploadPicture`）+ 发布（`.publishText`，带 XSRF 头）
    private func publish() async {
        // 发布必须走限流器；这里先留结构，避免 M0 出现"能点但什么都不发生"的按钮语义
        Logger.log(domain: .compose).info("publish requested (M3 实现)")
        isPresented = false
    }
}
