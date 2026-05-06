//
//  FFishAsiaApp.swift
//  FFishAsia
//
//  Created by PK on 2024/8/9.
//

import SwiftUI

@main
struct FFishAsiaApp: App {
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
