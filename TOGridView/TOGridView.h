//
//  TOGridView.h
//  
//  Copyright 2014 Timothy Oliver. All rights reserved.
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
#import <QuartzCore/QuartzCore.h>

@class TOGridView;
@class TOGridViewCell;

typedef enum {
    TOGridViewScrollPositionTop=0,
    TOGridViewScrollPositionMiddle,
    TOGridViewScrollPositionBottom
} TOGridViewScrollPosition;

///
/// Data Source Object
///
@protocol TOGridViewDataSource <NSObject>

@required
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView;
- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)cellIndex;

@optional
- (BOOL)gridView:(TOGridView *)gridView canMoveCellAtIndex:(NSInteger)cellIndex;
- (BOOL)gridView:(TOGridView *)gridView canEditCellAtIndex:(NSInteger)cellIndex;

@end

///
/// Delegate Object
///
@protocol TOGridViewDelegate <NSObject, UIScrollViewDelegate>

@required
- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView;
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView;

@optional
- (CGSize)boundaryInsetsForGridView:(TOGridView *)gridView;
- (UIView *)gridView: (TOGridView *)gridView decorationViewForRowWithIndex:(NSUInteger)rowIndex;
- (NSUInteger)heightOfRowsInGridView:(TOGridView *)gridView;
- (NSUInteger)verticalOffsetOfCellsInRowsInGridView:(TOGridView *)gridView;

- (void)gridView:(TOGridView *)gridView willDisplayCell:(TOGridViewCell *)cell atIndex:(NSInteger)index;
- (void)gridView:(TOGridView *)gridView didEndDisplayingCell:(TOGridViewCell *)cell atIndex:(NSInteger)index;

// Cell interaction
- (void)gridView:(TOGridView *)gridView didTapCellAtIndex:(NSUInteger)index;
- (void)gridView:(TOGridView *)gridView didLongTapCellAtIndex:(NSInteger)index;
- (void)gridView:(TOGridView *)gridView didMoveCellAtIndex:(NSInteger)prevIndex toIndex:(NSInteger)newIndex;

//Edit mode
- (void)gridView:(TOGridView *)gridView didHighlightCellAtIndex:(NSInteger)index;
- (void)gridView:(TOGridView *)gridView didUnhighlightCellAtIndex:(NSInteger)index;

@end

@interface TOGridView : UIScrollView <UIGestureRecognizerDelegate> 

@property (nonatomic, assign)    id <TOGridViewDataSource>    dataSource;                   /* The object that will provide the grid view with data. */
@property (nonatomic, assign)    id <TOGridViewDelegate>      delegate;                     /* The object that the grid view will send events to. */
@property (nonatomic, strong)    UIView                       *headerView;                  /* A UIView placed at the top of the grid view */
@property (nonatomic, strong)    UIView                       *backgroundView;              /* A UIView placed behind the grid view and locked so it won't scroll */
@property (nonatomic, assign)    BOOL                         editing;                      /* Whether the grid view is in an editing state now. */
@property (nonatomic, assign)    BOOL                         nonRetinaRenderContexts;      /* If the grid view has a lot of complex cells, setting this can help boost animation performance at a visual expense on Retina devices. */
@property (nonatomic, assign)    NSInteger                    dragScrollBoundaryDistance;   /* The distance, in points, from the top of the view downwards that will trigger auto-scrolling when dragging a cell (Same for the bottom). Default is 60 points. */
@property (nonatomic, assign)    CGFloat                      dragScrollMaxVelocity;        /* The maximum velocity the view will scroll at when dragging (Ramped up from 0 the closer the finger is to the view boundary). Default is 15 points. */                /* Main array of visible cells */
@property (nonatomic, readonly)  CGSize                       cellSize;                     /* The unmodified sizes of each cell. */
@property (nonatomic, readonly)  NSArray                      *visibleCellViews;            /* An array of all visible cells inside the grid view */
@property (nonatomic, readonly)  NSInteger                    numberOfCells;                /* Number of cells in the grid view */
@property (nonatomic, readonly)  NSInteger                    numberOfCellsPerRow;          /* Number of cells on each row at present */
@property (nonatomic, assign)    BOOL                         crossfadeCellsOnRotation;     /* Perform a crossfade transition on the visible cells when the grid view bounds change */
@property (nonatomic, readonly)  NSRange                      visibleCellRange;             /* The index + range of the number of cells presently visible in the grid view */

/* Init the class, and register the cell class to use at the same time. (Else the default TOGridViewCell class is implemented) */
- (id)initWithFrame:(CGRect)frame withCellClass:(Class)cellClass;

/* Register the class that is used to spawn new cell views */
- (void)registerCellClass:(Class)cellClass;

/* Get the cell object for a specific index (nil if invisible) */
- (TOGridViewCell *)cellForIndex:(NSInteger)index;

/* Dequeue a recycled cell for reuse */
- (TOGridViewCell *)dequeReusableCell;

/* Dequeue a recycled decoration view for reuse */
- (UIView *)dequeueReusableDecorationView;

/* Add new cells */
- (BOOL)insertCellAtIndex:(NSInteger)index animated:(BOOL)animated;
- (BOOL)insertCellsAtIndices:(NSArray *)indices animated:(BOOL)animated;

/* Delete existing cells */
- (BOOL)deleteCellAtIndex:(NSInteger)index animated:(BOOL)animated;
- (BOOL)deleteCellsAtIndices:(NSArray *)indices animated:(BOOL)animated;

/* Reload existing cells */
- (BOOL)reloadCellAtIndex:(NSInteger)index;
- (BOOL)reloadCellsAtIndices:(NSArray *)indices;

/* Unhighlight a cell after it had been tapped (As opposed to 'deselecting' in edit mode) */
- (void)unhighlightCellAtIndex:(NSInteger)index animated:(BOOL)animated;

/* Reload the entire table */
- (void)reloadGrid;

/* Put the grid view into edit mode (Where cells can be selected and re-ordered.) */
- (void)setEditing:(BOOL)editing animated:(BOOL)animated;   

/* Used to determine the origin (or center) of a cell at a particular index */
- (CGPoint)originOfCellAtIndex:(NSInteger)cellIndex;

/* Used to determine the size of a cell (eg in case specific cells needed to be padded in order to fit) */
- (CGSize)sizeOfCellAtIndex:(NSInteger)cellIndex;

/* Determine the current CGRect placement of a cell, relative to the grid view space */
- (CGRect)rectOfCellAtIndex:(NSInteger)cellIndex;

/* Get a list of indices of selected cells */
- (NSArray *)indicesOfSelectedCells;

/* Set cells to their selected state in edit mode */
- (BOOL)selectCellAtIndex:(NSInteger)index;
- (BOOL)selectCellsAtIndices:(NSArray *)indices;

/* Deselect cells when in edit mode */
- (BOOL)deselectCellAtIndex:(NSInteger)index;
- (BOOL)deselectCellsAtIndices:(NSArray *)indices;

/* Scroll to a specific cell in the index */
- (void)scrollToCellAtIndex:(NSInteger)cellIndex toPosition:(TOGridViewScrollPosition)position animated:(BOOL)animated completed:(void (^)(void))completed;

@end

/*  
 The old-skool method of declaring classes accepting delegate protocols. Necessary to implement CAAnimationDelegate. 
*/
@interface TOGridView (CAAnimationDelegate)

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;

@end
