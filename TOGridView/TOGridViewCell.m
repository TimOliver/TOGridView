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

#define ANIMATION_TIME 0.5f

@interface TOGridViewCell()

/* Gesture Recognizer Callbacks */
- (void)cellWasLongPressed: (UILongPressGestureRecognizer *)gestureRecognizer;
- (void)cellWasSwiped: (UISwipeGestureRecognizer *)gestureRecognizer;

@end

@implementation TOGridViewCell

@synthesize index                       = _index,
            gridView                    = _gridView,
            editing                   = _isEditing,
            highlighted               = _isHighlighted,
            selected                  = _isSelected,
            backgroundView              = _backgroundView,
            highlightedBackgroundView   = _highlightedBackgroundView,
            selectedBackgroundView      = _selectedBackgroundView
            ;

- (id)initWithFrame:(CGRect)frame
{    
    if (self = [super initWithFrame: frame])
    {
        self.backgroundColor = [UIColor whiteColor];
        
        _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget: self action: @selector(cellWasLongPressed:)];
        _longPressGestureRecognizer.minimumPressDuration = 0.5f;
        _longPressGestureRecognizer.delegate = self;
        [self addGestureRecognizer: _longPressGestureRecognizer];
        
        _swipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget: self action: @selector(cellWasSwiped:)];
        _swipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
        _swipeGestureRecognizer.delegate = self;
        [self addGestureRecognizer: _swipeGestureRecognizer];
    }
    
    return self;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    
}

- (void)setHighlighted: (BOOL)highlighted animated:(BOOL)animated
{
    if( highlighted == _isHighlighted )
        return;
    
    _isHighlighted = highlighted;
    
    if( animated )
    {
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
        }
        
        [self setHighlighted: !_isHighlighted];
        [UIView animateWithDuration: ANIMATION_TIME animations: ^{
            _highlightedBackgroundView.alpha = alpha;
        }
        completion: ^(BOOL finished)
        {
            [self setHighlighted: _isHighlighted];
            
            if( _isHighlighted == NO )
                _highlightedBackgroundView.hidden = YES;
    
        }];
    }
    else
    {
        _highlightedBackgroundView.alpha = 1.0f;
        
        if( _isHighlighted )
            _highlightedBackgroundView.hidden = NO;
        else
            _highlightedBackgroundView.hidden = YES;
        
        [self setHighlighted: _isHighlighted];
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    
}

#pragma mark -
#pragma mark Manual Touch Events
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan: touches withEvent: event];
    
    if( _gridView.highlightedCellIndex < 0 )
    {
        [self setHighlighted: YES animated: NO];
        _gridView.highlightedCellIndex = _index;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded: touches withEvent: event];
    
    if( [_gridView.delegate respondsToSelector: @selector(gridView:didTapCellAtIndex:)] )
        [_gridView.delegate gridView: _gridView didTapCellAtIndex: _index];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled: touches withEvent: event];
    
    [self setHighlighted: NO animated: NO];
    _gridView.highlightedCellIndex = -1;
}

#pragma mark -
#pragma mark Touch Delegate events
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    //Don't perform the long tap gesture if there isn't a delegate method to apply it to
    if( gestureRecognizer == _longPressGestureRecognizer && [_gridView.delegate respondsToSelector: @selector(gridView:didLongTapCellAtIndex:)] == NO)
        return NO;                                                                                                                                                                                                                                         
    
    if( gestureRecognizer == _swipeGestureRecognizer )
    {
        return NO;
    }
    
    return YES;
}

#pragma mark -
#pragma mark Touch Callbacks
- (void)cellWasLongPressed:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if( gestureRecognizer.state != UIGestureRecognizerStateBegan )
        return;
    
   if( [_gridView.delegate respondsToSelector: @selector(gridView:didLongTapCellAtIndex:)])
       [_gridView.delegate gridView: _gridView didLongTapCellAtIndex: _index];
}

- (void)cellWasSwiped:(UISwipeGestureRecognizer *)gestureRecognizer
{
    
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
