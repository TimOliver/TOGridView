//
//  TOGridView+Private.h
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

#pragma once

// Implementation detail: do not import or publish this header to library clients.
#import "TOGridView.h"
#import <QuartzCore/QuartzCore.h>

#define TOP_OFFSET      -self.contentInset.top
#define BOTTOM_OFFSET   (self.contentSize.height+(self.contentInset.bottom) - CGRectGetHeight(self.bounds))

FOUNDATION_EXPORT const NSTimeInterval TOGridViewReorderSpringDuration __attribute__((visibility("hidden")));
FOUNDATION_EXPORT const NSTimeInterval TOGridViewReorderStaggerDelay __attribute__((visibility("hidden")));
FOUNDATION_EXPORT void TOGridViewAnimateReordering(NSTimeInterval delay, void (^animations)(void), void (^completion)(BOOL)) __attribute__((visibility("hidden")));

// Internal storage belongs to the primary class. Categories add behavior only.
@interface TOGridView () <CAAnimationDelegate> {
    // Explicit storage makes these synthesized properties accessible across source files.
    CGSize _cellSize;
    __weak id<TOGridViewDataSource> _dataSource;
    __weak id<TOGridViewDataSourcePrefetching> _prefetchDataSource;
    
    /* Store what protocol methods the delegate/dataSource implement to help reduce overhead involved with checking that at runtime */
    struct {
        unsigned int dataSourceNumberOfCells;
        unsigned int dataSourceCellForIndex;
        unsigned int dataSourceCanMoveCell;
        unsigned int dataSourceCanEditCell;
        unsigned int dataSourceCanHighlightCell;
        unsigned int dataSourceCanLongTapCell;
        
        unsigned int delegateSizeOfCells;
        unsigned int delegateVerticalOffsetOfCells;
        unsigned int delegateNumberOfCellsPerRow;
        unsigned int delegateBoundaryInsets;
        unsigned int delegateDecorationView;
        unsigned int delegateHeightOfRows;
        unsigned int delegateDidTapCell;
        unsigned int delegateDidLongTapCell;
        unsigned int delegateDidMoveCell;
        unsigned int delegateWillDisplayCell;
        unsigned int delegateDidEndDisplayingCell;
        unsigned int delegateDidSelectCell;
        unsigned int delegateDidDeselectCell;
    } _gridViewFlags;
    
    struct {
        CGRect bounds;
        CGPoint contentOffset;
    } _gridViewBeforeRotationState;

    // Cache reconciliation, not view geometry: scrolling still updates the container.
    NSRange _reconciledCellRange;
    NSUInteger _cellLayoutGeneration;
    NSUInteger _reconciledCellLayoutGeneration;
    BOOL _hasReconciledCellRange;

    NSMutableIndexSet *_prefetchedIndices;
    __weak id<TOGridViewDataSourcePrefetching> _prefetchRequestSource;
    NSUInteger _prefetchGeneration;
    NSUInteger _prefetchRequestGeneration;
    NSUInteger _prefetchUpdateVersion;
    BOOL _prefetchUpdateScheduled;
    BOOL _prefetchNeedsDataSourceReload;

    NSMutableDictionary<NSNumber *, TOGridViewCell *> *_preparedCells;
    NSArray<NSNumber *> *_cellPreparationCandidates;
    CADisplayLink *_cellPreparationDisplayLink;
    NSUInteger _cellPreparationGeneration;
    CFTimeInterval _estimatedCellPreparationDuration;
    NSUInteger _cellPreparationDeadlineMisses;
    BOOL _cellPreparationSuspendedForBudget;
    CGFloat _previousPreparationOffset;
    BOOL _preparingCellsUpwards;
    BOOL _cellPreparationSuspendedForMemoryWarning;
    UITraitCollection *_preparedCellTraits;
}

/* The class that is used to spawn cells */
@property (nonatomic, assign) Class cellClass;

/* Stores for cells in use, and ones in standby */
@property (nonatomic, strong) NSMutableArray<TOGridViewCell *> *recycledCells;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TOGridViewCell *> *visibleCells;

/* A transparent viewport containing only cells, captured in one UIKit snapshot. */
@property (nonatomic, strong) UIView *cellContainerView;

/* Decoration views */
@property (nonatomic, strong) NSMutableSet<UIView *> *recyledDecorationViews;
@property (nonatomic, strong) NSMutableSet<UIView *> *visibleDecorationViews;

/* An array of all cells, and whether they're selected or not */
@property (nonatomic, strong) NSMutableSet<NSNumber *> *selectedCells;

@property (nonatomic, assign) UIEdgeInsets cellPaddingInsets;  /* Padding of cells from edge of view */
@property (nonatomic, assign) CGSize cellSize;  /*Size of each cell (This will become the tappable region) */

@property (nonatomic, assign, readwrite) NSInteger numberOfCells;  /* Number of cells in grid view */
@property (nonatomic, assign, readwrite) NSInteger numberOfCellsPerRow; /* Number of cells per row */


@property (nonatomic, assign) NSInteger widthBetweenCells;  /* The width between cells on a single row */
@property (nonatomic, assign) NSInteger rowHeight; /* The height of each row (ie the height of each decoration view) */


@property (nonatomic, assign) NSInteger offsetFromHeader;    /* Y-position of where the first row starts, after the header */
@property (nonatomic, assign) NSInteger offsetOfCellsInRow;  /* Y-offset of cell, within the row */

/* Keep track of cancelling touches if needed by our own touch events */
@property (nonatomic, assign) BOOL cancelTouches;

/* Timer to keep track of how long the user tapped and held a cell */
@property (nonatomic, strong) NSTimer *longPressTimer;

/* Checks our CALayer to see if we're being resized via an animation */
@property (nonatomic, readonly) CABasicAnimation *boundsChangeAnimation;

/* A snapshot of the view before we start rotating */
@property (nonatomic, strong) UIView *beforeSnapshotView;
@property (nonatomic, assign) UIEdgeInsets beforeSnapshotInsets;
@property (nonatomic, assign) NSUInteger snapshotAnimationGeneration;

/* One completion and one generation per insertion, including batches with no visible new cells. */
@property (nonatomic, copy) void (^insertionCompletionHandler)(void);
@property (nonatomic, copy) NSArray<TOGridViewCell *> *insertingCells;
@property (nonatomic, assign) NSUInteger insertionGeneration;

/* When rendering, completely can any calls to layoutSubviews in that interim */
@property (nonatomic, assign) BOOL freezeLayoutSubviews;
/* Temporarily halt laying out cells if we need to do something manually that causes iOS to call 'layoutSubViews' */
@property (nonatomic, assign) BOOL pauseCellLayout;
/* Temoporaily halt performing a crossfade animation if we need to perform some manual layout */
@property (nonatomic, assign) BOOL pauseCrossfadeAnimation;

/* Properties of the scroll view used to track the current dragging state of a cell */
@property (nonatomic, assign) CGFloat       dragScrollBias;         /* The amount the offset of the scrollview is incremented on each call of the timer*/
@property (nonatomic, assign) NSInteger     draggingOverIndex;      /* While dragging a cell around, this keeps track of which other cell's area it's currently hovering over */

/* Properties of a cell used to track the drag state. */
@property (nonatomic, strong) TOGridViewCell *draggingCell;         /* The specific cell item that's being dragged by the user */
@property (nonatomic, assign) NSInteger     draggingCellIndex;      /* The index of the cell being dragged */
@property (nonatomic, assign) CGPoint       draggingCellPanPoint;   /* The co-ords of the user's fingers from the last touch event to update the drag cell while it's animating */
@property (nonatomic, assign) CGSize        draggingCellOffset;     /* The distance between the cell's origin and the user's touch position */

/* Timer link added to the main run-loop so we can animate the view scrolling */
@property (nonatomic, strong) CADisplayLink *dragScrollTimerLink;

@end

@interface TOGridView (Layout)
- (void)resetCellMetrics;
- (CGFloat)heightOfGridViewContent;
- (CGSize)contentSizeOfScrollView;
- (CGRect)footerViewFrame;
- (void)invalidateVisibleCells;
- (NSInteger)indexOfVisibleCell:(TOGridViewCell *)cell;
- (NSInteger)indexOfCellAtPoint:(CGPoint)point;
- (void)enumerateCellDictionary:(NSDictionary<NSNumber *, TOGridViewCell *> *)cellDictionary withBlock:(void (^)(NSInteger index, TOGridViewCell *))block;
- (NSRange)rangeOfVisibleCellsInBounds:(CGRect)bounds;
- (void)layoutCells;
- (TOGridViewCell *)requestCellAtIndex:(NSInteger)index;
- (void)configureCell:(TOGridViewCell *)cell atIndex:(NSInteger)index prepared:(BOOL)prepared;
- (TOGridViewCell *)addCellAtIndex:(NSInteger)index dataSourceIndex:(NSInteger)dataSourceIndex;
- (void)layoutGridSubviews;
- (UIView *)snapshotOfGridViewInRect:(CGRect)rect;
@end

@interface TOGridView (Updates)
- (void)updateVisibleCellKeysWithDictionary:(NSDictionary<NSNumber *, NSNumber *> *)updatedCells;
- (void)updateSelectedCellKeysWithDictionary:(NSDictionary<NSNumber *, NSNumber *> *)updatedCells;
- (BOOL)performInsertionAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler;
- (void)finishInsertion;
- (void)finishInsertionWithLayout:(BOOL)layout;
- (BOOL)performDeletionAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler;
- (BOOL)performReloadAtIndices:(NSArray<NSNumber *> *)indices;
- (BOOL)performSelectionAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated;
- (BOOL)performDeselectionAtIndices:(NSArray<NSNumber *> *)indices;
- (void)updateCellsForEditingAnimated:(BOOL)animated;
@end

@interface TOGridView (Dragging)
- (void)updateCellsLayoutWithDraggedCellAtPoint:(CGPoint)dragPanPoint;
- (void)fireDragTimer:(id)timer;
- (TOGridViewCell *)cellInTouch:(UITouch *)touch;
- (void)handleTouchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)fireLongPressTimer:(NSTimer *)timer;
- (void)handleTouchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)handleTouchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)handleTouchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)cancelDraggingCell;
- (void)setCell:(TOGridViewCell *)cell atIndex:(NSInteger)index dragging:(BOOL)dragging animated:(BOOL)animated;
- (void)startAnimatingScrollViewDragging;
- (void)stopAnimatingScrollViewDragging;
@end

@interface TOGridView (Prefetching)
- (void)invalidateCellPreparation;
- (void)resetCellPreparationBudget;
- (void)didReceiveMemoryWarning:(NSNotification *)notification;
- (NSRange)cellPreparationRangeForVisibleRange:(NSRange)visibleRange;
- (void)updateCellPreparation;
- (void)prepareNextCell:(CADisplayLink *)link;
- (void)prepareCellBeforeDeadline:(CFTimeInterval)deadline;
- (void)invalidatePrefetching;
- (void)schedulePrefetchUpdate;
- (void)updatePrefetching;
@end
