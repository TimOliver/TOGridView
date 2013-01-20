//
//  TOGridView.h
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

#import <Foundation/Foundation.h>

@class TOGridView;
@class TOGridViewCell;

@protocol TOGridViewDataSource <NSObject>

@required
- (NSUInteger)numberOfCellsInGridView: (TOGridView *)gridView;
- (TOGridViewCell *)gridView: (TOGridView *)gridView cellForIndex: (NSInteger)cellIndex;

@end

@protocol TOGridViewDelegate <NSObject, UIScrollViewDelegate>

@required
- (CGSize)sizeOfCellsForGridView: (TOGridView *)gridView;
- (NSUInteger)numberOfCellsPerRowForGridView: (TOGridView *)gridView;

@optional
- (CGSize)innerPaddingForGridView: (TOGridView *)gridView;
- (UIView *)gridView: (TOGridView *)gridView decorationViewForRowWithIndex: (NSUInteger)rowIndex;
- (NSUInteger)heightOfRowsInGridView: (TOGridView *)gridView;
- (NSUInteger)offsetOfCellsInRowsInGridView: (TOGridView *)gridView;
- (void)gridView: (TOGridView *) didTapCellAtIndex: (NSUInteger)index;
- (void)gridView:(TOGridView *)gridView didLongTapCellAtIndex: (NSInteger)index;

@end

@interface TOGridView : UIScrollView {
    /* The class that is used to spawn cells */
    Class       _cellClass;
    
    /* The range of cells visible now */
    NSRange     _visibleCellRange;
    
    /* Stores for cells in use, and ones in stadby */
    NSMutableSet *_recycledCells;
    NSMutableSet *_visibleCells;

    /* Decoration views */
    NSMutableSet *_recyledDecorationViews;
    NSMutableSet *_visibleDecorationViews;
    
    /* An array of all cells, and whether they're selected or not */
    NSMutableArray *_selectedCells;
    
    /* Padding of cells from edge of view */
    CGSize _cellPaddingInset;
    /*Size of each cell */
    CGSize _cellSize;
    
    /* Number of cells in grid view */
    NSInteger _numberOfCells;
    
    /* Number of cells per row */
    NSInteger _numberOfCellsPerRow;
    
    /* The width between cells on a single row */
    NSInteger _widthBetweenCells;
    
    /* The height of each row (ie the height of each decoration view) */
    NSInteger _rowHeight;
    
    /* Y-position of where the first row starts, after the header */
    NSInteger _offsetFromHeader;
    
    /* Y-offset of cell, within the row */
    NSInteger _offsetOfCellsInRow;
    
    /* Only one cell can ever be highlighted at once. This tracks that state */
    NSInteger _highlightedCellIndex;
    
    struct {
        unsigned int dataSourceNumberOfCells;
        unsigned int dataSourceCellForIndex;
        
        unsigned int delegateSizeOfCells;
        unsigned int delegateNumberOfCellsPerRow;
        unsigned int delegateInnerPadding;
        unsigned int delegateDecorationView;
        unsigned int delegateHeightOfRows;
        unsigned int delegateOffsetOfCellInRow;
        unsigned int delegateDidLongTapCell;
    } _gridViewFlags;
}

@property(nonatomic,assign) id <TOGridViewDataSource>    dataSource;
@property(nonatomic,assign) id <TOGridViewDelegate>      delegate;
@property(nonatomic,strong) UIView                       *headerView;
@property(nonatomic,strong) UIView                       *backgroundView;
@property(nonatomic,assign) BOOL                         editing;
@property(nonatomic,assign) NSInteger                    highlightedCellIndex;

/* Init the class, and register the cell class to use at the same time */
- (id)initWithFrame:(CGRect)frame withCellClass: (Class)cellClass;

/* Register the class that is used to spawn new cell views */
- (void)registerCellClass: (Class)cellClass;

/* Dequeue a recycled cell for reuse */
- (TOGridViewCell *)dequeReusableCell;
- (UIView *)dequeueReusableDecorationView;

/* Add/edit/delete cells */
- (BOOL)deleteCellAtIndex: (NSInteger)index animated: (BOOL)animated;
- (BOOL)deleteCellsAtIndicies: (NSArray *)indices animated: (BOOL)animated;

/* Reload the entire table */
- (void)reloadGrid;

/**************************************************/
/* Cell callbacks */
- (void)tappedCellAtIndex: (NSInteger)cellIndex;

@end
