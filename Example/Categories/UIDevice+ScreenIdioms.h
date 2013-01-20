//
//  UIDevice+ExtendedIdioms.h
//
//  Copyright (c) 2013 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included
//  in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
//  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
//  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.

#import <UIKit/UIKit.h>

#define UI_USER_INTERFACE_SCREEN_IDIOM() ([[UIDevice currentDevice] respondsToSelector:@selector(userInterfaceScreenIdiom)] ? [[UIDevice currentDevice] userInterfaceScreenIdiom] : UIUserInterfaceScreenIdiomPhone35Inch)

typedef enum {
    UIUserInterfaceScreenIdiomUnknown,
    UIUserInterfaceScreenIdiomPhone35Inch,  // 3.5" screens  (iPhone original - iPhone 4S, iPod touch 1G - 4G)
    UIUserInterfaceScreenIdiomPhone4Inch,   // 4" screens    (iPhone 5, iPod touch 5G)
    UIUserInterfaceScreenIdiomPad           // iPad screen   (1024x768 points, 9.7" / 7.9" displays)
} UIUserInterfaceScreenIdiom;

@interface UIDevice (ScreenIdioms)

- (UIUserInterfaceScreenIdiom)userInterfaceScreenIdiom;

@end
