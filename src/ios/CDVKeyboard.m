/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVKeyboard.h"
#import <Cordova/CDVAvailability.h>
#import <Cordova/NSDictionary+CordovaPreferences.h>
#import <objc/runtime.h>

#ifndef __CORDOVA_3_2_0
#warning "The keyboard plugin is only supported in Cordova 3.2 or greater, it may not work properly in an older version. If you do use this plugin in an older version, make sure the HideKeyboardFormAccessoryBar and KeyboardShrinksView preference values are false."
#endif

@interface CDVKeyboard ()

@property (nonatomic, readwrite, assign) BOOL keyboardIsVisible;
@property (nonatomic, readwrite) CGRect frame;
@property (nonatomic, readwrite) BOOL closingkeyboard;

@end

@implementation CDVKeyboard

- (id)settingForKey:(NSString*)key
{
    return [self.commandDelegate.settings objectForKey:[key lowercaseString]];
}

#pragma mark Initialize

- (void)pluginInitialize
{
    NSLog(@"CDVKeyboard: pluginInitialize");
    NSDictionary *settings = self.commandDelegate.settings;

    self.hideFormAccessoryBar = [settings cordovaBoolSettingForKey:@"HideKeyboardFormAccessoryBar" defaultValue:YES];

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];

    [nc addObserver:self selector:@selector(onKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardDidFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];

    // Prevent WKWebView to resize window
    BOOL isWK = [self.webView isKindOfClass:NSClassFromString(@"WKWebView")];
    if (!isWK) {
        NSLog(@"CDVKeyboard: WARNING!!: Keyboard plugin works better with WK");
    }
    BOOL isPre10_0_0 = ![self osVersion:10 minor:0 patch:0];
    if (isWK && isPre10_0_0) {
        [nc removeObserver:self.webView name:UIKeyboardWillHideNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardWillShowNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardWillChangeFrameNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardDidChangeFrameNotification object:nil];
    }
}

- (BOOL)osVersion:(NSInteger)mayor minor:(NSInteger)minor patch:(NSInteger)patch
{
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){
        .majorVersion = mayor,
        .minorVersion = minor,
        .patchVersion = patch
        }];
}

#pragma mark Keyboard events

- (void) onKeyboardWillHide:(id)sender
{
    NSLog(@"CDVKeyboard: onKeyboardWillHide (restoring size)");
    CGRect frame = [[UIScreen mainScreen] bounds];

    [self setWKFrame:frame];
    self.closingkeyboard = YES;
    [self.commandDelegate evalJs:@"Keyboard.fireOnHiding();"];
}

- (void) onKeyboardDidHide:(id)sender
{
    NSLog(@"CDVKeyboard: onKeyboardDidHide");
    [self.commandDelegate evalJs:@"Keyboard.fireOnHide();"];
}

- (void) onKeyboardDidShow:(id)sender
{
    NSLog(@"CDVKeyboard: onKeyboardDidShow");
    [self.commandDelegate evalJs:@"Keyboard.fireOnShow();"];
}

- (void) onKeyboardWillShow:(NSNotification *)note
{
    NSLog(@"CDVKeyboard: onKeyboardWillShow");
    self.closingkeyboard = NO;
    [[self.webView scrollView] setContentInset:UIEdgeInsetsZero];
    [self.commandDelegate evalJs:@"Keyboard.fireOnShowing();"];
}

- (void) onKeyboardDidFrame:(NSNotification *)note
{
    CGRect rect = [[note.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double height = rect.size.height;
    if (!self.closingkeyboard) {
        NSLog(@"CDVKeyboard: onKeyboardDidFrame");
        CGRect f = [[UIScreen mainScreen] bounds];
        [self setWKFrame:CGRectMake(f.origin.x, f.origin.y, f.size.width, f.size.height - height)];
    }
    [[self.webView scrollView] setContentInset:UIEdgeInsetsZero];
    [self.commandDelegate evalJs: [NSString stringWithFormat:@"Keyboard.fireOnFrameChange(%f);", height]];
}

- (void)setWKFrame:(CGRect) frame
{
    self.frame = frame;

    __weak CDVKeyboard* weakSelf = self;
    SEL action = @selector(_updateFrame:);
    [NSObject cancelPreviousPerformRequestsWithTarget:weakSelf selector:action object:nil];
    [weakSelf performSelector:action withObject:nil afterDelay:0.05];
}

- (void)_updateFrame:(NSValue*) value
{
    if(!CGRectEqualToRect(self.frame, self.webView.frame)) {
        NSLog(@"CDVKeyboard: updating WK frame");
        [self.webView setFrame:self.frame];
    }
}


#pragma mark HideFormAccessoryBar

static IMP UIOriginalImp;
static IMP WKOriginalImp;

- (void)setHideFormAccessoryBar:(BOOL)hideFormAccessoryBar
{
    if (hideFormAccessoryBar == _hideFormAccessoryBar) {
        return;
    }

    NSString* UIClassString = [@[@"UI", @"Web", @"Browser", @"View"] componentsJoinedByString:@""];
    NSString* WKClassString = [@[@"WK", @"Content", @"View"] componentsJoinedByString:@""];

    Method UIMethod = class_getInstanceMethod(NSClassFromString(UIClassString), @selector(inputAccessoryView));
    Method WKMethod = class_getInstanceMethod(NSClassFromString(WKClassString), @selector(inputAccessoryView));

    if (hideFormAccessoryBar) {
        UIOriginalImp = method_getImplementation(UIMethod);
        WKOriginalImp = method_getImplementation(WKMethod);

        IMP newImp = imp_implementationWithBlock(^(id _s) {
            return nil;
        });

        method_setImplementation(UIMethod, newImp);
        method_setImplementation(WKMethod, newImp);
    } else {
        method_setImplementation(UIMethod, UIOriginalImp);
        method_setImplementation(WKMethod, WKOriginalImp);
    }

    _hideFormAccessoryBar = hideFormAccessoryBar;
}


#pragma mark Plugin interface

- (void)hideFormAccessoryBar:(CDVInvokedUrlCommand*)command
{
    id value = [command.arguments objectAtIndex:0];
    if (!([value isKindOfClass:[NSNumber class]])) {
        value = [NSNumber numberWithBool:NO];
    }

    self.hideFormAccessoryBar = [value boolValue];
}

- (void)hide:(CDVInvokedUrlCommand*)command
{
    [self.webView endEditing:YES];
}

#pragma mark dealloc

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
