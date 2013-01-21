//
//  TOGridViewCell.h
//
//  Copyright 2013 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import <UIKit/UIKit.h>

@class TOGridView;

@interface TOGridViewCell : UIView <UIGestureRecognizerDelegate> {    
    
    /* State tracking that would change the appearence of the cell. */
    BOOL _isEditing;        /* Whether the cell is currently in an editing state */
    BOOL _isHighlighted;    /* Cell is currently 'highlighted' (eg, when a user taps it to open something) */
    BOOL _isSelected;       /* Cell is 'selected' (eg, when the user is selecting multiple cells for a batch operation) */
    
    /* Various gesture recognizers for detecting interactions with the cell */
    UISwipeGestureRecognizer        *_swipeGestureRecognizer;
    UILongPressGestureRecognizer    *_longPressGestureRecognizer;
    
    UIView *_contentView;
}

- (void)setEditing: (BOOL)editing animated: (BOOL)animated;
- (void)setHighlighted: (BOOL)highlighted animated:(BOOL)animated;
- (void)setSelected: (BOOL)selected animated:(BOOL)animated;

@property (nonatomic, assign)   NSUInteger index;
@property (nonatomic, weak)     TOGridView *gridView;

@property (nonatomic, assign)   BOOL isEditing;
@property (nonatomic, assign)   BOOL isSelected;
@property (nonatomic, assign)   BOOL isHighlighted;

/* Views for various states that are placed in the background */
@property (nonatomic, strong)   UIView *backgroundView;
@property (nonatomic, strong)   UIView *highlightedBackgroundView;
@property (nonatomic, strong)   UIView *selectedBackgroundView;

/* The primary view to place dynamic content */
@property (nonatomic, readonly) UIView *contentView;

@end
