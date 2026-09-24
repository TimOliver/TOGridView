//
//  TOGridView+Dragging.m
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

#define LONG_PRESS_TIME 0.4f

// The touch helpers retain the original placement of calls to UIScrollView.

@implementation TOGridView (Dragging)

- (void)updateCellsLayoutWithDraggedCellAtPoint:(CGPoint)dragPanPoint
{
    NSInteger currentlyDraggedOverIndex = [self indexOfCellAtPoint:dragPanPoint];
    if (currentlyDraggedOverIndex == -1|| currentlyDraggedOverIndex == self.draggingOverIndex)
        return;
    
    if (NSLocationInRange(currentlyDraggedOverIndex, self.visibleCellRange) == NO)
        return;
    
    if (_gridViewFlags.dataSourceCanMoveCell) {
        if ([self.dataSource gridView:self canMoveCellAtIndex:currentlyDraggedOverIndex] == NO)
            return;
    }
    
    //The direction and number of stops we just moved the cell (eg cell 0 to cell 2 is '2')
    NSInteger offset = -(self.draggingOverIndex - currentlyDraggedOverIndex);
    
    //sort the cell keys into ascending order
    NSArray<NSNumber *> *cellIndices = [self.visibleCells.allKeys sortedArrayUsingSelector:@selector(compare:)];
    
    NSMutableDictionary<NSNumber *, NSNumber *> *newIndicies = [NSMutableDictionary dictionary];
    for (NSNumber *cellIndex in cellIndices) {
        NSInteger index = cellIndex.integerValue;
        TOGridViewCell *cell = self.visibleCells[cellIndex];
        
        if (cell == self.draggingCell)
            continue;
        
        NSInteger newIndex = 0;
        
        //If the offset is positive, we dragged the cell forward
        BOOL found = NO;
        if (offset > 0) {
            if (index <= self.draggingOverIndex + offset && index > self.draggingOverIndex) {
                newIndex = index - 1;
                found = YES;
            }
        }
        else {
            if (index >= self.draggingOverIndex + offset && index < self.draggingOverIndex) {
                newIndex = index + 1;
                found = YES;
            }
        }
        
        //Ignore cells that don't need to animate
        if (found == NO)
            continue;
        
        //add the new value to our update dictionary
        newIndicies[cellIndex] = @(newIndex);
        
        //figure out the number of cells between the one being dragged and this one
        NSInteger delta = newIndex - self.draggingOverIndex;
        delta = (delta < 0) ? -delta : delta; //64-bit compatible abs()
        
        CGRect frame = [self rectOfCellAtIndex:newIndex];
        // Keep row-crossing cells above their neighbors and below the dragged cell.
        if ((NSInteger)CGRectGetMinY(cell.frame) != (NSInteger)CGRectGetMinY(frame))
            [self.cellContainerView insertSubview:cell belowSubview:self.draggingCell];

        // Let UIKit retarget an in-flight spring from its current presentation state.
        TOGridViewAnimateReordering(delta * TOGridViewReorderStaggerDelay, ^{
            cell.frame = frame;
        }, nil);
    }
    
    //include the dragging cell with the visible updates
    newIndicies[@(self.draggingOverIndex)] = @(currentlyDraggedOverIndex);
    
    //update all of the cells with their new respective indices
    [self updateVisibleCellKeysWithDictionary:newIndicies];
    
    //update the current cell index we're dragging over
    self.draggingOverIndex = currentlyDraggedOverIndex;
}

/* Called every 1/60th of a second to animate the scroll view */
- (void)fireDragTimer:(id)timer
{
    CGPoint offset = self.contentOffset;
    offset.y += self.dragScrollBias; //Add the calculated scroll bias to the current scroll offset
    offset.y = MAX(TOP_OFFSET, offset.y); //Clamp the value so we can't accidentally scroll past the end of the content
    offset.y = MIN(BOTTOM_OFFSET, offset.y);
    self.contentOffset = offset;
    
    //layout cells now that the scroll offset has changed
    [self layoutCells];
    
    CGPoint adjustedDragPoint = self.draggingCellPanPoint;
    adjustedDragPoint.y += self.contentOffset.y ;
    [self updateCellsLayoutWithDraggedCellAtPoint:adjustedDragPoint];
    
    /* If we're dragging a cell, update its position inside the scrollView to stick to the user's finger. */
    /* We can't move the cell outside of this view since that kills the touch events. :( */
    /* We also can't simply add the bias like we did above since it introduces floating point noise (and the cell starts to move on its own on screen :( ) */
    if (self.draggingCell)
    {
        CGPoint center = self.draggingCell.center;
        center.y = self.draggingCellPanPoint.y + self.contentOffset.y;
        self.draggingCell.center = center;
    }
    
    //if we hit the boundary, cancel the animation timer
    if (self.contentOffset.y <= TOP_OFFSET || self.contentOffset.y >= BOTTOM_OFFSET)
        [self stopAnimatingScrollViewDragging];
}

- (TOGridViewCell *)cellInTouch:(UITouch *)touch
{
    //start off with the view we directly hit with the UITouch
    UIView *view = [touch view];
    
    //traverse hierarchy to see if we hit inside a cell
    TOGridViewCell *cell = nil;
    do
    {
        if ([view isKindOfClass:[TOGridViewCell class]])
        {
            cell = (TOGridViewCell *)view;
            break;
        }
    }
    while ((view = view.superview) != nil);
    
    return cell;
}

/* touchesBagan is initially called when we first touch this view on the screen. There is no delay. */
- (void)handleTouchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    //reset this as needed
    self.cancelTouches = NO;
    
    //don't do anything if the scroll view was delecerating
    if (self.decelerating)
    {
        self.cancelTouches = YES;
        [super touchesBegan:touches withEvent:event];
        return;
    }
    
    UITouch *touch = [touches anyObject];
    TOGridViewCell *cell = [self cellInTouch:touch];
    NSInteger index = [self indexOfVisibleCell:cell];
    
    if (cell && !self.decelerating)
    {
        if (_gridViewFlags.dataSourceCanHighlightCell) {
            if ([self.dataSource gridView:self canHighlightCellAtIndex:index])
                [cell setHighlighted:YES animated:NO];
        }
        else
            [cell setHighlighted:YES animated:NO];
        
        // Perform a check to see if we're elligble to handle a long tap.
        // If we're NOT editing, a long tap is only valid if the dataSource and delegates allow it
        // If we ARE editing, a long tap is only valid if the 'canMoveCell' delegate is implemented
        BOOL canPerformLongTap = YES;
        if (self.editing == NO) {
            if (_gridViewFlags.dataSourceCanLongTapCell)
                canPerformLongTap = [_dataSource gridView:self canLongTapCellAtIndex:index];
            
            canPerformLongTap = (canPerformLongTap && _gridViewFlags.delegateDidLongTapCell);
        }
        else {
            canPerformLongTap = _gridViewFlags.dataSourceCanMoveCell;
        }
        
        //if we're set up to receive a long-press tap event, fire the timer now
        if (self.dragging == NO && canPerformLongTap)
            self.longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_TIME target:self selector:@selector(fireLongPressTimer:) userInfo:touch repeats:NO];
    }
    
    [super touchesBegan:touches withEvent:event];
}

- (void)fireLongPressTimer:(NSTimer *)timer
{
    UITouch *touch = [timer userInfo];
    TOGridViewCell *cell = (TOGridViewCell *)[self cellInTouch:touch];
    NSInteger index = [self indexOfVisibleCell:cell];
    if (index == NSNotFound)
        return;
    
    if (self.editing == NO)
    {
        [self.delegate gridView:self didLongTapCellAtIndex:index];
        self.cancelTouches = YES;
    }
    else
    {
        BOOL canMove = [self.dataSource gridView:self canMoveCellAtIndex:index];
        if (canMove == NO)
            return;
        
        // Hang onto the cell
        self.draggingCell           = cell;
        self.draggingCellIndex      = index;
        self.draggingOverIndex      = index;
        
        //pull it out of the selection list (We'll re-insert it at the end)
        if (self.allowsSelectionDuringEditing)
            [self.selectedCells removeObject:@(index)];
        
        CGPoint pointInCell = [touch locationInView:cell];
        
        //set the anchor point
        cell.layer.anchorPoint = CGPointMake(pointInCell.x / CGRectGetWidth(cell.bounds), pointInCell.y / CGRectGetHeight(cell.bounds));
        cell.center = [touch locationInView:self];
        
        //make the cell animate out slightly
        [self bringSubviewToFront:self.cellContainerView];
        [self.cellContainerView bringSubviewToFront:self.draggingCell];
        [self setCell:self.draggingCell atIndex:self.draggingCellIndex dragging:YES animated:YES];
        
        //disable the scrollView
        [self setScrollEnabled:NO];
        
        //disable the cell layout
        self.pauseCellLayout = YES;
    }
}

/* touchesMoved is called when we start panning around the view without releasing our finger */
- (void)handleTouchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    
    if (self.editing && self.draggingCell)
    {
        CGPoint panPoint = [touch locationInView:self];
        
        /* Update the position of the cell being dragged */
        self.draggingCell.center = ({
            CGPoint point = CGPointMake(panPoint.x + self.draggingCellOffset.width, panPoint.y + self.draggingCellOffset.height);
            //CGFloat maxX  =
            point;
        });
        
        /* Update the cells behind the one being dragged with new positions */
        [self updateCellsLayoutWithDraggedCellAtPoint:panPoint];
        
        /* Convert the pan point relative to the scroll content size */
        panPoint.y -= self.bounds.origin.y; //compensate for scroll offset
        /* Clamp the bounds of the pan point to only valid range */
        panPoint.y = MAX(panPoint.y, 0.0f); panPoint.y = MIN(panPoint.y, CGRectGetHeight(self.bounds)); //clamp to the outer bounds of the view
        
        //Save a copy of the translated point for the drag animation below
        self.draggingCellPanPoint = panPoint;
        
        //Determine if the touch location is within the scroll boundaries at either the top or bottom
        BOOL startAnimating = NO;

        //If we're scrolling at the top
        if (self.contentOffset.y > TOP_OFFSET && panPoint.y < self.dragScrollBoundaryDistance + self.contentInset.top) {
            NSInteger minPoint = self.dragScrollBoundaryDistance;
            NSInteger adjustedPanPoint = panPoint.y - self.contentInset.top;
            adjustedPanPoint = MAX(adjustedPanPoint, 0);
            
            self.dragScrollBias = -(self.dragScrollMaxVelocity * (1.0f - ((CGFloat)adjustedPanPoint / (CGFloat)minPoint)));
            
            startAnimating = YES;
        }
        
        //we're scrolling at the bottom
        if (self.contentOffset.y < BOTTOM_OFFSET && panPoint.y > (CGRectGetHeight(self.bounds) - self.contentInset.bottom) - self.dragScrollBoundaryDistance) {
            NSInteger maxPoint = CGRectGetHeight(self.bounds);
            NSInteger minPoint = maxPoint - self.dragScrollBoundaryDistance;
            NSInteger adjustedPanPoint = panPoint.y + self.contentInset.bottom;
            adjustedPanPoint = MIN(adjustedPanPoint, maxPoint);
            
            self.dragScrollBias = (self.dragScrollMaxVelocity * (((CGFloat)(adjustedPanPoint-minPoint) / (CGFloat)(maxPoint-minPoint))));
            
            startAnimating = YES;
        }
        
        //Kickstart a timer that'll fire at 60FPS to dynamically animate the scrollview
        if (startAnimating)
            [self startAnimatingScrollViewDragging];
        else //cancel the scrolling if we tap up, or move our fingers into the middle of the screen
            [self stopAnimatingScrollViewDragging];
    }
    
    [super touchesMoved:touches withEvent:event];
}

/* touchesEnded is called if the user releases their finger from the device without panning the scroll view (eg a discrete tap and release) */
- (void)handleTouchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    id<TOGridViewDelegate> delegate = self.delegate;
    id<TOGridViewDataSource> dataSource = self.dataSource;
    if (self.cancelTouches)
        return;
    
    UITouch *touch = [touches anyObject];
    
    //if we were animating the scroll view at the time, cancel it
    [self stopAnimatingScrollViewDragging];
    
    //The cell under our finger
    TOGridViewCell *cell = [self cellInTouch:touch];
    if (!cell)
        return;
    
    //if we WEREN'T in edit mode, fire the delegate to say we tapped this cell (But make sure this cell didn't already fire a long press event)
    if (self.editing == NO)
    {
        NSInteger index = [self indexOfVisibleCell:cell];
        
        if (_gridViewFlags.dataSourceCanHighlightCell) {
            if ([dataSource gridView:self canHighlightCellAtIndex:index])
                [cell setHighlighted:YES animated:NO];
        }
        else
            [cell setHighlighted:YES animated:NO];
        
        if (cell && _gridViewFlags.delegateDidTapCell)
            [delegate gridView:self didTapCellAtIndex:index];
    }
    else //if we WERE editing
    {
        //if there's no cell being dragged (ie, we just tapped a cell), set it to 'selected'
        if (self.draggingCell == nil)
        {
            NSInteger index = [self indexOfVisibleCell:cell];
            
            //unhighlight it
            [cell setHighlighted:NO animated:NO];
            
            if (_gridViewFlags.dataSourceCanEditCell) {
                if ([dataSource gridView:self canEditCellAtIndex:index] == NO)
                    return;
            }
            
            NSNumber *cellIndexNumber = [NSNumber numberWithInteger:index];
            
            //set it to be either selected or unselected
            if (self.allowsSelectionDuringEditing) {
                if ([self.selectedCells containsObject:cellIndexNumber] == NO)
                {
                    [cell setSelected:YES animated:NO];
                    [self.selectedCells addObject:cellIndexNumber];
                    
                    if (_gridViewFlags.delegateDidSelectCell)
                        [delegate gridView:self didSelectCellAtIndex:index];
                }
                else
                {
                    [cell setSelected:NO animated:NO];
                    [self.selectedCells removeObject:cellIndexNumber];
                    
                    if (_gridViewFlags.delegateDidDeselectCell)
                        [delegate gridView:self didDeselectCellAtIndex:index];
                }
            }
            else {
                if (_gridViewFlags.dataSourceCanHighlightCell) {
                    if ([dataSource gridView:self canHighlightCellAtIndex:index])
                        [cell setHighlighted:YES animated:NO];
                }
                else
                    [cell setHighlighted:YES animated:NO];
                
                if (_gridViewFlags.delegateDidTapCell)
                    [delegate gridView:self didTapCellAtIndex:index];
            }
        }
        else //if there IS a cell being dragged about, re-insert it back into the view layout
        {
            NSInteger previousIndex = self.draggingCellIndex;
            NSInteger newIndex      = self.draggingOverIndex;
            
            if (_gridViewFlags.delegateDidMoveCell)
                [delegate gridView:self didMoveCellAtIndex:previousIndex toIndex:newIndex];
            
            //re-associate the cell with its new index
            if ([self.visibleCells[@(self.draggingCellIndex)] isEqual:self.draggingCell])
                [self.visibleCells removeObjectForKey:@(self.draggingCellIndex)];
            
            [self.visibleCells setObject:self.draggingCell forKey:@(newIndex)];
            
            //Grab the frame, reset the anchor point back to default (Which changes the frame to compensate), and then reapply the frame
            CGRect frame = self.draggingCell.frame;
            self.draggingCell.layer.anchorPoint = CGPointMake(0.5f,0.5f);
            self.draggingCell.frame = frame;
            
            //Temporarily revert the transformation back to default, and make sure to properly resize the cell
            //(In case it's slightly longer/shorter due to padding issues)
            CGAffineTransform transform = self.draggingCell.transform;
            self.draggingCell.transform = CGAffineTransformIdentity;
            
            frame = self.draggingCell.frame;
            frame.size = [self sizeOfCellAtIndex:newIndex];
            
            self.draggingCell.frame = frame;
            self.draggingCell.transform = transform;
            
            //if the cell was selected, add it back into the selection pool
            if (cell.selected)
                [self.selectedCells addObject:@(newIndex)];
            
            //animate it zipping back, and deselecting
            [self setCell:self.draggingCell atIndex:newIndex dragging:NO animated:YES];
            
            //unhighlight the cell
            [self.draggingCell setHighlighted:NO animated:YES];
            
            //reset the cell handle for next time
            self.draggingCell       = nil;
            self.draggingOverIndex  = -1;
            self.draggingCellIndex  = -1;
            
            //re-enable scrolling
            [self setScrollEnabled:YES];
            
            //enable the cell layout
            self.pauseCellLayout = NO;
        }
    }
    
    [self.longPressTimer invalidate];
    self.longPressTimer = nil;
    
    [super touchesEnded:touches withEvent:event];
}

/* touchesCancelled is usually called if the user tapped down, but then started scrolling the UIScrollView. (Or potentially, if the user rotates the device) */
/* This will relinquish any state control we had on any cells. */
- (void)handleTouchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    //The cell that was under our finger at the time
    TOGridViewCell *cell = [self cellInTouch:[touches anyObject]];
    
    //if there was actually a cell, cancel its highlighted state
    if (cell)
        [cell setHighlighted:NO animated:NO];
    
    //If we were in the middle of dragging a cell, kill it
    if (self.editing && self.draggingCell)
        [self cancelDraggingCell];
    
    if (self.longPressTimer) {
        [self.longPressTimer invalidate];
        self.longPressTimer = nil;
    }
    
    [super touchesCancelled:touches withEvent:event];
}

- (void)cancelDraggingCell
{
    //if we're not currently dragging a cell, nothing to do here
    if (self.draggingCell == nil)
        return;
    
    //reset the cell's properties
    self.draggingCell.layer.anchorPoint = CGPointMake(0.5f, 0.5f);
    [self setCell:self.draggingCell atIndex:self.draggingCellIndex dragging:NO animated:NO];
    self.draggingCell = nil;
    
    //invalidate the index info
    self.draggingOverIndex = -1;
    self.draggingCellIndex = -1;
    
    //restore the scroll view
    [self setScrollEnabled:YES];
    self.pauseCellLayout = NO;
    
    //kill the scrolling timer
    [self stopAnimatingScrollViewDragging];
     
    //reload all of the cells to put them back in order
    [self reloadGrid];
}

- (void)setCell:(TOGridViewCell *)cell atIndex:(NSInteger)index dragging:(BOOL)dragging animated:(BOOL)animated
{
    //The original transformation state and a slightly scaled version
    CGAffineTransform originTransform   = CGAffineTransformIdentity;
    CGAffineTransform destTransform     = CGAffineTransformScale(originTransform, 1.1f, 1.1f);
    
    //The original alpha (fully opaque) and slightly transparent
    CGFloat originAlpha = 1.0f;
    CGFloat destAlpha   = 0.75f;
    
    //Set the cell's raserization scale for the upcoming bitmap cache
    cell.layer.rasterizationScale = MAX(self.traitCollection.displayScale, 1.0);
    
    if (animated)
    {
        //Perform the animation
        id animationBlock = ^{
            if (dragging)
            {
                cell.transform  = destTransform;
                cell.alpha      = destAlpha;
                
                //set the view to rasterize to flatten it's render hierarchy
                cell.layer.shouldRasterize = YES;
            }
            else
            {
                cell.transform  = originTransform;
                cell.alpha      = originAlpha;
                
                CGRect frame = cell.frame;
                frame.origin = [self originOfCellAtIndex:index];
                cell.frame = frame;
            }
        };
        
        id completionBlock = ^(BOOL complete) {
            if (dragging == NO) {
                cell.layer.shouldRasterize = NO;
                [self.cellContainerView addSubview:cell];
            }
        };
        
        TOGridViewAnimateReordering(0, animationBlock, completionBlock);
    }
    else
    {
        /* Set the new values */
        if (dragging)
        {
            cell.transform = destTransform;
            cell.alpha = destAlpha;
        }
        else
        {
            cell.transform = originTransform;
            cell.alpha = originAlpha;
            
            CGRect frame = cell.frame;
            frame.origin = [self originOfCellAtIndex:index];
            cell.frame = frame;
            
            [self.cellContainerView addSubview:cell];
        }
    }
}

- (void)startAnimatingScrollViewDragging
{
    if (self.dragScrollTimerLink)
        return;
    
    self.dragScrollTimerLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(fireDragTimer:)];
    [self.dragScrollTimerLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)stopAnimatingScrollViewDragging
{
    if (self.dragScrollTimerLink == nil)
        return;
    
    [self.dragScrollTimerLink invalidate];
    self.dragScrollTimerLink = nil;
}

@end
