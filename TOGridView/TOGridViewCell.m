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

@end

@implementation TOGridViewCell

@synthesize index                       = _index,
            gridView                    = _gridView,
            editing                     = _isEditing,
            highlighted                 = _isHighlighted,
            selected                    = _isSelected,
            backgroundView              = _backgroundView,
            highlightedBackgroundView   = _highlightedBackgroundView,
            selectedBackgroundView      = _selectedBackgroundView;

- (id)initWithFrame:(CGRect)frame
{    
    if (self = [super initWithFrame: frame])
    {
        //Set up default state for this cell view
        self.backgroundColor = [UIColor whiteColor];
        self.autoresizesSubviews = YES;
        self.exclusiveTouch = YES;
        self.multipleTouchEnabled = NO;
    }
    
    return self;
}

- (void)dealloc
{
    //remove soft references on dealloc
    _gridView = nil;
}

#pragma mark -
#pragma mark Cell Selection Style Handlers
- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [self setEditing: animated];
    
    //Mainly for use if the subclass wants to do any animation transitions upon entering/exiting edit mode
}

/* Called when a cell is tapped and/or subsequently released to add a highlight effect. */
- (void)setHighlighted: (BOOL)highlighted animated:(BOOL)animated
{
    _isHighlighted = highlighted;
    
    //skip this if we haven't got a highlighted background view supplied
    if( _highlightedBackgroundView == nil )
        return;
    
    if( animated )
    {
        //cancel any animations in progress
        [_highlightedBackgroundView.layer removeAllAnimations];
        
        CGFloat alpha;
        _highlightedBackgroundView.hidden = NO;
        
        if( highlighted )
        {
            _highlightedBackgroundView.alpha = 0.0f;
            alpha = 1.0f;
        }
        else
        {
            _highlightedBackgroundView.alpha = 1.0f;
            alpha = 0.0f;
            
            [self setNeedsTransparentContent: YES];
        }
        
        //set the content view to the oppsoite state so we can transition to it
        [self setHighlighted: !_isHighlighted];
        
        /* Animate the highlighted background to crossfade */
        [UIView animateWithDuration: ANIMATION_TIME animations: ^{
            _highlightedBackgroundView.alpha = alpha;
        }
        completion: ^(BOOL finished)
        {
            if( _isHighlighted == NO )
            {
                _highlightedBackgroundView.hidden = YES;
                [self setNeedsTransparentContent: YES];
            }
        }];
        
        //set the content view to unhighlighted about halfway through the animation
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (ANIMATION_TIME*0.5f) * NSEC_PER_SEC), dispatch_get_current_queue(), ^{
            [self setHighlighted: _isHighlighted];
        });
    }
    else
    {
        _highlightedBackgroundView.alpha = 1.0f;
        
        if( _isHighlighted )
        {
            _highlightedBackgroundView.hidden = NO;
            [self setNeedsTransparentContent: YES];
        }
        else
        {
            _highlightedBackgroundView.hidden = YES;
            [self setNeedsTransparentContent: NO];
        }
        
        [self setHighlighted: _isHighlighted];
    }
}

- (void)setDragging: (BOOL)dragging atTouchPoint: (CGPoint)point animated: (BOOL)animated
{
    [self.superview bringSubviewToFront: self];
    
    //The location fo the touch event in relation to this cell (as TouchPoint is relative to the scroll view)
    CGPoint touchPointInCell = [self.superview convertPoint: point toView: self];
    
    //The original transformation state and a slightly scaled version
    CGAffineTransform originTransform = CGAffineTransformIdentity;
    CGAffineTransform destTransform = CGAffineTransformScale(CGAffineTransformIdentity, 1.1f, 1.1f);
    
    //The original alpha (fully opaque) and slightly transparent 
    CGFloat originAlpha = 1.0f;
    CGFloat destAlpha = 0.75;
    
    //the original anchor point (directly in the middle of this view) and the new one
    CGPoint originAnchorPoint = CGPointMake( 0.5f, 0.5f );
    CGPoint destAnchorPoint = CGPointMake( touchPointInCell.x / CGRectGetWidth(self.bounds), touchPointInCell.y / CGRectGetHeight(self.bounds) );
    
    if( animated )
    {
        /* Set initial state before animating */
        if( dragging )
        {
            self.transform = originTransform;
            self.alpha = originAlpha;
            self.layer.anchorPoint = destAnchorPoint;
            self.center = point;
        }
        else
        {
            self.transform = destTransform;
            self.alpha = destAlpha;
            self.center = point;
            
            //set up a CoreAnimation to reset the anchorpoint
            CABasicAnimation *anchorPointAnimation = [CABasicAnimation animationWithKeyPath: @"anchorPoint"];
            anchorPointAnimation.duration = 0.2f;
            anchorPointAnimation.fromValue = [NSValue valueWithCGPoint: destAnchorPoint];
            anchorPointAnimation.toValue = [NSValue valueWithCGPoint: originAnchorPoint];
            [self.layer addAnimation: anchorPointAnimation forKey: @"anchorPointAnimation"];
            self.layer.anchorPoint = originAnchorPoint;
        }
        
        /* Perform the animation */
        [UIView animateWithDuration: 0.20f delay: 0.0f options: UIViewAnimationCurveEaseOut animations:
         ^{
            if( dragging )
            {
                self.transform = destTransform;
                self.alpha = destAlpha;
            }
            else
            {
                self.transform = originTransform;
                self.alpha = originAlpha;
                self.center = [_gridView centerOfCellAtIndex: self.index];
            }
        } completion: nil];
    }
    else
    {
        /* Set the new values */
        if( dragging)
        {
            self.transform = originTransform;
            self.transform = destTransform;
            self.alpha = destAlpha;
            self.layer.anchorPoint = destAnchorPoint;
            self.center = point;
        }
        else
        {
            self.transform = originTransform;
            self.alpha = originAlpha;
            self.layer.anchorPoint = originAnchorPoint;
            self.center = point;
        }
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    
}

- (void)setNeedsTransparentContent:(BOOL)transparent
{
    for( UIView *view in _contentView.subviews )
        view.backgroundColor = transparent ? [UIColor clearColor] : self.backgroundColor;
}

#pragma mark -
#pragma mark Accessor Methods
- (UIView *)contentView
{
    if( _contentView == nil )
    {
        _contentView = [[UIView alloc] initWithFrame: self.bounds];
        _contentView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        _contentView.backgroundColor = [UIColor clearColor];
        
        [self addSubview: _contentView];
    }
    
    return _contentView;
}

- (void)setBackgroundView:(UIView *)backgroundView
{
    if( _backgroundView && _backgroundView == backgroundView )
        return;
    
    [_backgroundView removeFromSuperview];
    _backgroundView = backgroundView;
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _backgroundView.frame = self.bounds;
    
    [self insertSubview: _backgroundView atIndex: 0];
}

- (void)setHighlightedBackgroundView:(UIView *)highlightedBackgroundView
{
    if( _highlightedBackgroundView && _highlightedBackgroundView == highlightedBackgroundView)
        return;
    
    [_highlightedBackgroundView removeFromSuperview];
    _highlightedBackgroundView = highlightedBackgroundView;
    _highlightedBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _highlightedBackgroundView.frame = self.bounds;
    
    if( _backgroundView )
        [self insertSubview: _highlightedBackgroundView aboveSubview: _backgroundView ];
    else
        [self insertSubview: _highlightedBackgroundView atIndex: 0 ];
    
    _highlightedBackgroundView.hidden = YES;
}

- (void)setSelectedBackgroundView:(UIView *)selectedBackgroundView
{
    if( _selectedBackgroundView && _selectedBackgroundView == selectedBackgroundView)
        return;
    
    [_selectedBackgroundView removeFromSuperview];
    _selectedBackgroundView = selectedBackgroundView;
    _selectedBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _selectedBackgroundView.frame = self.bounds;
    
    if( _backgroundView )
        [self insertSubview: _selectedBackgroundView aboveSubview: _backgroundView ];
    else
        [self insertSubview: _selectedBackgroundView atIndex: 0 ];
    
    _selectedBackgroundView.hidden = YES;
}

@end
