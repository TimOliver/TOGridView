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

#define LONG_PRESS_TIME 0.4f

@interface TOGridView (hidden)

- (void)resetCellMetrics;
- (void)layoutCells;
- (CGSize)contentSizeOfScrollView;
- (TOGridViewCell *)cellForIndex: (NSInteger)index;
- (UIImage *)snapshotOfCellsInRect: (CGRect)rect;
- (void)invalidateVisibleCells;
- (void)didPan: (UIPanGestureRecognizer *)gestureRecognizer;
- (void)fireDragTimer: (id)timer;
- (TOGridViewCell *)cellInTouch: (UITouch *)touch;
- (void)fireLongPressTimer: (NSTimer *)timer;
- (NSInteger)indexOfCellAtPoint: (CGPoint)point;
- (void)updateCellsLayoutWithDraggedCellAtPoint: (CGPoint)dragPanPoint;
- (void)cancelDraggingCell;

@end

@implementation TOGridView

@synthesize dataSource                  = _dataSource,
            headerView                  = _headerView,
            backgroundView              = _backgroundView,
            editing                     = _isEditing,
            nonRetinaRenderContexts     = _nonRetinaRenderContexts,
            dragScrollBoundaryDistance  = _dragScrollBoundaryDistance,
            dragScrollMaxVelocity       = _dragScrollMaxVelocity;

#pragma mark -
#pragma mark View Management
- (id)initWithFrame:(CGRect)frame
{
    if( self = [super initWithFrame: frame] )
    {
        // Default configuration for the UIScrollView
        self.bounces                = YES;
        self.scrollsToTop           = YES;
        self.backgroundColor        = [UIColor blackColor];
        self.scrollEnabled          = YES;
        self.alwaysBounceVertical   = YES;
        
        // Disable the ability to tap multiple cells at the same time. (Otherwise it gets REALLY messy)
        self.multipleTouchEnabled   = NO;
        self.exclusiveTouch         = YES;
        
        // The sets to handle the recycling and repurposing/reuse of cells
        _recycledCells              = [NSMutableSet new];
        _visibleCells               = [NSMutableSet new];
        
        // The default class used to instantiate new cells
        _cellClass                  = [TOGridViewCell class];
        
        // Default settings for when dragging cells near the boundaries of the grid view
        _dragScrollBoundaryDistance = 60;
        _dragScrollMaxVelocity      = 15;
        
        _longPressIndex             = -1;
        _cellIndexBeingDraggedOver  = -1;
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
    for( NSInteger i = 0; i < _numberOfCells; i++ )
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
    CGPoint origin = CGPointZero;
    
    origin.y    = _offsetFromHeader;                    /* The height of the header view */
    origin.y    += _offsetOfCellsInRow;                 /* Relative offset of the cell in each row */
    origin.y    += _cellPaddingInset.height;            /* The inset padding arond the cells in the scrollview */
    origin.y    += (_rowHeight * floor(cellIndex/_numberOfCellsPerRow));
    
    origin.x =  _cellPaddingInset.width;
    origin.x    += ((cellIndex % _numberOfCellsPerRow) * (_cellSize.width+_widthBetweenCells));
    
    return origin;
}

- (CGSize)sizeOfCellAtIndex: (NSInteger)cellIndex
{
    CGSize cellSize = _cellSize;
    
    //if there's supposed to be NO padding between the edge of the view and the cell,
    //and this cell is short by uneven necessity of the number of cells per row
    //(eg, 1024/3 on iPad = 341.333333333 pixels per cell :S), pad it out
    if( _cellPaddingInset.width <= 0.0f + FLT_EPSILON && (cellIndex+1) % _numberOfCellsPerRow == 0 )
    {        
        CGPoint org = [self originOfCellAtIndex: cellIndex];
        if( org.x + cellSize.width < CGRectGetWidth(self.bounds) + FLT_EPSILON )
            cellSize.width = CGRectGetWidth(self.bounds) - org.x;
    }
    
    return cellSize;
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

//Work out which cells this point of space will technically belong to
- (NSInteger)indexOfCellAtPoint: (CGPoint)point
{
    //work out which row we're on
    NSInteger rowIndex = floor((point.y - (_offsetFromHeader + _cellPaddingInset.height)) / _rowHeight) * _numberOfCellsPerRow;
    
    //work out which number on the row we are
    NSInteger columnIndex = floor((point.x + _cellPaddingInset.width) / CGRectGetWidth(self.bounds) * _numberOfCellsPerRow);
    
    NSInteger index = rowIndex + columnIndex;
    index = MAX( -1, index); //if the number of cells is below the start, return -1
    index = MIN(_numberOfCells-1, index); //cap it at the max number of cells
    
    //return the cell index
    return index;
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

- (NSRange)visibleCells
{
    NSRange visibleCellRange;
    
    //The official origin of the first row, accounting for the header size and outer padding
    NSInteger   rowOrigin           = _offsetFromHeader + _cellPaddingInset.height;
    CGFloat     contentOffsetY      = self.bounds.origin.y; //bounds.origin on a scrollview contains the best up-to-date contentOffset
    NSInteger   numberOfRows        = floor(_numberOfCells / _numberOfCellsPerRow);
    
    NSInteger   firstVisibleRow     = floor((contentOffsetY-rowOrigin) / _rowHeight);
    NSInteger   lastVisibleRow      = floor(((contentOffsetY-rowOrigin)+CGRectGetHeight(self.bounds))/ _rowHeight);
    
    //make sure there are actually some visible rows
    if( lastVisibleRow >= 0 && firstVisibleRow <= numberOfRows )
    {
        visibleCellRange.location  = MAX(0,firstVisibleRow) * _numberOfCellsPerRow;
        visibleCellRange.length    = (((lastVisibleRow - MAX(0,firstVisibleRow))+1) * _numberOfCellsPerRow);
        
        if( visibleCellRange.location + visibleCellRange.length >= _numberOfCells )
            visibleCellRange.length = _numberOfCells - visibleCellRange.location;
    }
    else
    {
        visibleCellRange.location = -1;
        visibleCellRange.length = 0;
    }
    
    return visibleCellRange;
}

/* layoutCells handles all of the recycling/dequeing of cells as the scrollview is scrolling */
- (void)layoutCells
{
    if( _numberOfCells == 0 || _pauseCellLayout )
        return;
    
    _visibleCellRange = [self visibleCells];
    
    for( TOGridViewCell *cell in _visibleCells )
    {
        if( cell == _cellBeingDragged )
            continue;
        
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
        if( cell || _cellIndexBeingDraggedOver == index ) //if we already have a cell, or the user is currently dragging over a space for a cell
            continue;
        
        //Get the cell with its content setup from the dataSource
        cell = [_dataSource gridView: self cellForIndex: index];
        cell.gridView = self;
        cell.index = index;
        
        [cell setHighlighted: NO animated: NO];
        
        //if the cell has been selected, highlight it
        if( _isEditing && [[_selectedCells objectAtIndex: cell.index] boolValue] == YES )
            [cell setSelected: YES animated: NO];
        
        //make sure the frame is still properly set
        CGRect cellFrame;
        cellFrame.origin = [self originOfCellAtIndex: index];
        cellFrame.size = [self sizeOfCellAtIndex: index];
        cell.frame = cellFrame;
        
        //add it to the visible objects set (It's already out of the recycled set at this point)
        [_visibleCells addObject: cell];
        
        //Make sure the cell is inserted ABOVE any visible background view, but still BELOW the scroll indicator bar graphic.
        //(ie, we can't simply call 'addSubiew')
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
     -The first-gen iPad has a slow GPU (meaning lots of blending runs chuggy), but can bake entire views to UIImage REALLY fast (presumably because the views are non-Retina)
     -The third-gen iPad has a kickass GPU (meaning tonnes of blending is easy), but its CPU (While faster than the iPad 1), has to cope with rendering retina UIImages. When rendering 2 Retina images, the latency is impressively slow
     
     In order to get optimal render time+animation on both platforms, the following is happening:
     - On non-Retina devices, the before and after bitmaps are rendered and the cells are hidden throughout the animation (Only 1 alpha blend is happening, so iPad 1 is happy)
     - On Retina devices, only the first bitmap is rendered, which is then cross-faded with the live cells (The iPad 3 can handle manually blending multiple cells, but iPad 1 cannot without a serious FPS hit)
    */
    BOOL isRetinaDevice = [[UIScreen mainScreen] scale] > 1.0f;
    
    /* Apply the crossfade effect if this method is being called while there is a pending 'bounds' animation present. */
    /* Capture the 'before' state to UIImageView before we reposition all of the cells */
    CABasicAnimation *boundsAnimation = (CABasicAnimation *)[self.layer animationForKey: @"bounds"];
    if( boundsAnimation && _pauseCrossFadeAnimation == NO )
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
    if( boundsAnimation && _pauseCrossFadeAnimation == NO )
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
            //disable EVERY ANIMATION that may have been applied to each cell and its subviews in the interim.
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
                //Apply a CABasicAnimation to each cell to animate its opacity
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
     This delegate actually gets called about 3 times per animation. So only proceed when it's definitely finished up.
     I'm HOPING there's no way the system can terminate an animation mid-way and then not call the finished flag here. That would suck.
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
     Depending on the number of cells visible at any given point, a noticable speed boost can be given to Retina
     devices if the images are rendered at non-Retina resolutions (Given how fast these things rotate, it's BARELY noticable)
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

- (void)updateCellsLayoutWithDraggedCellAtPoint: (CGPoint)dragPanPoint
{
    NSInteger currentlyDraggedOverIndex = [self indexOfCellAtPoint: dragPanPoint];
    if( currentlyDraggedOverIndex == _cellIndexBeingDraggedOver || currentlyDraggedOverIndex == -1 )
        return;
    
    //The direction and number of stops we just moved the cell (eg cell 0 to cell 2 is '2')
    NSInteger offset = -(_cellIndexBeingDraggedOver - currentlyDraggedOverIndex);
    
    for( TOGridViewCell *cell in _visibleCells )
    {
        if( cell == _cellBeingDragged )
            continue;
        
        //If the offset is positive, we dragged the cell forward
        BOOL found = NO;
        if( offset > 0 )
        {
            if( cell.index <= _cellIndexBeingDraggedOver+offset && cell.index > _cellIndexBeingDraggedOver )
            {
                cell.index--;
                found = YES;
            }
        }
        else
        {
            if( cell.index >= _cellIndexBeingDraggedOver+offset && cell.index < _cellIndexBeingDraggedOver)
            {
                cell.index++;
                found = YES;
            }
        }
        
        //Ignore cells that don't need to animate
        if( found == NO )
            continue;
        
        //figure out the number of cells between the one being dragged and this one
        NSInteger delta = abs(cell.index - _cellIndexBeingDraggedOver);
        
        //animate it with a slight delay depending on how far away it was from the origin, so it looks a little more fluid 
        [UIView animateWithDuration: 0.25f delay: 0.05f*delta options: UIViewAnimationOptionCurveEaseInOut animations: ^{
            CGRect frame = cell.frame;
            CGFloat y = frame.origin.y;
            
            frame.origin = [self originOfCellAtIndex: cell.index];
            
            //if a cell is shifting lines, make sure it renders ABOVE any other cells
            if( (NSInteger)y != (NSInteger)frame.origin.y )
                [self insertSubview: cell belowSubview: _cellBeingDragged];
            
            //if the grid view is having to do a small amount of cell padding (eg, if the width of each cell doesn't fit the screen properly)
            //reset the cell here
            frame.size = [self sizeOfCellAtIndex: cell.index];
            cell.frame = frame;
            
        } completion: nil];
    }
    
    _cellIndexBeingDraggedOver = currentlyDraggedOverIndex;
}

#pragma mark -
#pragma mark Cell/Decoration Recycling

/* Dequeue a recycled cell for reuse */
- (TOGridViewCell *)dequeReusableCell
{
    //Grab a cell that was previously recycled
    TOGridViewCell *cell = [_recycledCells anyObject];
    if( cell )
    {
        [_recycledCells removeObject: cell];
        return cell;
    }
    
    //If there are no cells available, create a new one and set it up
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
- (BOOL)insertCellAtIndex: (NSInteger)index animated: (BOOL)animated
{
    return [self insertCellsAtIndices: [NSArray arrayWithObject: [NSNumber numberWithInt:index]] animated: animated];
}

- (BOOL)insertCellsAtIndices: (NSArray *)indices animated: (BOOL)animated
{
    //Make sure that the dataSource has already updated the number of cells, or this will cause utter chaos.
    NSInteger newNumberOfCells = [_dataSource numberOfCellsInGridView: self];
    if( newNumberOfCells < _numberOfCells + [indices count] )
        [NSException raise: @"Invalid dataSource!" format: @"Data source needs to be updated before new cells can be inserted. Number of cells was %d when it needed to be %d", _numberOfCells, newNumberOfCells ];
    
    //make the new number of cells formal now since we'll need it in a bunch of calculations below
    _numberOfCells = newNumberOfCells;
    
    //increment each visible cell to the next index as necessary
    for( TOGridViewCell *cell in _visibleCells )
    {
        NSInteger cellIncrement = 0;
        for( NSNumber *number in indices )
        {
            if( cell.index >= [number integerValue])
                cellIncrement++;
        }
        
        cell.index = cell.index + cellIncrement;
    }
    
    // reposition all of the cells to their new indices
    for( TOGridViewCell *cell in _visibleCells )
    {
        __block CGRect frame = cell.frame;
        frame.size = [self sizeOfCellAtIndex: cell.index];
        
        //animate all of the existing cells into place
        if( animated )
        {
            [UIView animateWithDuration: 0.2f animations: ^{
                frame.origin = [self originOfCellAtIndex: cell.index];
                
                //if we're sliding down a row, bring this cell to the front so it displays over the others
                if( (NSInteger)frame.origin.y != (NSInteger)cell.frame.origin.y )
                    [self bringSubviewToFront: cell];
                
                cell.frame = frame;
            }];
        }
        else
        {
            frame.origin = [self originOfCellAtIndex: cell.index];
            cell.frame = frame;
        }
    }
    
    //go through each new cell, and set it up
    NSRange visibleCells = [self visibleCells];
    for( NSNumber *number in indices )
    {
        NSInteger newIndex = [number integerValue];
        
        //set up the master array of selected cells to account for these new cells
        [_selectedCells insertObject: [NSNumber numberWithBool: NO] atIndex: newIndex];
        
        //if the cell is within the visible screen region, dequeue a new cell and make it display
        if( newIndex >= visibleCells.location && newIndex < visibleCells.location+visibleCells.length)
        {
            //if it is, poll the data source to create it and then add it in
            TOGridViewCell *newCell = [_dataSource gridView: self cellForIndex: newIndex];
            CGRect frame = newCell.frame;
            frame.origin = [self originOfCellAtIndex: newIndex];
            frame.size = [self sizeOfCellAtIndex: newIndex];
            newCell.frame = frame;
            newCell.index = newIndex;
            [_visibleCells addObject: newCell];

            //if there's a background view, add it above that,
            //if not add it at the VERY back.
            //otherwise, it will appear above the scrollbar if it's visible.
            if( _backgroundView )
                [self insertSubview: newCell aboveSubview: _backgroundView];
            else
                [self insertSubview: newCell atIndex: 0];
            
            //fade it in
            if( animated )
            {
                newCell.alpha = 0.0f;
                newCell.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.5f, 0.5f);
                [UIView animateWithDuration: 0.25f delay: 0.0f options: UIViewAnimationOptionCurveEaseOut animations: ^{
                    newCell.alpha = 1.0f;
                    newCell.transform = CGAffineTransformIdentity;
                } completion: nil];
            }
        }
    }
    
    //reset the size of the content view to account for the new cells
    self.contentSize = [self contentSizeOfScrollView];
    
    return YES;
}

- (BOOL)deleteCellAtIndex: (NSInteger)index animated: (BOOL)animated
{
    return [self deleteCellsAtIndices: [NSArray arrayWithObject: [NSNumber numberWithInt:index]] animated: animated];
}

- (BOOL)deleteCellsAtIndices: (NSArray *)indices animated: (BOOL)animated
{
    if( [indices count] == 0)
        return YES;
 
    //cancel the cell dragging if it's active
    if( _isEditing )
        [self cancelDraggingCell];
    
    //Hang onto the lowest cell necessary to animate all visible cells
    //This can either be the very lowest cell targeted for deletion, or simply the first visible cell on screen
    __block NSInteger firstCellToAnimate = _numberOfCells;
    //Hang onto the final cell that will be animated after the offset is applied
    __block NSInteger lastVisibleCell = 0;
    
    //Make sure that the dataSource has already updated the number of cells, otherwise all our calculations below will break
    NSInteger newNumberOfCells = [_dataSource numberOfCellsInGridView: self];
    if( newNumberOfCells > _numberOfCells - [indices count] )
        [NSException raise: @"Invalid dataSource!" format: @"Data source needs to be updated before cells can be deleted. Number of cells was %d when it needed to be %d", _numberOfCells, newNumberOfCells ];
    
    //make the new number of cells formal now since we'll need it in a bunch of calculations below
    _numberOfCells = newNumberOfCells;
    
    //go through each cell and work out which cells-to-delete are visible.
    NSMutableArray *visibleCellsToDelete = [NSMutableArray array];
    NSMutableArray *selectedCellsToDelete = [NSMutableArray array];
    for( NSNumber *number in indices )
    {
        NSInteger deleteIndex = [number integerValue];

        //remember the selected cell indices we need to delete
        [selectedCellsToDelete addObject: [_selectedCells objectAtIndex: deleteIndex]];
        
        //if the cell is within the visible screen region, prep it for animation
        if( deleteIndex >= _visibleCellRange.location && deleteIndex <= _visibleCellRange.location + _visibleCellRange.length)
        {
            TOGridViewCell *cell = [self cellForIndex: deleteIndex];
            if( cell == nil )
                continue;
            
            //reset its animation properties, just in case
            cell.alpha = 1.0f;
            cell.transform = CGAffineTransformIdentity;
            
            [visibleCellsToDelete addObject: cell];
        }
        
        if( deleteIndex <= firstCellToAnimate )
            firstCellToAnimate = deleteIndex;
    }

    //remove the objects from the selectedCells
    [_selectedCells removeObjectsInArray: selectedCellsToDelete];
    
    //work out what the new index for each visible cell will be after the targeted cells have been deleted
    for( TOGridViewCell *cell in _visibleCells )
    {
        NSInteger offset = 0;
        for( NSNumber *number in indices )
        {
            if( cell.index >= [number integerValue] )
                offset++;
        }
        
        //Check to see if this cell is after the lowest cell in the deletion stack
        BOOL shouldAnimateFromFirstVisibleCell = (cell.index == _visibleCellRange.location) && cell.index > firstCellToAnimate;
        
        //Set the new index for this cell after the targeted cells are removed around it.
        //cap it off at 0 (If it's negative, it's definitely going to get deleted) to prevent any strange wrapping 
        cell.index = MAX(0,cell.index - offset);
        
        if( shouldAnimateFromFirstVisibleCell )
            firstCellToAnimate = cell.index;
        
        //hang onto the final cell to use as the origin if we need to requeue any cells to animate in
        if( cell.index > lastVisibleCell )
            lastVisibleCell = cell.index;
    }
    
    //fade out all the cells
    if( animated )
    {
        //disable scrolling to allow this animation to complete
        [self setUserInteractionEnabled: NO];
        
        //halt animation
        CGPoint scrollPoint = self.contentOffset;
        [self setContentOffset: scrollPoint animated: NO];

        //stop 'layoutCells' from interacting with this (Since 'layoutSubviews' gets triggered by iOS everytime we add/remove a cell)
        _pauseCellLayout = YES;
        
        //Animate each of the selected cells to fade out
        [UIView animateWithDuration: 0.25f delay: 0.0f options: UIViewAnimationOptionCurveEaseInOut animations: ^{
            for ( TOGridViewCell *cell in visibleCellsToDelete )
            {
                cell.alpha = 0.0f;
                cell.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.5f, 0.5f);
            }
        } completion: ^(BOOL done) {
            //once done, recycle each cell that was animated out and add it back to the pool
            for ( TOGridViewCell *cell in visibleCellsToDelete )
            {
                //once animated out, recycle the cells
                [cell removeFromSuperview];
                
                //reset the cell
                cell.transform = CGAffineTransformIdentity;
                cell.alpha = 1.0f;
                [cell setSelected: NO animated: NO];
                
                //recycle the cell
                [_visibleCells removeObject: cell];
                [_recycledCells addObject: cell];
            }
            
            //Now that the cells are out of the hierarchy, re-calculate which cells should be visible on screen now
            NSRange newVisibleCells = [self visibleCells];
            //The next cell index below the old to use as the origin basis for all the new cells we create down there
            //NSInteger originCell = (ceil((self.contentOffset.y+CGRectGetHeight(self.bounds)) / _rowHeight) + 1)*_numberOfCellsPerRow;
            NSInteger originCell = (newVisibleCells.location+newVisibleCells.length);
            
            //Go through and create each new cell, with their new IDs but leave them in their previous position
            for( NSInteger i=0; i < newVisibleCells.length; i++ )
            {
                TOGridViewCell *newCell = [self cellForIndex: newVisibleCells.location+i];
                if( newCell )
                    continue;
                
                newCell = [_dataSource gridView: self cellForIndex: newVisibleCells.location+i];
                newCell.index = newVisibleCells.location+i;
                CGRect frame = newCell.frame;
                frame.origin = [self originOfCellAtIndex: originCell++];
                frame.size = [self sizeOfCellAtIndex: newVisibleCells.location+i];
                newCell.frame = frame;
                [_visibleCells addObject: newCell];
                
                [self addSubview: newCell];
            }
            
            //find the FINAL cell index so we can clean up after all of the animations
            NSInteger finalCellIndex = 0;
            for( TOGridViewCell *cell in _visibleCells )
            {
                if( cell.index > finalCellIndex )
                    finalCellIndex = cell.index;
            }
            
            //sort the visible cells into their respective order so we can sort it in the right order
            NSArray *sortedVisibleCells = [_visibleCells sortedArrayUsingDescriptors: [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"index" ascending: YES]]];
            
            //reset the size of all of the remaining cells before they move
            NSInteger i = 0;
            for( TOGridViewCell *cell in sortedVisibleCells )
            {                
                CGRect frame = cell.frame;
                frame.size = [self sizeOfCellAtIndex: cell.index];
                cell.frame = frame;
  
                [cell setSelected: NO animated: NO];
                
                CGPoint newOrigin = [self originOfCellAtIndex: cell.index];
                if( (NSInteger)cell.frame.origin.y != (NSInteger)newOrigin.y )
                    [self bringSubviewToFront: cell];

                [UIView animateWithDuration: 0.25f delay: (i++)*0.05f options: UIViewAnimationOptionCurveEaseInOut animations: ^{
                    CGRect frame = cell.frame;
                    frame.origin = newOrigin;
                    
                    //cap how far it can move up so it doesn't just shoot off
                    if( CGRectGetMaxY(cell.frame) - (newOrigin.y+CGRectGetHeight(self.bounds)) > CGRectGetHeight(self.bounds) )
                        frame.origin.y = CGRectGetMinY(cell.frame) - (CGRectGetHeight(self.bounds)+CGRectGetHeight(cell.frame));
                    
                    cell.frame = frame;
                } completion: ^(BOOL finished) {
                    if( cell.index != finalCellIndex )
                        return;
                    
                    //re-enable 'layoutCells'
                    _pauseCellLayout = NO;
                    
                    //reset all of the cells
                    [self layoutCells];
                    
                    //clean out the excess recycled cells
                    NSInteger maxNumberOfCellsInScreen = ceil(CGRectGetHeight(self.bounds) / _rowHeight) * _numberOfCellsPerRow;
                    NSInteger numberOfCells = [_recycledCells count] + [_visibleCells count];
                    if( numberOfCells > maxNumberOfCellsInScreen && [_visibleCells count] <= maxNumberOfCellsInScreen )
                    {
                        while( numberOfCells > maxNumberOfCellsInScreen )
                        {
                            TOGridViewCell *cell = [_recycledCells anyObject];
                            if( cell == nil )
                                continue;
                            
                            [_recycledCells removeObject: cell];
                            cell = nil;
                            
                            numberOfCells--;
                            
                            if( [_recycledCells count] == 0 )
                                break;
                        }
                    }
                    
                    //reenable user interaction
                    [self setUserInteractionEnabled: YES];
                
                    _pauseCrossFadeAnimation = YES;
                    [UIView animateWithDuration: 0.30f animations: ^{
                        self.contentSize = [self contentSizeOfScrollView];
                    } completion: ^(BOOL finished){
                        _pauseCrossFadeAnimation = NO;
                    }];
                    
                }];
            }
        }];
    }
    else
    {
        for ( TOGridViewCell *cell in visibleCellsToDelete )
        {
            [cell removeFromSuperview];
            [_visibleCells removeObject: cell];
            [_recycledCells addObject: cell];
        }
    
        //reset the size of the content view to account for the new cells
        self.contentSize = [self contentSizeOfScrollView];
    }
    
    return YES;
}

- (BOOL)reloadCellAtIndex: (NSInteger)index
{
    return [self reloadCellsAtIndices: [NSArray arrayWithObject: [NSNumber numberWithInteger:index]]];
}

- (BOOL)reloadCellsAtIndices: (NSArray *)indices
{
    if( [indices count] == 0 )
        return YES;
    
    for( NSNumber *index in indices )
    {
        NSInteger cellIndex = [index integerValue];
        
        //if the cell isn't visisble, skip it
        TOGridViewCell *cell = [self cellForIndex: cellIndex];
        if( cell == nil )
            continue;
        
        CGRect frame = cell.frame;
        [cell removeFromSuperview];
        [_visibleCells removeObject: cell];
        [_recycledCells addObject: cell];
        cell = nil;
        
        cell = [_dataSource gridView: self cellForIndex: cellIndex];
        cell.index = cellIndex;
        cell.frame = frame;
        
        if( _backgroundView )
            [self insertSubview: cell aboveSubview: _backgroundView];
        else
            [self insertSubview: cell atIndex: 0];
    }
    
    return YES;
}

/* This is called manually by the delegate object */
- (void)unhighlightCellAtIndex: (NSInteger)index animated: (BOOL)animated
{
    TOGridViewCell *cell = [self cellForIndex: index];
    if( cell )
        [cell setHighlighted: NO animated: animated];
}

/* Called every 1/60th of a second to animate the scroll view */
- (void)fireDragTimer:(id)timer
{
    CGPoint offset = self.contentOffset;
    offset.y += _dragScrollBias; //Add the calculated scroll bias to the current scroll offset
    offset.y = MAX( 0, offset.y ); //Clamp the value so we can't accidentally scroll past the end of the content
    offset.y = MIN( self.contentSize.height - CGRectGetHeight(self.bounds), offset.y );
    self.contentOffset = offset;
    
    CGPoint adjustedDragPoint = _cellDragPoint;
    adjustedDragPoint.y += self.contentOffset.y;
    [self updateCellsLayoutWithDraggedCellAtPoint: adjustedDragPoint];
    
    /* If we're dragging a cell, update its position inside the scrollView to stick to the user's finger. */
    /* We can't move the cell outside of this view since that kills the touch events. :( */
    /* We also can't simply add the bias like we did above since it introduces floating point noise (and the cell starts to move on its own on screen :( ) */
    if( _cellBeingDragged )
    {
        CGPoint center = _cellBeingDragged.center;
        center.y = _cellDragPoint.y + self.contentOffset.y;
        _cellBeingDragged.center = center;
    }
}

- (NSArray *)indicesOfSelectedCells
{
    NSMutableArray *selectedCells = [NSMutableArray array];
    
    for( NSInteger i = 0; i < [_selectedCells count]; i++ )
    {
        if( [[_selectedCells objectAtIndex: i] boolValue] )
            [selectedCells addObject: [NSNumber numberWithInt: i]];
    }
    
    return [NSArray arrayWithArray: selectedCells];
}

#pragma mark -
#pragma mark Cell Interactions Handler
- (TOGridViewCell *)cellInTouch:(UITouch *)touch
{
    //start off with the view we directly hit with the UITouch
    UIView *view = [touch view];
    
    //traverse hierarchy to see if we hit inside a cell
    TOGridViewCell *cell = nil;
    do
    {
        if( [view isKindOfClass: [TOGridViewCell class]] )
        {
            cell = (TOGridViewCell *)view;
            break;
        }
    }
    while( (view = view.superview) != nil );
    
    return cell;
}

/* touchesBagan is initially called when we first touch this view on the screen. There is no delay. */
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    //reset the long press counter
    _longPressIndex = -1;
    
    UITouch *touch = [touches anyObject];
    TOGridViewCell *cell = [self cellInTouch: touch];
    if( cell )
    {
        [cell setHighlighted: YES animated: NO];
        
        //if we're set up to receive a long-press tap event, fire the timer now
        if( (_isEditing == NO && _gridViewFlags.delegateDidLongTapCell) || (_isEditing && _gridViewFlags.dataSourceCanMoveCell) )
            _longPressTimer = [NSTimer scheduledTimerWithTimeInterval: LONG_PRESS_TIME target: self selector: @selector(fireLongPressTimer:) userInfo: touch repeats: NO];
    }
    
    [super touchesBegan: touches withEvent: event];
}

- (void)fireLongPressTimer:(NSTimer *)timer
{
    UITouch *touch = [timer userInfo];
    TOGridViewCell *cell = (TOGridViewCell *)[self cellInTouch: touch];
    
    if( _isEditing == NO )
    {
        [self.delegate gridView: self didLongTapCellAtIndex: cell.index];
        
        //let 'touchesEnded' know we already performed the event for this one
        _longPressIndex = cell.index;
    }
    else
    {
        BOOL canMove = [self.dataSource gridView: self canMoveCellAtIndex: cell.index];
        if( canMove == NO )
            return;
        
        // Hang onto the cell
        _cellBeingDragged = cell;
        _cellIndexBeingDraggedOver = cell.index;
        
        //make the cell animate out slightly
        [cell setDragging: YES animated: YES];
        
        CGPoint pointInCell = [touch locationInView: cell];
        
        //set the anchor point
        cell.layer.anchorPoint = CGPointMake( pointInCell.x/CGRectGetWidth(cell.bounds), pointInCell.y/CGRectGetHeight(cell.bounds));
        cell.center = [touch locationInView: self];
        
        //disable the scrollView
        [self setScrollEnabled: NO];
    }
}

/* touchesMoved is called when we start panning around the view without releasing our finger */
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint panPoint = [touch locationInView: self];
    
    if( _isEditing && _cellBeingDragged )
    {
        _cellBeingDragged.center = CGPointMake(panPoint.x + _draggedCellOffset.width, panPoint.y + _draggedCellOffset.height);
        
        /* Update the cells behind the one being dragged with new positions */
        [self updateCellsLayoutWithDraggedCellAtPoint: panPoint];
        
        panPoint.y -= self.bounds.origin.y; //compensate for scroll offset
        panPoint.y = MAX( panPoint.y, 0 ); panPoint.y = MIN( panPoint.y, CGRectGetHeight(self.bounds) ); //clamp to the outer bounds of the view
        
        //Save a copy of the translated point for the drag animation below
        _cellDragPoint = panPoint;
        
        //Determine if the touch location is within the scroll boundaries at either the top or bottom
        if( (panPoint.y < _dragScrollBoundaryDistance && self.contentOffset.y > 0.0f) ||
            (panPoint.y > CGRectGetHeight(self.bounds) - _dragScrollBoundaryDistance && (self.contentOffset.y < self.contentSize.height - CGRectGetHeight(self.bounds))) )
        {
            //Kickstart a timer that'll fire at 60FPS to dynamically animate the scrollview
            if( _dragScrollTimer == nil )
                _dragScrollTimer = [NSTimer scheduledTimerWithTimeInterval: 1.0f/60.0f target: self selector: @selector(fireDragTimer:) userInfo: nil repeats: YES];
            
            //If we're scrolling at the top
            if( panPoint.y < _dragScrollBoundaryDistance )
                _dragScrollBias = -(_dragScrollMaxVelocity - ((_dragScrollMaxVelocity/_dragScrollBoundaryDistance) * panPoint.y));
            else if ( panPoint.y > CGRectGetHeight(self.bounds) - _dragScrollBoundaryDistance ) //we're scrolling at the bottom
                _dragScrollBias = ((panPoint.y - (CGRectGetHeight(self.bounds) - _dragScrollBoundaryDistance)) / _dragScrollBoundaryDistance) * _dragScrollMaxVelocity;
        }
        
        //cancel the scrolling if we tap up, or move our fingers into the middle of the screen
        if( ( panPoint.y>_dragScrollBoundaryDistance && panPoint.y<CGRectGetHeight(self.bounds)-_dragScrollBoundaryDistance ) )
        {
            [_dragScrollTimer invalidate];
            _dragScrollTimer = nil;
        }
    }
        
    [super touchesMoved: touches withEvent: event];
}

/* touchesEnded is called if the user releases their finger from the device without panning the scroll view (eg a discrete tap and release) */
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    
    //The cell under our finger
    TOGridViewCell *cell = [self cellInTouch: touch];
    
    //if we were animating the scroll view at the time, cancel it
    [_dragScrollTimer invalidate];
    
    //if we WEREN'T in edit mode, fire the delegate to say we tapped this cell (But make sure this cell didn't already fire a long press event)
    if( _isEditing == NO )
    {
        if( cell && _gridViewFlags.delegateDidTapCell && cell.index != _longPressIndex )
            [self.delegate gridView: self didTapCellAtIndex: cell.index];
    }
    else //if we WERE editing
    {
        //if there's no cell being dragged (ie, we just tapped a cell), set it to 'selected'
        if( _cellBeingDragged == nil )
        {
            NSNumber *selectedNumber = [_selectedCells objectAtIndex: cell.index];
            
            //unhighlight it
            [cell setHighlighted: NO animated: NO];
            
            //set it to be either selected or unselected
            if( [selectedNumber boolValue] == NO )
                [cell setSelected: YES animated: NO];
            else
                [cell setSelected: NO animated: NO];
            
            //Since NSNumber is not mutable. Pull out the old value in the array and insert the toggled value
            [_selectedCells removeObjectAtIndex: cell.index];
            [_selectedCells insertObject: [NSNumber numberWithBool: !([selectedNumber boolValue]) ] atIndex: cell.index];
        }
        else //if there IS a cell being dragged about, handle that now
        {
            if( _gridViewFlags.delegateDidMoveCell )
                [self.delegate gridView: self didMoveCellAtIndex: _cellBeingDragged.index toIndex: _cellIndexBeingDraggedOver];
            
            _cellBeingDragged.index = _cellIndexBeingDraggedOver;
            
            //Grab the frame, reset the anchor point back to default (Which changes the frame to compensate), and then reapply the frame
            CGRect frame = _cellBeingDragged.frame;
            _cellBeingDragged.layer.anchorPoint = CGPointMake(0.5f,0.5f);
            _cellBeingDragged.frame = frame;
            
            //Temporarily revert the transformation back to default, and make sure to properly resize the cell
            //(In case it's slightly longer/shorter due to padding issues)
            CGAffineTransform transform = _cellBeingDragged.transform;
            _cellBeingDragged.transform = CGAffineTransformIdentity;
            
            frame = _cellBeingDragged.frame;
            frame.size = [self sizeOfCellAtIndex: _cellBeingDragged.index];

            _cellBeingDragged.frame = frame;
            _cellBeingDragged.transform = transform;
            
            //animate it zipping back, and deselecting
            [_cellBeingDragged setDragging: NO animated: YES];
            [_cellBeingDragged setHighlighted: NO animated: YES];
            
            //reset the cell handle for next time
            _cellBeingDragged = nil;
            _cellIndexBeingDraggedOver = -1;
            
            //re-enable scrolling
            [self setScrollEnabled: YES];
        }
    }
    
    //kill the tap and hold timer if it was present
    [_longPressTimer invalidate];
    
    [super touchesEnded: touches withEvent: event];
}

/* touchesCancelled is usually called if the user tapped down, but then started scrolling the UIScrollView. (Or potentially, if the user rotates the device) */
/* This will relinquish any state control we had on any cells. */
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    //The cell that was under our finger at the time
    TOGridViewCell *cell = [self cellInTouch: [touches anyObject]];
    
    //if there was actually a cell, cancel its highlighted state
    if( cell )
        [cell setHighlighted: NO animated: NO];
    
    //If we were in the middle of dragging a cell, kill it
    if( _isEditing && _cellBeingDragged )
        [self cancelDraggingCell];
    
    //if we were tapping and holding a cell, kill that
    [_longPressTimer invalidate];
    
    [super touchesCancelled: touches withEvent: event];
}

- (void)cancelDraggingCell
{
    if( _cellBeingDragged == nil )
        return;
    
    _cellBeingDragged.layer.anchorPoint = CGPointMake( 0.5f, 0.5f );
    [_cellBeingDragged setDragging: NO animated: NO];
    _cellBeingDragged = nil;
    
    _cellIndexBeingDraggedOver = -1;
    
    [self setScrollEnabled: YES];
}

#pragma mark -
#pragma mark Accessors
- (void)setDelegate:(id<TOGridViewDelegate>)delegate
{
    if( self.delegate == delegate )
        return;
    
    [super setDelegate: delegate];
    
    //Update the flags with the state of the new delegate
    _gridViewFlags.delegateDecorationView       = [self.delegate respondsToSelector: @selector(gridView:decorationViewForRowWithIndex:)];
    _gridViewFlags.delegateInnerPadding         = [self.delegate respondsToSelector: @selector(innerPaddingForGridView:)];
    _gridViewFlags.delegateNumberOfCellsPerRow  = [self.delegate respondsToSelector: @selector(numberOfCellsPerRowForGridView:)];
    _gridViewFlags.delegateSizeOfCells          = [self.delegate respondsToSelector: @selector(sizeOfCellsForGridView:)];
    _gridViewFlags.delegateHeightOfRows         = [self.delegate respondsToSelector: @selector(heightOfRowsInGridView:)];
    _gridViewFlags.delegateDidLongTapCell       = [self.delegate respondsToSelector: @selector(gridView:didLongTapCellAtIndex:)];
    _gridViewFlags.delegateDidTapCell           = [self.delegate respondsToSelector: @selector(gridView:didTapCellAtIndex:)];
    _gridViewFlags.delegateDidMoveCell          = [self.delegate respondsToSelector: @selector(gridView:didMoveCellAtIndex:toIndex:)];
}

- (void)setDataSource:(id<TOGridViewDataSource>)dataSource
{
    if( _dataSource == dataSource )
        return;
    
    _dataSource = dataSource;
    
    //Update the flags with the current state of the data source
    _gridViewFlags.dataSourceCellForIndex       = [_dataSource respondsToSelector: @selector(gridView:cellForIndex:)];
    _gridViewFlags.dataSourceNumberOfCells      = [_dataSource respondsToSelector: @selector(numberOfCellsInGridView:)];
    _gridViewFlags.dataSourceCanEditCell        = [_dataSource respondsToSelector: @selector(gridView:canEditCellAtIndex:)];
    _gridViewFlags.dataSourceCanMoveCell        = [_dataSource respondsToSelector: @selector(gridView:canMoveCellAtIndex:)];
}

- (void)setHeaderView:(UIView *)headerView
{
    if( _headerView == headerView )
        return;
    
    //remove the older header view and set up the new header view
    [_headerView removeFromSuperview];
    _headerView = headerView;
    _headerView.frame = CGRectMake( 0, 0, CGRectGetWidth(_headerView.frame), CGRectGetHeight(_headerView.frame));
    _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    //Set the origin of the first cell to be beneath this header view
    _offsetFromHeader = CGRectGetHeight(headerView.bounds);
    
    //add the view to the scroll view
    [self addSubview: _headerView];
    
    //reset the size of the scroll view to account for this new header views
    self.contentSize = [self contentSizeOfScrollView];
    
    //update any and all visible cells as well
    [self invalidateVisibleCells];
    [self layoutCells];
}

- (void)setBackgroundView:(UIView *)backgroundView
{
    if( _backgroundView == backgroundView )
        return;
    
    //remove the old background view and set up the new one
    [_backgroundView removeFromSuperview];
    _backgroundView = backgroundView;
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _backgroundView.frame = self.bounds;
    
    //make sure to insert it BELOW any visible cells
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
    
    //If we were in the middle of dragging a cell, kill it
    if( _isEditing )
        [self cancelDraggingCell];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    _isEditing = editing;
    
    /* If we ended editing, make sure to kill the scroll timer. */
    if( !_isEditing )
    {
        [_dragScrollTimer invalidate];
        _dragScrollTimer = nil;
        
        //deselect and exit edit mode for all visible cells
        for( TOGridViewCell *cell in _visibleCells )
        {
            [cell setSelected: NO animated: NO];
            [cell setEditing: NO animated: animated];
        }
        
        for( TOGridViewCell *cell in _recycledCells )
        {
            [cell setSelected: NO animated: NO];
            [cell setEditing: NO animated: animated];
        }

        //reset the list of selected cells
        _selectedCells = nil;
        _selectedCells = [NSMutableArray array];
        for( NSInteger i=0; i<_numberOfCells; i++ )
            [_selectedCells addObject: [NSNumber numberWithBool: NO]];
    }
    else
    {
        for( TOGridViewCell *cell in _visibleCells )
            [cell setEditing: YES animated: animated];
    }
}


@end
