//
//  PrintTextView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by nakamuxu on 2005-10-01.
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

final class PrintTextView: NSTextView, Themable, URLDetectable {
    
    // MARK: Constants
    
    static let verticalPrintMargin: CGFloat = 56.0    // default 90.0
    static let horizontalPrintMargin: CGFloat = 24.0  // default 72.0
    
    private let lineFragmentPadding: CGFloat = 18.0
    private let lineNumberPadding: CGFloat = 10.0
    private let headerFooterFontSize: CGFloat = 9.0
    
    
    // MARK: Public Properties
    
    var filePath: String?
    var documentName: String?
    private(set) var theme: Theme?
    private(set) lazy var syntaxParser = SyntaxParser(textStorage: self.textStorage!)
    
    // settings on current window to be set by Document.
    // These values are used if set option is "Same as document's setting"
    var documentShowsLineNumber = false
    var documentShowsInvisibles = false
    
    var urlDetectionTask: Task<Void, Error>?
    
    
    // MARK: Private Properties
    
    private let tabWidth: Int
    private let lineHeight: CGFloat
    private var printsLineNumber = false
    private var xOffset: CGFloat = 0
    private var lastPaperContentSize: NSSize = .zero
    private lazy var dateFormatter: DateFormatter = .init()
    
    private var asyncHighlightObserver: AnyCancellable?
    
    
    
    // MARK: -
    // MARK: Lifecycle
    
    init() {
        
        self.tabWidth = UserDefaults.standard[.tabWidth]
        self.lineHeight = UserDefaults.standard[.lineHeight]
        
        // setup textContainer
        let textContainer = TextContainer()
        textContainer.widthTracksTextView = true
        textContainer.isHangingIndentEnabled = UserDefaults.standard[.enablesHangingIndent]
        textContainer.hangingIndentWidth = UserDefaults.standard[.hangingIndentWidth]
        textContainer.lineFragmentPadding = self.lineFragmentPadding
        // -> If padding is changed while printing, the print area can be cropped due to text wrapping.
        
        // setup textView components
        let textStorage = NSTextStorage()
        let layoutManager = PrintLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        
        super.init(frame: .zero, textContainer: textContainer)
        
        self.maxSize = .infinite
        self.isHorizontallyResizable = false
        self.isVerticallyResizable = true
        
        self.linkTextAttributes = UserDefaults.standard[.autoLinkDetection]
            ? [.underlineStyle: NSUnderlineStyle.single.rawValue]
            : [:]
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    deinit {
        self.layoutManager?.delegate = nil
        self.urlDetectionTask?.cancel()
    }
    
    
    
    // MARK: Text View Methods
    
    /// the top/left point of text container
    override var textContainerOrigin: NSPoint {
        
        return NSPoint(x: self.xOffset, y: 0)
    }
    
    
    /// view's opacity
    override var isOpaque: Bool {
        
        return true
    }
    
    
    /// job title
    override var printJobTitle: String {
        
        return self.documentName ?? super.printJobTitle
    }
    
    
    /// return page header attributed string
    override var pageHeader: NSAttributedString {
        
        return self.headerFooter(for: .header)
    }
    
    
    /// return page footer attributed string
    override var pageFooter: NSAttributedString {
        
        return self.headerFooter(for: .footer)
    }
    
    
    /// set printing font
    override var font: NSFont? {
        
        didSet {
            guard let font = font else { return }
            
            // setup paragraph style
            let paragraphStyle = NSParagraphStyle.default.mutable
            paragraphStyle.tabStops = []
            paragraphStyle.defaultTabInterval = CGFloat(self.tabWidth) * font.width(of: " ")
            paragraphStyle.lineHeightMultiple = self.lineHeight
            self.defaultParagraphStyle = paragraphStyle
            self.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: self.string.nsRange)
            
            // set font also to layout manager
            (self.layoutManager as? LayoutManager)?.textFont = font
        }
    }
    
    
    /// return the number of pages available for printing
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        
        // apply print settings
        self.applyPrintSettings()
        
        // adjust content size based on print setting
        if let paperContentSize = NSPrintOperation.current?.printInfo.paperContentSize,
            self.lastPaperContentSize != paperContentSize
        {
            self.lastPaperContentSize = paperContentSize
            self.frame.size = paperContentSize
            self.layoutManager?.doForegroundLayout()
        }
        
        return super.knowsPageRange(range)
    }
    
    
    /// draw
    override func draw(_ dirtyRect: NSRect) {
        
        // store graphics state to keep line number area drawable
        // -> Otherwise, line numbers can be cropped. (2016-03 by 1024jp)
        NSGraphicsContext.saveGraphicsState()
        
        super.draw(dirtyRect)
        
        NSGraphicsContext.restoreGraphicsState()
        
        // draw line numbers if needed
        if self.printsLineNumber {
            guard
                let layoutManager = self.layoutManager as? LayoutManager,
                let textContainer = self.textContainer
            else { return assertionFailure() }
            
            // prepare text attributes for line numbers
            let numberFontSize = (0.9 * (self.font?.pointSize ?? 12)).rounded()
            let numberFont = NSFont.lineNumberFont(ofSize: numberFontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: numberFont,
                                                        .foregroundColor: self.textColor ?? .textColor]
            
            // calculate character width by treating the font as a mono-space font
            let numberSize = NSAttributedString(string: "8", attributes: attrs).size()
            
            // adjust values for line number drawing
            let horizontalOrigin = self.baseWritingDirection == .leftToRight
                ? self.textContainerOrigin.x + textContainer.lineFragmentPadding - self.lineNumberPadding
                : self.textContainerOrigin.x + textContainer.size.width
            let baselineOffset = layoutManager.baselineOffset(for: self.layoutOrientation)
            let numberAscender = numberFont.ascender
            
            // vertical text
            let isVerticalText = self.layoutOrientation == .vertical
            if isVerticalText {
                // rotate axis
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.rotate(by: -.pi / 2)
            }
            
            let options: NSTextView.LineEnumerationOptions = isVerticalText ? [.bySkippingWrappedLine] : []
            let range = ((self.layoutManager as? PrintLayoutManager)?.showsSelectionOnly == true) ? self.selectedRange : nil
            self.enumerateLineFragments(in: dirtyRect, for: range, options: options.union(.bySkippingExtraLine)) { (lineRect, line, lineNumber) in
                let numberString: String = {
                    switch line {
                        case .new:
                            if isVerticalText, lineNumber != 1, !lineNumber.isMultiple(of: 5) {
                                return "·"  // draw number only every 5 times
                            }
                            return String(lineNumber)
                        
                        case .wrapped:
                            return "-"
                    }
                }()
                
                // adjust position to draw
                let width = CGFloat(numberString.count) * numberSize.width
                let point: NSPoint
                if isVerticalText {
                    point = NSPoint(x: -lineRect.midY - width / 2,
                                    y: horizontalOrigin - numberSize.height)
                } else {
                    point = NSPoint(x: horizontalOrigin - width,  // - width to align to right
                                    y: lineRect.minY + baselineOffset - numberAscender)
                }
                
                // draw number
                NSAttributedString(string: numberString, attributes: attrs).draw(at: point)
            }
            
            if isVerticalText {
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    
    
    
    // MARK: Private Methods
    
    /// parse current print settings in printInfo
    private func applyPrintSettings() {
        
        guard
            let layoutManager = self.layoutManager as? PrintLayoutManager,
            let printInfo = NSPrintOperation.current?.printInfo
        else { return assertionFailure() }
        
        // set scope to print
        layoutManager.showsSelectionOnly = printInfo.isSelectionOnly
        
        // check whether print line numbers
        self.printsLineNumber = {
            switch PrintVisibilityMode(printInfo[.lineNumber]) {
                case .no:
                    return false
                case .sameAsDocument:
                    return self.documentShowsLineNumber
                case .yes:
                    return true
            }
        }()
        
        // adjust paddings considering the line numbers
        self.xOffset = (self.printsLineNumber && self.baseWritingDirection == .leftToRight) ? self.lineFragmentPadding : 0
        self.textContainerInset.width = (self.printsLineNumber && self.baseWritingDirection == .rightToLeft) ? self.lineFragmentPadding : 0
        
        // check whether print invisibles
        layoutManager.showsInvisibles = {
            switch PrintVisibilityMode(printInfo[.invisibles]) {
                case .no:
                    return false
                case .sameAsDocument:
                    return self.documentShowsInvisibles
                case .yes:
                    return true
            }
        }()
        
        // set whether draws background
        self.drawsBackground = printInfo[.printsBackground] ?? true
        
        // create theme
        let themeName = printInfo[.theme] ?? ThemeName.blackAndWhite
        let theme = ThemeManager.shared.setting(name: themeName)  // nil for Black and White
        
        guard self.theme?.name != theme?.name else { return }
        
        // set theme
        // -> The following two procedures are important to change .textColor in the preview properly
        //    while printing only the selection (2022-03 macOS 12):
        //    1. Set .textColor after setting .backgroundColor.
        //    2. Ensure glyphs.
        self.theme = theme
        self.backgroundColor = theme?.background.color ?? .textBackgroundColor  // expensive task
        self.textColor = theme?.text.color ?? .textColor
        layoutManager.invisiblesColor = theme?.invisibles.color ?? .disabledControlTextColor
        layoutManager.ensureGlyphs(forCharacterRange: self.string.nsRange)
        
        // perform syntax highlight
        let progress = self.syntaxParser.highlight()
        
        // asynchronously trigger preview update if needed
        if
            let progress = progress,
            let controller = NSPrintOperation.current?.printPanel.accessoryControllers.first as? PrintPanelAccessoryController
        {
            self.asyncHighlightObserver = progress.publisher(for: \.isFinished)
                .first { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak controller] _ in controller?.needsUpdatePreview = true }
        }
    }
    
    
    /// return attributed string for header/footer
    private func headerFooter(for location: HeaderFooterLocation) -> NSAttributedString {
        
        let keys = location.keys
        
        guard
            let printInfo = NSPrintOperation.current?.printInfo,
            printInfo[keys.needsDraw] == true
        else { return NSAttributedString() }
        
        let primaryInfoType = PrintInfoType(printInfo[keys.primaryContent])
        let primaryAlignment = AlignmentType(printInfo[keys.primaryAlignment])
        let secondaryInfoType = PrintInfoType(printInfo[keys.secondaryContent])
        let secondaryAlignment = AlignmentType(printInfo[keys.secondaryAlignment])
        
        let primaryString = self.printInfoString(type: primaryInfoType)
        let secondaryString = self.printInfoString(type: secondaryInfoType)
        
        switch (primaryString, secondaryString) {
            // case: empty
            case (nil, nil):
                return NSAttributedString()
            
            // case: single content
            case let (.some(string), nil):
                return NSAttributedString(string: string, attributes: self.headerFooterAttributes(for: primaryAlignment))
            case let (nil, .some(string)):
                return NSAttributedString(string: string, attributes: self.headerFooterAttributes(for: secondaryAlignment))
            
            case let (.some(primaryString), .some(secondaryString)):
                switch (primaryAlignment, secondaryAlignment) {
                    // case: double-sided
                    case (.left, .right):
                        return NSAttributedString(string: primaryString + "\t\t" + secondaryString, attributes: self.headerFooterAttributes(for: .left))
                    case (.right, .left):
                        return NSAttributedString(string: secondaryString + "\t\t" + primaryString, attributes: self.headerFooterAttributes(for: .left))
                    
                    // case: two lines
                    default:
                        let primaryAttrString = NSAttributedString(string: primaryString, attributes: self.headerFooterAttributes(for: primaryAlignment))
                        let secondaryAttrString = NSAttributedString(string: secondaryString, attributes: self.headerFooterAttributes(for: secondaryAlignment))
                        
                        return [primaryAttrString, secondaryAttrString].joined(separator: "\n")
            }
        }
    }
    
    
    /// return attributes for header/footer string
    private func headerFooterAttributes(for alignment: AlignmentType) -> [NSAttributedString.Key: Any] {
        
        let font = NSFont.userFont(ofSize: self.headerFooterFontSize)
        
        let paragraphStyle = NSParagraphStyle.default.mutable
        paragraphStyle.lineBreakMode = .byTruncatingMiddle
        paragraphStyle.alignment = alignment.textAlignment
        
        // tab stops for double-sided alignment (imitation of super.pageHeader)
        if let printInfo = NSPrintOperation.current?.printInfo {
            let xMax = printInfo.paperSize.width - printInfo.topMargin / 2
            paragraphStyle.tabStops = [NSTextTab(type: .centerTabStopType, location: xMax / 2),
                                       NSTextTab(type: .rightTabStopType, location: xMax)]
        }
        
        return [.font: font,
                .paragraphStyle: paragraphStyle]
            .compactMapValues { $0 }
    }
    
    
    /// create string for header/footer
    private func printInfoString(type: PrintInfoType) -> String? {
        
        switch type {
            case .documentName:
                return self.documentName
            
            case .syntaxName:
                return self.syntaxParser.style.name
            
            case .filePath:
                guard let filePath = self.filePath else {  // print document name instead if document doesn't have file path yet
                    return self.documentName
                }
                if UserDefaults.standard[.headerFooterPathAbbreviatingWithTilde] {
                    return filePath.abbreviatingWithTildeInSandboxedPath
                }
                return filePath
            
            case .printDate:
                self.dateFormatter.dateFormat = UserDefaults.standard[.headerFooterDateFormat]
                return String(format: "Printed on %@".localized, self.dateFormatter.string(from: Date()))
            
            case .pageNumber:
                guard let pageNumber = NSPrintOperation.current?.currentPage else { return nil }
                return String(pageNumber)
            
            case .none:
                return nil
        }
    }
    
}



private extension NSLayoutManager {
    
    /// This method causes the text to be laid out in the foreground.
    ///
    /// - Note: This method is based on `textEditDoForegroundLayoutToCharacterIndex:` in Apple's TextView.app source code.
    func doForegroundLayout() {
        
        guard self.numberOfGlyphs > 0 else { return }
        
        // cause layout by asking a question which has to determine where the glyph is
        self.textContainer(forGlyphAt: self.numberOfGlyphs - 1, effectiveRange: nil)
    }
    
}



// MARK: -

private final class PrintLayoutManager: LayoutManager {
    
    var showsSelectionOnly = false {
        
        didSet {
            guard showsSelectionOnly != oldValue else { return }
            
            let range = self.attributedString().range
            self.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            self.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)  // important for vertical orientation
            self.ensureGlyphs(forCharacterRange: range)
            self.ensureLayout(forCharacterRange: range)
        }
    }
    
    
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        
        // hide unselected glyphs if set so
        guard
            self.showsSelectionOnly,
            let selectedRange = layoutManager.firstTextView?.selectedRange,
            self.attributedString().length != selectedRange.length
        else { return 0 }  // return 0 for the default processing
        
        let glyphIndexesToHide = (0..<glyphRange.length).filter { !selectedRange.contains(characterIndexes[$0]) }
        
        guard !glyphIndexesToHide.isEmpty else { return 0 }
        
        let newProperties = UnsafeMutablePointer(mutating: properties)
        for index in glyphIndexesToHide {
            newProperties[index].insert(.null)
        }
        
        layoutManager.setGlyphs(glyphs, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        
        return glyphRange.length
    }
    
    
    override func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        
        // zero width for folded characters
        if self.showsSelectionOnly,
           let selectedRange = layoutManager.firstTextView?.selectedRange,
            !selectedRange.contains(charIndex)
        {
            return .zeroAdvancement
        }
        
        return super.layoutManager(layoutManager, shouldUse: action, forControlCharacterAt: charIndex)
    }
    
}



// MARK: -

private enum HeaderFooterLocation {
    
    case header
    case footer
    
    
    struct Keys {
        
        var needsDraw: NSPrintInfo.AttributeKey
        var primaryContent: NSPrintInfo.AttributeKey
        var primaryAlignment: NSPrintInfo.AttributeKey
        var secondaryContent: NSPrintInfo.AttributeKey
        var secondaryAlignment: NSPrintInfo.AttributeKey
    }
    
    
    var keys: Keys {
        
        switch self {
            case .header:
                return Keys(needsDraw: .printsHeader,
                            primaryContent: .primaryHeaderContent,
                            primaryAlignment: .primaryHeaderAlignment,
                            secondaryContent: .secondaryHeaderContent,
                            secondaryAlignment: .secondaryHeaderAlignment)
            
            case .footer:
                return Keys(needsDraw: .printsFooter,
                            primaryContent: .primaryFooterContent,
                            primaryAlignment: .primaryFooterAlignment,
                            secondaryContent: .secondaryFooterContent,
                            secondaryAlignment: .secondaryFooterAlignment)
        }
    }
    
}



private extension AlignmentType {
    
    var textAlignment: NSTextAlignment {
        
        switch self {
            case .left:
                return .left
            case .center:
                return .center
            case .right:
                return .right
        }
    }
}
