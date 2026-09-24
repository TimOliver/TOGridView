//
//  TOGridView+Prefetching.m
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

// A display link retains its target. Keep the grid weak so queued preparation cannot
// extend the view's lifetime, including when it is removed while work is pending.
@interface TOGridViewCellPreparationTarget : NSObject
@property (nonatomic, weak) TOGridView *grid;
- (void)tick:(CADisplayLink *)link;
@end

@implementation TOGridViewCellPreparationTarget
- (void)tick:(CADisplayLink *)link
{
    TOGridView *grid = self.grid;
    if (grid != nil)
        [grid prepareNextCell:link];
    else
        [link invalidate];
}
@end

@implementation TOGridView (Prefetching)

- (void)invalidateCellPreparation
{
    _cellPreparationGeneration++;
    [self resetCellPreparationBudget];
    [_cellPreparationDisplayLink invalidate];
    _cellPreparationDisplayLink = nil;
    _cellPreparationCandidates = nil;
    _preparedCellTraits = nil;
    if (_preparedCells.count > 0) {
        [self.recycledCells addObjectsFromArray:_preparedCells.allValues];
        [_preparedCells removeAllObjects];
    }
}

- (void)resetCellPreparationBudget
{
    _cellPreparationDeadlineMisses = 0;
    _cellPreparationSuspendedForBudget = NO;
    _estimatedCellPreparationDuration = 0.001;
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
    [self invalidateCellPreparation];
    [self.recycledCells removeAllObjects];
    // Do not immediately refill the cache in response to a queued prefetch update.
    // Resume when a later visible-range/layout change needs reconciliation.
    _cellPreparationSuspendedForMemoryWarning = YES;
}

- (NSRange)cellPreparationRangeForVisibleRange:(NSRange)visibleRange
{
    if (!self.cellPrefetchingEnabled || _cellPreparationSuspendedForMemoryWarning ||
        _prefetchNeedsDataSourceReload || self.window == nil || self.hidden || self.window.hidden ||
        self.dataSource == nil || self.pauseCellLayout || self.freezeLayoutSubviews ||
        self.draggingCell != nil || self.insertingCells != nil || self.boundsChangeAnimation != nil ||
        CGRectIsEmpty(self.bounds) || self.rowHeight <= 0 || visibleRange.length == 0 ||
        self.numberOfCells <= 0 || visibleRange.location >= (NSUInteger)self.numberOfCells)
        return NSMakeRange(0, 0);

    NSUInteger count = self.numberOfCells;
    NSUInteger distance = MAX(1, self.numberOfCellsPerRow);
    NSUInteger end = visibleRange.location + MIN(visibleRange.length, count - visibleRange.location);
    NSUInteger start = visibleRange.location - MIN(distance, visibleRange.location);
    end += MIN(distance, count - end);
    return NSMakeRange(start, end - start);
}

- (void)updateCellPreparation
{
    if (!self.cellPrefetchingEnabled)
        return;
    if (_preparedCellTraits != nil && ![_preparedCellTraits isEqual:self.traitCollection])
        [self invalidateCellPreparation];
    NSRange visibleRange = self.rowHeight > 0 ? self.visibleCellRange : NSMakeRange(0, 0);
    NSRange range = [self cellPreparationRangeForVisibleRange:visibleRange];
    if (range.length == 0) {
        [self invalidateCellPreparation];
        return;
    }
    if (self.bounds.origin.y != _previousPreparationOffset)
        _preparingCellsUpwards = self.bounds.origin.y < _previousPreparationOffset;
    _previousPreparationOffset = self.bounds.origin.y;

    for (NSNumber *key in _preparedCells.allKeys) {
        if (!NSLocationInRange(key.unsignedIntegerValue, range)) {
            TOGridViewCell *cell = _preparedCells[key];
            if (cell != nil)
                [self.recycledCells addObject:cell];
            [_preparedCells removeObjectForKey:key];
        }
    }
    NSMutableArray<NSNumber *> *before = [NSMutableArray array];
    NSMutableArray<NSNumber *> *after = [NSMutableArray array];
    for (NSUInteger index = visibleRange.location; index > range.location; index--) {
        NSNumber *key = @(index - 1);
        if (_preparedCells[key] == nil && self.visibleCells[key] == nil)
            [before addObject:key];
    }
    for (NSUInteger index = NSMaxRange(visibleRange); index < NSMaxRange(range); index++) {
        NSNumber *key = @(index);
        if (_preparedCells[key] == nil && self.visibleCells[key] == nil)
            [after addObject:key];
    }
    _cellPreparationCandidates = _preparingCellsUpwards ? [before arrayByAddingObjectsFromArray:after] : [after arrayByAddingObjectsFromArray:before];
    if (_cellPreparationCandidates.count == 0) {
        [_cellPreparationDisplayLink invalidate];
        _cellPreparationDisplayLink = nil;
    } else if (!_cellPreparationSuspendedForBudget && _cellPreparationDisplayLink == nil) {
        TOGridViewCellPreparationTarget *target = [TOGridViewCellPreparationTarget new];
        target.grid = self;
        _cellPreparationDisplayLink = [CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
        float maximum = self.window.screen.maximumFramesPerSecond;
        _cellPreparationDisplayLink.preferredFrameRateRange = CAFrameRateRangeMake(MIN(30, maximum), maximum, maximum);
        [_cellPreparationDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)prepareNextCell:(CADisplayLink *)link
{
    if (link != _cellPreparationDisplayLink)
        return;
    // Leave some time for the rest of UIKit's frame. This is a best-effort estimate:
    // one client's synchronous cell callback cannot be interrupted halfway through.
    CFTimeInterval reserve = MIN(0.002, (link.targetTimestamp - link.timestamp) * 0.25);
    [self prepareCellBeforeDeadline:link.targetTimestamp - reserve];
}

- (void)prepareCellBeforeDeadline:(CFTimeInterval)deadline
{
    [self updateCellPreparation];
    if (_cellPreparationCandidates.count == 0 || _cellPreparationSuspendedForBudget)
        return;
    CFTimeInterval start = CACurrentMediaTime();
    if (deadline - start < _estimatedCellPreparationDuration) {
        // A costly sample (or consistently late callbacks) must not leave an idle
        // display link spinning forever. Keep ready cells, and retry only after a
        // visible-range change or invalidation gives us a new preparation context.
        if (++_cellPreparationDeadlineMisses >= 3) {
            _cellPreparationSuspendedForBudget = YES;
            [_cellPreparationDisplayLink invalidate];
            _cellPreparationDisplayLink = nil;
        }
        return;
    }
    _cellPreparationDeadlineMisses = 0;

    NSNumber *key = _cellPreparationCandidates.firstObject;
    NSUInteger generation = _cellPreparationGeneration;
    CGRect bounds = self.bounds;
    UITraitCollection *traits = self.traitCollection;
    __block TOGridViewCell *cell = nil;
    BOOL animationsEnabled = UIView.areAnimationsEnabled;
    [UIView setAnimationsEnabled:NO];
    @try {
        [traits performAsCurrentTraitCollection:^{
            cell = [self requestCellAtIndex:key.integerValue];
            if (generation == self->_cellPreparationGeneration) {
                [self configureCell:cell atIndex:key.integerValue prepared:NO];
                [cell setNeedsLayout];
                [cell layoutIfNeeded];
            }
        }];
    } @finally {
        [UIView setAnimationsEnabled:animationsEnabled];
    }
    // React immediately to expensive cells, then allow the estimate to decay gradually.
    if (generation == _cellPreparationGeneration)
        _estimatedCellPreparationDuration = MAX(0.001, MAX(CACurrentMediaTime() - start, _estimatedCellPreparationDuration * 0.9));
    if (generation == _cellPreparationGeneration && CGRectEqualToRect(bounds, self.bounds) &&
        [traits isEqual:self.traitCollection] && cell.superview == nil) {
        if (_preparedCells == nil)
            _preparedCells = [NSMutableDictionary dictionary];
        _preparedCells[key] = cell;
        _preparedCellTraits = traits;
    } else if (cell.superview == nil) {
        // A callback may reload/disable the grid. Never publish that stale result.
        [self.recycledCells addObject:cell];
    }
    [self updateCellPreparation];
}

- (void)invalidatePrefetching
{
    _prefetchGeneration++;
    [self invalidateCellPreparation];
    [self schedulePrefetchUpdate];
}

- (void)schedulePrefetchUpdate
{
    // No allocation or queue work for clients that have not opted in.
    if (_prefetchDataSource == nil && _prefetchedIndices.count == 0 && !self.cellPrefetchingEnabled)
        return;
    _prefetchUpdateVersion++;
    if (_prefetchUpdateScheduled)
        return;
    _prefetchUpdateScheduled = YES;
    __weak TOGridView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TOGridView *grid = weakSelf;
        if (grid == nil)
            return;
        grid->_prefetchUpdateScheduled = NO;
        [grid updatePrefetching];
        [grid updateCellPreparation];
    });
}

- (void)updatePrefetching
{
    id<TOGridViewDataSourcePrefetching> source = self.prefetchDataSource;
    id<TOGridViewDataSourcePrefetching> previousSource = _prefetchRequestSource;
    NSUInteger generation = _prefetchGeneration;
    NSUInteger version = _prefetchUpdateVersion;
    CGRect bounds = self.bounds;
    NSMutableIndexSet *desired = [NSMutableIndexSet indexSet];
    NSRange visibleRange = NSMakeRange(0, 0);
    if (source != nil && self.dataSource != nil && self.window != nil && self.prefetchRowCount > 0 &&
        self.numberOfCells > 0 && self.numberOfCellsPerRow > 0 && self.rowHeight > 0 &&
        !CGRectIsEmpty(bounds) && !_prefetchNeedsDataSourceReload && !self.pauseCellLayout && !self.freezeLayoutSubviews &&
        self.draggingCell == nil && self.insertingCells == nil) {
        visibleRange = [self rangeOfVisibleCellsInBounds:bounds];
        NSUInteger count = self.numberOfCells;
        if (visibleRange.length > 0 && visibleRange.location < count) {
            // Clamp before multiplying, including extremely large caller-supplied row counts.
            NSUInteger columns = self.numberOfCellsPerRow;
            NSUInteger distance = self.prefetchRowCount > count / columns ? count : self.prefetchRowCount * columns;
            NSUInteger end = visibleRange.location + MIN(visibleRange.length, count - visibleRange.location);
            visibleRange.length = end - visibleRange.location;
            NSUInteger start = visibleRange.location - MIN(distance, visibleRange.location);
            [desired addIndexesInRange:NSMakeRange(start, visibleRange.location - start)];
            [desired addIndexesInRange:NSMakeRange(end, MIN(distance, count - end))];
            // Geometry may have changed before UIKit gets to its next layout pass.
            for (NSNumber *index in self.visibleCells)
                [desired removeIndex:index.unsignedIntegerValue];
            for (NSNumber *index in _preparedCells)
                [desired removeIndex:index.unsignedIntegerValue];
        } else {
            visibleRange = NSMakeRange(0, 0);
        }
    }

    NSMutableIndexSet *cancelled = [_prefetchedIndices mutableCopy] ?: [NSMutableIndexSet indexSet];
    BOOL sameRequests = previousSource == source && _prefetchRequestGeneration == generation;
    if (sameRequests) {
        [cancelled removeIndexes:desired];
        // A newly visible item may still be waiting for layout to call cellForIndex:.
        // Keep its load alive until addCellAtIndex: hands it to the data source.
        [cancelled removeIndexesInRange:visibleRange];
    }
    NSMutableIndexSet *retained = [_prefetchedIndices mutableCopy] ?: [NSMutableIndexSet indexSet];
    [retained removeIndexes:cancelled];
    _prefetchedIndices = retained;
    _prefetchRequestSource = source;
    _prefetchRequestGeneration = generation;

    // Publish the retained requests first, so a callback can safely disable, replace,
    // or reload the provider without cancelling the same request a second time.
    if (cancelled.count > 0 && [previousSource respondsToSelector:@selector(gridView:cancelPrefetchingForCellsAtIndices:)]) {
        NSMutableArray<NSNumber *> *indices = [NSMutableArray arrayWithCapacity:cancelled.count];
        [cancelled enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [indices addObject:@(index)]; }];
        [previousSource gridView:self cancelPrefetchingForCellsAtIndices:indices];
    }
    if (generation != _prefetchGeneration || version != _prefetchUpdateVersion || !CGRectEqualToRect(bounds, self.bounds)) {
        [self schedulePrefetchUpdate];
        return;
    }

    [desired removeIndexes:retained];
    if (desired.count > 0) {
        [_prefetchedIndices addIndexes:desired];
        NSMutableArray<NSNumber *> *indices = [NSMutableArray arrayWithCapacity:desired.count];
        [desired enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [indices addObject:@(index)]; }];
        [source gridView:self prefetchCellsAtIndices:indices];
    }
}

@end
