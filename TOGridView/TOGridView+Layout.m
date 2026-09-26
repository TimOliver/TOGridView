//
//  TOGridView+Layout.m
//
//  Copyright 2013-2015 Timothy Oliver. All rights reserved.
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

#import "TOGridView+Private.h"

@implementation TOGridView (Layout)

- (void)resetCellMetrics
{
    _cellLayoutGeneration++;
    [self invalidateCellPreparation];
    [self schedulePrefetchUpdate];
    // Hold weak collaborators for this calculation. Missing optional metrics reset
    // to their defaults when the delegate changes or has been released.
    id<TOGridViewDelegate> delegate = self.delegate;
    id<TOGridViewDataSource> dataSource = self.dataSource;
    self.numberOfCellsPerRow = _gridViewFlags.delegateNumberOfCellsPerRow ? MAX(1, (NSInteger)[delegate numberOfCellsPerRowForGridView:self]) : 1;
    self.numberOfCells = _gridViewFlags.dataSourceNumberOfCells ? [dataSource numberOfCellsInGridView:self] : 0;
    _prefetchNeedsDataSourceReload = NO;
    self.cellPaddingInsets = _gridViewFlags.delegateBoundaryInsets ? [delegate boundaryInsetsForGridView:self] : UIEdgeInsetsZero;
    self.cellSize = _gridViewFlags.delegateSizeOfCells ? [delegate sizeOfCellsForGridView:self] : CGSizeZero;
    self.rowHeight = _gridViewFlags.delegateHeightOfRows ? [delegate heightOfRowsInGridView:self] : self.cellSize.height;
    self.offsetOfCellsInRow = _gridViewFlags.delegateVerticalOffsetOfCells ? [delegate verticalOffsetOfCellsInRowsInGridView:self] : 0;

    /* Work out the spacing between cells */
    self.widthBetweenCells = self.numberOfCellsPerRow > 1 ? (NSInteger)floor(((CGRectGetWidth(self.bounds) - (self.cellPaddingInsets.left + self.cellPaddingInsets.right)) //Overall width of row
                                               - (_cellSize.width * self.numberOfCellsPerRow)) //minus the combined width of all cells
                                              / (self.numberOfCellsPerRow-1)) : 0; //no gaps in a single-column layout
    self.widthBetweenCells = MAX(self.widthBetweenCells, 0);
    
    /* Set up the scrollview and the subsequent contentView */
    self.contentSize = [self contentSizeOfScrollView];
    
    /* Reposition the footer view if need be */
    if (self.footerView)
        self.footerView.frame = [self footerViewFrame];
}

/* Works out the height, of purely just the grid view's content. */
- (CGFloat)heightOfGridViewContent
{
    CGFloat height = 0.0f;
    
    height =  (self.offsetFromHeader);
    height += (self.cellPaddingInsets.top + self.cellPaddingInsets.bottom);
    height += (self.footerView.frame.size.height);
    
    if (self.numberOfCells)
        height += (NSInteger)(ceil((CGFloat)self.numberOfCells / (CGFloat)self.numberOfCellsPerRow) * self.rowHeight);
    
    return height;
}

/* Take into account the offsets/header size/cell rows to cacluclate the total size of the scrollview */
- (CGSize)contentSizeOfScrollView
{
    CGSize size;
    
    //width
    size.width      = CGRectGetWidth(self.bounds);
    
    //height
    size.height =  [self heightOfGridViewContent];
    
    //If the height is LESS than the overall view height, pad it out so the header can be hidden
    CGFloat insetHeights = self.contentInset.bottom + self.contentInset.top;
    size.height = MAX(size.height, (CGRectGetHeight(self.bounds) - insetHeights) + self.offsetFromHeader);
    
    return size;
}

- (CGRect)footerViewFrame
{
    if (self.footerView)
        return (CGRect){{0.0f, [self heightOfGridViewContent] - CGRectGetHeight(self.footerView.frame)}, self.footerView.frame.size};
    
    return CGRectZero;
}

- (void)invalidateVisibleCells
{
    _cellLayoutGeneration++;
    [self invalidateCellPreparation];
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        [cell removeFromSuperview];
        [self.recycledCells addObject:cell];
    }];
    
    [self.visibleCells removeAllObjects];
}

- (NSInteger)indexOfVisibleCell:(TOGridViewCell *)cell
{
    __block NSInteger index = NSNotFound;
    [self.visibleCells enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, TOGridViewCell *visibleCell, BOOL *stop) {
        if (visibleCell == cell)
        {
            index = key.integerValue;
            *stop = YES;
        }
    }];
    
    return index;
}

//Work out which cells this point of space will technically belong to
- (NSInteger)indexOfCellAtPoint:(CGPoint)point
{
    //work out which row we're on
    NSInteger   rowOrigin    = self.offsetFromHeader + self.cellPaddingInsets.top;
    NSInteger   rowIndex     = floor((point.y-rowOrigin) / self.rowHeight) * self.numberOfCellsPerRow;
    
    //work out which number on the row we are
    NSInteger columnIndex   = floor((point.x + self.cellPaddingInsets.left) / CGRectGetWidth(self.bounds) * self.numberOfCellsPerRow);
    columnIndex = MIN(self.numberOfCellsPerRow - 1, columnIndex);
    columnIndex = MAX(0, columnIndex);
    
    NSInteger index = rowIndex + columnIndex;
    index = MAX(-1, index); //if the number of cells is below the start, return -1
    index = MIN(self.numberOfCells-1, index); //cap it at the max number of cells
    
    //return the cell index
    return index;
}

- (void)enumerateCellDictionary:(NSDictionary<NSNumber *, TOGridViewCell *> *)cellDictionary withBlock:(void (^)(NSInteger index, TOGridViewCell *))block
{
    if (block == nil)
        return;
    
    [cellDictionary enumerateKeysAndObjectsWithOptions:0 usingBlock:^(NSNumber *key, TOGridViewCell *cell, BOOL *stop) {
        block(key.integerValue, cell);
    }];
}

- (NSRange)rangeOfVisibleCellsInBounds:(CGRect)bounds
{
    if (self.numberOfCells == 0)
        return (NSRange){0,0};
    
    NSRange visibleCellRange;
    
    //The official origin of the first row, accounting for the header size and outer padding
    NSInteger   rowOrigin           = self.offsetFromHeader + self.cellPaddingInsets.top;
    CGFloat     contentOffsetY      = bounds.origin.y; //bounds.origin on a scrollview contains the best up-to-date contentOffset
    CGFloat     contentHeight       = bounds.size.height;
    NSInteger   numberOfRows        = floor(self.numberOfCells / self.numberOfCellsPerRow);
    
    NSInteger   firstVisibleRow     = floor((contentOffsetY-rowOrigin) / self.rowHeight);
    NSInteger   lastVisibleRow      = floor(((contentOffsetY-rowOrigin)+contentHeight) / self.rowHeight);
    
    //if the header is in view, scale the size up a bit so we include the cells that would have otherwise been
    //there, had the header view NOT been there
    if (self.headerView && contentOffsetY < CGRectGetHeight(self.headerView.frame))
        contentHeight += CGRectGetHeight(self.headerView.frame);
    
    //make sure there are actually some visible rows
    if (lastVisibleRow >= 0 && firstVisibleRow <= numberOfRows)
    {
        visibleCellRange.location  = MAX(0,firstVisibleRow) * self.numberOfCellsPerRow;
        visibleCellRange.length    = (((lastVisibleRow - MAX(0,firstVisibleRow))+1) * self.numberOfCellsPerRow);
        
        if (visibleCellRange.location + visibleCellRange.length >= self.numberOfCells)
            visibleCellRange.length = self.numberOfCells - visibleCellRange.location;
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
    // The owner may have gone away while the grid remains in the hierarchy.
    if (self.dataSource == nil) {
        self.numberOfCells = 0;
        [self invalidateVisibleCells];
        [self schedulePrefetchUpdate];
        return;
    }
    if (self.numberOfCells == 0) {
        [self schedulePrefetchUpdate];
        return;
    }
    
    //work out the index range of which cells should be visible now
    NSRange visibleCellRange = [self rangeOfVisibleCellsInBounds:self.bounds];
    if (_preparedCellTraits != nil && ![_preparedCellTraits isEqual:self.traitCollection]) {
        [self invalidateCellPreparation];
        [self schedulePrefetchUpdate];
    }
    NSUInteger generation = _cellLayoutGeneration;
    BOOL canReuseRange = self.draggingCell == nil && self.insertingCells == nil && !self.pauseCellLayout;
    if (canReuseRange && _hasReconciledCellRange && _reconciledCellLayoutGeneration == generation &&
        NSEqualRanges(_reconciledCellRange, visibleCellRange) && self.visibleCells.count == visibleCellRange.length)
        return;
    // An intact previous range already supplies the overlap. Only incoming indices
    // need lookup/configuration; edits and incomplete passes retain the full scan.
    NSRange unchangedRange = NSMakeRange(0, 0);
    if (canReuseRange && _hasReconciledCellRange && _reconciledCellLayoutGeneration == generation &&
        self.visibleCells.count == _reconciledCellRange.length &&
        _reconciledCellRange.length > 0 && visibleCellRange.length > 0)
        unchangedRange = NSIntersectionRange(_reconciledCellRange, visibleCellRange);
    _hasReconciledCellRange = NO;
    _cellPreparationSuspendedForMemoryWarning = NO;
    if (_cellPreparationSuspendedForBudget && !NSEqualRanges(_reconciledCellRange, visibleCellRange))
        [self resetCellPreparationBudget];
    NSRange preparationRange = [self cellPreparationRangeForVisibleRange:visibleCellRange];
    // Prune synchronously so a series of scroll offsets in one run-loop turn cannot
    // accumulate prepared rows before the deferred scheduler gets a chance to run.
    for (NSNumber *key in _preparedCells.allKeys) {
        if (!NSLocationInRange(key.unsignedIntegerValue, preparationRange)) {
            TOGridViewCell *cell = _preparedCells[key];
            if (cell != nil)
                [self.recycledCells addObject:cell];
            [_preparedCells removeObjectForKey:key];
        }
    }
    
    //go through each visible cell and see if they've moved beyond the visible range
    NSSet<NSNumber *> *cellsToRecyle = [self.visibleCells keysOfEntriesWithOptions:0 passingTest:^BOOL(NSNumber *key, TOGridViewCell *cell, BOOL *stop) {
        NSInteger index = key.integerValue;
        
        if (NSLocationInRange(index, visibleCellRange))
            return NO;
        
        if (_gridViewFlags.delegateDidEndDisplayingCell)
            [self.delegate gridView:self didEndDisplayingCell:cell atIndex:index];
        
        [cell.layer removeAllAnimations];
        [cell removeFromSuperview];
        if (NSLocationInRange(index, preparationRange)) {
            if (self->_preparedCells == nil)
                self->_preparedCells = [NSMutableDictionary dictionary];
            self->_preparedCells[key] = cell;
            self->_preparedCellTraits = self.traitCollection;
        } else {
            [self.recycledCells addObject:cell];
        }
        
        return YES;
    }];
    [self.visibleCells removeObjectsForKeys:[cellsToRecyle allObjects]];
    
    /* Only proceed with the following code if the number of visible cells is lower than it should be. */
    /* This code produces the most latency, so minimizing its call frequency is critical */
    if (self.visibleCells.count < visibleCellRange.length) {
        for (NSInteger i = 0; i < visibleCellRange.length; i++)
        {
            NSInteger index = visibleCellRange.location+i;
            if (_cellLayoutGeneration == generation && NSLocationInRange(index, unchangedRange)) {
                i += NSMaxRange(unchangedRange) - index - 1;
                continue;
            }
        
            TOGridViewCell *cell = [self cellForIndex:index];
            if (cell) {
                continue;
            }

            //when the user is dragging a cell around in edit mode, it will be offsetting
            //the values of all of the cells around it. Compensate for that here
            //(eg, every cell index past the dragging index bumped up or decreased by 1)
            NSInteger indexOffset = 0;
            if (self.draggingCellIndex >= 0) {
                //if the dragging cell is after its origin
                if (self.draggingOverIndex >= self.draggingCellIndex) {
                    if (index >= self.draggingCellIndex && index < self.draggingOverIndex)
                        indexOffset = 1;
                }
                else { //the dragging cell was dragged before
                    if (index <= self.draggingCellIndex && index > self.draggingOverIndex)
                        indexOffset = -1;
                }
            }
        
            [self addCellAtIndex:index dataSourceIndex:index + indexOffset];
        }
    }

    // If a callback invalidated layout, retain the old generation so the next pass
    // cannot reuse this result. Edits and dragging always take the full path.
    _reconciledCellRange = visibleCellRange;
    _reconciledCellLayoutGeneration = generation;
    _hasReconciledCellRange = self.draggingCell == nil && self.insertingCells == nil &&
        !self.pauseCellLayout && self.visibleCells.count == visibleCellRange.length;
    [self schedulePrefetchUpdate];
}

/* Requesting/configuring a cell is separate from making it visible. */
- (TOGridViewCell *)requestCellAtIndex:(NSInteger)index
{
    // The cell data source now owns any data-prefetch request for this item.
    if (_prefetchRequestGeneration == _prefetchGeneration)
        [_prefetchedIndices removeIndex:index];
    TOGridViewCell *cell = [self.dataSource gridView:self cellForIndex:index];
    if (cell == nil)
        [NSException raise:NSInternalInconsistencyException format:@"The datasource may not return a nil cell object"];
    return cell;
}

- (void)configureCell:(TOGridViewCell *)cell atIndex:(NSInteger)index prepared:(BOOL)prepared
{
    id<TOGridViewDataSource> dataSource = self.dataSource;
    if (!prepared || cell.hidden)
        cell.hidden = NO;
    if (!prepared || cell.highlighted)
        [cell setHighlighted:NO animated:NO];

    //if the cell has been selected, highlight it
    if (self.allowsSelectionDuringEditing) {
        BOOL selected = self.editing && [self.selectedCells containsObject:@(index)];
        if ((!prepared && selected) || cell.selected != selected)
            [cell setSelected:selected animated:NO];
    }

    // Recheck permissions at display time, but avoid toggling a prepared cell's state.
    if (!prepared)
        cell.draggable = NO;
    BOOL draggable = _gridViewFlags.dataSourceCanMoveCell && [dataSource gridView:self canMoveCellAtIndex:index];
    if (cell.draggable != draggable)
        cell.draggable = draggable;

    //set the cell editing state
    BOOL editing = _gridViewFlags.dataSourceCanEditCell && self.editing && [dataSource gridView:self canEditCellAtIndex:index];
    if (!prepared || cell.editing != editing)
        cell.editing = editing;

    //make sure the frame is still properly set
    CGRect cellFrame;
    cellFrame.origin = [self originOfCellAtIndex:index];
    cellFrame.size = [self sizeOfCellAtIndex:index];
    if (!prepared || !CGRectEqualToRect(cell.frame, cellFrame))
        cell.frame = cellFrame;
}

/* Share the display lifecycle between scrolling and insertion. */
- (TOGridViewCell *)addCellAtIndex:(NSInteger)index dataSourceIndex:(NSInteger)dataSourceIndex
{
    BOOL animationsEnabled = [UIView areAnimationsEnabled];
    [UIView setAnimationsEnabled:NO];
    @try {
        TOGridViewCell *cell = dataSourceIndex == index ? _preparedCells[@(index)] : nil;
        BOOL prepared = cell != nil;
        if (cell != nil)
            [_preparedCells removeObjectForKey:@(index)];
        else
            cell = [self requestCellAtIndex:dataSourceIndex];

        // Selection/editing may have changed while the cell waited offscreen.
        [self configureCell:cell atIndex:index prepared:prepared];
        [self.visibleCells setObject:cell forKey:@(index)];
        if (_gridViewFlags.delegateWillDisplayCell)
            [self.delegate gridView:self willDisplayCell:cell atIndex:index];
        if (cell.superview == nil)
            [self.cellContainerView insertSubview:cell atIndex:0];
        return cell;
    }
    @finally {
        [UIView setAnimationsEnabled:animationsEnabled];
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
 when a CAAnimation object has been applied to the 'bounds' property of the view), the view captures UIKit snapshots of the old cells. It crossfades these over the live cells in their new
 arrangement for the same duration as the rotation animation.
 */
- (void)layoutGridSubviews
{
    if (self.freezeLayoutSubviews)
        return;
    
    //For cases when our layout code needs to defer laying out cells
    BOOL pauseCellLayout = NO;
    
    /* Apply the crossfade effect if this method is being called while there is a pending 'bounds' animation present. */
    /* Capture the 'before' state before we reposition all of the cells */
    CABasicAnimation *boundsAnimation = self.boundsChangeAnimation;
    if (boundsAnimation)
    {
        //if a cell is currently being dragged, cancel it
        if (self.draggingCell)
            [self cancelDraggingCell];
        
        //halt the scroll view if it's currently moving
        if (self.isDecelerating || self.isDragging)
        {
            CGPoint contentOffset = self.bounds.origin;
            
            if (contentOffset.y < TOP_OFFSET) //reset back to 0 if it's rubber-banding at the top
                [self setContentOffset:(CGPoint){0.0f, -self.contentInset.top} animated:NO];
            else if (contentOffset.y > BOTTOM_OFFSET) // reset if rubber-banding at the bottom
                [self setContentOffset:CGPointMake(0, self.contentSize.height - CGRectGetHeight(self.bounds)) animated:NO];
            else //just halt it where-ever it is right now.
                [self setContentOffset:contentOffset animated:NO];
        }
        
        //At this point, self.bounds is already the newly resized value.
        //The original bounds are still available as the 'before' value in the layer animation object
        CGRect beforeRect = _gridViewBeforeRotationState.bounds;
        
        //Save the current visible cells before we apply the rotation so we can re-align it afterwards
        NSRange visibleCells = [self rangeOfVisibleCellsInBounds:beforeRect];
        CGFloat yOffsetFromTopOfRow = (beforeRect.origin.y + self.contentInset.top) - (self.offsetFromHeader + self.cellPaddingInsets.top + (floor(visibleCells.location/self.numberOfCellsPerRow) * self.rowHeight));
        
        //Save a copy of the current number of cells per row so we can compare below
        NSInteger numberOfCellsPerRow = self.numberOfCellsPerRow;
        
        //poll the delegate again to see if anything needs changing since the bounds have changed
        //(Also, by this point, [UIViewController interfaceOrientation] has updated to the new orientation too)
        [self resetCellMetrics];
        
        //it's only worth expending the compute time to generate a screenshot if:
        // - Crossfading is actually on
        // - The number of cells per row actually changes
        if (self.window != nil && self.beforeSnapshotView == nil && self.crossfadeCellsOnRotation && self.pauseCrossfadeAnimation == NO && self.numberOfCellsPerRow != numberOfCellsPerRow) {
            self.freezeLayoutSubviews = YES;
            {
                self.beforeSnapshotView = [self snapshotOfGridViewInRect:beforeRect];
            }
            self.freezeLayoutSubviews = NO;
            
            self.beforeSnapshotInsets = self.contentInset;
        }
        
        BOOL boundsHeightIncreased = (NSInteger)CGRectGetHeight(beforeRect) - (NSInteger)CGRectGetHeight(self.bounds) < 0;
        pauseCellLayout = (!self.crossfadeCellsOnRotation && self.numberOfCellsPerRow == numberOfCellsPerRow && boundsHeightIncreased == NO);
        
        //if we're not crossfading, force all of the visible cells to re-align
        if (self.crossfadeCellsOnRotation == NO || self.pauseCellLayout) {
            //arrange the cells to their new configuration
            [self.visibleCells enumerateKeysAndObjectsUsingBlock:^(NSNumber *index, TOGridViewCell *cell, BOOL *stop) {
                cell.frame = (CGRect){[self originOfCellAtIndex:index.integerValue], [self sizeOfCellAtIndex:index.integerValue]};
            }];
        }
        
        //manually set contentOffset's value based off bounds.
        //Not sure why, but if we don't do this, periodically, contentOffset resets to [0,0] (possibly as a result of the frame changing) and borks the animation :S
        if (self.contentSize.height - self.bounds.size.height >= self.contentOffset.y)
            self.contentOffset = CGPointMake(0, self.bounds.origin.y);
        
        //If the header view is completely hidden (ie, only cells), re-orient the scroll view so the same cells are onscreen in the new orientation
        if ((self.contentOffset.y+self.contentInset.top) - self.offsetFromHeader > 0.0f && yOffsetFromTopOfRow >= 0.0f && visibleCells.location >= self.numberOfCellsPerRow)
        {
            CGFloat y = self.offsetFromHeader + self.cellPaddingInsets.top + (self.rowHeight * floor(visibleCells.location/self.numberOfCellsPerRow)) + yOffsetFromTopOfRow;
            y = MIN(self.contentSize.height - self.bounds.size.height, y);
            self.contentOffset = CGPointMake(0,y);
        }
        
        //remove any animations that animate scrolling
        for (NSString *key in self.layer.animationKeys) {
            if ([key rangeOfString:@"origin"].location != NSNotFound)
                [self.layer removeAnimationForKey:key];
        }
    }
    
    //lay out all of the cells given the current bounds state
    if (self.pauseCellLayout == NO && pauseCellLayout == NO)
        [self layoutCells];
    
    if (boundsAnimation && self.crossfadeCellsOnRotation && self.pauseCrossfadeAnimation == NO)
    {
        CGRect beforeRect = _gridViewBeforeRotationState.bounds;
        
        /*
         "bounds" stores the scroll offset in its 'origin' property, and the actual size of the view in the 'size' property.
         Since we DO want the view to animate resizing itself, but we DON'T want it to animate scrolling at the same time, we'll have
         to modify the animation properties (which is why we made a mutable copy above) and then re-insert it back in.
         */
        CABasicAnimation *fullBoundsAnimation = (CABasicAnimation *)[self.layer animationForKey:@"bounds"];
        if (fullBoundsAnimation) {
            fullBoundsAnimation = [fullBoundsAnimation mutableCopy];
            [self.layer removeAnimationForKey:@"bounds"];
            beforeRect = [[boundsAnimation fromValue] CGRectValue];
            
            /*  This is a dumb optimisation for iComics. When the device rotation animation starts,
                I set the UINavigationController bar to opaque, which GREATLY increases performance.
                Unfortunately, when I set the bar to opaque, it re-aligns the grid view to below the navbar,
                and then changes contentInset to 0. When this happens, it turns out it's unnecessary to change
                the bounds position in here, as it was already set before the relayout occurs. 
                TL;DR Crazy hack makes crazy crap happen. This works, and yet I feel so dirty.
             */
            if (self.beforeSnapshotInsets.top == self.contentInset.top)
                beforeRect.origin.y = self.bounds.origin.y;

            [fullBoundsAnimation setFromValue:[NSValue valueWithCGRect:beforeRect]];
            fullBoundsAnimation.delegate = self;
            fullBoundsAnimation.removedOnCompletion = YES;
            [self.layer addAnimation:fullBoundsAnimation forKey:@"bounds"];
        }
        
        //arrange the cells to their new configuration
        [self.visibleCells enumerateKeysAndObjectsUsingBlock:^(NSNumber *index, TOGridViewCell *cell, BOOL *stop) {
            cell.frame = (CGRect){[self originOfCellAtIndex:index.integerValue], [self sizeOfCellAtIndex:index.integerValue]};
            [cell.layer removeAllAnimations];
            
            cell.alpha = 0.0f;
            [UIView animateWithDuration:boundsAnimation.duration animations:^{ cell.alpha = 1.0f; }];
        }];
        
        UIView *snapshot = self.beforeSnapshotView;
        if (self.window != nil && snapshot != nil) {
            NSUInteger generation = ++self.snapshotAnimationGeneration;
            snapshot.frame = (CGRect){self.frame.origin, snapshot.frame.size};
            [snapshot.layer removeAllAnimations];
            [self.superview addSubview:snapshot];

            CGFloat delta = self.contentOffset.y - beforeRect.origin.y;
            snapshot.alpha = 1.0f;
            [UIView animateWithDuration:boundsAnimation.duration animations:^{
                snapshot.frame = CGRectOffset(snapshot.frame, 0.0f, -delta);
                snapshot.alpha = 0.0f;
            } completion:^(BOOL finished) {
                // An interrupted transition must also release its overlay. Capture the
                // actual view so an older completion cannot remove a newer snapshot.
                if (self.beforeSnapshotView == snapshot && generation != self.snapshotAnimationGeneration)
                    return;
                [snapshot removeFromSuperview];
                if (self.beforeSnapshotView == snapshot)
                    self.beforeSnapshotView = nil;
            }];
        }
    }
    
    // Keep the container viewport-sized while preserving content-space cell frames.
    // Its geometry must not add another animation on top of the cells' animations.
    [UIView performWithoutAnimation:^{
        self.cellContainerView.frame = self.bounds;
        self.cellContainerView.bounds = self.bounds;
    }];

    /* Update the background view to stay in the background */
    if (self.backgroundView)
        self.backgroundView.frame = CGRectMake(0, self.bounds.origin.y, CGRectGetWidth(self.backgroundView.bounds), CGRectGetHeight(self.backgroundView.bounds));
}

- (UIView *)snapshotOfGridViewInRect:(CGRect)rect
{
    // Capture the committed cell hierarchy once, before rotation lays it out again.
    // The container's coordinates match the scroll view, including its bounds origin.
    UIView *snapshot;
    if (CGRectEqualToRect(rect, self.cellContainerView.bounds))
        snapshot = [self.cellContainerView snapshotViewAfterScreenUpdates:NO];
    else
        snapshot = [self.cellContainerView resizableSnapshotViewFromRect:rect afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
    snapshot.userInteractionEnabled = NO;
    snapshot.accessibilityElementsHidden = YES;
    return snapshot;
}

@end
