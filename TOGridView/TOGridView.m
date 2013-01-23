//
//  TOGridView.m
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

#import "TOGridView.h"
#import "TOGridViewCell.h"
#import <QuartzCore/QuartzCore.h>

@interface TOGridView (hidden)

- (void)resetCellMetrics;
- (void)layoutCells;
- (CGSize)contentSizeOfScrollView;
- (CGPoint)originOfCellAtIndex: (NSInteger)cellIndex;
- (TOGridViewCell *)cellForIndex: (NSInteger)index;
- (UIImage *)snapshotOfCellsInRect: (CGRect)rect;
- (void)invalidateVisibleCells;

@end

@implementation TOGridView

@synthesize dataSource = _dataSource,
            headerView = _headerView,
            backgroundView = _backgroundView,
            editing = _isEditing,
            highlightedCellIndex = _highlightedCellIndex,
            nonRetinaRenderContexts = _nonRetinaRenderContexts;

#pragma mark -
#pragma mark View Management
- (id)initWithFrame:(CGRect)frame
{
    if( self = [super initWithFrame: frame] )
    {
        self.bounces                = YES;
        self.scrollsToTop           = YES;
        self.backgroundColor        = [UIColor blackColor];
        self.scrollEnabled          = YES;
        self.alwaysBounceVertical   = YES;
        
        _recycledCells              = [NSMutableSet new];
        _visibleCells               = [NSMutableSet new];
        _cellClass                  = [TOGridViewCell class];
        
        _highlightedCellIndex       = -1;
    }
    
    return self;
}

- (id)initWithFrame:(CGRect)frame withCellClass:(Class)cellClass
{
    if( self = [self initWithFrame: frame] )
    {
        [self registerCellClass: cellClass];
    }
    
    return self;
}

- (void)registerCellClass: (Class)cellClass
{
    _cellClass = cellClass;
}

/* Kickstart the loading of the cells when this view is added to the view hierarchy */
- (void)didMoveToSuperview
{
    [self reloadGrid];
}

- (void)dealloc
{
    /* Remove the weak references from the cells */
    for( TOGridViewCell *cell in _recycledCells )
        cell.gridView = nil;
    
    for( TOGridViewCell *cell in _visibleCells )
        cell.gridView = nil;
    
    /* General clean-up */
    _recycledCells = nil;
    _visibleCells = nil;
}

#pragma mark -
#pragma mark Set-up
- (void)reloadGrid
{
    /* Get the number of cells from the data source */
    if( _gridViewFlags.dataSourceNumberOfCells )
        _numberOfCells = [_dataSource numberOfCellsInGridView: self];
    
    /* Use the delegate+dataSource to set up the rendering logistics of the cells */
    [self resetCellMetrics];
    
    /* Set up an array to track the selected state of each cell */
    _selectedCells = nil;
    _selectedCells = [NSMutableArray arrayWithCapacity: _numberOfCells];
    for( NSInteger i = 0; i < [_selectedCells count]; i++ )
        [_selectedCells addObject: [NSNumber numberWithBool: FALSE]];

    /* Perform a redraw operation */
    [self layoutCells];
}

- (void)resetCellMetrics
{
    /* Get outer padding of cells */
    if( _gridViewFlags.delegateInnerPadding )
        _cellPaddingInset = [self.delegate innerPaddingForGridView: self];
    
    /* Grab the size of each cell */
    if( _gridViewFlags.delegateSizeOfCells )
        _cellSize = [self.delegate sizeOfCellsForGridView: self];
    
    /* See if there is a custom height for each row of cells */
    if( _gridViewFlags.delegateHeightOfRows )
        _rowHeight = [self.delegate heightOfRowsInGridView: self];
    else
        _rowHeight = _cellSize.height;
    
    /* See if there is a custom offset of cells from within each row */
    if( _gridViewFlags.delegateOffsetOfCellInRow )
        _offsetOfCellsInRow = [self.delegate offsetOfCellsInRowsInGridView: self];
    
    /* Get the number of cells per row */
    if( _gridViewFlags.delegateNumberOfCellsPerRow )
        _numberOfCellsPerRow = [self.delegate numberOfCellsPerRowForGridView:self];
    
    /* Work out the spacing between cells */
    _widthBetweenCells = (NSInteger)floor(((CGRectGetWidth(self.bounds) - (_cellPaddingInset.width*2)) //Overall width of row
                                           - (_cellSize.width * _numberOfCellsPerRow)) //minus the combined width of all cells
                                          / (_numberOfCellsPerRow-1)); //divided by the number of gaps between
    
    /* Set up the scrollview and the subsequent contentView */
    self.contentSize = [self contentSizeOfScrollView];
}

/* Take into account the offsets/header size/cell rows to cacluclate the total size of the scrollview */
- (CGSize)contentSizeOfScrollView
{
    CGSize size;
    size.width      = CGRectGetWidth(self.bounds);
    
    size.height     = _offsetFromHeader;
    size.height     += _cellPaddingInset.height * 2;
    
    if( _numberOfCells )
        size.height += (NSInteger)(ceil( (CGFloat)_numberOfCells / (CGFloat)_numberOfCellsPerRow ) * _rowHeight);
    
    return size;
}

/* The origin of each cell */
- (CGPoint)originOfCellAtIndex:(NSInteger)cellIndex
{
    CGPoint origin;
    
    origin.y    = _offsetFromHeader;        /* The height of the header view */
    origin.y    += _offsetOfCellsInRow;     /* Relative offset of the cell in each row */
    origin.y    +=_cellPaddingInset.height; /* The inset padding arond the cells in the scrollview */
    origin.y    += (_rowHeight * floor(cellIndex/_numberOfCellsPerRow));
    
    origin.x    =  _cellPaddingInset.width;
    origin.x    += ((cellIndex % _numberOfCellsPerRow) * (_cellSize.width+_widthBetweenCells));
    
    return origin;
}

- (void)invalidateVisibleCells
{
    for( TOGridViewCell *cell in _visibleCells )
    {
        [cell removeFromSuperview];
        [_recycledCells addObject: cell];
    }
    
    [_visibleCells minusSet: _recycledCells];
}

#pragma mark -
#pragma mark Cell Management
- (TOGridViewCell *)cellForIndex:(NSInteger)index
{
    for( TOGridViewCell *cell in _visibleCells )
    {
        if( cell.index == index)
            return cell;
    }
    
    return nil;
}

/* layoutCells handles all of the recycling/dequeing of cells as the scrollview is scrolling */
- (void)layoutCells
{
    if( _numberOfCells == 0 )
        return;
    
    //The official origin of the first row, accounting for the header size and outer padding
    NSInteger rowOrigin = _offsetFromHeader + _cellPaddingInset.height;
    CGFloat contentOffsetY = self.bounds.origin.y; //bounds.origin on a scrollview contains the best up-to-date contentOffset
    NSInteger numberOfRows = floor(_numberOfCells / _numberOfCellsPerRow);
    
    NSInteger firstVisibleRow   = floor((contentOffsetY-rowOrigin) / _rowHeight);
    NSInteger lastVisibleRow    = floor(((contentOffsetY-rowOrigin)+CGRectGetHeight(self.bounds))/ _rowHeight);
    
    //make sure there are actually some visible rows
    if( lastVisibleRow >= 0 && firstVisibleRow <= numberOfRows )
    {
        _visibleCellRange.location  = MAX(0,firstVisibleRow) * _numberOfCellsPerRow;
        _visibleCellRange.length    = (((lastVisibleRow - MAX(0,firstVisibleRow))+1) * _numberOfCellsPerRow);
    
        if( _visibleCellRange.location + _visibleCellRange.length >= _numberOfCells )
            _visibleCellRange.length = _numberOfCells - _visibleCellRange.location;
    }
    else
    {
        _visibleCellRange.location = -1;
        _visibleCellRange.length = 0;
    }
    
    for( TOGridViewCell *cell in _visibleCells )
    {
        if( cell.index < _visibleCellRange.location || cell.index >= _visibleCellRange.location+_visibleCellRange.length )
        {
            [_recycledCells addObject: cell];
            [cell removeFromSuperview];
        }
    }
    if( [_recycledCells count] )
        [_visibleCells minusSet: _recycledCells];
    
    /* Only proceed with the following code if the number of visible cells is lower than it should be. */
    /* This code produces the most latency, so minimizing its call frequency is critical */
    if( [_visibleCells count] >= _visibleCellRange.length )
        return;
    
    for( NSInteger i = 0; i < _visibleCellRange.length; i++ )
    {
        NSInteger index = _visibleCellRange.location+i;
        
        TOGridViewCell *cell = [self cellForIndex: index];
        if( cell )
            continue;
        
        //Get the cell with its content setup from the dataSource
        cell = [_dataSource gridView: self cellForIndex: index];
        cell.gridView = self;
        cell.index = index;
        
        //make sure the frame is still properly set
        CGRect cellFrame;
        cellFrame.origin = [self originOfCellAtIndex: index];
        cellFrame.size = _cellSize;
        
        //if there's supposed to be NO padding between the edge of the view and the cell,
        //and this cell is short by uneven necessity of the number of cells per row (eg, 1024/3 on iPad = 341.333333333),
        //pad it out
        if( _cellPaddingInset.width <= 0.0f + FLT_EPSILON && (index+1) % _numberOfCellsPerRow == 0 )
        {
            if( CGRectGetMinX(cellFrame) + CGRectGetWidth(cellFrame) < CGRectGetWidth(self.bounds) + FLT_EPSILON )
                cellFrame.size.width = CGRectGetWidth(self.bounds) - CGRectGetMinX(cellFrame);
        }
            
        cell.frame = cellFrame;
        
        //unhighlight it
        if( _highlightedCellIndex == index)
            [cell setHighlighted: YES animated: NO];
        else
            [cell setHighlighted: NO animated: NO];
        
        //add it to the visible objects set (It's already out of the recycled set at this point)
        [_visibleCells addObject: cell];
        
        //Make sure the cell is inserted ABOVE any visible background view, but still BELOW the scroller graphic view
        if( _backgroundView )
            [self insertSubview: cell aboveSubview: _backgroundView];
        else
            [self insertSubview: cell atIndex: 0];
    }
}

/* 
layoutSubviews is called automatically whenever the scrollView's contentOffset changes,
or when the parent view controller changes orientation.

This orientation animation technique is a modified version of one of the techniques that was 
presented at WWDC 2012 in the presentation 'Polishing Your Interface Rotations'. It's been designed
with the goal of handling everything from within the view itself, without requiring any additional work
on the view controller's behalf.

When the iOS device is physically rotated and the orientation change event fires, (Which is captured here by detecting
when a CAAnimation object has been applied to the 'bounds' property of the view), the view quickly renders 
the 'before' and 'after' arrangement of the cells to UIImageViews. It then hides the original cells, overlays both image
views over the top of the scrollview, and cross-fade animates between the two for the same duration as the rotation animation.
*/
- (void)layoutSubviews
{
    [super layoutSubviews];
    
    /* 
     Bit of a sneaky hack here. We've got two interesting scenarios happening:
     The first-gen iPad has a slow GPU (meaning lots of blending is chuggy), but can bake views to UIImage REALLY fast (presumably because the views are non-Retina)
     The third-gen iPad has a kickass GPU (meaning tonnes of blending is easy), but its CPU (While faster than the iPad 1), has to cope with rendering retina UIImages.
     
     In order to get optimal render time+animation on both platforms, the following is happening:
     - On non-Retina devices, the before and after bitmaps are rendered and the cells are hidden throughout the animation (Only 1 alpha blend is happening, so iPad 1 is happy)
     - On Retina devices, only the first bitmap is rendered, which is then cross-faded with the live cells (The iPad 3 can handle manually blending multiple cells, but iPad 1 cannot without a serious FPS hit)
    */
    BOOL isRetinaDevice = [[UIScreen mainScreen] scale] > 1.0f;
    
    /* Apply the crossfade effect if this method is being called while there is a pending 'bounds' animation present. */
    /* Capture the 'before' state to UIImageView before we reposition all of the cells */
    CABasicAnimation *boundsAnimation = (CABasicAnimation *)[self.layer animationForKey: @"bounds"];
    if( boundsAnimation )
    {
        //make a mutable copy of the bounds animation,
        //as we will need to change the 'from' state in a little while
        boundsAnimation = [boundsAnimation mutableCopy];
        [self.layer removeAnimationForKey: @"bounds"];
        
        //disable user interaction
        self.userInteractionEnabled = NO;
        
        //halt the scroll view if it's currently moving
        if( self.isDecelerating || self.isDragging )
        {
            CGPoint contentOffset = self.bounds.origin;
            
            if( contentOffset.y < 0) //reset back to 0 if it's rubber-banding at the top
                [self setContentOffset: CGPointZero animated: NO];
            else if ( contentOffset.y > self.contentSize.height - CGRectGetHeight(self.bounds) ) // reset if rubber-banding at the bottom
                [self setContentOffset: CGPointMake( 0, self.contentSize.height - CGRectGetHeight(self.bounds) ) animated: NO];
            else //just halt it where-ever it is right now.
                [self setContentOffset: contentOffset animated: NO];
        }
        
        //At this point, self.bounds is already the newly resized value.
        //The original bounds are still available as the 'before' value in the layer animation object
        CGRect beforeRect = [boundsAnimation.fromValue CGRectValue];
        _beforeSnapshot = [[UIImageView alloc] initWithImage: [self snapshotOfCellsInRect: beforeRect]];
        
        //Save the current visible cells before we apply the rotation so we can re-align it afterwards
        NSRange visibleCells = _visibleCellRange;
        CGFloat yOffsetFromTopOfRow = beforeRect.origin.y - (_offsetFromHeader + _cellPaddingInset.height + (floor(visibleCells.location/_numberOfCellsPerRow) * _rowHeight));
        
        //poll the delegate again to see if anything needs changing since the bounds have changed
        //(Also, by this point, [UIViewController interfaceOrientation] has updated to the new orientation too)
        [self resetCellMetrics];
        
        //manually set contentOffset's value based off bounds.
        //Not sure why, but if we don't do this, periodically, contentOffset resets to [0,0] (possibly as a result of the frame changing) and borks the animation :S
        if( self.contentSize.height - self.bounds.size.height >= beforeRect.origin.y )
            self.contentOffset = beforeRect.origin;
        
        /* 
         If the header view is completely hidden (ie, only cells), re-orient the scroll view so the same cells are
         onscreen in the new orientation
         */
        if( self.contentOffset.y - _offsetFromHeader > 0.0f && yOffsetFromTopOfRow >= 0.0f && visibleCells.location >= _numberOfCellsPerRow )
        {
            CGFloat y = _offsetFromHeader + _cellPaddingInset.height + (_rowHeight * floor(visibleCells.location/_numberOfCellsPerRow)) + yOffsetFromTopOfRow;
            y = MIN( self.contentSize.height - self.bounds.size.height, y );
            
            self.contentOffset = CGPointMake(0,y);
        }
            
        //remove all of the current cells so they can be reset in the next layout call
        [self invalidateVisibleCells];
    }
    
    //layout the cells (and if we are mid-orientation, this will add/remove any more cells as required)
    [self layoutCells];
    
    //set up the second half of the animation crossfade and then start the crossfade animation
    if( boundsAnimation )
    {
        /*
            "bounds" stores the scroll offset in its 'origin' property, and the actual size of the view in the 'size' property.
            Since we DO want the view to animate resizing itself, but we DON'T want it to animate scrolling at the same time, we'll have
            to modify the animation properties (which is why we made a mutable copy above) and then re-insert it back in.
        */
        CGRect beforeRect = [boundsAnimation.fromValue CGRectValue];
        beforeRect.origin.y = self.bounds.origin.y; //set the before and after scrolloffsets to the same value
        boundsAnimation.fromValue = [NSValue valueWithCGRect: beforeRect];
        boundsAnimation.delegate = self;
        boundsAnimation.removedOnCompletion = YES;
        [self.layer addAnimation: boundsAnimation forKey: @"bounds"];
        
        //Bake the 'after' snapshot to the second imageView (only if we're a non-retina device) and get it ready for display
        if( !isRetinaDevice )
        {
            _afterSnapshot          = [[UIImageView alloc] initWithImage: [self snapshotOfCellsInRect: self.bounds]];
            _afterSnapshot.alpha    = 1.0f;
            _afterSnapshot.frame    = CGRectMake( CGRectGetMinX(self.frame), CGRectGetMinY(self.frame), CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
            [_afterSnapshot.layer removeAllAnimations];
        }
        
        //Get the 'before' snapshot ready
        _beforeSnapshot.frame       = CGRectMake( CGRectGetMinX(self.frame), CGRectGetMinY(self.frame), CGRectGetWidth(_beforeSnapshot.frame), CGRectGetHeight(_beforeSnapshot.frame));
        _beforeSnapshot.alpha       = 0.0f;
        [_beforeSnapshot.layer removeAllAnimations];
        
        for( TOGridViewCell *cell in _visibleCells )
        {
            //disable EVERY ANIMATION that may have been applied to each cell and its sub-cells in the interim.
            //(This includes content, background, and highlight views)
            [cell.layer removeAllAnimations];
            for( UIView *subview in cell.subviews )
                [subview.layer removeAllAnimations];
            
            //If we're animating between 2 snapshots, just hide the cells (MASSIVE performance boost on iPad 1)
            if( !isRetinaDevice )
            {
                cell.hidden = YES; //Hide all of the visible cells
            }
            else
            {
                //Apply a CABasicAnimation to each cell to animate it
                CABasicAnimation *opacity   = [CABasicAnimation animationWithKeyPath: @"opacity"];
                opacity.timingFunction      = boundsAnimation.timingFunction;
                opacity.fromValue           = [NSNumber numberWithFloat: 0.0f];
                opacity.toValue             = [NSNumber numberWithFloat: 1.0f];
                opacity.duration            = boundsAnimation.duration;
                [cell.layer addAnimation: opacity forKey: @"opacity"];
            }
        }
        
        //add the 'before' snapshot (Turns out it's better performance to add it to our superview rather than as a subview)
        [self.superview insertSubview: _beforeSnapshot aboveSubview: self];
        CABasicAnimation *opacity   = [CABasicAnimation animationWithKeyPath: @"opacity"];
        opacity.timingFunction      = boundsAnimation.timingFunction;
        opacity.fromValue           = [NSNumber numberWithFloat: 1.0f];
        opacity.toValue             = [NSNumber numberWithFloat: 0.0f];
        opacity.duration            = boundsAnimation.duration;
        [_beforeSnapshot.layer addAnimation: opacity forKey: @"opacity"];
        
        
        //add the 'after' snapshot
        if( !isRetinaDevice )
        {
            [self.superview insertSubview: _afterSnapshot aboveSubview: _beforeSnapshot];
            
            opacity                 = [CABasicAnimation animationWithKeyPath: @"opacity"];
            opacity.timingFunction  = boundsAnimation.timingFunction;
            opacity.fromValue       = [NSNumber numberWithFloat: 0.0f];
            opacity.toValue         = [NSNumber numberWithFloat: 1.0f];
            opacity.duration        = boundsAnimation.duration;
            [_afterSnapshot.layer addAnimation: opacity forKey: @"opacity"];
        }
    }
    
    /* Update the background view to stay in the background */
    if( _backgroundView )
        _backgroundView.frame = CGRectMake( 0, self.bounds.origin.y, CGRectGetWidth(_backgroundView.bounds), CGRectGetHeight(_backgroundView.bounds));
}

/* CAAnimation Delegate */
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    /* 
     This delegate actually gets called about 3 times per animation. So only proceed when it's definitely finished.
     I'm HOPING there's no way the system can terminate an animation mid-way and not call 'completed' here
    */
    if( flag == NO )
        return;
    
    /* Remove the snapshots from the superview */
    if( _beforeSnapshot ) { [_beforeSnapshot removeFromSuperview]; _beforeSnapshot = nil; }
    if( _afterSnapshot )  { [_afterSnapshot removeFromSuperview];  _afterSnapshot  = nil; }
    
    /* Reset all of the visible cells to their default display state. */
    for( TOGridViewCell *cell in _visibleCells )
    {
        cell.hidden = NO;
        cell.alpha = 1.0f;
    }
    
    /* Re-enable user interaction */
    self.userInteractionEnabled = YES;
}

/* Returns a UIImage of all of the visible cells on screen baked into it. */
- (UIImage *)snapshotOfCellsInRect:(CGRect)rect
{
    UIImage *image = nil;
    
    /* 
     Testing rendering the context, locked to non-Retina. Even if the iPad 3 only has to render one Retina bitmap,
     there's still a lot of noticable latency. And when the view is rotating, you can't even really see the Retina graphics.
     */
    UIGraphicsBeginImageContextWithOptions( rect.size, NO, _nonRetinaRenderContexts ? 1.0f : 0.0f );
    {
        CGContextRef context = UIGraphicsGetCurrentContext();
        
        for( TOGridViewCell *cell in _visibleCells )
        {
            //Save/Restore the graphics states to reset the global translation for each cell
            CGContextSaveGState(context);
            {
                //As 'renderInContext' uses the calling CALayer's local co-ord space,
                //the cells need to be positioned in the canvas using Quartz's matrix translations.
                CGContextTranslateCTM( context, cell.frame.origin.x, (cell.frame.origin.y-CGRectGetMinY(rect)) );
                [cell.layer renderInContext: context];
            }
            CGContextRestoreGState(context);
        }
        
        image = UIGraphicsGetImageFromCurrentImageContext();
    }
    UIGraphicsEndImageContext();
    
    return image;
}

#pragma mark -
#pragma mark Cell/Decoration Handling

/* Dequeue a recycled cell for reuse */
- (TOGridViewCell *)dequeReusableCell
{
    TOGridViewCell *cell = [_recycledCells anyObject];
    
    if( cell )
    {
        [_recycledCells removeObject: cell];
        return cell;
    }
    
    cell = [[_cellClass alloc] initWithFrame: CGRectMake(0, 0, _cellSize.width, _cellSize.height)];
    cell.frame = CGRectMake(0, 0, _cellSize.width, _cellSize.height);
    cell.gridView = self;
    [cell setHighlighted: NO animated: NO];
    
    return cell;
}

- (UIView *)dequeueReusableDecorationView
{
    return nil;
}

#pragma mark -
#pragma mark Cell Edit Handling
- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    _isEditing = editing;
    
    
}

- (BOOL)insertCellAtIndex: (NSInteger)index animated: (BOOL)animated
{
    return YES;
}

- (BOOL)insertCellsAtIndicies: (NSArray *)indices animated: (BOOL)animated
{
    return YES;
}

- (BOOL)deleteCellAtIndex: (NSInteger)index animated: (BOOL)animated
{
    return YES;
}

- (BOOL)deleteCellsAtIndicies: (NSArray *)indices animated: (BOOL)animated
{
    return YES;
}

- (void)unhighlightCellAtIndex: (NSInteger)index animated: (BOOL)animated
{
    if( _highlightedCellIndex != index )
        return;
    
    TOGridViewCell *cell = [self cellForIndex: index];
    if( cell )
        [cell setHighlighted: NO animated: animated];
    
    _highlightedCellIndex = -1;
}

#pragma mark -
#pragma mark Accessors
- (void)setDelegate:(id<TOGridViewDelegate>)delegate
{
    if( self.delegate == delegate )
        return;
    
    [super setDelegate: delegate];
    
    _gridViewFlags.delegateDecorationView       = [self.delegate respondsToSelector: @selector(gridView:decorationViewForRowWithIndex:)];
    _gridViewFlags.delegateInnerPadding         = [self.delegate respondsToSelector: @selector(innerPaddingForGridView:)];
    _gridViewFlags.delegateNumberOfCellsPerRow  = [self.delegate respondsToSelector: @selector(numberOfCellsPerRowForGridView:)];
    _gridViewFlags.delegateSizeOfCells          = [self.delegate respondsToSelector: @selector(sizeOfCellsForGridView:)];
    _gridViewFlags.delegateHeightOfRows         = [self.delegate respondsToSelector: @selector(heightOfRowsInGridView:)];
    _gridViewFlags.delegateDidLongTapCell       = [self.delegate respondsToSelector: @selector(gridView:didLongTapCellAtIndex:)];
    _gridViewFlags.delegateDidTapCell           = [self.delegate respondsToSelector: @selector(gridView:didTapCellAtIndex:)];
}

- (void)setDataSource:(id<TOGridViewDataSource>)dataSource
{
    if( _dataSource == dataSource )
        return;
    
    _dataSource = dataSource;
    
    _gridViewFlags.dataSourceCellForIndex       = [_dataSource respondsToSelector: @selector( gridView:cellForIndex:)];
    _gridViewFlags.dataSourceNumberOfCells      = [_dataSource respondsToSelector: @selector(numberOfCellsInGridView:)];
}

- (void)setHeaderView:(UIView *)headerView
{
    if( _headerView == headerView )
        return;
    
    [_headerView removeFromSuperview];
    _headerView = headerView;
    _headerView.frame = CGRectMake( 0, 0, CGRectGetWidth(_headerView.frame), CGRectGetHeight(_headerView.frame));
    _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    _offsetFromHeader = CGRectGetHeight(headerView.bounds);
    
    [self addSubview: _headerView];
    
    self.contentSize = [self contentSizeOfScrollView];
    [self invalidateVisibleCells];
    [self layoutCells];
}

- (void)setBackgroundView:(UIView *)backgroundView
{
    if( _backgroundView == backgroundView )
        return;
    [_backgroundView removeFromSuperview];
    _backgroundView = backgroundView;
    
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _backgroundView.frame = self.bounds;
    
    [self insertSubview: _backgroundView atIndex: 0];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame: frame];

    /* If the frame changes, and we're NOT animating, invalidate all of the visible cells and reload the view */
    /* If we ARE animating (eg, orientation change), this will be handled in layoutSubviews. */
    if( [self.layer animationForKey: @"bounds"] == nil )
    {
        [self invalidateVisibleCells];
        [self resetCellMetrics];
    }
    
}



@end
