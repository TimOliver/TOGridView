#import <XCTest/XCTest.h>
#import "TOGridView.h"

@interface TOGridView (ScrollingTests)
- (void)layoutCells;
@end

@interface GeometryOverrideGrid : TOGridView
@end

@implementation GeometryOverrideGrid
- (CGPoint)originOfCellAtIndex:(NSInteger)index
{
    CGPoint origin = [super originOfCellAtIndex:index];
    return CGPointMake(origin.x + 3, origin.y + 4);
}
- (CGSize)sizeOfCellAtIndex:(NSInteger)index
{
    CGSize size = [super sizeOfCellAtIndex:index];
    return CGSizeMake(size.width - 2, size.height - 1);
}
@end

// Count actual dictionary scans, without inspecting the grid's cache flags.
@interface ScanningCellDictionary : NSMutableDictionary
@property (nonatomic, strong) NSMutableDictionary *storage;
@property (nonatomic) NSUInteger scans;
@end

@implementation ScanningCellDictionary
- (instancetype)init { if ((self = [super init])) _storage = [NSMutableDictionary new]; return self; }
- (NSUInteger)count { return self.storage.count; }
- (NSEnumerator *)keyEnumerator { return self.storage.keyEnumerator; }
- (id)objectForKey:(id)key { return self.storage[key]; }
- (void)setObject:(id)object forKey:(id<NSCopying>)key { self.storage[key] = object; }
- (void)removeObjectForKey:(id)key { [self.storage removeObjectForKey:key]; }
- (NSSet *)keysOfEntriesWithOptions:(NSEnumerationOptions)options passingTest:(BOOL (^)(id, id, BOOL *))predicate
{
    self.scans++;
    return [self.storage keysOfEntriesWithOptions:options passingTest:predicate];
}
@end

@interface GridScrollingTests : XCTestCase <TOGridViewDataSource, TOGridViewDelegate>
@property (nonatomic, strong) TOGridView *grid;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *items;
@property (nonatomic) NSUInteger configurations;
@property (nonatomic) NSUInteger endedDisplays;
@end

@implementation GridScrollingTests
- (void)setUp
{
    [super setUp];
    self.items = [NSMutableArray new];
    for (NSUInteger i = 0; i < 200; i++) [self.items addObject:@(i)];
    self.grid = [[TOGridView alloc] initWithFrame:CGRectMake(0, 0, 300, 300)];
    self.grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid reloadGrid];
}
- (void)tearDown
{
    self.grid = nil;
    [super tearDown];
}
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView { return self.items.count; }
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView { return 3; }
- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView { return CGSizeMake(100, 80); }
- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)index
{
    self.configurations++;
    TOGridViewCell *cell = [gridView dequeueReusableCell];
    cell.accessibilityValue = self.items[index].stringValue;
    return cell;
}
- (void)gridView:(TOGridView *)gridView didEndDisplayingCell:(TOGridViewCell *)cell atIndex:(NSInteger)index
{
    self.endedDisplays++;
}
- (void)assertVisibleContent
{
    NSRange range = self.grid.visibleCellRange;
    XCTAssertEqual(self.grid.visibleCellViews.count, range.length);
    for (NSUInteger index = range.location; index < NSMaxRange(range); index++) {
        TOGridViewCell *cell = [self.grid cellForIndex:index];
        XCTAssertEqualObjects(cell.accessibilityValue, self.items[index].stringValue);
        XCTAssertTrue(CGRectEqualToRect(cell.frame, [self.grid rectOfCellAtIndex:index]));
    }
}
- (void)testSameRangeSkipsScanningButRowCrossingsReconcile
{
    ScanningCellDictionary *cells = [ScanningCellDictionary new];
    [cells addEntriesFromDictionary:[self.grid valueForKey:@"visibleCells"]];
    [self.grid setValue:cells forKey:@"visibleCells"];
    [self.grid layoutCells];
    cells.scans = 0;
    self.configurations = self.endedDisplays = 0;
    TOGridViewCell *first = [self.grid cellForIndex:0];
    for (NSUInteger offset = 1; offset <= 10; offset++) {
        self.grid.contentOffset = CGPointMake(0, offset);
        [self.grid layoutSubviews];
    }
    XCTAssertEqual(cells.scans, 0);
    XCTAssertEqual(self.configurations, 0);
    XCTAssertEqual(self.endedDisplays, 0);
    XCTAssertEqual([self.grid cellForIndex:0], first);
    UIView *container = [self.grid valueForKey:@"cellContainerView"];
    XCTAssertTrue(CGRectEqualToRect(container.frame, self.grid.bounds));
    XCTAssertTrue(CGRectEqualToRect(container.bounds, self.grid.bounds));
    self.grid.contentOffset = CGPointMake(0, 90);
    [self.grid layoutSubviews];
    XCTAssertGreaterThan(cells.scans, 0);
    XCTAssertEqual(self.configurations, 3);
    XCTAssertEqual(self.endedDisplays, 3);
    [self assertVisibleContent];
}
- (void)testSameCountReloadAndSingleCellReloadRefreshContent
{
    self.items[0] = @999;
    [self.grid reloadCellsAtIndices:@[@0]];
    [self.grid layoutCells];
    [self assertVisibleContent];
    self.items[1] = @888;
    [self.grid reloadGrid];
    [self.grid layoutCells];
    [self assertVisibleContent];
}
- (void)testInsertionAndDeletionWithinSameVisibleRange
{
    [self.items insertObject:@999 atIndex:0];
    [self.grid insertCellAtIndex:0 animated:NO];
    [self.grid layoutCells];
    [self assertVisibleContent];
    [self.items removeObjectAtIndex:1];
    [self.grid deleteCellAtIndex:1 animated:NO];
    [self.grid layoutCells];
    [self assertVisibleContent];
}
- (void)testHeaderResizeEmptyGridAndRefillInvalidateTheRange
{
    self.grid.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 30)];
    [self.grid layoutCells];
    [self assertVisibleContent];
    self.grid.frame = CGRectMake(0, 0, 360, 320);
    [self.grid layoutCells];
    [self assertVisibleContent];
    [self.items removeAllObjects];
    [self.grid reloadGrid];
    XCTAssertEqual(self.grid.visibleCellViews.count, 0);
    [self.items addObjectsFromArray:@[@1, @2, @3]];
    [self.grid reloadGrid];
    [self assertVisibleContent];
}
- (void)testRecycledCellsAreReusedWithoutAllocatingOrDuplicating
{
    NSSet *original = [NSSet setWithArray:self.grid.visibleCellViews];
    self.grid.contentOffset = CGPointMake(0, 800);
    [self.grid layoutCells];
    XCTAssertEqualObjects([NSSet setWithArray:self.grid.visibleCellViews], original);
    [self assertVisibleContent];
}
- (void)testVisibleRangeAtRowBoundariesAndOutsideContent
{
    NSArray<NSNumber *> *offsets = @[@0, @79, @80, @160, @(-400), @5360];
    NSArray<NSValue *> *ranges = @[
        [NSValue valueWithRange:NSMakeRange(0, 12)],
        [NSValue valueWithRange:NSMakeRange(0, 15)],
        [NSValue valueWithRange:NSMakeRange(3, 12)],
        [NSValue valueWithRange:NSMakeRange(6, 12)],
        [NSValue valueWithRange:NSMakeRange(NSUIntegerMax, 0)],
        [NSValue valueWithRange:NSMakeRange(NSUIntegerMax, 0)]
    ];
    for (NSUInteger i = 0; i < offsets.count; i++) {
        self.grid.contentOffset = CGPointMake(0, offsets[i].doubleValue);
        XCTAssertTrue(NSEqualRanges(self.grid.visibleCellRange, ranges[i].rangeValue));
        [self.grid layoutCells];
        [self assertVisibleContent];
    }
}
- (void)testGeometryOverridesStillControlCellPlacement
{
    self.grid = [[GeometryOverrideGrid alloc] initWithFrame:CGRectMake(0, 0, 300, 300)];
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid reloadGrid];
    XCTAssertTrue(CGRectEqualToRect([self.grid rectOfCellAtIndex:0], CGRectMake(3, 4, 98, 79)));
    XCTAssertTrue(CGRectEqualToRect([self.grid cellForIndex:0].frame, CGRectMake(3, 4, 98, 79)));
    [self assertVisibleContent];
}
@end
