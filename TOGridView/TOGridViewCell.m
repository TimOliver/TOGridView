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
            selectedBackgroundView      = _selectedBackgroundView,
            tapGestureRecognizer        = _tapGestureRecognizer,
            longPressGestureRecognizer  = _longPressGestureRecognizer;

- (id)initWithFrame:(CGRect)frame
{    
    if (self = [super initWithFrame: frame])
    {
        self.backgroundColor = [UIColor whiteColor];
        self.autoresizesSubviews = YES;
        self.exclusiveTouch = YES;
        self.multipleTouchEnabled = NO;
    }
    
    return self;
}

- (void)dealloc
{
    _gridView = nil;
}

- (void)didMoveToSuperview
{
    /* This shouldn't be possible unless something other than the parent grid view is messing with this cell. */
    if( _gridView == nil )
        [NSException raise: @"Improper View Setup" format: @"%@", @"Cells cannot be added to a superview without a valid parent gridview."];
    
    _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget: _gridView action: @selector(_gridViewCellDidTap:)];
    _tapGestureRecognizer.delegate = _gridView;
    [self addGestureRecognizer: _tapGestureRecognizer];
    
    _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget: _gridView action: @selector(_gridViewCellDidLongPress:)];
    _longPressGestureRecognizer.delegate = _gridView;
    _longPressGestureRecognizer.minimumPressDuration = 0.1f;
    [self addGestureRecognizer: _longPressGestureRecognizer];
    
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget: _gridView action: @selector(_gridViewCellDidPan:)];
    _panGestureRecognizer.delegate = _gridView;
    _panGestureRecognizer.enabled = NO;
    [self addGestureRecognizer: _panGestureRecognizer];
    
    _swipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget: _gridView action: @selector(_gridViewCellDidSwipe:)];
    _swipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
    _swipeGestureRecognizer.delegate = _gridView;
    [self addGestureRecognizer: _swipeGestureRecognizer];
}

#pragma mark -
#pragma mark Cell Selection Style Handlers
- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [self setEditing: animated];
    
    //Mainly for use if the subclass wants to do any animation transitions
}

/* Called when a cell is tapped and/or subsequently released to add a highlight effect. */
- (void)setHighlighted: (BOOL)highlighted animated:(BOOL)animated
{
    _isHighlighted = highlighted;
    
    //skip this if we haven't got a background view supplied
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

- (void)setDragging: (BOOL)dragging animated: (BOOL)animated
{
    CGAffineTransform originTransform = CGAffineTransformIdentity;
    CGAffineTransform destTransform = CGAffineTransformScale(self.transform, 1.2f, 1.2f);
    
    CGFloat originAlpha = 1.0f;
    CGFloat destAlpha = 0.75;
    
    if( animated )
    {
        /* Set initial state */
        if( dragging )
        {
            self.transform = originTransform;
            self.alpha = originAlpha;
        }
        else
        {
            self.transform = CGAffineTransformIdentity;
            self.transform = destTransform;
            self.alpha = destAlpha;
        }
        
        [UIView animateWithDuration: 0.4f animations: ^{
            if( dragging )
            {
                self.transform = destTransform;
                self.alpha = destAlpha;
            }
            else
            {
                self.transform = originTransform;
                self.alpha = originAlpha;
            }
        }];
    }
    else
    {
        if( dragging)
        {
            self.transform = originTransform;
            self.transform = destTransform;
            self.alpha = destAlpha;
        }
        else
        {
            self.transform = originTransform;
            self.alpha = originAlpha;
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

/********************************************************************************
 
 UIGestureRecgonizer Subclass for detecting single tap events
 
 *******************************************************************************/
@interface TOTapGestureRecognizer ()

- (void)timerFired: (NSTimer *)timer;

@end

@implementation TOTapGestureRecognizer

/* State Reset */
- (void)reset
{
    [super reset];
    
    self.state = UIGestureRecognizerStatePossible;
}

/* Gesture Recognizer Prevention Defines */
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer
{
    /* Pan events (eg scroll views) will always force this recognizer to cancel. */
    if( [preventedGestureRecognizer isKindOfClass: [UIPanGestureRecognizer class]] )
        return NO;
    
    return [super canPreventGestureRecognizer: preventedGestureRecognizer];
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer
{
    if( [preventingGestureRecognizer isKindOfClass: [UIPanGestureRecognizer class]] )
        return YES;
    
    return [super canBePreventedByGestureRecognizer: preventingGestureRecognizer];
}

/* Touch Responder Events */
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan: touches withEvent: event];

    _timer = [NSTimer scheduledTimerWithTimeInterval: 0.15f target: self selector: @selector(timerFired:) userInfo:nil repeats: NO];
}

- (void)timerFired:(NSTimer *)timer
{
    //Starts when a user presses down inside a view
    self.state = UIGestureRecognizerStateBegan;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved: touches withEvent: event];
    
    [_timer invalidate];
    self.state = UIGestureRecognizerStateCancelled;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded: touches withEvent: event];
    
    [_timer invalidate];
    
    self.state = UIGestureRecognizerStateBegan;
    self.state = UIGestureRecognizerStateRecognized;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled: touches withEvent: event];
    self.state = UIGestureRecognizerStateCancelled;
}

- (void)invalidateTouch
{
    self.state = UIGestureRecognizerStateCancelled;
}

@end
