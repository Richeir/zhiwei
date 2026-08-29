import SwiftUI

// MARK: - R7 判据自检面板（DEBUG 入口：我的 → R7 通道判据自检）
//
// 存在的意义：把"路线 B 能不能走通"从阅读体验变成一次点击。
// 四项全绿 = M0 出口条件达成，可以进 M1；任何一项红，按 R7 预案改设计再动手。

struct R7SpikeView: View {
    @Environment(AppContainer.self) private var container
    @State private var runner: R7SpikeRunner?
    @State private var idleSeconds: Double = 45

    var body: some View {
        List {
            Section("前置") {
                LabeledContent("保活策略") {
                    Picker("保活策略", selection: strategyBinding) {
                        ForEach(Array(ChannelWebViewHost.SurvivalStrategy.allCases.enumerated()), id: \.offset) { _, item in
                            Text(label(for: item)).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Stepper(value: $idleSeconds, in: 10 ... 300, step: 5) {
                    HStack {
                        Text("判据① 静置时长")
                        Spacer()
                        Text("\(Int(idleSeconds)) 秒").foregroundStyle(Theme.muted).monospacedDigit()
                    }
                }
                LabeledContent("登录态（判据③④ 需要）") {
                    Text(container.session.status.isLoggedIn ? "已登录" : "未登录 · 先去「我的」登录")
                        .foregroundStyle(container.session.status.isLoggedIn ? Theme.accent : Theme.destructive)
                }
            }

            Section {
                ForEach(R7Judge.allCases) { judge in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(judge.title).font(.subheadline.weight(.medium))
                            Spacer()
                            outcomeChip(runner?.verdicts[judge]?.outcome ?? .pending)
                        }
                        if let detail = runner?.verdicts[judge]?.detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(Theme.muted)
                                .textSelection(.enabled)
                        }
                        Text(judge.fallback).font(.caption2).foregroundStyle(Theme.muted.opacity(0.8))
                        if judge.needsHuman {
                            Label("本项需要人工配合", systemImage: "hand.raised")
                                .font(.caption2)
                                .foregroundStyle(Theme.accent)
                        }
                        Button("只跑这一项") {
                            Task { await runner?.run(judge) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("四项判据")
                    Spacer()
                    Button("全部重跑") { Task { await runAll() } }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }

            Section("结论") {
                if let runner {
                    Text(runner.allPassed
                        ? "四项全过：路线 B 成立，可进 M1。"
                        : "尚有两项未确认：不要带病进入 M1（§10 关键路径）。")
                        .font(.footnote)
                        .foregroundStyle(runner.allPassed ? Theme.accent : Theme.destructive)
                    Button("把结论写入本机存储") {
                        storeResult(runner)
                    }
                } else {
                    Text("通道未就绪（AppContainer 未装载 WebViewChannelLive）")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationTitle("R7 通道判据")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if runner == nil, let live = container.channel as? WebViewChannelLive {
                runner = R7SpikeRunner(channel: live)
            }
        }
        .onChange(of: idleSeconds) { _, value in
            runner?.idleSeconds = value
        }
    }

    private var strategyBinding: Binding<ChannelWebViewHost.SurvivalStrategy> {
        Binding(
            get: { runner?.strategy ?? .hiddenSubview },
            set: { runner?.strategy = $0 })
    }

    private func runAll() async {
        runner?.idleSeconds = idleSeconds
        await runner?.runAll()
    }

    private func label(for strategy: ChannelWebViewHost.SurvivalStrategy) -> String {
        switch strategy {
        case .hiddenSubview: "A · keyWindow 内 1×1 子视图"
        case .floatingWindow: "B · 独立 UIWindow"
        case .detached: "对照 · 纯离屏（不入场）"
        }
    }

    @ViewBuilder
    private func outcomeChip(_ outcome: R7Verdict.Outcome) -> some View {
        let color: Color = switch outcome {
        case .passed: Theme.accent
        case .failed: Theme.destructive
        case .inconclusive: .orange
        case .running, .pending: Theme.muted
        }
        Text(outcome.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("结果：\(outcome.rawValue)")
    }

    private func storeResult(_ runner: R7SpikeRunner) {
        let lines = R7Judge.allCases.compactMap { judge -> String? in
            guard let verdict = runner.verdicts[judge] else { return nil }
            return "判据\(judge.rawValue) [\(verdict.outcome.rawValue)] \(verdict.detail.replacingOccurrences(of: "\n", with: " "))"
        }
        container.store.setString(lines.joined(separator: "\n---\n"), for: .r7SpikeLastResult)
    }
}
