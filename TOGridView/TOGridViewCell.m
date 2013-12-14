//
//  TOGridViewCell.m
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

#import "TOGridViewCell.h"
#import "TOGridView.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIGestureRecognizerSubclass.h>

#define ANIMATION_TIME 0.7f

@interface TOGridViewCell()

{
    /* State tracking that would change the appearence of the cell. */
    BOOL _isEditing;        /* Whether the cell is currently in an editing state */
    BOOL _isHighlighted;    /* Cell is currently 'highlighted' (ie, when a user taps it outside of edit mode) */
    BOOL _isSelected;       /* Cell is 'selected' (eg, when the user is selecting multiple cells for a batch operation) */
    BOOL _isDragging;       /* Cell is currently being dragged around the screen by the user */
}

/* The view that all of the dynamic content of this cell is added to. */
@property (nonatomic,strong) UIView *contentView;

@end

@implementation TOGridViewCell

- (id)initWithFrame:(CGRect)frame
{    
    if (self = [super initWithFrame:frame])
    {
        //Set up default state for this cell view
        self.backgroundColor = [UIColor whiteColor];
        self.autoresizesSubviews = YES;
        self.exclusiveTouch = YES;
        self.multipleTouchEnabled = NO;
    }
    
    return self;
}

#pragma mark -
#pragma mark Cell Selection Style Handlers
- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [self setEditing:animated];
    
    //Mainly for use if the subclass wants to do any animation transitions upon entering/exiting edit mode
}

/* Called when a cell is tapped and/or subsequently released to add a highlight effect. */
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    if (highlighted == _isHighlighted)
        return;
    
    _isHighlighted = highlighted;
    
    //skip this if we haven't got a highlighted background view supplied
    if (self.highlightedBackgroundView == nil)
        return;
    
    if (animated)
    {
        //cancel any animations in progress
        [self.highlightedBackgroundView.layer removeAllAnimations];
        
        CGFloat alpha;
        self.highlightedBackgroundView.hidden = NO;
        
        if (highlighted)
        {
            self.highlightedBackgroundView.alpha = 0.0f;
            alpha = 1.0f;
        }
        else
        {
            self.highlightedBackgroundView.alpha = 1.0f;
            alpha = 0.0f;
            
            [self setNeedsTransparentContent:YES];
        }
        
        //set the content view to the oppsoite state so we can transition to it
        [self setHighlighted:(!_isHighlighted)];
        
        /* Animate the highlighted background to crossfade */
        [UIView animateWithDuration:ANIMATION_TIME animations:^{
            self.highlightedBackgroundView.alpha = alpha;
        }
        completion:^(BOOL finished)
        {
            if (_isHighlighted == NO)
            {
                self.highlightedBackgroundView.hidden = YES;
                [self setNeedsTransparentContent:YES];
            }
        }];

        //set the content view to unhighlighted about halfway through the animation
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (ANIMATION_TIME*0.5f) * NSEC_PER_SEC), dispatch_get_current_queue(), ^{
            [self setHighlighted:_isHighlighted];
        });
    }
    else
    {
        self.highlightedBackgroundView.alpha = 1.0f;
        
        if (_isHighlighted)
        {
            self.highlightedBackgroundView.hidden = NO;
            [self setNeedsTransparentContent:YES];
        }
        else
        {
            self.highlightedBackgroundView.hidden = YES;
            [self setNeedsTransparentContent:NO];
        }
        
        [self setHighlighted:_isHighlighted];
    }
}

- (void)setDragging:(BOOL)dragging animated:(BOOL)animated
{
    [self.superview bringSubviewToFront:self];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    _isSelected = selected;
    
    if (_selectedBackgroundView == nil)
        return;
    
    if (animated)
    {
        //cancel any animations in progress
        [self.selectedBackgroundView.layer removeAllAnimations];
        
        CGFloat alpha;
        self.selectedBackgroundView.hidden = NO;
        
        if (_isSelected)
        {
            self.selectedBackgroundView.alpha = 0.0f;
            alpha = 1.0f;
        }
        else
        {
            self.selectedBackgroundView.alpha = 1.0f;
            alpha = 0.0f;
            
            [self setNeedsTransparentContent:YES];
        }
        
        //set the content view to the oppsoite state so we can transition to it
        [self setSelected:(!_isSelected)];
        
        /* Animate the highlighted background to crossfade */
        [UIView animateWithDuration:ANIMATION_TIME animations:^{
            self.selectedBackgroundView.alpha = alpha;
        }
        completion:^(BOOL finished)
        {
             if (_isSelected == NO)
             {
                 self.selectedBackgroundView.hidden = YES;
                 [self setNeedsTransparentContent:YES];
             }
        }];
        
        //set the content view to unhighlighted about halfway through the animation
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (ANIMATION_TIME*0.5f) * NSEC_PER_SEC), dispatch_get_current_queue(), ^{
            [self setSelected:_isSelected];
        });
    }
    else
    {
        self.selectedBackgroundView.alpha = 1.0f;
        
        if (_isSelected)
        {
            self.selectedBackgroundView.hidden = NO;
            [self setNeedsTransparentContent:YES];
        }
        else
        {
            self.selectedBackgroundView.hidden = YES;
            [self setNeedsTransparentContent:NO];
        }
        
        [self setSelected:_isSelected];
    }
}

- (void)setNeedsTransparentContent:(BOOL)transparent
{
    for( UIView *view in self.contentView.subviews )
        view.backgroundColor = transparent ? [UIColor clearColor] : self.backgroundColor;
}

#pragma mark -
#pragma mark Accessor Methods
- (UIView *)contentView
{
    if (_contentView == nil)
    {
        _contentView = [[UIView alloc] initWithFrame:self.bounds];
        _contentView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        _contentView.backgroundColor = [UIColor clearColor];
        
        [self addSubview:_contentView];
    }
    
    return _contentView;
}

- (void)setBackgroundView:(UIView *)backgroundView
{
    if (self.backgroundView && self.backgroundView == backgroundView)
        return;
    
    [self.backgroundView removeFromSuperview];
    _backgroundView = backgroundView;
    self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundView.frame = self.bounds;
    
    [self insertSubview:self.backgroundView atIndex:0];
}

- (void)setHighlightedBackgroundView:(UIView *)highlightedBackgroundView
{
    if (self.highlightedBackgroundView && self.highlightedBackgroundView == highlightedBackgroundView)
        return;
    
    [self.highlightedBackgroundView removeFromSuperview];
    _highlightedBackgroundView = highlightedBackgroundView;
    self.highlightedBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.highlightedBackgroundView.frame = self.bounds;
    
    if (self.backgroundView)
        [self insertSubview:self.highlightedBackgroundView aboveSubview:self.backgroundView ];
    else
        [self insertSubview:self.highlightedBackgroundView atIndex:0];
    
    self.highlightedBackgroundView.hidden = YES;
}

- (void)setSelectedBackgroundView:(UIView *)selectedBackgroundView
{
    if (self.selectedBackgroundView && self.selectedBackgroundView == selectedBackgroundView)
        return;
    
    [self.selectedBackgroundView removeFromSuperview];
    _selectedBackgroundView = selectedBackgroundView;
    self.selectedBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.selectedBackgroundView.frame = self.bounds;
    
    if (self.backgroundView)
        [self insertSubview:self.selectedBackgroundView aboveSubview:self.backgroundView];
    else
        [self insertSubview:self.selectedBackgroundView atIndex:0];
    
    self.selectedBackgroundView.hidden = YES;
}

@end
