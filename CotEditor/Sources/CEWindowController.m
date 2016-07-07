/*
 
 CEWindowController.m
 
 CotEditor
 http://coteditor.com
 
 Created by nakamuxu on 2004-12-13.

 ------------------------------------------------------------------------------
 
 © 2004-2007 nakamuxu
 © 2013-2016 1024jp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 */

#import "CEWindowController.h"

#import "CotEditor-Swift.h"

#import "CEDocument.h"
#import "CEDefaults.h"


@interface CEWindowController ()

@property (nonatomic, nullable) IBOutlet ToolbarController *toolbarController;

@end




#pragma mark -

@implementation CEWindowController

#pragma mark Window Controller Methods

// ------------------------------------------------------
/// clean up
- (void)dealloc
// ------------------------------------------------------
{
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:CEDefaultWindowAlphaKey];
}


// ------------------------------------------------------
/// prepare window
- (void)windowDidLoad
// ------------------------------------------------------
{
    [super windowDidLoad];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // set window size
    [[self window] setContentSize:NSMakeSize((CGFloat)[defaults doubleForKey:CEDefaultWindowWidthKey],
                                             (CGFloat)[defaults doubleForKey:CEDefaultWindowHeightKey])];
    
    // setup background
    [(AlphaWindow *)[self window] setBackgroundAlpha:[defaults doubleForKey:CEDefaultWindowAlphaKey]];
    
    // observe opacity setting change
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:CEDefaultWindowAlphaKey
                                               options:NSKeyValueObservingOptionNew
                                               context:nil];
}


// ------------------------------------------------------
/// apply user defaults change
-(void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSString *, id> *)change context:(nullable void *)context
// ------------------------------------------------------
{
    if ([keyPath isEqualToString:CEDefaultWindowAlphaKey]) {
        [(AlphaWindow *)[self window] setBackgroundAlpha:(CGFloat)[change[NSKeyValueChangeNewKey] doubleValue]];
    }
}


// ------------------------------------------------------
/// cascade initial window position
- (BOOL)shouldCascadeWindows
// ------------------------------------------------------
{
    // -> It returns NO by default if the window controller was invoked from a storyboard.
    return YES;
}


// ------------------------------------------------------
/// apply passed-in document instance to window
- (void)setDocument:(nullable id)document
// ------------------------------------------------------
{
    [super setDocument:document];
    
    [[self toolbarController] setDocument:document];
    [[self contentViewController] setRepresentedObject:document];
    
    // apply document state to UI
    [[self document] applyContentToWindow];
}



#pragma mark Public Methods

// ------------------------------------------------------
/// show incompatible char list
- (void)showIncompatibleCharList
// ------------------------------------------------------
{
//    [(WindowContentViewController *)[self contentViewController] showSidebarPaneWithIndex:SidebarTabIndexIncompatibleChararacters];
    [(WindowContentViewController *)[self contentViewController] showSidebarPaneWithIndex:1];
}


// ------------------------------------------------------
/// pass editor instance to document
- (nullable CEEditorWrapper *)editor
// ------------------------------------------------------
{
    return [(WindowContentViewController *)[self contentViewController] editor];
}

@end
