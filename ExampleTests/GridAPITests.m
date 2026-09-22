#import <XCTest/XCTest.h>
#import "TOGridView.h"

@interface GridAPITestProvider : NSObject <TOGridViewDataSource, TOGridViewDelegate>
@end

@implementation GridAPITestProvider
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView { return 40; }
- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)index { return [gridView dequeueReusableCell]; }
- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView { return CGSizeMake(160, 80); }
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView { return 2; }
@end

@interface GridAPITestInsetProvider : GridAPITestProvider
@end

@implementation GridAPITestInsetProvider
- (UIEdgeInsets)boundaryInsetsForGridView:(TOGridView *)gridView { return UIEdgeInsetsMake(10, 10, 10, 10); }
- (NSUInteger)verticalOffsetOfCellsInRowsInGridView:(TOGridView *)gridView { return 20; }
@end

@interface GridAPITestLegacyGrid : TOGridView
@property (nonatomic) NSUInteger dequeueCount;
@end

@implementation GridAPITestLegacyGrid
- (TOGridViewCell *)dequeReusableCell
{
    self.dequeueCount++;
    return [super dequeReusableCell];
}
@end

@interface GridAPITests : XCTestCase
@end

@implementation GridAPITests

- (void)testDefaultCellAndLegacyDequeueOverride
{
    GridAPITestLegacyGrid *grid = [[GridAPITestLegacyGrid alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    XCTAssertNotNil([grid dequeueReusableCell]);
    XCTAssertEqual(grid.dequeueCount, 1);
    XCTAssertNotNil([grid dequeReusableCell]);
    XCTAssertEqual(grid.dequeueCount, 2);
    [grid registerCellClass:nil];
    XCTAssertEqual([grid dequeueReusableCell].class, TOGridViewCell.class);
    XCTAssertThrowsSpecificNamed([grid registerCellClass:UIView.class], NSException, NSInvalidArgumentException);
}

- (void)testCollectionsAreEmptyInsteadOfNilBeforeLoading
{
    TOGridView *grid = [[TOGridView alloc] initWithFrame:CGRectZero];
    XCTAssertEqualObjects(grid.visibleCellViews, @[]);
    XCTAssertEqualObjects(grid.indicesOfSelectedCells, @[]);
    XCTAssertNil([grid cellForIndex:0]);
    XCTAssertNil([grid dequeueReusableDecorationView]);
    XCTAssertNotNil([TOGridViewCell new].contentView);
}

- (void)testDataSourceAndDelegateAreZeroingWeak
{
    TOGridView *grid = [[TOGridView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    @autoreleasepool {
        GridAPITestProvider *provider = [GridAPITestProvider new];
        grid.dataSource = provider;
        grid.delegate = provider;
        [grid reloadGrid];
        XCTAssertGreaterThan(grid.visibleCellViews.count, 0);
    }
    XCTAssertNil(grid.dataSource);
    XCTAssertNil(grid.delegate);
    // Scrolling after the owner is released must not ask a stale source for cells.
    grid.contentOffset = CGPointMake(0, 160);
    [grid layoutIfNeeded];
    XCTAssertNoThrow([grid reloadGrid]);
    XCTAssertEqual(grid.numberOfCells, 0);
    XCTAssertEqualObjects(grid.visibleCellViews, @[]);
    XCTAssertTrue(isfinite(grid.contentSize.height));
}

- (void)testClearingDataSourceAndReplacingDelegateResetsMetrics
{
    TOGridView *grid = [[TOGridView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    GridAPITestInsetProvider *insetProvider = [GridAPITestInsetProvider new];
    GridAPITestProvider *plainProvider = [GridAPITestProvider new];
    grid.dataSource = insetProvider;
    grid.delegate = insetProvider;
    [grid reloadGrid];
    XCTAssertTrue(CGPointEqualToPoint([grid originOfCellAtIndex:0], CGPointMake(10, 30)));
    grid.delegate = plainProvider;
    [grid reloadGrid];
    XCTAssertTrue(CGPointEqualToPoint([grid originOfCellAtIndex:0], CGPointZero));
    grid.dataSource = nil;
    [grid reloadGrid];
    XCTAssertEqual(grid.numberOfCells, 0);
    XCTAssertEqualObjects(grid.visibleCellViews, @[]);
}

- (void)testOptionalGridViewsCanBeRemoved
{
    TOGridView *grid = [[TOGridView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 40)];
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 40)];
    UIView *background = [UIView new];
    grid.headerView = header;
    grid.footerView = footer;
    grid.backgroundView = background;
    XCTAssertNoThrow(grid.headerView = nil);
    XCTAssertNoThrow(grid.footerView = nil);
    XCTAssertNoThrow(grid.backgroundView = nil);
    XCTAssertNil(header.superview);
    XCTAssertNil(footer.superview);
    XCTAssertNil(background.superview);
}

- (void)testOptionalCellBackgroundsCanBeRemoved
{
    TOGridViewCell *cell = [[TOGridViewCell alloc] initWithFrame:CGRectMake(0, 0, 160, 80)];
    UIView *background = [UIView new];
    UIView *highlight = [UIView new];
    UIView *selection = [UIView new];
    cell.backgroundView = background;
    cell.highlightedBackgroundView = highlight;
    cell.selectedBackgroundView = selection;
    XCTAssertNoThrow(cell.backgroundView = nil);
    XCTAssertNoThrow(cell.highlightedBackgroundView = nil);
    XCTAssertNoThrow(cell.selectedBackgroundView = nil);
    XCTAssertNil(background.superview);
    XCTAssertNil(highlight.superview);
    XCTAssertNil(selection.superview);
    [cell setHighlighted:YES animated:YES];
    [cell setSelected:YES animated:YES];
    XCTAssertTrue(cell.highlighted);
    XCTAssertTrue(cell.selected);
}

@end
