#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>
#import "TOGridView.h"

@interface TOGridView (PreparationTesting)
- (void)layoutCells;
- (void)prepareNextCell:(CADisplayLink *)link;
- (void)prepareCellBeforeDeadline:(CFTimeInterval)deadline;
- (void)updatePrefetching;
- (void)updateCellPreparation;
@end

@interface PreparationCell : TOGridViewCell
@property (nonatomic) NSUInteger reuseCount;
@property (nonatomic) NSUInteger layoutCount;
@property (nonatomic) NSUInteger stateUpdates;
@end
@implementation PreparationCell
- (void)prepareForReuse { [super prepareForReuse]; self.reuseCount++; }
- (void)layoutSubviews { [super layoutSubviews]; self.layoutCount++; }
- (void)setEditing:(BOOL)value animated:(BOOL)animated { [super setEditing:value animated:animated]; self.stateUpdates++; }
- (void)setSelected:(BOOL)value animated:(BOOL)animated { [super setSelected:value animated:animated]; self.stateUpdates++; }
- (void)setHighlighted:(BOOL)value animated:(BOOL)animated { [super setHighlighted:value animated:animated]; self.stateUpdates++; }
- (void)setDraggable:(BOOL)value { [super setDraggable:value]; self.stateUpdates++; }
- (void)setHidden:(BOOL)value { [super setHidden:value]; self.stateUpdates++; }
- (void)setFrame:(CGRect)value { [super setFrame:value]; self.stateUpdates++; }
@end

@interface PreparationGrid : TOGridView
@property (nonatomic) CFTimeInterval preparationTimestamp;
@property (nonatomic) BOOL testWithGenerousDeadline;
@property (nonatomic) CGFloat cellOriginAdjustment;
@end
@implementation PreparationGrid
- (CGPoint)originOfCellAtIndex:(NSInteger)index
{
    CGPoint origin = [super originOfCellAtIndex:index];
    origin.x += self.cellOriginAdjustment;
    return origin;
}
- (void)prepareNextCell:(CADisplayLink *)link
{
    self.preparationTimestamp = link.timestamp;
    if (self.testWithGenerousDeadline)
        [super prepareCellBeforeDeadline:CACurrentMediaTime() + 1];
    else
        [super prepareNextCell:link];
}
@end

@interface GridCellPreparationTests : XCTestCase <TOGridViewDataSource, TOGridViewDelegate, TOGridViewDataSourcePrefetching>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) PreparationGrid *grid;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *items;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *requests;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *displayed;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *ended;
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *dataRequests;
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *dataCancellations;
@property (nonatomic, copy) void (^onConfigure)(NSInteger index, PreparationCell *cell);
@property (nonatomic) BOOL cellsCanEdit;
@property (nonatomic) BOOL cellsCanMove;
@end

@implementation GridCellPreparationTests
- (void)setUp
{
    [super setUp];
    self.cellsCanEdit = self.cellsCanMove = YES;
    self.items = [NSMutableArray new];
    for (NSUInteger i = 0; i < 200; i++) [self.items addObject:@(i)];
    self.requests = [NSMutableArray new]; self.displayed = [NSMutableArray new]; self.ended = [NSMutableArray new];
    self.dataRequests = [NSMutableArray new]; self.dataCancellations = [NSMutableArray new];
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    self.grid = [[PreparationGrid alloc] initWithFrame:CGRectMake(0, 0, 300, 300) withCellClass:PreparationCell.class];
    self.grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.grid.dataSource = self; self.grid.delegate = self;
    [self.window.rootViewController.view addSubview:self.grid];
    [self.grid layoutIfNeeded];
    [self.requests removeAllObjects]; [self.displayed removeAllObjects];
}
- (void)tearDown
{
    self.onConfigure = nil;
    self.grid.cellPrefetchingEnabled = NO;
    self.grid.prefetchDataSource = nil;
    [self.grid removeFromSuperview];
    self.grid = nil;
    self.window.hidden = YES; self.window = nil;
    [super tearDown];
}
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)grid { return self.items.count; }
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)grid { return 3; }
- (CGSize)sizeOfCellsForGridView:(TOGridView *)grid { return CGSizeMake(100, 80); }
- (BOOL)gridView:(TOGridView *)grid canEditCellAtIndex:(NSInteger)index { return self.cellsCanEdit; }
- (BOOL)gridView:(TOGridView *)grid canMoveCellAtIndex:(NSInteger)index { return self.cellsCanMove; }
- (TOGridViewCell *)gridView:(TOGridView *)grid cellForIndex:(NSInteger)index
{
    XCTAssertTrue(NSThread.isMainThread);
    PreparationCell *cell = (PreparationCell *)[grid dequeueReusableCell];
    cell.accessibilityValue = self.items[index].stringValue;
    [self.requests addObject:@(index)];
    if (self.onConfigure) self.onConfigure(index, cell);
    return cell;
}
- (void)gridView:(TOGridView *)grid willDisplayCell:(TOGridViewCell *)cell atIndex:(NSInteger)index { [self.displayed addObject:@(index)]; }
- (void)gridView:(TOGridView *)grid didEndDisplayingCell:(TOGridViewCell *)cell atIndex:(NSInteger)index { [self.ended addObject:@(index)]; }
- (void)gridView:(TOGridView *)grid prefetchCellsAtIndices:(NSArray<NSNumber *> *)indices { [self.dataRequests addObject:indices]; }
- (void)gridView:(TOGridView *)grid cancelPrefetchingForCellsAtIndices:(NSArray<NSNumber *> *)indices { [self.dataCancellations addObject:indices]; }
- (NSDictionary<NSNumber *, PreparationCell *> *)preparedCells { return [self.grid valueForKey:@"preparedCells"] ?: @{}; }
- (void)step { [self.grid prepareCellBeforeDeadline:CACurrentMediaTime() + 1]; }
- (void)warmNextRow
{
    self.grid.cellPrefetchingEnabled = YES;
    [self step]; [self step]; [self step];
}
- (void)scrollTo:(CGFloat)y
{
    self.grid.contentOffset = CGPointMake(0, y);
    [self.grid layoutCells];
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
- (void)testDisabledByDefaultAndNeverDefersVisibleCells
{
    XCTAssertFalse(self.grid.cellPrefetchingEnabled);
    [self step];
    XCTAssertEqual(self.requests.count, 0);
    [self scrollTo:800];
    XCTAssertEqual(self.requests.count, 12);
    [self assertVisibleContent];
}
- (void)testOneDetachedLaidOutCellPerStepAndNoDisplayCallbacks
{
    self.grid.cellPrefetchingEnabled = YES;
    for (NSUInteger i = 0; i < 3; i++) {
        [self step];
        XCTAssertEqual(self.requests.count, i + 1);
        PreparationCell *cell = self.preparedCells[@(12 + i)];
        XCTAssertNotNil(cell);
        XCTAssertNil(cell.superview);
        XCTAssertGreaterThan(cell.layoutCount, 0);
        XCTAssertNil([self.grid cellForIndex:12 + i]);
    }
    [self step];
    XCTAssertEqualObjects(self.requests, (@[@12, @13, @14]));
    XCTAssertEqual(self.displayed.count, 0);
    XCTAssertEqual(self.ended.count, 0);
    XCTAssertNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
}
- (void)testActualDisplayLinkSpreadsConfigurationAcrossRefreshes
{
    // Verify refresh pacing independently of simulator/host load. Deadline skipping
    // is checked separately, and the device benchmark uses the real deadline.
    self.grid.testWithGenerousDeadline = YES;
    XCTestExpectation *prepared = [self expectationWithDescription:@"Three refreshes prepare one row"];
    prepared.expectedFulfillmentCount = 3;
    NSMutableArray<NSNumber *> *timestamps = [NSMutableArray new];
    __weak PreparationGrid *weakGrid = self.grid;
    self.onConfigure = ^(NSInteger index, PreparationCell *cell) {
        [timestamps addObject:@(weakGrid.preparationTimestamp)];
        [prepared fulfill];
    };
    self.grid.cellPrefetchingEnabled = YES;
    [self waitForExpectations:@[prepared] timeout:3];
    XCTAssertEqualObjects(self.requests, (@[@12, @13, @14]));
    XCTAssertEqual([NSSet setWithArray:timestamps].count, 3);
    for (NSUInteger i = 1; i < timestamps.count; i++)
        XCTAssertGreaterThan(timestamps[i].doubleValue, timestamps[i - 1].doubleValue);
}
- (void)testExpiredDeadlineSkipsWork
{
    self.grid.cellPrefetchingEnabled = YES;
    [self.grid prepareCellBeforeDeadline:CACurrentMediaTime() - 1];
    XCTAssertEqual(self.requests.count, 0);
    [self step];
    XCTAssertEqual(self.requests.count, 1);
}
- (void)testRepeatedBudgetMissesParkUntilVisibleRangeChanges
{
    self.grid.cellPrefetchingEnabled = YES;
    [self step];
    PreparationCell *readyCell = self.preparedCells[@12];
    // Model an unusually expensive sample without making the test depend on CPU speed.
    [self.grid setValue:@2 forKey:@"estimatedCellPreparationDuration"];
    for (NSUInteger i = 0; i < 3; i++)
        [self.grid prepareCellBeforeDeadline:CACurrentMediaTime() + 0.1];
    XCTAssertNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
    XCTAssertEqual(self.requests.count, 1);
    XCTAssertEqual(self.preparedCells[@12], readyCell);

    // Queued updates, generous deadlines and motion within this range cannot restart it.
    for (NSUInteger i = 0; i < 5; i++) {
        [self.grid updateCellPreparation];
        [self step];
    }
    [self scrollTo:1];
    [self.grid updateCellPreparation];
    XCTAssertNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
    XCTAssertEqual(self.requests.count, 1);

    [self scrollTo:80];
    [self assertVisibleContent];
    XCTAssertEqual([self.grid cellForIndex:12], readyCell);
    [self.grid updateCellPreparation];
    XCTAssertNotNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
    [self step];
    XCTAssertNotNil(self.preparedCells[@15]);
}
- (void)testSuccessfulPreparationResetsConsecutiveMissesAndReloadRestartsParkedWork
{
    self.grid.cellPrefetchingEnabled = YES;
    for (NSUInteger i = 0; i < 2; i++)
        [self.grid prepareCellBeforeDeadline:CACurrentMediaTime() - 1];
    [self step];
    for (NSUInteger i = 0; i < 2; i++)
        [self.grid prepareCellBeforeDeadline:CACurrentMediaTime() - 1];
    XCTAssertNotNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
    [self.grid prepareCellBeforeDeadline:CACurrentMediaTime() - 1];
    XCTAssertNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
    [self.grid reloadGrid];
    [self.requests removeAllObjects];
    [self step];
    XCTAssertEqualObjects(self.requests, (@[@12]));
}
- (void)testPreparedPromotionSkipsUnchangedStateSettersIncludingSelection
{
    self.grid.allowsSelectionDuringEditing = YES;
    [self.grid setEditing:YES animated:NO];
    [self.grid selectCellAtIndex:12 animated:NO];
    [self warmNextRow];
    PreparationCell *cell = self.preparedCells[@12];
    XCTAssertTrue(cell.selected);
    XCTAssertTrue(cell.editing);
    XCTAssertTrue(cell.draggable);
    cell.stateUpdates = 0;
    [self scrollTo:80];
    XCTAssertEqual([self.grid cellForIndex:12], cell);
    XCTAssertEqual(cell.stateUpdates, 0);
    [self assertVisibleContent];
}
- (void)testPreparedPromotionRefreshesChangedStatePermissionsAndGeometry
{
    self.grid.allowsSelectionDuringEditing = YES;
    [self.grid setEditing:YES animated:NO];
    [self warmNextRow];
    PreparationCell *cell = self.preparedCells[@12];
    [self.grid selectCellAtIndex:12 animated:NO];
    XCTAssertFalse(cell.selected); // The offscreen cell has not been updated yet.
    self.cellsCanEdit = self.cellsCanMove = NO;
    self.grid.cellOriginAdjustment = 5;
    cell.hidden = YES;
    [cell setHighlighted:YES animated:NO];
    [self scrollTo:80];
    XCTAssertEqual([self.grid cellForIndex:12], cell);
    XCTAssertTrue(cell.selected);
    XCTAssertFalse(cell.editing);
    XCTAssertFalse(cell.draggable);
    XCTAssertFalse(cell.hidden);
    XCTAssertFalse(cell.highlighted);
    XCTAssertTrue(CGRectEqualToRect(cell.frame, [self.grid rectOfCellAtIndex:12]));
}
- (void)testPromotionAndReversalReuseIdentityWithoutReconfiguration
{
    NSMutableArray *firstRow = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        TOGridViewCell *cell = [self.grid cellForIndex:i];
        XCTAssertNotNil(cell);
        if (cell != nil) [firstRow addObject:cell];
    }
    [self warmNextRow];
    PreparationCell *prepared = self.preparedCells[@12];
    NSUInteger reuseCount = prepared.reuseCount;
    [self scrollTo:80];
    XCTAssertEqual([self.grid cellForIndex:12], prepared);
    XCTAssertEqual(prepared.reuseCount, reuseCount);
    XCTAssertEqualObjects(self.displayed, (@[@12, @13, @14]));
    XCTAssertEqualObjects([self.ended sortedArrayUsingSelector:@selector(compare:)], (@[@0, @1, @2]));
    XCTAssertEqual(self.requests.count, 3);
    [self scrollTo:0];
    XCTAssertEqual(self.requests.count, 3);
    for (NSUInteger i = 0; i < 3; i++) XCTAssertEqual([self.grid cellForIndex:i], firstRow[i]);
    [self assertVisibleContent];
}
- (void)testFastJumpsFillVisibleCellsAndKeepCacheBounded
{
    [self warmNextRow];
    for (NSNumber *offset in @[@800, @1600, @2400, @800, @80, @160, @240]) {
        [self scrollTo:offset.doubleValue];
        [self assertVisibleContent];
        XCTAssertLessThanOrEqual(self.preparedCells.count, 6);
        for (PreparationCell *cell in self.preparedCells.allValues) {
            XCTAssertNil(cell.superview);
            XCTAssertFalse([self.grid.visibleCellViews containsObject:cell]);
        }
    }
}
- (void)testPreparationPrioritizesScrollDirection
{
    self.grid.cellPrefetchingEnabled = YES;
    [self scrollTo:800];
    [self.requests removeAllObjects];
    [self step];
    XCTAssertEqualObjects(self.requests, (@[@42]));
    [self scrollTo:400];
    [self.requests removeAllObjects];
    [self step];
    XCTAssertEqualObjects(self.requests, (@[@14]));
}
- (void)testReloadInsertionDeletionAndResizeInvalidatePreparedContent
{
    [self warmNextRow];
    self.items[12] = @999;
    [self.grid reloadCellAtIndex:12];
    XCTAssertEqual(self.preparedCells.count, 0);
    [self step];
    XCTAssertEqualObjects(self.preparedCells[@12].accessibilityValue, @"999");
    [self.items insertObject:@888 atIndex:0];
    [self.grid insertCellAtIndex:0 animated:NO];
    // The last visible cell moved offscreen and can be kept with its new, valid index.
    XCTAssertEqualObjects(self.preparedCells[@12].accessibilityValue, self.items[12].stringValue);
    [self step];
    XCTAssertEqualObjects(self.preparedCells[@12].accessibilityValue, self.items[12].stringValue);
    [self.items removeObjectAtIndex:0];
    [self.grid deleteCellAtIndex:0 animated:NO];
    XCTAssertEqual(self.preparedCells.count, 0);
    [self step];
    self.grid.frame = CGRectMake(0, 0, 360, 300);
    XCTAssertEqual(self.preparedCells.count, 0);
    [self.grid layoutIfNeeded];
    [self step];
    XCTAssertTrue(CGRectEqualToRect(self.preparedCells[@12].frame, [self.grid rectOfCellAtIndex:12]));
    [self assertVisibleContent];
}
- (void)testEditingAndDragSuspensionDiscardPreparedState
{
    [self warmNextRow];
    [self.grid setEditing:YES animated:NO];
    XCTAssertEqual(self.preparedCells.count, 0);
    [self step];
    XCTAssertTrue(self.preparedCells[@12].editing);
    [self.grid setValue:@YES forKey:@"pauseCellLayout"];
    [self step];
    XCTAssertEqual(self.preparedCells.count, 0);
    XCTAssertNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
    [self.grid setValue:@NO forKey:@"pauseCellLayout"];
    [self step];
    XCTAssertEqual(self.preparedCells.count, 1);
}
- (void)testDisableDetachAndMemoryWarningStopPreparation
{
    [self warmNextRow];
    self.grid.cellPrefetchingEnabled = NO;
    XCTAssertEqual(self.preparedCells.count, 0);
    [self warmNextRow];
    [self.grid removeFromSuperview];
    XCTAssertEqual(self.preparedCells.count, 0);
    [self step];
    XCTAssertNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
    [self.window.rootViewController.view addSubview:self.grid];
    [self.grid layoutIfNeeded];
    [self warmNextRow];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    NSUInteger count = self.requests.count;
    [self step];
    XCTAssertEqual(self.requests.count, count);
    XCTAssertEqual(self.preparedCells.count, 0);
    XCTAssertEqual([[self.grid valueForKey:@"recycledCells"] count], 0);
    [self scrollTo:80];
    [self step];
    XCTAssertGreaterThan(self.preparedCells.count, 0);
}
- (void)testDataPrefetchRequestsAreConsumedWhenCellIsPrepared
{
    self.grid.prefetchDataSource = self;
    [self.grid updatePrefetching];
    XCTAssertEqualObjects(self.dataRequests.lastObject, (@[@12, @13, @14, @15, @16, @17]));
    [self warmNextRow];
    [self.grid updatePrefetching];
    XCTAssertEqual(self.dataRequests.count, 1);
    XCTAssertEqual(self.dataCancellations.count, 0);
    [self scrollTo:800];
    [self.grid updatePrefetching];
    XCTAssertEqualObjects(self.dataCancellations.lastObject, (@[@15, @16, @17]));
}
- (void)testConfigurationCallbackCanReloadOrDisableWithoutCachingStaleCell
{
    self.grid.cellPrefetchingEnabled = YES;
    __weak PreparationGrid *weakGrid = self.grid;
    __block BOOL reloaded = NO;
    self.onConfigure = ^(NSInteger index, PreparationCell *cell) {
        if (!reloaded) { reloaded = YES; [weakGrid reloadGrid]; }
    };
    [self step];
    XCTAssertEqual(self.preparedCells.count, 0);
    [self assertVisibleContent];
    self.onConfigure = ^(NSInteger index, PreparationCell *cell) { weakGrid.cellPrefetchingEnabled = NO; };
    [self step];
    XCTAssertEqual(self.preparedCells.count, 0);
    XCTAssertNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
}

- (void)testPreparationUsesGridTraitsAndDropsCacheWhenTheyChange
{
    self.grid.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if (@available(iOS 17.0, *)) [self.grid updateTraitsIfNeeded];
    self.grid.cellPrefetchingEnabled = YES;
    self.onConfigure = ^(NSInteger index, PreparationCell *cell) {
        XCTAssertEqual(UITraitCollection.currentTraitCollection.userInterfaceStyle, UIUserInterfaceStyleDark);
    };
    [self step];
    self.onConfigure = nil;
    self.grid.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    if (@available(iOS 17.0, *)) [self.grid updateTraitsIfNeeded];
    [self scrollTo:80];
    // Index 12 must be configured again in the new environment before display.
    XCTAssertEqual([[self.requests filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self == 12"]] count], 2);
}
@end
