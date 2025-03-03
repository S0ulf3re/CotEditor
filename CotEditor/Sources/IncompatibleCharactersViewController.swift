//
//  IncompatibleCharsViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-12-18.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
//  © 2014-2022 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Cocoa

final class IncompatibleCharactersViewController: NSViewController {
    
    // MARK: Private Properties
    
    private var document: Document?  { self.representedObject as? Document }
    private var scanner: IncompatibleCharacterScanner?  { self.document?.incompatibleCharacterScanner }
    
    @objc private dynamic var message: String?
    @objc private dynamic var incompatibleCharacters: [IncompatibleCharacter] = []
    
    private var scannerObservers: [AnyCancellable] = []
    
    @IBOutlet private var incompatibleCharsController: NSArrayController?
    
    
    
    // MARK: -
    // MARK: View Controller Methods
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // set accessibility
        self.view.setAccessibilityElement(true)
        self.view.setAccessibilityRole(.group)
        self.view.setAccessibilityLabel("incompatible characters".localized)
    }
    
    
    /// update content before display
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        self.scanner?.shouldScan = true
        self.scanner?.scan()
    }
    
    
    /// clear incompatible characters markup
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.scanner?.shouldScan = false
        
        if !self.incompatibleCharacters.isEmpty {
            self.document?.textStorage.clearAllMarkup()
        }
    }
    
    
    /// set delegate
    override var representedObject: Any? {
        
        willSet {
            self.scannerObservers.removeAll()
            
            guard newValue is Document else {
                assertionFailure("representedObject of \(self.className) must be an instance of \(Document.self)")
                return
            }
        }
        
        didSet {
            guard let scanner = self.scanner else { return }
            
            scanner.shouldScan = self.isViewShown
            scanner.invalidate()
            
            scanner.$incompatibleCharacters
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.didUpdateIncompatibleCharacters($0) }
                .store(in: &self.scannerObservers)
            scanner.$isScanning
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.updateMessage(isScanning: $0) }
                .store(in: &self.scannerObservers)
        }
    }
    
    
    
    // MARK: Action Messages
    
    /// select correspondent char in text view
    @IBAction func selectCharacter(_ tableView: NSTableView) {
        
        guard
            tableView.clickedRow > -1,  // invalid click
            let incompatibles = self.incompatibleCharsController?.arrangedObjects as? [IncompatibleCharacter],
            let selectedIncompatible = incompatibles[safe: tableView.clickedRow],
            let textView = self.document?.textView
        else { return }
        
        textView.selectedRange = selectedIncompatible.range
        textView.scrollRangeToVisible(textView.selectedRange)
        textView.showFindIndicator(for: textView.selectedRange)
    }
    
    
    
    // MARK: Private Methods
    
    @MainActor private func didUpdateIncompatibleCharacters(_ incompatibleCharacters: [IncompatibleCharacter]) {
        
        guard let textStorage = self.document?.textStorage else { return }
        
        if !self.incompatibleCharacters.isEmpty {
            textStorage.clearAllMarkup()
        }
        
        self.incompatibleCharacters = incompatibleCharacters
        
        self.updateMessage(isScanning: false)
        textStorage.markup(ranges: incompatibleCharacters.map(\.range))
    }
    
    
    /// Update the state message on the table.
    @MainActor private func updateMessage(isScanning: Bool) {
        
        self.message = isScanning ? "Scanning incompatible characters…".localized
                                  : (self.incompatibleCharacters.isEmpty
                                     ? "No incompatible characters were found.".localized
                                     : nil)
    }
    
}



private extension NSTextStorage {
    
    /// change background color of pased-in ranges
    func markup(ranges: [NSRange]) {
        
        guard !ranges.isEmpty else { return }
        
        for manager in self.layoutManagers {
            guard let color = manager.firstTextView?.textColor?.withAlphaComponent(0.2) else { continue }
            
            for range in ranges {
                manager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }
        }
    }
    
    
    /// clear all background highlight (including text finder's highlights)
    func clearAllMarkup() {
        
        let range = self.string.nsRange
        
        for manager in self.layoutManagers {
            manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        }
    }
    
}
