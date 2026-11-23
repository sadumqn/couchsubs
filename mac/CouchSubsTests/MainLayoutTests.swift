// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import RemotePlay
import SwiftUI
import XCTest
@testable import CouchSubs

/// Yeni arayüz en küçük pencerede (1200 × 760) taşmaz; ayar sütunlarındaki denetimler sütunun içinde kalır.
@MainActor
final class MainLayoutTests: XCTestCase {
    private func model(output: SubtitleOutput, running: Bool, clickThrough: Bool) -> AppModel {
        let store = MemoryStore()
        store.save(Data(repeating: 1, count: 8), for: StoreKey.accountId)
        store.save(RegisteredConsole(host: "192.168.1.253", name: "PS5-789", registKey: Data(repeating: 0x31, count: 16),
                                     morning: Data(repeating: 2, count: 16)), for: StoreKey.console)
        store.save(LGTV(name: "LG TV", host: "192.168.1.153"), for: StoreKey.tv)
        store.save("tv-key", for: StoreKey.tvKey)
        let model = AppModel(services: FakeServices(), store: store, defaults: .isolated())
        model.step = .done
        model.settings.output = output
        model.settings.overlayClickThrough = clickThrough
        model.isRunning = running
        return model
    }

    private var states: [(SubtitleOutput, Bool, Bool)] {
        SubtitleOutput.allCases.flatMap { output in [false, true].flatMap { running in [false, true].map { (output, running, $0) } } }
    }

    /// Ayarlar'daki iki sütundan biri en küçük pencerede: (1200 − 2·24 − 240 − 24 − 24) / 2.
    private static let settingsColumn: CGFloat = (DS.size("windowWidth") - 2 * DS.space("l") - DS.size("settingsNav") - 2 * DS.space("l")) / 2

    /// Kabuk (üst çubuk, ana ekran, reklam bandı) en küçük pencereye sığar; hiçbir öğe daha geniş/uzun en az ölçü istemez.
    func testShellFitsTheSmallestWindow() {
        for (output, running, click) in states {
            let model = model(output: output, running: running, clickThrough: click)
            for tab in [ShellTab.home, .history, .settings] {
                model.showSettings = tab == .settings
                model.showHistory = tab == .history
                // En küçük pencerenin önerisiyle ölçülür (ideal ölçü değil): içerik bu boyda kalmalı, pencereyi büyütmemeli.
                let host = NSHostingController(rootView: AppShell().environmentObject(model).appSurface())
                let size = host.sizeThatFits(in: CGSize(width: DS.size("windowWidth"), height: DS.size("windowHeight")))
                XCTAssertLessThanOrEqual(size.width, DS.size("windowWidth"), "\(tab) \(output) çalışıyor=\(running)")
                XCTAssertLessThanOrEqual(size.height, DS.size("windowHeight"), "\(tab) \(output) çalışıyor=\(running)")
            }
        }
    }

    /// "Altyazıyı göster" kartının denetimleri ayar sütununun içinde kalır (segmentli seçici AppKit'te en uzun etiket
    /// kadar eşit bölmeler çizer; SwiftUI ölçüsü bunu göstermez, pencerede yerleşen AppKit görünümlerine bakılır).
    func testOutputCardControlsStayInsideTheColumn() {
        let width = Self.settingsColumn
        for output in SubtitleOutput.allCases {
            let model = model(output: output, running: false, clickThrough: false)
            let host = NSHostingView(rootView: SubtitleOutputCard().environmentObject(model).appSurface().newLook().frame(width: width))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let controls = views(in: host).dropFirst()
            XCTAssertFalse(controls.isEmpty)
            for control in controls {
                let frame = control.convert(control.bounds, to: host)
                XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(output) sütun=\(width) \(type(of: control))")
                XCTAssertLessThanOrEqual(frame.maxX, width, "\(output) sütun=\(width) \(type(of: control))")
            }
            window.close()
        }
    }

    private func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views(in: $0) } }
}
