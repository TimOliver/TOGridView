#import <XCTest/XCTest.h>
#import "TOGridView.h"

@interface TOGridView (ReuseTesting)
- (void)layoutCells;
@end

@interface GridReuseCell : TOGridViewCell
@property (nonatomic) NSUInteger configurations;
@property (nonatomic) NSUInteger preparations;
@property (nonatomic, strong) NSObject *pendingLoad;
@end
@implementation GridReuseCell
- (void)prepareForReuse
{
    [super prepareForReuse];
    self.preparations++;
    self.pendingLoad = nil;
}
@end

@interface GridReuseTests : XCTestCase <TOGridViewDataSource, TOGridViewDelegate>
@property (nonatomic, strong) TOGridView *grid;
@end
@implementation GridReuseTests
- (void)setUp
{
    [super setUp];
    self.grid = [[TOGridView alloc] initWithFrame:CGRectMake(0, 0, 300, 300) withCellClass:GridReuseCell.class];
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid reloadGrid];
}
- (void)tearDown { self.grid = nil; [super tearDown]; }
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)grid { return 200; }
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)grid { return 3; }
- (CGSize)sizeOfCellsForGridView:(TOGridView *)grid { return CGSizeMake(100, 80); }
- (TOGridViewCell *)gridView:(TOGridView *)grid cellForIndex:(NSInteger)index
{
    GridReuseCell *cell = (GridReuseCell *)[grid dequeueReusableCell];
    XCTAssertNil(cell.pendingLoad);
    XCTAssertEqual(cell.preparations, cell.configurations);
    cell.configurations++;
    cell.pendingLoad = [NSObject new];
    return cell;
}
- (void)testReuseHappensBeforeConfigurationAndOnlyForRecycledCells
{
    NSSet<GridReuseCell *> *original = [NSSet setWithArray:self.grid.visibleCellViews];
    for (GridReuseCell *cell in original) XCTAssertEqual(cell.preparations, 0);
    self.grid.contentOffset = CGPointMake(0, 800);
    [self.grid layoutCells];
    XCTAssertEqualObjects(original, [NSSet setWithArray:self.grid.visibleCellViews]);
    for (GridReuseCell *cell in original) {
        XCTAssertEqual(cell.preparations, 1);
        XCTAssertNotNil(cell.pendingLoad);
    }
    GridReuseCell *fresh = (GridReuseCell *)[self.grid dequeueReusableCell];
    XCTAssertEqual(fresh.preparations, 0);
}
- (void)testLeavingDisplayDoesNotPrepareUntilEitherDequeueSpellingIsUsed
{
    NSArray<GridReuseCell *> *original = (NSArray<GridReuseCell *> *)self.grid.visibleCellViews;
    self.grid.contentOffset = CGPointMake(0, 10000);
    [self.grid layoutCells];
    XCTAssertEqual(self.grid.visibleCellViews.count, 0);
    for (GridReuseCell *cell in original) {
        XCTAssertEqual(cell.preparations, 0);
        XCTAssertNotNil(cell.pendingLoad);
    }
    GridReuseCell *first = (GridReuseCell *)[self.grid dequeReusableCell];
    GridReuseCell *second = (GridReuseCell *)[self.grid dequeueReusableCell];
    XCTAssertNotEqual(first, second);
    XCTAssertEqual(first.preparations, 1);
    XCTAssertEqual(second.preparations, 1);
    XCTAssertNil(first.pendingLoad);
    XCTAssertNil(second.pendingLoad);
}
- (void)testSingleCellAndFullReloadPrepareReusedCells
{
    GridReuseCell *first = (GridReuseCell *)[self.grid cellForIndex:0];
    [self.grid reloadCellAtIndex:0];
    XCTAssertEqual([self.grid cellForIndex:0], first);
    XCTAssertEqual(first.preparations, 1);
    [self.grid reloadGrid];
    XCTAssertEqual(first.preparations, 2);
}
- (void)testBaseHookPreservesExistingState
{
    TOGridViewCell *cell = [TOGridViewCell new];
    cell.selected = YES;
    cell.editing = YES;
    cell.accessibilityLabel = @"Existing content";
    [cell prepareForReuse];
    XCTAssertTrue(cell.selected);
    XCTAssertTrue(cell.editing);
    XCTAssertEqualObjects(cell.accessibilityLabel, @"Existing content");
}
@end
