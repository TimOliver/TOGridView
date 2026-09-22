//
//  TOGridView.h
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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "TOGridViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@class TOGridView;

typedef NS_ENUM(NSInteger, TOGridViewScrollPosition) {
    TOGridViewScrollPositionTop=0,
    TOGridViewScrollPositionMiddle,
    TOGridViewScrollPositionBottom
};

///
/// Data Source Object
///
NS_SWIFT_UI_ACTOR
@protocol TOGridViewDataSource <NSObject>

@required
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView;
- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)cellIndex;

@optional
- (BOOL)gridView:(TOGridView *)gridView canHighlightCellAtIndex:(NSInteger)cellIndex;
- (BOOL)gridView:(TOGridView *)gridView canMoveCellAtIndex:(NSInteger)cellIndex;
- (BOOL)gridView:(TOGridView *)gridView canEditCellAtIndex:(NSInteger)cellIndex;
- (BOOL)gridView:(TOGridView *)gridView canLongTapCellAtIndex:(NSInteger)cellIndex;

@end

///
/// Delegate Object
///
NS_SWIFT_UI_ACTOR
@protocol TOGridViewDelegate <NSObject, UIScrollViewDelegate>

@required
- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView;
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView;

@optional
- (UIEdgeInsets)boundaryInsetsForGridView:(TOGridView *)gridView;
- (nullable UIView *)gridView:(TOGridView *)gridView decorationViewForRowWithIndex:(NSUInteger)rowIndex;
- (NSUInteger)heightOfRowsInGridView:(TOGridView *)gridView;
- (NSUInteger)verticalOffsetOfCellsInRowsInGridView:(TOGridView *)gridView;

// Per cell addition/removal notifications
- (void)gridView:(TOGridView *)gridView willDisplayCell:(TOGridViewCell *)cell atIndex:(NSInteger)index;
- (void)gridView:(TOGridView *)gridView didEndDisplayingCell:(TOGridViewCell *)cell atIndex:(NSInteger)index;

// Cell interaction
- (void)gridView:(TOGridView *)gridView didTapCellAtIndex:(NSUInteger)index;
- (void)gridView:(TOGridView *)gridView didLongTapCellAtIndex:(NSInteger)index;
- (void)gridView:(TOGridView *)gridView didMoveCellAtIndex:(NSInteger)prevIndex toIndex:(NSInteger)newIndex;

//Edit mode
- (void)gridView:(TOGridView *)gridView didSelectCellAtIndex:(NSInteger)index;
- (void)gridView:(TOGridView *)gridView didDeselectCellAtIndex:(NSInteger)index;

@end

/* Access the grid and its callbacks on the main thread, like other UIKit views. */
@interface TOGridView : UIScrollView <UIGestureRecognizerDelegate> 

@property (nonatomic, weak, nullable) id <TOGridViewDataSource>    dataSource;  /* The object that provides cells. Keep a strong reference elsewhere. */
@property (nonatomic, weak, nullable) id <TOGridViewDelegate>      delegate;    /* The object that the grid view will send events to. */

@property (nonatomic, strong, nullable) UIView      *headerView;                  /* A UIView placed at the top of the grid view. Set nil to remove. */
@property (nonatomic, strong, nullable) UIView      *backgroundView;              /* A UIView placed behind the grid view and locked so it won't scroll */
@property (nonatomic, strong, nullable) UIView      *footerView;                  /* A UIView placed at the bottom of the grid view. */
@property (nonatomic, assign)    BOOL        editing;                      /* Whether the grid view is in an editing state now. */
@property (nonatomic, assign)    BOOL        nonRetinaRenderContexts API_DEPRECATED("This property has no effect; UIKit manages snapshot resolution.", ios(5.0, 15.0));      /* Compatibility property; UIKit snapshots now manage their own resolution. */
@property (nonatomic, assign)    NSInteger   dragScrollBoundaryDistance;   /* The distance, in points, from the top of the view downwards that will trigger auto-scrolling when dragging a cell (Same for the bottom). Default is 80 points. */
@property (nonatomic, assign)    CGFloat     dragScrollMaxVelocity;        /* The maximum velocity the view will scroll at when dragging (Ramped up from 0 the closer the finger is to the view boundary). Default is 20 points. */
@property (nonatomic, readonly)  CGSize      cellSize;                     /* The unmodified sizes of each cell. */
@property (nonatomic, copy, readonly) NSArray<TOGridViewCell *> *visibleCellViews;            /* An array of all visible cells inside the grid view */
@property (nonatomic, readonly)  NSInteger   numberOfCells;                /* Number of cells in the grid view */
@property (nonatomic, readonly)  NSInteger   numberOfCellsPerRow;          /* Number of cells on each row at present */
@property (nonatomic, assign)    BOOL        crossfadeCellsOnRotation;     /* Perform a crossfade transition on the visible cells when the grid view bounds change */
@property (nonatomic, readonly)  NSRange     visibleCellRange;             /* The index + range of the number of cells presently visible in the grid view */
@property (nonatomic, assign)    BOOL        allowsSelectionDuringEditing; /* When editing, cells can be selected for batch operations (Default: NO) */

/* Initialize and register a TOGridViewCell subclass. Nil uses TOGridViewCell. */
- (instancetype)initWithFrame:(CGRect)frame withCellClass:(nullable Class)cellClass NS_SWIFT_NAME(init(frame:cellClass:));

/* Register the TOGridViewCell subclass used for new cells. Nil restores the default. */
- (void)registerCellClass:(nullable Class)cellClass;

/* Get the cell object for a specific index (nil if invisible) */
- (nullable TOGridViewCell *)cellForIndex:(NSInteger)index;

/* Return a recycled cell, or create one using the registered class. Reuse order is unspecified. */
- (TOGridViewCell *)dequeueReusableCell;

/* Original spelling, retained for existing callers and subclass overrides. */
- (TOGridViewCell *)dequeReusableCell;

/* Dequeue a recycled decoration view for reuse */
- (nullable UIView *)dequeueReusableDecorationView;

/* Add new cells. Update the data source first; indices are unique positions in its final state.
   Animated insertions use staggered springs, revealing new cells while the movement settles.
   The completion handler runs once per batch, including an empty batch or an interrupted animation. */
- (BOOL)insertCellAtIndex:(NSInteger)index animated:(BOOL)animated;
- (BOOL)insertCellAtIndex:(NSInteger)index animated:(BOOL)animated completionHandler:(void (^ _Nullable)(void))completionHandler;
- (BOOL)insertCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated;
- (BOOL)insertCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated completionHandler:(void (^ _Nullable)(void))completionHandler;

/* Delete existing cells */
- (BOOL)deleteCellAtIndex:(NSInteger)index animated:(BOOL)animated;
- (BOOL)deleteCellAtIndex:(NSInteger)index animated:(BOOL)animated completionHandler:(void (^ _Nullable)(void))completionHandler;
- (BOOL)deleteCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated;
- (BOOL)deleteCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated completionHandler:(void (^ _Nullable)(void))completionHandler;

/* Reload existing cells */
- (BOOL)reloadCellAtIndex:(NSInteger)index;
- (BOOL)reloadCellsAtIndices:(NSArray<NSNumber *> *)indices;

/* Unhighlight a cell after it had been tapped (As opposed to 'deselecting' in edit mode) */
- (void)unhighlightCellAtIndex:(NSInteger)index animated:(BOOL)animated;

/* Reload the entire table */
- (void)reloadGrid;

/* Put the grid view into edit mode (Where cells can be selected and re-ordered.) */
- (void)setEditing:(BOOL)editing animated:(BOOL)animated NS_REQUIRES_SUPER;

/* Used to determine the origin (or center) of a cell at a particular index */
- (CGPoint)originOfCellAtIndex:(NSInteger)cellIndex;

/* Used to determine the size of a cell (eg in case specific cells needed to be padded in order to fit) */
- (CGSize)sizeOfCellAtIndex:(NSInteger)cellIndex;

/* Determine the current CGRect placement of a cell, relative to the grid view space */
- (CGRect)rectOfCellAtIndex:(NSInteger)cellIndex;

/* Selected indices in ascending order; an empty array when nothing is selected. */
- (NSArray<NSNumber *> *)indicesOfSelectedCells;

/* Set cells to their selected state in edit mode */
- (BOOL)selectCellAtIndex:(NSInteger)index animated:(BOOL)animated;
- (BOOL)selectCellsAtIndices:(NSArray<NSNumber *> *)indices animated:(BOOL)animated;

/* Deselect cells when in edit mode */
- (BOOL)deselectCellAtIndex:(NSInteger)index;
- (BOOL)deselectCellsAtIndices:(NSArray<NSNumber *> *)indices;

/* Scroll to a specific cell in the index */
- (void)scrollToCellAtIndex:(NSInteger)cellIndex toPosition:(TOGridViewScrollPosition)position animated:(BOOL)animated completed:(void (^ _Nullable)(void))completed;

@end

NS_ASSUME_NONNULL_END
