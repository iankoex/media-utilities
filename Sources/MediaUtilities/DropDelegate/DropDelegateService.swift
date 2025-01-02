//
//  File.swift
//  
//
//  Created by Ian on 08/12/2022.
//

import Foundation
import SwiftUI

@available(iOS 13.0, macOS 10.15, *)
class DropDelegateService: ObservableObject {
    @Published var isActive: Bool = false
    @Published var isValidated: Bool = false {
        didSet { processAttempts() }
    }
    @Published var isAllowed: Bool = false
    @Published var isGuarded: Bool
    @Published var attempts: CGFloat = 0
    @Published var isCopyingFile: Bool = false
    @Published var progress = Progress()
    // Helpers for a bug in macOS where you can't drop from Safari
    // Tried NSPasteBoard with no success this is the workaround I found
    var temporaryImage: UnifiedImage? = nil
    var anItemWasDropped: Bool = false
    
    init(
        isGuarded: Bool
    ) {
        self.isGuarded = isGuarded
    }

    private func processAttempts() {
        if isAllowed == false {
            withAnimation {
                attempts += 1
            }
        }
    }

    func setIsAllowed(to bool: Bool) {
        DispatchQueue.main.async {
            self.isAllowed = bool
            self.processAttempts()
        }
    }

    func setIsCopying(to bool: Bool) {
        DispatchQueue.main.async {
            self.isCopyingFile = bool
        }
    }

    static let audioVisualIdentifiers: [String] = ["public.audiovisual-content", "public.url", "public.file-url"]
    static let urlIndentifier: String = "public.url"
    static let audioVisualContentIndentifier = "public.audiovisual-content"
}
