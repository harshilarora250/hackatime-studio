#if DEBUG
import AppKit
import SwiftUI
import WidgetKit

/// Developer tool (Debug builds only): when `STUDIO_SNAPSHOT_DIR` is set, Studio renders its own
/// window for every page in light and dark mode to PNGs, then quits. Used to visually verify UI
/// without Screen Recording permission. Optional `STUDIO_SNAPSHOT_ROUTES` (comma-separated) and
/// `STUDIO_SNAPSHOT_SETUP` (enterKey|success|guided0…3) narrow what is captured.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(model: AppModel) {
        // `STUDIO_DEBUG_WIDGET_SAMPLE`: write sample data for the desktop widgets, then quit.
        if ProcessInfo.processInfo.environment["STUDIO_DEBUG_WIDGET_SAMPLE"] != nil {
            do {
                try WidgetSnapshot.sample().save()
                WidgetCenter.shared.reloadAllTimelines()
                print("widget-sample:", WidgetSnapshot.fileURL?.path ?? "no App Group container")
            } catch {
                print("widget-sample failed:", error)
            }
            exit(0)
        }
        // `STUDIO_DEBUG_SETUP_KEY`: run the real setup path (verify with the API, then save), then quit.
        if let key = ProcessInfo.processInfo.environment["STUDIO_DEBUG_SETUP_KEY"] {
            Task {
                try? await Task.sleep(for: .seconds(2))
                let result = await model.check(key: key)
                print("setup-check:", result)
                if case .valid(let profile) = result { print("setup-saved:", model.saveAPIKey(key, profile: profile)) }
                try? await Task.sleep(for: .seconds(1))
                exit(0)
            }
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["STUDIO_SNAPSHOT_DIR"] else { return }
        let routesEnv = ProcessInfo.processInfo.environment["STUDIO_SNAPSHOT_ROUTES"]
        let setupEnv = ProcessInfo.processInfo.environment["STUDIO_SNAPSHOT_SETUP"]
        let routes: [Route] = routesEnv?.split(separator: ",").compactMap { name in
            Route.allCases.first { "\($0)" == name }
        } ?? Route.allCases

        Task {
            try? await Task.sleep(for: .seconds(4))
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { exit(2) }
            window.setContentSize(NSSize(width: 1240, height: 900))
            for appearance in [AppearancePreference.light, .dark] {
                model.appearance = appearance
                if let setup = setupEnv {
                    model.setupFlow = switch setup {
                    case "enterKey": .enterKey
                    case "success": .success
                    default: .guided(Int(setup.dropFirst(6)) ?? 0)
                    }
                    try? await Task.sleep(for: .seconds(2))
                    capture(window, to: "\(dir)/setup-\(setup)-\(appearance.rawValue).png")
                    continue
                }
                model.setupFlow = nil
                for route in routes {
                    model.route = route
                    try? await Task.sleep(for: .seconds(2.5))
                    capture(window, to: "\(dir)/\(route)-\(appearance.rawValue).png")
                }
            }
            exit(0)
        }
    }

    private static func capture(_ window: NSWindow, to path: String) {
        guard let view = window.contentView, let layer = view.layer else { return }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return }
        ctx.translateBy(x: 0, y: size.height * scale)
        ctx.scaleBy(x: scale, y: -scale)
        layer.render(in: ctx)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
