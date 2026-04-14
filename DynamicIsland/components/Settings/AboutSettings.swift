//
//  AboutSettings.swift
//  DynamicIsland
//
//  Split from SettingsView.swift
//
import SwiftUI
import Defaults
import Sparkle
import AVFoundation

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow

    private var buildConfigurationTint: Color {
        appBuildConfigurationName == "Debug" ? .orange : .green
    }

    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Release name")
                        Spacer()
                        Text(Defaults[.releaseName])
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                    HStack {
                        Text("Build configuration")
                        Spacer()
                        Text(appBuildConfigurationName.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(buildConfigurationTint)
                            )
                    }
                } header: {
                    Text("Version info")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(sponsorPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Donate")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(productPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
                Text("Your support funds software development learning for students in 9th–12th grade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            VStack(spacing: 0) {
                Divider()
                Text("Made by \(appAuthorName)")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(.regularMaterial)
        }
        .toolbar {
            //            Button("Welcome window") {
            //                openWindow(id: "onboarding")
            //            }
            //            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }
}

struct SettingsLoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)
        context.coordinator.attach(layer: layer, url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var controller: SettingsLoopingPlayerController?

        func attach(layer: AVPlayerLayer, url: URL) {
            controller = SettingsLoopingPlayerController(url: url, autoPlay: true)
            layer.player = controller?.player
        }
    }
}

final class SettingsLoopingPlayerController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL, autoPlay: Bool = true) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        if autoPlay {
            player.play()
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    deinit {
        player.pause()
        looper = nil
    }
}