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

@interface TOGridViewCell()

/* Gesture Recognizer Callbacks */
- (void)cellWasTapped: (UITapGestureRecognizer *)gestureRecognizer;
- (void)cellWasLongPressed: (UILongPressGestureRecognizer *)gestureRecognizer;
- (void)cellWasSwiped: (UISwipeGestureRecognizer *)gestureRecognizer;

@end

@implementation TOGridViewCell

@synthesize index = _index, gridView = _gridView, isHighlighted = _isHighlighted, isSelected = _isSelected;

- (id)init
{    
    if (self = [super init])
    {
        self.backgroundColor = [UIColor whiteColor];
        
        _tapGestureRecognizer       = [[UITapGestureRecognizer alloc] initWithTarget:       self action: @selector(cellWasTapped:)];
        _tapGestureRecognizer.delegate = self;
        [self addGestureRecognizer: _tapGestureRecognizer];
        
        _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget: self action: @selector(cellWasLongPressed:)];
        _longPressGestureRecognizer.minimumPressDuration = 1.0f;
        _longPressGestureRecognizer.delegate = self;
        [_longPressGestureRecognizer requireGestureRecognizerToFail: _tapGestureRecognizer];
        [self addGestureRecognizer: _longPressGestureRecognizer];
        
        _swipeGestureRecognizer     = [[UISwipeGestureRecognizer alloc] initWithTarget:     self action: @selector(cellWasSwiped:)];
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
    _isHighlighted = highlighted;

    if( _isHighlighted )
        self.backgroundColor = [UIColor redColor];
    else
        self.backgroundColor = [UIColor whiteColor];
}

#pragma mark -
#pragma mark Manual Touch Events
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    if( _gridView.highlightedCellIndex < 0 )
    {
        [self setHighlighted: YES animated: NO];
        _gridView.highlightedCellIndex = _index;
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self setHighlighted: NO animated: YES];
    _gridView.highlightedCellIndex = -1;
}

#pragma mark -
#pragma mark Touch Delegate events
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if( gestureRecognizer == _tapGestureRecognizer && _gridView.highlightedCellIndex >= 0 )
        return NO;
    
    if( gestureRecognizer == _longPressGestureRecognizer && [_gridView.dataSource respondsToSelector: @selector(gridView:didLongTapCellAtIndex:)] == NO)
        return NO;                                                                                                                                                                                                                                         
    
    return YES;
}

#pragma mark -
#pragma mark Touch Callbacks
- (void)cellWasTapped:(UITapGestureRecognizer *)gestureRecognizer
{
    NSLog( @"Tapped!");
}

- (void)cellWasLongPressed:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if( gestureRecognizer.state != UIGestureRecognizerStateBegan )
        return;
    
    NSLog( @"Long Tapped %@", gestureRecognizer );
}

- (void)cellWasSwiped:(UISwipeGestureRecognizer *)gestureRecognizer
{
    NSLog( @"Swiped Tapped" );
}

@end
