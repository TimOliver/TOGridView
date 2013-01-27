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
@class TOTapGestureRecognizer;

@interface TOGridViewCell : UIView <UIGestureRecognizerDelegate> {    
    
    /* State tracking that would change the appearence of the cell. */
    BOOL _isEditing;        /* Whether the cell is currently in an editing state */
    BOOL _isHighlighted;    /* Cell is currently 'highlighted' (ie, when a user taps it outside of edit mode) */
    BOOL _isSelected;       /* Cell is 'selected' (eg, when the user is selecting multiple cells for a batch operation) */
    BOOL _isDragging;       /* Cell is currently being dragged around the screen by the user */
    
    /* Various gesture recognizers for detecting interactions with the cell */
    UITapGestureRecognizer          *_tapGestureRecognizer;         /* When the user taps the cell, faster than the long press */
    UILongPressGestureRecognizer    *_longPressGestureRecognizer;   /* When the user taps and holds the cell. */
    UISwipeGestureRecognizer        *_swipeGestureRecognizer;       /* When the user swipes the cell. */
    UIPanGestureRecognizer          *_panGestureRecognizer;         /* When the user drags the view around the screen. */
    
    /* The view that all of the dynamic content of this cell is added to. */
    UIView *_contentView;
}

/* Set the state of the cell to editing. Will be called on all visible cells when the grid view enters edit mode */
- (void)setEditing: (BOOL)editing animated: (BOOL)animated;
/* Highlighted occurs when the user taps the view in non-edit mode */
- (void)setHighlighted: (BOOL)highlighted animated:(BOOL)animated;
/* Selected occurs when a cell is tapped in edit mode. Multiple cells may be selected at once. */
- (void)setSelected: (BOOL)selected animated:(BOOL)animated;
/* Sent when the view needs to transition into its dragging state */
- (void)setDragging: (BOOL)dragging animated: (BOOL)animated;

/* 
 Ideally, for on-the-fly rendering performance, no views in the content view should
 be transparent (eg, they should have a BG color matching the back view).
 In the cases where the content need be transparent (eg, the highlighted background crossfading),
 this method can be overridden on the cell subclass so it has a chance to set up the views properly. */
- (void)setNeedsTransparentContent: (BOOL)transparent;

/* Grid view management properties. You probably should modify these manually. (You can try. It might be hilarious XD) */
@property (nonatomic, assign)   NSUInteger index;
@property (nonatomic, weak)     TOGridView *gridView;

/* Public accessors for the cell state */
@property (nonatomic, assign)   BOOL editing;
@property (nonatomic, assign)   BOOL selected;
@property (nonatomic, assign)   BOOL highlighted;

/* Views for various states that are placed in the background */
@property (nonatomic, strong)   UIView *backgroundView;
@property (nonatomic, strong)   UIView *highlightedBackgroundView;
@property (nonatomic, strong)   UIView *selectedBackgroundView;

/* The primary view to place dynamic content */
@property (nonatomic, readonly) UIView *contentView;

@property (nonatomic, readonly) UITapGestureRecognizer *tapGestureRecognizer;
@property (nonatomic, readonly) UILongPressGestureRecognizer *longPressGestureRecognizer;

@end

/* Custom subclass of UIGestureRecognizer to detect single-taps properly */
@interface TOTapGestureRecognizer : UIGestureRecognizer {
    NSTimer *_timer;
}

- (void)invalidateTouch;

@end
