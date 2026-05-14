//
//  FFishAsiaApp.swift
//  FFishAsia
//
//  Created by PK on 2024/8/9.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct FFishAsiaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(FFishAsiaAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 640)
        }
        .defaultSize(width: 960, height: 720)
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}

#if os(macOS)
private final class FFishAsiaAppDelegate: NSObject, NSApplicationDelegate {
    private var snapshotWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("FFISH_SNAPSHOT_SCREEN=") }) else {
            return
        }

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let window = NSWindow(
                contentRect: NSRect(x: 80, y: 80, width: 1120, height: 840),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "FFishAsia"
            window.contentViewController = NSHostingController(
                rootView: ContentView().frame(minWidth: 760, minHeight: 640)
            )
            window.setContentSize(NSSize(width: 1120, height: 840))
            window.setFrameTopLeftPoint(NSPoint(x: 80, y: 80))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.snapshotWindow = window
        }
    }
}
#endif
