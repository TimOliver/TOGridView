//
//  TOGridView.m
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

#import "TOGridView.h"
#import <QuartzCore/QuartzCore.h>

@interface TOGridView (hidden)

- (void)resetCellMetrics;
- (void)layoutCells;
- (CGSize)contentSizeOfScrollView;
- (CGPoint)originOfCellAtIndex: (NSInteger)cellIndex;
- (TOGridViewCell *)cellForIndex: (NSInteger)index;
- (UIImage *)snapshotOfCellsInRect: (CGRect)rect;
- (void)invalidateVisibleCells;

@end

@implementation TOGridView

@synthesize dataSource = _dataSource, headerView = _headerView, backgroundView = _backgroundView;

#pragma mark -
#pragma mark View Management
- (id)initWithFrame:(CGRect)frame
{
    if( self = [super initWithFrame: frame] )
    {
        self.bounces                = YES;
        self.scrollsToTop           = YES;
        self.backgroundColor        = [UIColor blackColor];
        self.scrollEnabled          = YES;
        self.alwaysBounceVertical   = YES;
        
        _recycledCells  = [NSMutableSet new];
        _visibleCells   = [NSMutableSet new];
        _cellClass      = [TOGridViewCell class];
    }
    
    return self;
}

- (id)initWithFrame:(CGRect)frame withCellClass:(Class)cellClass
{
    if( self = [self initWithFrame: frame] )
    {
        [self registerCellClass: cellClass];
    }
    
    return self;
}

- (void)registerCellClass: (Class)cellClass
{
    _cellClass = cellClass;
}

/* Kickstart the loading of the cells when this view is added to the view hierarchy */
- (void)didMoveToSuperview
{
    [self reloadGrid];
}

#pragma mark -
#pragma mark Set-up
- (void)reloadGrid
{
    /* Get the number of cells from the data source */
    if( _gridViewFlags.dataSourceNumberOfCells )
        _numberOfCells = [_dataSource numberOfCellsInGridView: self];
    
    /* Use the delegate+dataSource to set up the rendering logistics of the cells */
    [self resetCellMetrics];
    
    /* Set up an array to track the selected state of each cell */
    _selectedCells = nil;
    _selectedCells = [NSMutableArray arrayWithCapacity: _numberOfCells];
    for( NSInteger i = 0; i < [_selectedCells count]; i++ )
        [_selectedCells addObject: [NSNumber numberWithBool: FALSE]];

    /* Perform a redraw operation */
    [self layoutCells];
}

- (void)resetCellMetrics
{
    /* Get outer padding of cells */
    if( _gridViewFlags.delegateInnerPadding )
        _cellPaddingInset = [self.delegate innerPaddingForGridView: self];
    
    /* Grab the size of each cell */
    if( _gridViewFlags.delegateSizeOfCells )
        _cellSize = [self.delegate sizeOfCellsForGridView: self];
    
    /* See if there is a custom height for each row of cells */
    if( _gridViewFlags.delegateHeightOfRows )
        _rowHeight = [self.delegate heightOfRowsInGridView: self];
    else
        _rowHeight = _cellSize.height;
    
    /* See if there is a custom offset of cells from within each row */
    if( _gridViewFlags.delegateOffsetOfCellInRow )
        _offsetOfCellsInRow = [self.delegate offsetOfCellsInRowsInGridView: self];
    
    /* Get the number of cells per row */
    if( _gridViewFlags.delegateNumberOfCellsPerRow )
        _numberOfCellsPerRow = [self.delegate numberOfCellsPerRowForGridView:self];
    
    /* Work out the spacing between cells */
    _widthBetweenCells = (NSInteger)floor(((CGRectGetWidth(self.bounds) - (_cellPaddingInset.width*2)) //Overall width of row
                                           - (_cellSize.width * _numberOfCellsPerRow)) //minus the combined width of all cells
                                          / (_numberOfCellsPerRow-1)); //divided by the number of gaps between
    
    /* Set up the scrollview */
    self.contentSize = [self contentSizeOfScrollView];
}

- (CGSize)contentSizeOfScrollView
{
    CGSize size;
    size.width = CGRectGetWidth(self.bounds);
    
    size.height = _offsetFromHeader;
    size.height += _cellPaddingInset.height * 2;
    
    if( _numberOfCells )
        size.height += (NSInteger)(ceil( (CGFloat)_numberOfCells / (CGFloat)_numberOfCellsPerRow ) * _rowHeight);
    
    return size;
}

- (CGPoint)originOfCellAtIndex:(NSInteger)cellIndex
{
    CGPoint origin;
    
    origin.y = _offsetFromHeader + _offsetOfCellsInRow + _cellPaddingInset.height + (_rowHeight * floor(cellIndex/_numberOfCellsPerRow));
    origin.x = _cellPaddingInset.width  + ((cellIndex % _numberOfCellsPerRow) * (_cellSize.width+_widthBetweenCells));
    
    return origin;
}

- (void)invalidateVisibleCells
{
    for( TOGridViewCell *cell in _visibleCells )
    {
        [cell removeFromSuperview];
        [_recycledCells addObject: cell];
    }
    
    [_visibleCells minusSet: _recycledCells];
}

#pragma mark -
#pragma mark Cell Management
- (TOGridViewCell *)cellForIndex:(NSInteger)index
{
    for( TOGridViewCell *cell in _visibleCells )
    {
        if( cell.index == index)
            return cell;
    }
    
    return nil;
}

- (void)layoutCells
{
    if( _numberOfCells == 0 )
        return;
    
    //The official origin of the first row, accounting for the header size and outer padding
    NSInteger rowOrigin = _offsetFromHeader + _cellPaddingInset.height;
    CGFloat contentOffsetY = self.bounds.origin.y; //bounds.origin on a scrollview contains the best up-to-date contentOffset
    NSInteger numberOfRows = floor(_numberOfCells / _numberOfCellsPerRow);
    
    NSInteger firstVisibleRow   = floor((contentOffsetY-rowOrigin) / _rowHeight);
    NSInteger lastVisibleRow    = floor(((contentOffsetY-rowOrigin)+CGRectGetHeight(self.bounds))/ _rowHeight);
    
    //make sure there are actually some visible rows
    if( lastVisibleRow >= 0 && firstVisibleRow <= numberOfRows )
    {
        _visibleCellRange.location  = MAX(0,firstVisibleRow) * _numberOfCellsPerRow;
        _visibleCellRange.length    = (((lastVisibleRow - MAX(0,firstVisibleRow))+1) * _numberOfCellsPerRow);
    
        if( _visibleCellRange.location + _visibleCellRange.length >= _numberOfCells )
            _visibleCellRange.length = _numberOfCells - _visibleCellRange.location;
    }
    else
    {
        _visibleCellRange.location = -1;
        _visibleCellRange.length = 0;
    }
    
    for( TOGridViewCell *cell in _visibleCells )
    {
        if( cell.index < _visibleCellRange.location || cell.index >= _visibleCellRange.location+_visibleCellRange.length )
        {
            [_recycledCells addObject: cell];
            [cell removeFromSuperview];
        }
    }
    if( [_recycledCells count] )
        [_visibleCells minusSet: _recycledCells];
    
    if( [_visibleCells count] >= _visibleCellRange.length )
        return;
    
    for( NSInteger i = 0; i < _visibleCellRange.length; i++ )
    {
        NSInteger index = _visibleCellRange.location+i;
        
        TOGridViewCell *cell = [self cellForIndex: index];
        if( cell )
            continue;
        
        cell = [_dataSource gridView: self cellForIndex: index];
        cell.index = index;
        
        CGRect cellFrame;
        cellFrame.origin = [self originOfCellAtIndex: index];
        cellFrame.size = _cellSize;
        cell.frame = cellFrame;
        
        [_visibleCells addObject: cell];
        
        if( _backgroundView )
            [self insertSubview: cell aboveSubview: _backgroundView];
        else
            [self insertSubview: cell atIndex: 0];
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
        
    __block UIImageView *_beforeSnapshot, *_afterSnapshot;
    
    //detecting an animation to change the bounds
    CABasicAnimation *boundsAnimation = (CABasicAnimation *)[self.layer animationForKey: @"bounds"];
    if( boundsAnimation )
    {
        self.scrollEnabled = NO;
        
        //halt the scroll view if it's currently moving
        if( self.isDecelerating || self.isDragging )
            [self setContentOffset: self.bounds.origin animated: NO];
        
        CGRect beforeRect = [boundsAnimation.fromValue CGRectValue];
        _beforeSnapshot = [[UIImageView alloc] initWithImage: [self snapshotOfCellsInRect: beforeRect]];
        
        [self resetCellMetrics];
        
        //manually set contentOffset's value based off bounds.
        //Not sure why, but if we don't do this, periodically, contentOffset resets to 0,0 and borks the animation :S
        if( self.contentSize.height - self.bounds.size.height >= beforeRect.origin.y )
            self.contentOffset = beforeRect.origin;
        
        for( TOGridViewCell *cell in _visibleCells )
        {
            CGRect frame = cell.frame;
            frame.origin = [self originOfCellAtIndex: cell.index];
            frame.size = _cellSize;
            cell.frame = frame;
        }
    }
    
    //update the cells
    [self layoutCells];
    
    //set up the second half of the animation crossfade and then animate it
    if( boundsAnimation )
    {        
        CGFloat duration = boundsAnimation.duration;
        
        CGRect afterRect = self.bounds;
        _afterSnapshot = [[UIImageView alloc] initWithImage: [self snapshotOfCellsInRect: afterRect]];
        
        _beforeSnapshot.frame = CGRectMake( CGRectGetMinX(self.frame), CGRectGetMinY(self.frame), CGRectGetWidth(_beforeSnapshot.frame), CGRectGetHeight(_beforeSnapshot.frame));
        [_beforeSnapshot.layer removeAllAnimations];
        
        _afterSnapshot.frame = CGRectMake( CGRectGetMinX(self.frame), CGRectGetMinY(self.frame), CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
        [_afterSnapshot.layer removeAllAnimations];
        
        for( TOGridViewCell *cell in _visibleCells )
        {
            cell.hidden = YES;
            [cell.layer removeAllAnimations];
        }
        
        //place these snapshots outside the scrollview, otherwise they'll move during animation
        //TODO: Maybe try and find a way to keep these snapshots within the view itself.
        [self.superview insertSubview: _beforeSnapshot aboveSubview: self];
        [self.superview insertSubview: _afterSnapshot aboveSubview: _beforeSnapshot];
        
        _afterSnapshot.alpha    = 0.0f;
        _beforeSnapshot.alpha   = 1.0f;
        
        [UIView animateWithDuration: duration delay: 0.0f options: UIViewAnimationCurveEaseInOut animations: ^{
            _beforeSnapshot.alpha = 0.0f;
            _afterSnapshot.alpha = 1.0f;
        } completion: ^(BOOL complete) {
            [_afterSnapshot removeFromSuperview];
            [_beforeSnapshot removeFromSuperview];
            
            _afterSnapshot = nil;
            _beforeSnapshot = nil;
            
            for( TOGridViewCell *cell in _visibleCells )
                cell.hidden = NO;
            
            self.scrollEnabled = YES;
        }];
    }
    
    /* Update the background view to stay in the background */
    if( _backgroundView )
        _backgroundView.frame = CGRectMake( 0, self.bounds.origin.y, CGRectGetWidth(_backgroundView.bounds), CGRectGetHeight(_backgroundView.bounds));
}

- (UIImage *)snapshotOfCellsInRect:(CGRect)rect
{
    UIGraphicsBeginImageContextWithOptions( rect.size, NO, [[UIScreen mainScreen] scale] );
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    for( TOGridViewCell *cell in _visibleCells )
    {
        CGContextSaveGState(context);
        CGContextTranslateCTM( context, cell.frame.origin.x, (cell.frame.origin.y-CGRectGetMinY(rect)) );
        [cell.layer renderInContext: context];
        CGContextRestoreGState(context);
    }
        
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return image;
}

#pragma mark -
#pragma mark Cell/Decoration Handling

/* Dequeue a recycled cell for reuse */
- (TOGridViewCell *)dequeReusableCell
{
    TOGridViewCell *cell = [_recycledCells anyObject];
    
    if( cell )
    {
        [_recycledCells removeObject: cell];
        return cell;
    }
    
    cell = [[_cellClass alloc] init];
    cell.frame = CGRectMake(0, 0, _cellSize.width, _cellSize.height);
    cell.gridView = self;
    return cell;
}

- (UIView *)dequeueReusableDecorationView
{
    return nil;
}

/* Add/edit/delete cells */
- (BOOL)deleteCellAtIndex: (NSInteger)index animated: (BOOL)animated
{
    return YES;
}

- (BOOL)deleteCellsAtIndicies: (NSArray *)indices animated: (BOOL)animated
{
    return YES;
}

#pragma mark -
#pragma mark Accessors
- (void)setDelegate:(id<TOGridViewDelegate>)delegate
{
    if( self.delegate == delegate )
        return;
    
    [super setDelegate: delegate];
    
    _gridViewFlags.delegateDecorationView       = [self.delegate respondsToSelector: @selector(gridView:decorationViewForRowWithIndex:)];
    _gridViewFlags.delegateInnerPadding         = [self.delegate respondsToSelector: @selector(innerPaddingForGridView:)];
    _gridViewFlags.delegateNumberOfCellsPerRow  = [self.delegate respondsToSelector: @selector(numberOfCellsPerRowForGridView:)];
    _gridViewFlags.delegateSizeOfCells          = [self.delegate respondsToSelector: @selector(sizeOfCellsForGridView:)];
    _gridViewFlags.delegateHeightOfRows         = [self.delegate respondsToSelector: @selector(heightOfRowsInGridView:)];
}

- (void)setDataSource:(id<TOGridViewDataSource>)dataSource
{
    if( _dataSource == dataSource )
        return;
    
    _dataSource = dataSource;
    
    _gridViewFlags.dataSourceCellForIndex       = [_dataSource respondsToSelector: @selector( gridView:cellForIndex:)];
    _gridViewFlags.dataSourceNumberOfCells      = [_dataSource respondsToSelector: @selector(numberOfCellsInGridView:)];
}

- (void)setHeaderView:(UIView *)headerView
{
    if( _headerView == headerView )
        return;
    
    [_headerView removeFromSuperview];
    _headerView = headerView;
    _headerView.frame = CGRectMake( 0, 0, CGRectGetWidth(_headerView.frame), CGRectGetHeight(_headerView.frame));
    _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    _offsetFromHeader = CGRectGetHeight(headerView.bounds);
    
    [self addSubview: _headerView];
    
    self.contentSize = [self contentSizeOfScrollView];
    [self invalidateVisibleCells];
    [self layoutCells];
}

- (void)setBackgroundView:(UIView *)backgroundView
{
    if( _backgroundView == backgroundView )
        return;
    [_backgroundView removeFromSuperview];
    _backgroundView = backgroundView;
    
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _backgroundView.frame = self.bounds;
    
    [self insertSubview: _backgroundView atIndex: 0];
    
    for( TOGridViewCell *cell in _visibleCells )
        [self insertSubview: cell aboveSubview: _backgroundView];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame: frame];

    /* If the frame changes, and we're NOT animating, invalidate all of the visible cells and reload the view */
    /* If we are animating (eg, orientation change), this will be handled in layoutSubviews. */
    if( [self.layer animationForKey: @"bounds"] == nil )
    {
        [self invalidateVisibleCells];
        [self resetCellMetrics];
    }
}

@end
