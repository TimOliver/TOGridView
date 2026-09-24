//
//  TOGridView.m
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

@implementation TOGridView

@dynamic delegate; // UIScrollView owns the weak delegate storage.
@synthesize cellSize = _cellSize;
@synthesize dataSource = _dataSource;
@synthesize prefetchDataSource = _prefetchDataSource;

#pragma mark - View Lifecycle

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        // Default configuration for the UIScrollView
        self.bounces                    = YES;
        self.scrollsToTop               = YES;
        self.backgroundColor            = [UIColor blackColor];
        self.scrollEnabled              = YES;
        self.alwaysBounceVertical       = YES;
        
        // Disable the ability to tap multiple cells at the same time. (Otherwise it gets REALLY messy)
        self.multipleTouchEnabled       = NO;
        self.exclusiveTouch             = YES;
        
        // The sets to handle the recycling and repurposing/reuse of cells
        self.recycledCells              = [NSMutableArray array];
        self.visibleCells               = [NSMutableDictionary dictionary];
        self.cellContainerView          = [[UIView alloc] initWithFrame:self.bounds];
        self.cellContainerView.bounds   = self.bounds;
        [self insertSubview:self.cellContainerView atIndex:0];
        
        // Default settings for when dragging cells near the boundaries of the grid view
        self.dragScrollBoundaryDistance = 80;
        self.dragScrollMaxVelocity      = 20;
        
        // Default state handling for touch events
        self.numberOfCellsPerRow        = 1;
        self.draggingOverIndex          = -1;
        self.draggingCellIndex          = -1;
        _prefetchRowCount               = 2;
        _estimatedCellPreparationDuration = 0.001;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(didReceiveMemoryWarning:)
                                                   name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [_cellPreparationDisplayLink invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (instancetype)initWithFrame:(CGRect)frame withCellClass:(Class)cellClass
{
    if (self = [self initWithFrame:frame])
        [self registerCellClass:cellClass];
    
    return self;
}

- (void)registerCellClass:(Class)cellClass
{
    if (cellClass != Nil && ![cellClass isSubclassOfClass:TOGridViewCell.class])
        [NSException raise:NSInvalidArgumentException format:@"Cell classes must inherit from TOGridViewCell."];
    self.cellClass = cellClass;
    [self invalidateCellPreparation];
    [self schedulePrefetchUpdate];
}

/* Kickstart the loading of the cells when this view is added to the view hierarchy */
- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    // Removal can happen while the owning controller and data source are deallocating.
    if (self.superview != nil)
        [self reloadGrid];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window == nil)
        [self invalidatePrefetching];
    else
        [self schedulePrefetchUpdate];
}

#pragma mark - Public Cell API

- (void)reloadGrid
{    
    [self invalidatePrefetching];
    [self finishInsertion];

    /* Use the delegate+dataSource to set up the rendering logistics of the cells */
    [self resetCellMetrics];
    
    /* Remove any existing cells */
    [self invalidateVisibleCells];
    
    /* Perform a redraw operation */
    [self layoutCells];
}

/* The origin of each cell */
- (CGPoint)originOfCellAtIndex:(NSInteger)cellIndex
{
    CGPoint origin = CGPointZero;
    
    origin.y    =   self.offsetFromHeader;                   /* The height of the header view */
    origin.y    +=  self.offsetOfCellsInRow;                 /* Relative offset of the cell in each row */
    origin.y    +=  self.cellPaddingInsets.top;            /* The inset padding arond the cells in the scrollview */
    origin.y    += (self.rowHeight * floor(cellIndex/self.numberOfCellsPerRow));
    
    origin.x    =  self.cellPaddingInsets.left;
    origin.x    += ((cellIndex % self.numberOfCellsPerRow) * (self.cellSize.width+self.widthBetweenCells));
    
    return origin;
}

- (CGSize)sizeOfCellAtIndex:(NSInteger)cellIndex
{
    CGSize cellSize = self.cellSize;
    
    //if there's supposed to be NO padding between the edge of the view and the cell,
    //and this cell is short by uneven necessity of the number of cells per row
    //(eg, 1024/3 on iPad = 341.333333333 pixels per cell :S), pad it out
    if ((self.cellPaddingInsets.left <= 0.0f + FLT_EPSILON && self.cellPaddingInsets.right <= 0.0f + FLT_EPSILON) && (cellIndex+1) % self.numberOfCellsPerRow == 0)
    {
        CGPoint org = [self originOfCellAtIndex:cellIndex];
        if (org.x + cellSize.width < CGRectGetWidth(self.bounds) + FLT_EPSILON)
            cellSize.width = CGRectGetWidth(self.bounds) - org.x;
    }
    
    return cellSize;
}

- (CGRect)rectOfCellAtIndex:(NSInteger)cellIndex
{
    return (CGRect){[self originOfCellAtIndex:cellIndex], [self sizeOfCellAtIndex:cellIndex]};
}

- (TOGridViewCell *)cellForIndex:(NSInteger)index
{
    return self.visibleCells[@(index)];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutGridSubviews];
}

- (void)scrollToCellAtIndex:(NSInteger)cellIndex toPosition:(TOGridViewScrollPosition)position animated:(BOOL)animated completed:(void (^)(void))completed
{
    CGPoint cellPosition = [self originOfCellAtIndex:cellIndex];
    CGFloat scrollPosition = 0.0f;
    
    switch (position)
    {
        case TOGridViewScrollPositionTop:
            scrollPosition = cellPosition.y;
            break;
        case TOGridViewScrollPositionMiddle:
            scrollPosition = cellPosition.y - (floor(CGRectGetHeight(self.bounds) * 0.5f) + floor(self.cellSize.height*0.5f));
            break;
        case TOGridViewScrollPositionBottom:
            scrollPosition = (cellPosition.y - CGRectGetHeight(self.bounds)) - self.cellSize.height;
            break;
        default:
            break;
    }
    
    scrollPosition = MAX(0.0f, scrollPosition);
    
    if (animated)
    {
        [UIView animateWithDuration:0.5f animations:^{
            self.contentOffset = CGPointMake(0.0f, scrollPosition);
        } completion:^(BOOL finished) {
            if (completed)
                completed();
        }];
    }
    else
    {
        self.contentOffset = CGPointMake(0.0f, scrollPosition);
        [self layoutCells];
        if (completed)
            completed();
    }
}

/* Dequeue a recycled cell for reuse */
- (TOGridViewCell *)dequeueReusableCell
{
    // Keep dispatching through the original selector for existing subclasses.
    return [self dequeReusableCell];
}

- (TOGridViewCell *)dequeReusableCell
{
    TOGridViewCell *cell = nil;
    
    //Grab a cell that was previously recycled
    if ([self.recycledCells count] > 0)
    {
        cell = self.recycledCells.lastObject;
        [self.recycledCells removeLastObject];
        [cell prepareForReuse];
        return cell;
    }
    
    //If there are no cells available, create a new one and set it up
    Class cellClass = self.cellClass ?: TOGridViewCell.class;
    cell = [[cellClass alloc] initWithFrame:(CGRect){CGPointZero, self.cellSize}];
    if (cell == nil)
        [NSException raise:NSInternalInconsistencyException format:@"The registered cell class must return a cell from initWithFrame:."];
    [cell setHighlighted:NO animated:NO];
    
    return cell;
}

- (UIView *)dequeueReusableDecorationView
{
    return nil;
}

#pragma mark - Cell Updates

- (BOOL)insertCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    return [self insertCellsAtIndices:@[@(index)] animated:animated completionHandler:nil];
}

- (BOOL)insertCellAtIndex:(NSInteger)index animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    return [self insertCellsAtIndices:@[@(index)] animated:animated completionHandler:completionHandler];
}

- (BOOL)insertCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated
{
    return [self insertCellsAtIndices:indices animated:animated completionHandler:nil];
}

- (BOOL)insertCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    return [self performInsertionAtIndices:indices animated:animated completionHandler:completionHandler];
}

- (BOOL)deleteCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    return [self deleteCellsAtIndices:@[@(index)] animated:animated completionHandler:nil];
}

- (BOOL)deleteCellAtIndex:(NSInteger)index animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    return [self deleteCellsAtIndices:@[@(index)] animated:animated completionHandler:completionHandler];
}

- (BOOL)deleteCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated
{
    return [self deleteCellsAtIndices:indices animated:animated completionHandler:nil];
}

- (BOOL)deleteCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    return [self performDeletionAtIndices:indices animated:animated completionHandler:completionHandler];
}

- (BOOL)reloadCellAtIndex:(NSInteger)index
{
    return [self reloadCellsAtIndices:@[@(index)]];
}

- (BOOL)reloadCellsAtIndices:(NSArray<NSNumber *> *)indices
{
    return [self performReloadAtIndices:indices];
}

/* This is called manually by the delegate object */
- (void)unhighlightCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    TOGridViewCell *cell = [self cellForIndex:index];
    if (cell)
        [cell setHighlighted:NO animated:animated];
}

- (NSArray<NSNumber *> *)indicesOfSelectedCells
{
    return [[self.selectedCells allObjects] sortedArrayUsingSelector:@selector(compare:)] ?: @[];
}

- (BOOL)selectCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    return [self selectCellsAtIndices:@[@(index)] animated:animated];
}

- (BOOL)selectCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated
{
    return [self performSelectionAtIndices:indices animated:animated];
}

- (BOOL)deselectCellAtIndex:(NSInteger)index
{
    return [self deselectCellsAtIndices:@[@(index)]];
}

- (BOOL)deselectCellsAtIndices:(NSArray<NSNumber *> *)indices
{
    return [self performDeselectionAtIndices:indices];
}

#pragma mark - Touch Handling

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self handleTouchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self handleTouchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self handleTouchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self handleTouchesCancelled:touches withEvent:event];
}

#pragma mark - Accessors

- (void)setCellPrefetchingEnabled:(BOOL)cellPrefetchingEnabled
{
    if (_cellPrefetchingEnabled == cellPrefetchingEnabled)
        return;
    _cellPrefetchingEnabled = cellPrefetchingEnabled;
    _cellPreparationSuspendedForMemoryWarning = NO;
    [self invalidateCellPreparation];
    [self schedulePrefetchUpdate];
}

- (void)setPrefetchDataSource:(id<TOGridViewDataSourcePrefetching>)prefetchDataSource
{
    if (_prefetchDataSource == prefetchDataSource)
        return;
    _prefetchDataSource = prefetchDataSource;
    [self invalidatePrefetching];
}

- (void)setPrefetchRowCount:(NSUInteger)prefetchRowCount
{
    if (_prefetchRowCount == prefetchRowCount)
        return;
    _prefetchRowCount = prefetchRowCount;
    if (prefetchRowCount == 0)
        [self invalidatePrefetching];
    else
        [self schedulePrefetchUpdate];
}

- (void)setDelegate:(id<TOGridViewDelegate>)delegate
{
    if (self.delegate == delegate)
        return;
    
    _cellLayoutGeneration++;
    [self invalidateCellPreparation];
    [self schedulePrefetchUpdate];
    [super setDelegate:delegate];
    
    //Update the flags with the state of the new delegate
    _gridViewFlags.delegateDecorationView        = [delegate respondsToSelector:@selector(gridView:decorationViewForRowWithIndex:)];
    _gridViewFlags.delegateBoundaryInsets        = [delegate respondsToSelector:@selector(boundaryInsetsForGridView:)];
    _gridViewFlags.delegateNumberOfCellsPerRow   = [delegate respondsToSelector:@selector(numberOfCellsPerRowForGridView:)];
    _gridViewFlags.delegateSizeOfCells           = [delegate respondsToSelector:@selector(sizeOfCellsForGridView:)];
    _gridViewFlags.delegateHeightOfRows          = [delegate respondsToSelector:@selector(heightOfRowsInGridView:)];
    _gridViewFlags.delegateDidLongTapCell        = [delegate respondsToSelector:@selector(gridView:didLongTapCellAtIndex:)];
    _gridViewFlags.delegateDidTapCell            = [delegate respondsToSelector:@selector(gridView:didTapCellAtIndex:)];
    _gridViewFlags.delegateDidMoveCell           = [delegate respondsToSelector:@selector(gridView:didMoveCellAtIndex:toIndex:)];
    _gridViewFlags.delegateVerticalOffsetOfCells = [delegate respondsToSelector:@selector(verticalOffsetOfCellsInRowsInGridView:)];
    _gridViewFlags.delegateWillDisplayCell       = [delegate respondsToSelector:@selector(gridView:willDisplayCell:atIndex:)];
    _gridViewFlags.delegateDidEndDisplayingCell  = [delegate respondsToSelector:@selector(gridView:didEndDisplayingCell:atIndex:)];
    _gridViewFlags.delegateDidSelectCell         = [delegate respondsToSelector:@selector(gridView:didSelectCellAtIndex:)];
    _gridViewFlags.delegateDidDeselectCell       = [delegate respondsToSelector:@selector(gridView:didDeselectCellAtIndex:)];
}

- (void)setDataSource:(id<TOGridViewDataSource>)dataSource
{
    if (self.dataSource == dataSource)
        return;
    
    _cellLayoutGeneration++;
    _dataSource = dataSource;
    _prefetchNeedsDataSourceReload = YES;
    [self invalidatePrefetching];
    
    //Update the flags with the current state of the data source
    _gridViewFlags.dataSourceCellForIndex       = [dataSource respondsToSelector:@selector(gridView:cellForIndex:)];
    _gridViewFlags.dataSourceNumberOfCells      = [dataSource respondsToSelector:@selector(numberOfCellsInGridView:)];
    _gridViewFlags.dataSourceCanEditCell        = [dataSource respondsToSelector:@selector(gridView:canEditCellAtIndex:)];
    _gridViewFlags.dataSourceCanMoveCell        = [dataSource respondsToSelector:@selector(gridView:canMoveCellAtIndex:)];
    _gridViewFlags.dataSourceCanHighlightCell   = [dataSource respondsToSelector:@selector(gridView:canHighlightCellAtIndex:)];
    _gridViewFlags.dataSourceCanLongTapCell     = [dataSource respondsToSelector:@selector(gridView:canLongTapCellAtIndex:)];
}

- (void)setHeaderView:(UIView *)headerView
{
    if (self.headerView == headerView)
        return;
    
    //remove the older header view and set up the new header view
    [self.headerView removeFromSuperview];
    _headerView = headerView;
    self.headerView.frame = CGRectMake(0, 0, CGRectGetWidth(self.frame), CGRectGetHeight(self.headerView.frame));
    self.headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    //Set the origin of the first cell to be beneath this header view
    self.offsetFromHeader = CGRectGetHeight(headerView.bounds);
    
    //add the view to the scroll view
    if (headerView != nil)
        [self addSubview:headerView];
    
    //reset the size of the scroll view to account for this new header views
    self.contentSize = [self contentSizeOfScrollView];
    
    //update any and all visible cells as well
    [self invalidateVisibleCells];
    [self layoutCells];
}

- (void)setFooterView:(UIView *)footerView
{
    if (self.footerView == footerView)
        return;
    
    //remove the older footer view and set up the new one
    [self.footerView removeFromSuperview];
    _footerView = footerView;
    self.footerView.frame = CGRectMake(0, 0, CGRectGetWidth(self.footerView.frame), CGRectGetHeight(self.footerView.frame));
    self.footerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    //add the view to the scroll view
    if (footerView != nil)
        [self addSubview:footerView];
    
    //reset the size of the scroll view to account for this new header views
    self.contentSize = [self contentSizeOfScrollView];
    
    //update any and all visible cells as well
    [self invalidateVisibleCells];
    [self layoutCells];
}

- (void)setBackgroundView:(UIView *)backgroundView
{
    if (self.backgroundView == backgroundView)
        return;
    
    //remove the old background view and set up the new one
    [self.backgroundView removeFromSuperview];
    _backgroundView = backgroundView;
    self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.backgroundView.frame = self.bounds;
    
    //make sure to insert it BELOW any visible cells
    if (backgroundView != nil)
        [self insertSubview:backgroundView atIndex:0];
}

- (void)setFrame:(CGRect)frame
{
    CGRect previousBounds = self.bounds;
    
    [super setFrame:frame];

    // Moving the view (or assigning its current frame) does not change cell geometry.
    if (CGSizeEqualToSize(previousBounds.size, self.bounds.size))
        return;

    [self finishInsertion];

    //If we were in the middle of dragging a cell, kill it
    if (self.editing)
        [self cancelDraggingCell];
    
    /* If the frame changes, and we're NOT animating, invalidate all of the visible cells and reload the view */
    /* If we ARE animating (eg, orientation change), this will be handled in layoutSubviews. */
    if (self.boundsChangeAnimation == nil)
    {
        [self invalidateVisibleCells];
        [self resetCellMetrics];
    }
    else {
        _gridViewBeforeRotationState.bounds = previousBounds;
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [self invalidateCellPreparation];
    [self schedulePrefetchUpdate];
    _editing = editing;
    
    [self updateCellsForEditingAnimated:animated];
}

- (NSRange)visibleCellRange
{
    return [self rangeOfVisibleCellsInBounds:self.bounds];
}

- (NSArray<TOGridViewCell *> *)visibleCellViews
{
    return [self.visibleCells allValues] ?: @[];
}

- (CABasicAnimation *)boundsChangeAnimation
{
    CABasicAnimation *boundsAnimation = nil;
    for (NSString *key in self.layer.animationKeys) {
        if ([key isEqualToString:@"bounds"]) {
            boundsAnimation = (CABasicAnimation *)[self.layer animationForKey:key];
            break;
        }
        else if ([key rangeOfString:@"bounds"].location != NSNotFound && [key rangeOfString:@"size"].location != NSNotFound)
            boundsAnimation = (CABasicAnimation *)[self.layer animationForKey:key];
    }
    
    return boundsAnimation;
}

- (void)setPauseCellLayout:(BOOL)pauseCellLayout
{
    _cellLayoutGeneration++;
    _pauseCellLayout = pauseCellLayout;
    // Indices may be remapped during an edit or drag. Cancel the old requests even
    // if the entire operation finishes before the deferred update runs.
    if (pauseCellLayout)
        [self invalidatePrefetching];
    else
        [self schedulePrefetchUpdate];
}

- (void)setVisibleCells:(NSMutableDictionary<NSNumber *, TOGridViewCell *> *)visibleCells
{
    _cellLayoutGeneration++;
    _visibleCells = visibleCells;
}

- (void)setContentInset:(UIEdgeInsets)contentInset
{
    [super setContentInset:contentInset];
    [self resetCellMetrics];
}

@end
