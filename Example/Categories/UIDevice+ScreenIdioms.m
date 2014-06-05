//
//  UIDevice+ExtendedIdioms.m
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

#import "UIDevice+ScreenIdioms.h"

#define RETINA_4INCH_HEIGHT_IN_POINTS 568

@implementation UIDevice (ExtendedIdioms)

- (UIUserInterfaceScreenIdiom)userInterfaceScreenIdiom
{
    /* If it's an iPad, we can just defer to the tried and true method. */
    if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
        return UIUserInterfaceScreenIdiomPad;
    
    /* If it's NOT an iPad, we'll have to see what kind of screen it has. */
    CGSize screenSize       = [[UIScreen mainScreen] bounds].size; /* Get the dimensions of the device screen, in portrait mode */
    NSInteger screenHeight  = MAX((NSInteger)screenSize.height, (NSInteger)screenSize.width); /* Typecast the dimensions to integers to avoid any floating point inaccuracies */
    
    /* Perform manual size check to establish the screen size. */
    if ( screenHeight == RETINA_4INCH_HEIGHT_IN_POINTS )
        return UIUserInterfaceScreenIdiomPhone4Inch;
 
    return UIUserInterfaceScreenIdiomPhone35Inch;
}

@end
