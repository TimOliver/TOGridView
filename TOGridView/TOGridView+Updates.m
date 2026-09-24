//
//  TOGridView+Updates.m
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

const NSTimeInterval TOGridViewReorderSpringDuration = 0.35;
const NSTimeInterval TOGridViewReorderStaggerDelay = 0.03;

void TOGridViewAnimateReordering(NSTimeInterval delay, void (^animations)(void), void (^completion)(BOOL))
{
    // A critically damped spring gives the cascade a quick response and a soft landing.
    if (@available(iOS 17.0, *)) {
        [UIView animateWithSpringDuration:TOGridViewReorderSpringDuration bounce:0.0 initialSpringVelocity:0.0 delay:delay
                                 options:UIViewAnimationOptionBeginFromCurrentState
                              animations:animations completion:completion];
    } else {
        [UIView animateWithDuration:TOGridViewReorderSpringDuration delay:delay usingSpringWithDamping:1.0 initialSpringVelocity:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:animations completion:completion];
    }
}

@implementation TOGridView (Updates)

- (void)updateVisibleCellKeysWithDictionary:(NSDictionary<NSNumber *, NSNumber *> *)updatedCells
{
    _cellLayoutGeneration++;
    //Make a copy off the main list to work off (So we don't overwrite older values as we go)
    NSDictionary<NSNumber *, TOGridViewCell *> *visibleCellsCopy = [self.visibleCells copy];
    
    [updatedCells enumerateKeysAndObjectsUsingBlock:^(NSNumber *oldKey, NSNumber *newKey, BOOL *stop) {
        TOGridViewCell *cell = visibleCellsCopy[oldKey];
        if (cell == nil)
            return;
        
        //flush the object out, regardless of key
        [self.visibleCells removeObjectsForKeys:[self.visibleCells allKeysForObject:cell]];
        
        //add it back in as the new one
        [self.visibleCells setObject:cell forKey:newKey];
    }];
}

- (void)updateSelectedCellKeysWithDictionary:(NSDictionary<NSNumber *, NSNumber *> *)updatedCells
{
    if (self.selectedCells.count == 0)
        return;
    
    //Make a copy off the main list to work off (So we don't overwrite older values as we go)
    NSSet<NSNumber *> *selectedCellsCopy = [self.selectedCells copy];
    
    [updatedCells enumerateKeysAndObjectsUsingBlock:^(NSNumber *oldKey, NSNumber *newKey, BOOL *stop) {
        //skip if the cell isn't selected
        if ([selectedCellsCopy containsObject:oldKey] == NO)
            return;
        
        [self.selectedCells removeObject:oldKey];
        [self.selectedCells addObject:newKey];
    }];
}

- (BOOL)performInsertionAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    if (indices.count == 0) {
        if (completionHandler)
            completionHandler();
        return YES;
    }

    // Indices describe positions in the final data source, as in UICollectionView.
    NSInteger newNumberOfCells = [self.dataSource numberOfCellsInGridView:self];
    if (newNumberOfCells != self.numberOfCells + (NSInteger)indices.count)
        [NSException raise:NSInternalInconsistencyException format:@"Update the data source before insertion: expected %ld cells, got %ld.", (long)(self.numberOfCells + indices.count), (long)newNumberOfCells];

    NSMutableIndexSet *insertedIndices = [NSMutableIndexSet indexSet];
    for (NSNumber *number in indices) {
        NSInteger index = number.integerValue;
        if (index < 0 || index >= newNumberOfCells || ![number isEqualToNumber:@(index)] || [insertedIndices containsIndex:index])
            [NSException raise:NSInvalidArgumentException format:@"Insertion indices must be unique positions in the updated data source: %@.", indices];
        [insertedIndices addIndex:index];
    }

    [self invalidatePrefetching];
    [self finishInsertion];
    self.pauseCellLayout = YES;
    self.pauseCrossfadeAnimation = YES;
    self.numberOfCells = newNumberOfCells;

    NSInteger (^newIndexForOldIndex)(NSInteger) = ^NSInteger(NSInteger index) {
        __block NSInteger newIndex = index;
        [insertedIndices enumerateIndexesUsingBlock:^(NSUInteger insertedIndex, BOOL *stop) {
            if (insertedIndex <= newIndex)
                newIndex++;
            else
                *stop = YES;
        }];
        return newIndex;
    };

    // Build new stores atomically, so adjacent indices cannot overwrite each other.
    NSMutableDictionary<NSNumber *, TOGridViewCell *> *remappedCells = [NSMutableDictionary dictionary];
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        remappedCells[@(newIndexForOldIndex(index))] = cell;
    }];
    self.visibleCells = remappedCells;
    if (self.selectedCells) {
        NSMutableSet<NSNumber *> *remappedSelection = [NSMutableSet set];
        for (NSNumber *index in self.selectedCells)
            [remappedSelection addObject:@(newIndexForOldIndex(index.integerValue))];
        self.selectedCells = remappedSelection;
    }

    self.contentSize = [self contentSizeOfScrollView];
    NSRange visibleRange = self.visibleCellRange;
    NSMutableArray<TOGridViewCell *> *newCells = [NSMutableArray array];
    if (animated) {
        // The amount of view work is bounded by the viewport, not the batch size.
        for (NSUInteger i = 0; i < visibleRange.length; i++) {
            NSInteger index = visibleRange.location + i;
            if (self.visibleCells[@(index)])
                continue;
            TOGridViewCell *cell = [self addCellAtIndex:index dataSourceIndex:index];
            if ([insertedIndices containsIndex:index]) {
                cell.hidden = YES;
                [newCells addObject:cell];
            } else {
                NSUInteger precedingInsertions = [insertedIndices countOfIndexesInRange:NSMakeRange(0, index)];
                cell.frame = [self rectOfCellAtIndex:index - precedingInsertions];
            }
        }
    }

    void (^moveCells)(void) = ^{
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            cell.frame = [self rectOfCellAtIndex:index];
        }];
        if (self.footerView)
            self.footerView.frame = [self footerViewFrame];
    };

    if (!animated) {
        [UIView performWithoutAnimation:moveCells];
        self.pauseCellLayout = NO;
        self.pauseCrossfadeAnimation = NO;
        [self layoutCells];
        if (completionHandler)
            completionHandler();
        return YES;
    }

    self.insertingCells = newCells;
    self.insertionCompletionHandler = completionHandler;
    NSUInteger generation = ++self.insertionGeneration;
    void (^finish)(void) = ^{
        if (generation != self.insertionGeneration)
            return;
        [self finishInsertionWithLayout:YES];
    };
    // Match deletion's cascade: each row wrap adds a small delay, while cells
    // moving within the same row travel together. Unchanged cells add no delay.
    NSMutableArray<NSNumber *> *movingIndices = [NSMutableArray array];
    for (NSNumber *key in [[self.visibleCells allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        TOGridViewCell *cell = self.visibleCells[key];
        if (!CGRectEqualToRect(cell.frame, [self rectOfCellAtIndex:key.integerValue]))
            [movingIndices addObject:key];
    }
    CGRect footerFrame = [self footerViewFrame];
    BOOL movesFooter = self.footerView && !CGRectEqualToRect(self.footerView.frame, footerFrame);
    BOOL hasMovement = movingIndices.count > 0 || movesFooter;
    // Movement and reveal overlap; finish only after both have settled.
    __block NSUInteger remainingAnimations = movingIndices.count + (movesFooter ? 1 : 0) + (newCells.count > 0 ? 1 : 0);
    void (^didFinishAnimation)(BOOL) = ^(BOOL finished) {
        if (generation != self.insertionGeneration)
            return;
        if (--remainingAnimations == 0)
            finish();
    };

    if (remainingAnimations == 0) {
        finish();
        return YES;
    }

    NSUInteger stagger = 0;
    for (NSNumber *key in movingIndices) {
        TOGridViewCell *cell = self.visibleCells[key];
        CGRect frame = [self rectOfCellAtIndex:key.integerValue];
        if ((NSInteger)CGRectGetMinY(cell.frame) != (NSInteger)CGRectGetMinY(frame)) {
            [self.cellContainerView bringSubviewToFront:cell];
            if ((NSInteger)CGRectGetMinX(cell.frame) != (NSInteger)CGRectGetMinX(frame))
                stagger++;
        }
        TOGridViewAnimateReordering(stagger * TOGridViewReorderStaggerDelay, ^{
            cell.frame = frame;
        }, didFinishAnimation);
    }
    if (movesFooter) {
        TOGridViewAnimateReordering(stagger * TOGridViewReorderStaggerDelay, ^{
            self.footerView.frame = footerFrame;
        }, didFinishAnimation);
    }
    if (newCells.count > 0) {
        void (^revealNewCells)(void) = ^{
            // A reload, resize or later edit may have already recycled these cells.
            if (generation != self.insertionGeneration)
                return;
            [UIView performWithoutAnimation:^{
                for (TOGridViewCell *cell in newCells) {
                    cell.hidden = NO;
                    cell.alpha = 0.0;
                    cell.transform = CGAffineTransformMakeScale(0.5, 0.5);
                }
            }];
            [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                for (TOGridViewCell *cell in newCells) {
                    cell.alpha = 1.0;
                    cell.transform = CGAffineTransformIdentity;
                }
            } completion:didFinishAnimation];
        };
        // Reveal new cells while the movement is still settling.
        NSTimeInterval revealDelay = hasMovement && UIView.areAnimationsEnabled ? 0.2 : 0;
        if (revealDelay > 0)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(revealDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), revealNewCells);
        else
            revealNewCells();
    }
    return YES;
}

/* End an insertion before a reload, resize or subsequent edit can reuse its cells. */
- (void)finishInsertion
{
    [self finishInsertionWithLayout:NO];
}

- (void)finishInsertionWithLayout:(BOOL)layout
{
    if (self.insertingCells == nil)
        return;
    self.insertionGeneration++;
    NSArray<TOGridViewCell *> *cells = self.insertingCells;
    void (^completion)(void) = self.insertionCompletionHandler;
    self.insertingCells = nil;
    self.insertionCompletionHandler = nil;
    self.pauseCellLayout = NO;
    self.pauseCrossfadeAnimation = NO;
    [UIView performWithoutAnimation:^{
        for (TOGridViewCell *cell in cells) {
            cell.hidden = NO;
            cell.alpha = 1.0;
            cell.transform = CGAffineTransformIdentity;
        }
        for (TOGridViewCell *cell in self.visibleCells.allValues)
            [cell.layer removeAllAnimations];
    }];
    // Normalize animated cells before layout can recycle and reconfigure them.
    if (layout) {
        [self layoutCells];
        NSUInteger capacity = MAX(self.visibleCells.count, (NSUInteger)(ceil(CGRectGetHeight(self.bounds) / self.rowHeight) * self.numberOfCellsPerRow));
        NSUInteger spareCells = capacity - self.visibleCells.count;
        if (self.recycledCells.count > spareCells)
            [self.recycledCells removeObjectsInRange:NSMakeRange(spareCells, self.recycledCells.count - spareCells)];
    }
    if (completion)
        completion();
}

- (BOOL)performDeletionAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    if ([indices count] == 0)
        return YES;

    [self invalidatePrefetching];
    [self finishInsertion];
    
    //cancel the cell dragging if it's active
    if (self.editing)
        [self cancelDraggingCell];
    
    NSRange visibleCellRange = [self rangeOfVisibleCellsInBounds:self.bounds];
    
    //Hang onto the lowest cell necessary to animate all visible cells
    //This can either be the very lowest cell targeted for deletion, or simply the first visible cell on screen
    __block NSInteger firstCellToAnimate = self.numberOfCells;
    
    //Hang onto the final cell that will be animated after the offset is applied
    __block NSInteger lastVisibleCell = 0;
    
    //Make sure that the dataSource has already updated the number of cells, otherwise all our calculations below will break
    NSInteger newNumberOfCells = [self.dataSource numberOfCellsInGridView:self];
    if (newNumberOfCells > self.numberOfCells - [indices count])
        [NSException raise:@"Invalid dataSource!" format:@"Data source needs to be updated before cells can be deleted. Number of cells was %ld when it needed to be %ld", (long)self.numberOfCells, (long)newNumberOfCells];
    
    //make the new number of cells formal now since we'll need it in a bunch of calculations below
    self.numberOfCells = newNumberOfCells;
    
    //go through each cell and work out which cells-to-delete are visible.
    NSMutableArray<TOGridViewCell *> *visibleCellsToDelete = [NSMutableArray array];
    for (NSNumber *number in indices)
    {
        NSInteger deleteIndex = number.integerValue;
        
        //remember the selected cell indices we need to delete
        [self.selectedCells removeObject:number];
        
        //if the cell is within the visible screen region, prep it for animation
        if (NSLocationInRange(deleteIndex, visibleCellRange))
        {
            TOGridViewCell *cell = [self cellForIndex:deleteIndex];
            if (cell == nil)
                continue;
            
            //reset its animation properties, just in case
            cell.alpha      = 1.0f;
            cell.transform  = CGAffineTransformIdentity;
            
            [visibleCellsToDelete addObject:cell];
        }
        
        if (deleteIndex <= firstCellToAnimate)
            firstCellToAnimate = deleteIndex;
    }
    
    //work out what the new index for each visible cell will be after the targeted cells have been deleted
    NSMutableDictionary<NSNumber *, NSNumber *> *updatedCellKeys = [NSMutableDictionary dictionary];
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        NSInteger offset = 0;
        for (NSNumber *number in indices)
        {
            if (index >= number.integerValue)
                offset++;
        }
        
        //Check to see if this cell is after the lowest cell in the deletion stack
        BOOL shouldAnimateFromFirstVisibleCell = (index == visibleCellRange.location && index > firstCellToAnimate);
        
        //Set the new index for this cell after the targeted cells are removed around it.
        //cap it off at 0 (If it's negative, it's definitely going to get deleted) to prevent any strange wrapping
        NSInteger newIndex = MAX(0, index - offset);
        
        //note the cell that changed so we can update visibleCells once this loop is complete
        [updatedCellKeys setObject:@(newIndex) forKey:@(index)];
        
        //if this cell is selected, update its index in the selected array
        if (self.allowsSelectionDuringEditing) {
            NSNumber *prevIndex = @(index);
            if ([self.selectedCells containsObject:prevIndex])
            {
                [self.selectedCells removeObject:prevIndex];
                [self.selectedCells addObject:@(newIndex)];
            }
        }
        
        if (shouldAnimateFromFirstVisibleCell)
            firstCellToAnimate = newIndex;
        
        //hang onto the final cell to use as the origin if we need to requeue any cells to animate in
        if (index > lastVisibleCell)
            lastVisibleCell = newIndex;
        
        //just make sure we clean up from a previous animation
        cell.hidden = NO;
    }];
    
    //fade out all the cells
    if (animated)
    {
        //disable scrolling to allow this animation to complete
        [self setUserInteractionEnabled:NO];
        
        //halt animation
        CGPoint scrollPoint = self.contentOffset;
        [self setContentOffset:scrollPoint animated:NO];
        
        //stop 'layoutCells' from interacting with this (Since 'layoutSubviews' gets triggered by iOS everytime we add/remove a cell)
        self.pauseCellLayout = YES;
        self.pauseCrossfadeAnimation = YES;
        
        //Animate each of the selected cells to fade out
        [UIView animateWithDuration:0.15f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
            for (TOGridViewCell *cell in visibleCellsToDelete)
            {
                cell.alpha = 0.0f;
                cell.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.5f, 0.5f);
            }
        } completion:^(BOOL done) {
            //once done, recycle each cell that was animated out and add it back to the pool
            for (TOGridViewCell *cell in visibleCellsToDelete)
            {
                //once animated out, recycle the cells
                [cell removeFromSuperview];
                
                //reset the cell
                cell.transform = CGAffineTransformIdentity;
                cell.alpha = 1.0f;
                [cell setSelected:NO animated:NO];
                
                //recycle the cell
                [self.visibleCells removeObjectsForKeys:[self.visibleCells allKeysForObject:cell]];
                [self.recycledCells addObject:cell];
            }
            
            //update the remaining cells with the new values
            [self updateVisibleCellKeysWithDictionary:updatedCellKeys];
            [self updateSelectedCellKeysWithDictionary:updatedCellKeys];
            
            //Now that the cells are out of the hierarchy, re-calculate which cells should be visible on screen now
            NSRange newVisibleCells = [self visibleCellRange];
            //The next cell index below the old to use as the origin basis for all the new cells we create down there
            NSInteger originCell = (newVisibleCells.location+newVisibleCells.length);
            
            //Go through and create each new cell, with their new IDs but leave them in their previous position
            for (NSInteger i=0; i < newVisibleCells.length; i++)
            {
                NSInteger newIndex = newVisibleCells.location+i;
                
                TOGridViewCell *newCell = [self cellForIndex:newIndex];
                if (newCell)
                    continue;
                
                newCell         = [self.dataSource gridView:self cellForIndex:newIndex];
                CGRect frame    = newCell.frame;
                frame.origin    = [self originOfCellAtIndex:originCell++];
                frame.size      = [self sizeOfCellAtIndex:newVisibleCells.location+i];
                newCell.frame   = frame;
                [newCell setEditing:self.editing animated:NO];
                [self.visibleCells setObject:newCell forKey:@(newIndex)];
                
                [self.cellContainerView addSubview:newCell];
            }
            
            //sort the visible cells into their respective order so we can sort it in the right order
            NSArray<NSNumber *> *sortedVisibleCellIndices = [[self.visibleCells allKeys] sortedArrayUsingSelector:@selector(compare:)];
            
            void (^completionBlock)(void) = ^{
                //reset all of the cells
                self.pauseCellLayout = NO;
                [self layoutCells];
                
                //clean out the excess recycled cells
                NSInteger maxNumberOfCellsInScreen = ceil(CGRectGetHeight(self.bounds) / self.rowHeight) * self.numberOfCellsPerRow;
                NSInteger numberOfCells = [self.recycledCells count] + [self.visibleCells count];
                if (numberOfCells > maxNumberOfCellsInScreen && [self.visibleCells count] <= maxNumberOfCellsInScreen)
                {
                    while (numberOfCells > maxNumberOfCellsInScreen)
                    {
                        if ([self.recycledCells count] == 0)
                            break;
                        
                        TOGridViewCell *cell = self.recycledCells[0];
                        if (cell == nil)
                            continue;
                        
                        [self.recycledCells removeObject:cell];
                        cell = nil;
                        
                        numberOfCells--;
                    }
                }
                
                //reenable user interaction
                [self setUserInteractionEnabled:YES];
                
                [UIView animateWithDuration:0.30f animations:^{
                    self.contentSize = [self contentSizeOfScrollView];
                    
                    if (self.contentOffset.y + CGRectGetHeight(self.bounds) > self.contentSize.height) {
                        CGPoint contentOffset = self.contentOffset;
                        contentOffset.y = self.contentSize.height - CGRectGetHeight(self.bounds);
                        self.contentOffset = contentOffset;
                    }
                    
                    if (self.footerView)
                        self.footerView.frame = [self footerViewFrame];
                    
                } completion:^(BOOL finished) {
                    self.pauseCrossfadeAnimation = NO;
                    
                    if (completionHandler)
                        completionHandler();
                }];
            };
            
            if (sortedVisibleCellIndices.count) {
                // Wait for every spring to settle before layout can recycle cells.
                __block NSUInteger remainingAnimations = sortedVisibleCellIndices.count;
                //reset the size of all of the remaining cells before they move
                NSInteger i = 0; //i is used to add a cascading delay in front of cells
                for (NSNumber *key in sortedVisibleCellIndices)
                {
                    NSInteger index = key.integerValue;
                    TOGridViewCell *cell = self.visibleCells[key];
                    
                    //change the size of the cell as necessary
                    CGRect frame = cell.frame;
                    frame.size = [self sizeOfCellAtIndex:index];
                    cell.frame = frame;
                    
                    [cell setSelected:NO animated:NO];
                    
                    //change the origin
                    CGPoint newOrigin = [self originOfCellAtIndex:index];
                    if ((NSInteger)cell.frame.origin.y != (NSInteger)newOrigin.y)
                        [self.cellContainerView bringSubviewToFront:cell];
                    
                    //if this cell is truly moving a sizable distance, add a delay to the animation
                    //(Otherwise it'll look like cells down the page take longer to move than others)
                    if ((NSInteger)cell.frame.origin.y != (NSInteger)newOrigin.y && (NSInteger)cell.frame.origin.x != (NSInteger)newOrigin.x)
                        i++;
                    
                    TOGridViewAnimateReordering(i * TOGridViewReorderStaggerDelay, ^{
                        CGRect frame = cell.frame;
                        frame.origin = newOrigin;
                        
                        //cap how far it can move up so it doesn't just shoot off so quickly that it becomes invisible
                        if (CGRectGetMaxY(cell.frame) - (newOrigin.y+CGRectGetHeight(self.bounds)) > CGRectGetHeight(self.bounds))
                            frame.origin.y = CGRectGetMinY(cell.frame) - (CGRectGetHeight(self.bounds)+CGRectGetHeight(cell.frame));
                        
                        cell.frame = frame;
                    }, ^(BOOL finished) {
                        if (--remainingAnimations != 0)
                            return;
                        
                        completionBlock();
                    });
                }
            }
            else {
                completionBlock();
            }
        }];
    }
    else
    {
        //loop through all of the cells to delete and remove them
        for (TOGridViewCell *cell in visibleCellsToDelete)
        {
            [cell removeFromSuperview];
            [self.visibleCells removeObjectsForKeys:[self.visibleCells allKeysForObject:cell]];
            [self.recycledCells addObject:cell];
        }
        
        [self updateVisibleCellKeysWithDictionary:updatedCellKeys];
        [self updateSelectedCellKeysWithDictionary:updatedCellKeys];
        
        //reposition all of the current cells with their new indices
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            cell.frame = (CGRect){[self originOfCellAtIndex:index], [self sizeOfCellAtIndex:index]};
        }];
        
        //reset the size of the content view to account for the new cells
        self.contentSize = [self contentSizeOfScrollView];
        
        //re-layout all of the cells and re-adding any new ones
        [self layoutCells];
        
        if (completionHandler)
            completionHandler();
    }
    
    return YES;
}

- (BOOL)performReloadAtIndices:(NSArray<NSNumber *> *)indices
{
    id<TOGridViewDataSource> dataSource = self.dataSource;
    if ([indices count] == 0)
        return YES;

    _cellLayoutGeneration++;
    [self invalidatePrefetching];
    [self finishInsertion];
    
    for (NSNumber *index in indices)
    {
        NSInteger cellIndex = index.integerValue;
        
        //if the cell isn't visisble, skip it
        TOGridViewCell *cell = [self cellForIndex:cellIndex];
        if (cell == nil)
            continue;
        
        CGRect frame = cell.frame;
        [cell removeFromSuperview];
        [self.visibleCells removeObjectForKey:@(cellIndex)];
        [self.recycledCells addObject:cell];
        cell = nil;
        
        cell = [dataSource gridView:self cellForIndex:cellIndex];
        cell.frame = frame;
        
        cell.draggable = NO;
        if (_gridViewFlags.dataSourceCanMoveCell) {
            if ([dataSource gridView:self canMoveCellAtIndex:cellIndex])
                cell.draggable = YES;
        }
        
        if (_gridViewFlags.dataSourceCanEditCell && self.editing)
            cell.editing = [dataSource gridView:self canEditCellAtIndex:cellIndex];
        else
            cell.editing = NO;
        
        [cell setNeedsLayout];
        
        [self.cellContainerView insertSubview:cell atIndex:0];
        
        [self.visibleCells setObject:cell forKey:index];
    }
    
    return YES;
}

- (BOOL)performSelectionAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated
{
    if (self.allowsSelectionDuringEditing == NO)
        return YES;
    
    for (NSNumber *index in indices)
    {
        NSInteger cellIndex = [index integerValue];
        
        if (_gridViewFlags.dataSourceCanEditCell) {
            if ([self.dataSource gridView:self canEditCellAtIndex:cellIndex] == NO)
                continue;
        }
        
        if ([self.selectedCells containsObject:@(cellIndex)] == NO)
            [self.selectedCells addObject:@(cellIndex)];
        
        //if the cell is visible on-screen, set its state to selected
        TOGridViewCell *cell = [self cellForIndex:cellIndex];
        if (cell)
            [cell setSelected:YES animated:animated];
    }
    
    return YES;
}

- (BOOL)performDeselectionAtIndices:(NSArray<NSNumber *> *)indices
{
    for (NSNumber *index in indices)
    {
        NSInteger cellIndex = [index integerValue];
        
        //update the entry in the array to 'selected'
        [self.selectedCells removeObject:@(cellIndex)];
        
        //if the cell is visible on-screen, set its state to selected
        TOGridViewCell *cell = [self cellForIndex:cellIndex];
        if (cell)
            [cell setSelected:NO animated:NO];
    }
    
    return YES;
}

- (void)updateCellsForEditingAnimated:(BOOL)animated
{
    /* If we ended editing, make sure to kill the scroll timer. */
    if (self.editing == NO)
    {
        //flush the selected cells
        self.selectedCells = nil;
        
        [self stopAnimatingScrollViewDragging];
        
        //deselect and exit edit mode for all visible cells
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            [cell setSelected:NO animated:NO];
            [cell setEditing:NO animated:animated];
        }];
        
        for (TOGridViewCell *cell in self.recycledCells)
        {
            [cell setSelected:NO animated:NO];
            [cell setEditing:NO animated:animated];
        }
    }
    else
    {
        //re-init the list of selected cells
        if (self.allowsSelectionDuringEditing)
            self.selectedCells = [NSMutableSet set];
        
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            [cell setSelected:NO animated:NO];
            
            if (self->_gridViewFlags.dataSourceCanEditCell && [self.dataSource gridView:self canEditCellAtIndex:index])
                [cell setEditing:YES animated:animated];
        }];
    }
}

@end
