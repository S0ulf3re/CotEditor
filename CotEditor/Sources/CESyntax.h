/*
=================================================
CESyntax
(for CotEditor)

 Copyright (C) 2004-2007 nakamuxu.
 Copyright (C) 2014 CotEditor Project
 http://coteditor.github.io
=================================================

encoding="UTF-8"
Created:2004.12.22
 
 -fno-objc-arc
 
-------------------------------------------------

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA. 


=================================================
*/

#import <Cocoa/Cocoa.h>
#import <OgreKit/OgreKit.h>
#import "CESyntaxManager.h"
#import "CELayoutManager.h"
#import "RKLMatchEnumerator.h"
#import "DEBUG_macro.h"


@class CETextViewCore;


@interface CESyntax : NSObject

@property (nonatomic, retain) CELayoutManager *layoutManager;
@property (nonatomic, retain) NSString *wholeString;
@property (nonatomic, retain) NSString *localString;  // カラーリング対象文字列
@property (nonatomic, retain) NSString *syntaxStyleName;
@property (nonatomic) BOOL isPrinting;  // プリンタ中かどうかを返す
        // （[NSGraphicsContext currentContextDrawingToScreen] は真を返す時があるため、専用フラグを使う）

// readonly
@property (nonatomic, retain, readonly) NSArray *completeWordsArray;  // 保持している入力補完文字列配列
@property (nonatomic, retain, readonly) NSCharacterSet *completeFirstLetterSet;  // 保持している入力補完の最初の1文字のセット

// Public method
- (NSUInteger)wholeStringLength;
- (BOOL)setSyntaxStyleNameFromExtension:(NSString *)inExtension;
- (void)setCompleteWordsArrayFromColoringDictionary;
- (void)colorAllString:(NSString *)inWholeString;
- (void)colorVisibleRange:(NSRange)inRange withWholeString:(NSString *)inWholeString;
- (NSArray *)outlineMenuArrayWithWholeString:(NSString *)inWholeString;
- (BOOL)isPrinting;
- (void)setIsPrinting:(BOOL)inValue;

// Action Message
- (IBAction)cancelColoring:(id)sender;

@end
