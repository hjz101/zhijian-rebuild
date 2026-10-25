// TTSPlayerBar.swift — 阅读页/全局迷你朗读条
//
// 接入示例：
// ```swift
// ReaderView(...)
//   .safeAreaInset(edge: .bottom) {
//       TTSPlayerBar(tts: env.tts)
//   }
// ```
import SwiftUI

struct TTSPlayerBar: View {
    @ObservedObject var tts: TTSController
    @ObservedObject private var sources: TTSSourceStore

    init(tts: TTSController) {
        self.tts = tts
        _sources = ObservedObject(wrappedValue: tts.ttsSources)
    }

    var body: some View {
        if tts.isActive {
            VStack(spacing: 8) {
                ProgressView(value: tts.progress)
                    .progressViewStyle(.linear)
                    .tint(ZJ.accent)
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)

                HStack(spacing: 10) {
                    sourceMenu

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(tts.currentSourceName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ZJ.textSecondary)
                                .lineLimit(1)
                            roleBadge
                            Text("\(min(tts.currentSegmentIndex + 1, max(tts.segmentCount, 1)))/\(tts.segmentCount)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(ZJ.textTertiary)
                        }
                        Text(tts.currentSentence.isEmpty ? (tts.isPaused ? "已暂停" : "准备朗读…") : tts.currentSentence)
                            .font(ZJFont.ui(13))
                            .foregroundStyle(ZJ.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    controlButton("gobackward.15", label: "上一句") { tts.skipBackward() }
                    playPauseButton
                    controlButton("goforward.15", label: "下一句") { tts.skipForward() }
                    controlButton("stop.fill", label: "停止") { tts.stop() }
                    rateMenu
                }

                if let error = tts.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(ZJ.error)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, ZJ.s4)
            .padding(.vertical, ZJ.s3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ZJ.rLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ZJ.rLg, style: .continuous)
                    .strokeBorder(ZJ.separator, lineWidth: 1)
            )
            .padding(.horizontal, ZJ.s3)
            .padding(.bottom, ZJ.s2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.2), value: tts.isActive)
        }
    }

    // MARK: 子视图

    private var roleBadge: some View {
        Text(tts.currentRoleName ?? tts.currentRole.displayName)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                (tts.currentRole == .dialogue ? ZJ.celadon : ZJ.gold).opacity(0.18),
                in: Capsule()
            )
            .foregroundStyle(tts.currentRole == .dialogue ? ZJ.celadon : ZJ.gold)
    }

    private var playPauseButton: some View {
        Button {
            if tts.isPaused {
                tts.resume()
            } else if tts.isSpeaking {
                tts.pause()
            } else {
                tts.resume()
            }
        } label: {
            Image(systemName: tts.isSpeaking ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(ZJ.accent, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tts.isSpeaking ? "暂停朗读" : "继续朗读")
    }

    private func controlButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 30)
                .foregroundStyle(ZJ.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var sourceMenu: some View {
        Menu {
            Button {
                tts.selectSource(nil)
            } label: {
                Label("系统朗读", systemImage: tts.selectedSourceID == nil ? "checkmark" : "speaker.wave.2")
            }
            if !sources.enabledSources.isEmpty {
                Divider()
                ForEach(sources.enabledSources) { source in
                    Button {
                        tts.selectSource(source.id)
                    } label: {
                        Label(source.name, systemImage: tts.selectedSourceID == source.id ? "checkmark" : "waveform")
                    }
                }
            }
        } label: {
            Image(systemName: tts.selectedSourceID == nil ? "speaker.wave.2.fill" : "waveform.circle.fill")
                .font(.system(size: 17))
                .frame(width: 30, height: 30)
                .foregroundStyle(tts.selectedSourceID == nil ? ZJ.textSecondary : ZJ.celadon)
        }
        .accessibilityLabel("朗读来源：\(tts.currentSourceName)")
    }

    private var rateMenu: some View {
        Menu {
            ForEach([0.8, 0.9, 1.0, 1.15, 1.3, 1.5], id: \.self) { multiplier in
                Button {
                    tts.setRate(Float(min(max(0.5 * multiplier, 0.2), 1.0)))
                } label: {
                    Text(String(format: "%.2fx", multiplier))
                    if abs(Double(tts.rate) / 0.5 - multiplier) < 0.01 {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Text(String(format: "%.2fx", Double(tts.rate) / 0.5))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(ZJ.textSecondary)
                .frame(minWidth: 32)
        }
        .accessibilityLabel("朗读语速")
    }
}

// MARK: - 便捷容器

/// 从环境取 TTSController 的包装，方便阅读页直接使用：
/// `TTSPlayerBarEnvironment()`。
struct TTSPlayerBarEnvironment: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TTSPlayerBar(tts: env.tts)
    }
}
