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

#import "TOGridView.h"
#import "TOGridViewCell.h"
#import <QuartzCore/QuartzCore.h>

#define LONG_PRESS_TIME 0.4f

#define HORIZONTAL_PADDING 20.0f

#define TOP_OFFSET      -self.contentInset.top
#define BOTTOM_OFFSET   (self.contentSize.height+(self.contentInset.bottom) - CGRectGetHeight(self.bounds))

static const NSTimeInterval TOGridViewReorderSpringDuration = 0.35;
static const NSTimeInterval TOGridViewReorderStaggerDelay = 0.03;

static void TOGridViewAnimateReordering(NSTimeInterval delay, void (^animations)(void), void (^completion)(BOOL))
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

@interface TOGridView () {
    
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
}

/* The class that is used to spawn cells */
@property (nonatomic, assign) Class cellClass;

/* Stores for cells in use, and ones in standby */
@property (nonatomic, strong) NSMutableArray *recycledCells;
@property (nonatomic, strong) NSMutableDictionary *visibleCells;

/* A transparent viewport containing only cells, captured in one UIKit snapshot. */
@property (nonatomic, strong) UIView *cellContainerView;

/* Decoration views */
@property (nonatomic, strong) NSMutableSet *recyledDecorationViews;
@property (nonatomic, strong) NSMutableSet *visibleDecorationViews;

/* An array of all cells, and whether they're selected or not */
@property (nonatomic, strong) NSMutableSet *selectedCells;

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
@property (nonatomic, copy) NSArray *insertingCells;
@property (nonatomic, assign) NSUInteger insertionGeneration;

/* When rendering, completely can any calls to layoutSubviews in that interim */
@property (nonatomic, assign) __block BOOL freezeLayoutSubviews;
/* Temporarily halt laying out cells if we need to do something manually that causes iOS to call 'layoutSubViews' */
@property (nonatomic, assign) __block BOOL pauseCellLayout;
/* Temoporaily halt performing a crossfade animation if we need to perform some manual layout */
@property (nonatomic, assign) __block BOOL pauseCrossfadeAnimation;

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

- (void)enumerateCellDictionary:(NSDictionary *)cellDictionary withBlock:(void (^)(NSInteger index, TOGridViewCell *cell))block;
- (void)updateVisibleCellKeysWithDictionary:(NSDictionary *)updatedCells;
- (void)updateSelectedCellKeysWithDictionary:(NSDictionary *)updatedCells;
- (void)resetCellMetrics;
- (void)layoutCells;
- (TOGridViewCell *)addCellAtIndex:(NSInteger)index dataSourceIndex:(NSInteger)dataSourceIndex;
- (void)finishInsertion;
- (void)finishInsertionWithLayout:(BOOL)layout;
- (UIView *)snapshotOfGridViewInRect:(CGRect)rect;
- (CGFloat)heightOfGridViewContent;
- (CGSize)contentSizeOfScrollView;
- (NSRange)rangeOfVisibleCellsInBounds:(CGRect)bounds;
- (CGRect)footerViewFrame;
- (void)invalidateVisibleCells;
- (void)fireDragTimer:(id)timer;
- (TOGridViewCell *)cellInTouch:(UITouch *)touch;
- (NSInteger)indexOfVisibleCell:(TOGridViewCell *)cell;
- (void)setCell:(TOGridViewCell*)cell atIndex:(NSInteger)index dragging:(BOOL)dragging animated:(BOOL)animated;
- (void)fireLongPressTimer:(NSTimer *)timer;
- (NSInteger)indexOfCellAtPoint:(CGPoint)point;
- (void)updateCellsLayoutWithDraggedCellAtPoint:(CGPoint)dragPanPoint;
- (void)cancelDraggingCell;
- (void)startAnimatingScrollViewDragging;
- (void)stopAnimatingScrollViewDragging;

@end

@implementation TOGridView

#pragma mark -
#pragma mark View Management
- (id)initWithFrame:(CGRect)frame
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
        self.draggingOverIndex          = -1;
        self.draggingCellIndex          = -1;
    }
    
    return self;
}

- (id)initWithFrame:(CGRect)frame withCellClass:(Class)cellClass
{
    if (self = [self initWithFrame:frame])
        [self registerCellClass:cellClass];
    
    return self;
}

- (void)registerCellClass:(Class)cellClass
{
    self.cellClass = cellClass;
}

/* Kickstart the loading of the cells when this view is added to the view hierarchy */
- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    // Removal can happen while the owning controller and data source are deallocating.
    if (self.superview != nil)
        [self reloadGrid];
}

- (void)dealloc
{
    /* General clean-up */
    self.recycledCells = nil;
    self.visibleCells = nil;
}

#pragma mark -
#pragma mark Set-up
- (void)reloadGrid
{    
    [self finishInsertion];

    /* Use the delegate+dataSource to set up the rendering logistics of the cells */
    [self resetCellMetrics];
    
    /* Remove any existing cells */
    [self invalidateVisibleCells];
    
    /* Perform a redraw operation */
    [self layoutCells];
}

- (void)resetCellMetrics
{
    /* Get the number of cells per row */
    if (_gridViewFlags.delegateNumberOfCellsPerRow)
        self.numberOfCellsPerRow = [self.delegate numberOfCellsPerRowForGridView:self];
    
    /* Get the number of cells from the data source */
    if (_gridViewFlags.dataSourceNumberOfCells)
        self.numberOfCells = [self.dataSource numberOfCellsInGridView:self];
    
    /* Get outer padding of cells */
    if (_gridViewFlags.delegateBoundaryInsets)
        self.cellPaddingInsets = [self.delegate boundaryInsetsForGridView:self];
    
    /* Grab the size of each cell */
    if (_gridViewFlags.delegateSizeOfCells)
        self.cellSize = [self.delegate sizeOfCellsForGridView:self];
    
    /* See if there is a custom height for each row of cells */
    if (_gridViewFlags.delegateHeightOfRows)
        self.rowHeight = [self.delegate heightOfRowsInGridView:self];
    else
        self.rowHeight = self.cellSize.height;
    
    /* See if there is a custom offset of cells from within each row */
    if (_gridViewFlags.delegateVerticalOffsetOfCells)
        self.offsetOfCellsInRow = [self.delegate verticalOffsetOfCellsInRowsInGridView:self];
    
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

- (void)invalidateVisibleCells
{
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

#pragma mark -
#pragma mark Cell Management
- (void)enumerateCellDictionary:(NSDictionary *)cellDictionary withBlock:(void (^)(NSInteger index, TOGridViewCell *))block
{
    if (block == nil)
        return;
    
    [cellDictionary enumerateKeysAndObjectsWithOptions:0 usingBlock:^(NSNumber *key, TOGridViewCell *cell, BOOL *stop) {
        block(key.integerValue, cell);
    }];
}

- (void)updateVisibleCellKeysWithDictionary:(NSDictionary *)updatedCells
{
    //Make a copy off the main list to work off (So we don't overwrite older values as we go)
    NSDictionary *visibleCellsCopy = [self.visibleCells copy];
    
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

- (void)updateSelectedCellKeysWithDictionary:(NSDictionary *)updatedCells
{
    if (self.selectedCells.count == 0)
        return;
    
    //Make a copy off the main list to work off (So we don't overwrite older values as we go)
    NSSet *selectedCellsCopy = [self.selectedCells copy];
    
    [updatedCells enumerateKeysAndObjectsUsingBlock:^(NSNumber *oldKey, NSNumber *newKey, BOOL *stop) {
        //skip if the cell isn't selected
        if ([selectedCellsCopy containsObject:oldKey] == NO)
            return;
        
        [self.selectedCells removeObject:oldKey];
        [self.selectedCells addObject:newKey];
    }];
}

- (TOGridViewCell *)cellForIndex:(NSInteger)index
{
    return self.visibleCells[@(index)];
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
    if (self.numberOfCells == 0)
        return;
    
    //work out the index range of which cells should be visible now
    NSRange visibleCellRange = [self rangeOfVisibleCellsInBounds:self.bounds];
    
    //go through each visible cell and see if they've moved beyond the visible range
    NSSet *cellsToRecyle = [self.visibleCells keysOfEntriesWithOptions:0 passingTest:^BOOL(NSNumber *key, TOGridViewCell *cell, BOOL *stop) {
        NSInteger index = key.integerValue;
        
        if (NSLocationInRange(index, visibleCellRange))
            return NO;
        
        if (_gridViewFlags.delegateDidEndDisplayingCell)
            [self.delegate gridView:self didEndDisplayingCell:cell atIndex:index];
        
        [cell.layer removeAllAnimations];
        [cell removeFromSuperview];
        [self.recycledCells addObject:cell];
        
        return YES;
    }];
    [self.visibleCells removeObjectsForKeys:[cellsToRecyle allObjects]];
    
    /* Only proceed with the following code if the number of visible cells is lower than it should be. */
    /* This code produces the most latency, so minimizing its call frequency is critical */
    if ([self.visibleCells count] >= visibleCellRange.length)
        return;
    
    for (NSInteger i = 0; i < visibleCellRange.length; i++)
    {
        NSInteger index = visibleCellRange.location+i;
        
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

/* Share the display lifecycle between scrolling and insertion. */
- (TOGridViewCell *)addCellAtIndex:(NSInteger)index dataSourceIndex:(NSInteger)dataSourceIndex
{
    BOOL animationsEnabled = [UIView areAnimationsEnabled];
    [UIView setAnimationsEnabled:NO];
    @try {
        //Get the cell with its content setup from the dataSource
        TOGridViewCell *cell = [self.dataSource gridView:self cellForIndex:dataSourceIndex];
        if (cell == nil)
            [NSException raise:NSInternalInconsistencyException format:@"The datasource may not return a nil cell object"];

        cell.hidden = NO;
        [cell setHighlighted:NO animated:NO];
        
        //if the cell has been selected, highlight it
        if (self.allowsSelectionDuringEditing) {
            if (self.editing && self.selectedCells && [self.selectedCells containsObject:@(index)])
                [cell setSelected:YES animated:NO];
            else if (cell.selected)
                [cell setSelected:NO animated:NO];
        }
        
        //see if we're editing and the current cell is draggable
        cell.draggable = NO;
        if (_gridViewFlags.dataSourceCanMoveCell) {
            if ([self.dataSource gridView:self canMoveCellAtIndex:index])
                cell.draggable = YES;
        }
        
        //set the cell editing state
        if (_gridViewFlags.dataSourceCanEditCell && self.editing)
            cell.editing = [self.dataSource gridView:self canEditCellAtIndex:index];
        else
            cell.editing = NO;
        
        //make sure the frame is still properly set
        CGRect cellFrame;
        cellFrame.origin = [self originOfCellAtIndex:index];
        cellFrame.size = [self sizeOfCellAtIndex:index];
        cell.frame = cellFrame;
        
        //add it to the visible objects set (It's already out of the recycled set at this point)
        [self.visibleCells setObject:cell forKey:@(index)];
        
        //if set, let the delegate know we're about to display this cell
        if (_gridViewFlags.delegateWillDisplayCell)
            [self.delegate gridView:self willDisplayCell:cell atIndex:index];
        
        // Keep cell order inside the transparent container; headers, footers,
        // backgrounds and scroll indicators remain separate from its snapshot.
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
- (void)layoutSubviews
{
    [super layoutSubviews];
    
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
    NSArray *cellIndices = [self.visibleCells.allKeys sortedArrayUsingSelector:@selector(compare:)];
    
    NSMutableDictionary *newIndicies = [NSMutableDictionary dictionary];
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

#pragma mark -
#pragma mark Cell/Decoration Recycling

/* Dequeue a recycled cell for reuse */
- (TOGridViewCell *)dequeReusableCell
{
    TOGridViewCell *cell = nil;
    
    //Grab a cell that was previously recycled
    if ([self.recycledCells count] > 0)
    {
        cell = self.recycledCells[0];
        [self.recycledCells removeObject:cell];
        return cell;
    }
    
    //If there are no cells available, create a new one and set it up
    if (self.cellClass) {
        cell = [[self.cellClass alloc] initWithFrame:CGRectMake(0, 0, self.cellSize.width, self.cellSize.height)];
        cell.frame = CGRectMake(0, 0, self.cellSize.width, self.cellSize.height);
        [cell setHighlighted:NO animated:NO];
    }
    
    return cell;
}

- (UIView *)dequeueReusableDecorationView
{
    return nil;
}

#pragma mark -
#pragma mark Cell Edit Handling
- (BOOL)insertCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    return [self insertCellsAtIndices:@[@(index)] animated:animated completionHandler:nil];
}

- (BOOL)insertCellAtIndex:(NSInteger)index animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    return [self insertCellsAtIndices:@[@(index)] animated:animated completionHandler:completionHandler];
}

- (BOOL)insertCellsAtIndices:(NSArray *)indices animated:(BOOL)animated
{
    return [self insertCellsAtIndices:indices animated:animated completionHandler:nil];
}

- (BOOL)insertCellsAtIndices:(NSArray *)indices animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
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
    NSMutableDictionary *remappedCells = [NSMutableDictionary dictionary];
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        remappedCells[@(newIndexForOldIndex(index))] = cell;
    }];
    self.visibleCells = remappedCells;
    if (self.selectedCells) {
        NSMutableSet *remappedSelection = [NSMutableSet set];
        for (NSNumber *index in self.selectedCells)
            [remappedSelection addObject:@(newIndexForOldIndex(index.integerValue))];
        self.selectedCells = remappedSelection;
    }

    self.contentSize = [self contentSizeOfScrollView];
    NSRange visibleRange = self.visibleCellRange;
    NSMutableArray *newCells = [NSMutableArray array];
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
    NSMutableArray *movingIndices = [NSMutableArray array];
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
    NSArray *cells = self.insertingCells;
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

- (BOOL)deleteCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    return [self deleteCellsAtIndices:@[@(index)] animated:animated completionHandler:nil];
}

- (BOOL)deleteCellAtIndex:(NSInteger)index animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    return [self deleteCellsAtIndices:@[@(index)] animated:animated completionHandler:completionHandler];
}

- (BOOL)deleteCellsAtIndices:(NSArray *)indices animated:(BOOL)animated
{
    return [self deleteCellsAtIndices:indices animated:animated completionHandler:nil];
}

- (BOOL)deleteCellsAtIndices:(NSArray *)indices animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler
{
    if ([indices count] == 0)
        return YES;

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
    NSMutableArray *visibleCellsToDelete = [NSMutableArray array];
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
    NSMutableDictionary *updatedCellKeys = [NSMutableDictionary dictionary];
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
            NSArray *sortedVisibleCellIndices = [[self.visibleCells allKeys] sortedArrayUsingSelector:@selector(compare:)];
            
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

- (BOOL)reloadCellAtIndex:(NSInteger)index
{
    return [self reloadCellsAtIndices:@[@(index)]];
}

- (BOOL)reloadCellsAtIndices:(NSArray *)indices
{
    if ([indices count] == 0)
        return YES;

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
        
        cell = [self.dataSource gridView:self cellForIndex:cellIndex];
        cell.frame = frame;
        
        cell.draggable = NO;
        if (_gridViewFlags.dataSourceCanMoveCell) {
            if ([self.dataSource gridView:self canMoveCellAtIndex:cellIndex])
                cell.draggable = YES;
        }
        
        if (_gridViewFlags.dataSourceCanEditCell && self.editing)
            cell.editing = [self.dataSource gridView:self canEditCellAtIndex:cellIndex];
        else
            cell.editing = NO;
        
        [cell setNeedsLayout];
        
        [self.cellContainerView insertSubview:cell atIndex:0];
        
        [self.visibleCells setObject:cell forKey:index];
    }
    
    return YES;
}

/* This is called manually by the delegate object */
- (void)unhighlightCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    TOGridViewCell *cell = [self cellForIndex:index];
    if (cell)
        [cell setHighlighted:NO animated:animated];
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

- (NSArray *)indicesOfSelectedCells
{
    return [[self.selectedCells allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

- (BOOL)selectCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    return [self selectCellsAtIndices:@[@(index)] animated:animated];
}

- (BOOL)selectCellsAtIndices:(NSArray *)indices animated:(BOOL)animated
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

- (BOOL)deselectCellAtIndex:(NSInteger)index
{
    return [self deselectCellsAtIndices:@[@(index)]];
}

- (BOOL)deselectCellsAtIndices:(NSArray *)indices
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
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
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
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
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
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
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
            if ([self.dataSource gridView:self canHighlightCellAtIndex:index])
                [cell setHighlighted:YES animated:NO];
        }
        else
            [cell setHighlighted:YES animated:NO];
        
        if (cell && _gridViewFlags.delegateDidTapCell)
            [self.delegate gridView:self didTapCellAtIndex:index];
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
                if ([self.dataSource gridView:self canEditCellAtIndex:index] == NO)
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
                        [self.delegate gridView:self didSelectCellAtIndex:index];
                }
                else
                {
                    [cell setSelected:NO animated:NO];
                    [self.selectedCells removeObject:cellIndexNumber];
                    
                    if (_gridViewFlags.delegateDidDeselectCell)
                        [self.delegate gridView:self didDeselectCellAtIndex:index];
                }
            }
            else {
                if (_gridViewFlags.dataSourceCanHighlightCell) {
                    if ([self.dataSource gridView:self canHighlightCellAtIndex:index])
                        [cell setHighlighted:YES animated:NO];
                }
                else
                    [cell setHighlighted:YES animated:NO];
                
                if (_gridViewFlags.delegateDidTapCell)
                    [self.delegate gridView:self didTapCellAtIndex:index];
            }
        }
        else //if there IS a cell being dragged about, re-insert it back into the view layout
        {
            NSInteger previousIndex = self.draggingCellIndex;
            NSInteger newIndex      = self.draggingOverIndex;
            
            if (_gridViewFlags.delegateDidMoveCell)
                [self.delegate gridView:self didMoveCellAtIndex:previousIndex toIndex:newIndex];
            
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
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
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
    cell.layer.rasterizationScale = [[UIScreen mainScreen] scale];
    
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
    
    [self.dragScrollTimerLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    self.dragScrollTimerLink = nil;
}

#pragma mark -
#pragma mark Accessors
- (void)setDelegate:(id<TOGridViewDelegate>)delegate
{
    if (self.delegate == delegate)
        return;
    
    [super setDelegate:delegate];
    
    //Update the flags with the state of the new delegate
    _gridViewFlags.delegateDecorationView        = [self.delegate respondsToSelector:@selector(gridView:decorationViewForRowWithIndex:)];
    _gridViewFlags.delegateBoundaryInsets        = [self.delegate respondsToSelector:@selector(boundaryInsetsForGridView:)];
    _gridViewFlags.delegateNumberOfCellsPerRow   = [self.delegate respondsToSelector:@selector(numberOfCellsPerRowForGridView:)];
    _gridViewFlags.delegateSizeOfCells           = [self.delegate respondsToSelector:@selector(sizeOfCellsForGridView:)];
    _gridViewFlags.delegateHeightOfRows          = [self.delegate respondsToSelector:@selector(heightOfRowsInGridView:)];
    _gridViewFlags.delegateDidLongTapCell        = [self.delegate respondsToSelector:@selector(gridView:didLongTapCellAtIndex:)];
    _gridViewFlags.delegateDidTapCell            = [self.delegate respondsToSelector:@selector(gridView:didTapCellAtIndex:)];
    _gridViewFlags.delegateDidMoveCell           = [self.delegate respondsToSelector:@selector(gridView:didMoveCellAtIndex:toIndex:)];
    _gridViewFlags.delegateVerticalOffsetOfCells = [self.delegate respondsToSelector:@selector(verticalOffsetOfCellsInRowsInGridView:)];
    _gridViewFlags.delegateWillDisplayCell       = [self.delegate respondsToSelector:@selector(gridView:willDisplayCell:atIndex:)];
    _gridViewFlags.delegateDidEndDisplayingCell  = [self.delegate respondsToSelector:@selector(gridView:didEndDisplayingCell:atIndex:)];
    _gridViewFlags.delegateDidSelectCell         = [self.delegate respondsToSelector:@selector(gridView:didSelectCellAtIndex:)];
    _gridViewFlags.delegateDidDeselectCell       = [self.delegate respondsToSelector:@selector(gridView:didDeselectCellAtIndex:)];
}

- (void)setDataSource:(id<TOGridViewDataSource>)dataSource
{
    if (self.dataSource == dataSource)
        return;
    
    _dataSource = dataSource;
    
    //Update the flags with the current state of the data source
    _gridViewFlags.dataSourceCellForIndex       = [_dataSource respondsToSelector:@selector(gridView:cellForIndex:)];
    _gridViewFlags.dataSourceNumberOfCells      = [_dataSource respondsToSelector:@selector(numberOfCellsInGridView:)];
    _gridViewFlags.dataSourceCanEditCell        = [_dataSource respondsToSelector:@selector(gridView:canEditCellAtIndex:)];
    _gridViewFlags.dataSourceCanMoveCell        = [_dataSource respondsToSelector:@selector(gridView:canMoveCellAtIndex:)];
    _gridViewFlags.dataSourceCanHighlightCell   = [_dataSource respondsToSelector:@selector(gridView:canHighlightCellAtIndex:)];
    _gridViewFlags.dataSourceCanLongTapCell     = [_dataSource respondsToSelector:@selector(gridView:canLongTapCellAtIndex:)];
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
    [self addSubview:self.headerView];
    
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
    [self addSubview:self.footerView];
    
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
    [self insertSubview:self.backgroundView atIndex:0];
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
    _editing = editing;
    
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
            
            if (_gridViewFlags.dataSourceCanEditCell && [self.dataSource gridView:self canEditCellAtIndex:index])
                [cell setEditing:YES animated:animated];
        }];
    }
}

- (NSRange)visibleCellRange
{
    return [self rangeOfVisibleCellsInBounds:self.bounds];
}

- (NSArray *)visibleCellViews
{
    return [self.visibleCells allValues];
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
    _pauseCellLayout = pauseCellLayout;
}

- (void)setContentInset:(UIEdgeInsets)contentInset
{
    [super setContentInset:contentInset];
    [self resetCellMetrics];
}

@end
