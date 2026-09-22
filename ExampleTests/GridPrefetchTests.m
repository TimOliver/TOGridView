#import <XCTest/XCTest.h>
#import "TOGridView.h"

@interface TOGridView (PrefetchTesting)
- (void)layoutCells;
@end

@interface GridPrefetchRecorder : NSObject <TOGridViewDataSourcePrefetching>
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *requests;
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *cancellations;
@property (nonatomic, copy) void (^onRequest)(TOGridView *grid, NSArray<NSNumber *> *indices);
@property (nonatomic, copy) void (^onCancel)(TOGridView *grid, NSArray<NSNumber *> *indices);
@end

@implementation GridPrefetchRecorder
- (instancetype)init
{
    if ((self = [super init])) {
        _requests = [NSMutableArray new];
        _cancellations = [NSMutableArray new];
    }
    return self;
}
- (void)gridView:(TOGridView *)grid prefetchCellsAtIndices:(NSArray<NSNumber *> *)indices
{
    NSAssert(NSThread.isMainThread, @"Prefetch callbacks must run on the main thread");
    [self.requests addObject:indices];
    if (self.onRequest) self.onRequest(grid, indices);
}
- (void)gridView:(TOGridView *)grid cancelPrefetchingForCellsAtIndices:(NSArray<NSNumber *> *)indices
{
    NSAssert(NSThread.isMainThread, @"Cancellation must run on the main thread");
    [self.cancellations addObject:indices];
    if (self.onCancel) self.onCancel(grid, indices);
}
@end

// Cancellation is optional; clients can keep a shared cache instead.
@interface GridPrefetchOnlyProvider : NSObject <TOGridViewDataSourcePrefetching>
@property (nonatomic) NSUInteger requests;
@end
@implementation GridPrefetchOnlyProvider
- (void)gridView:(TOGridView *)grid prefetchCellsAtIndices:(NSArray<NSNumber *> *)indices { self.requests++; }
@end

@interface GridPrefetchTests : XCTestCase <TOGridViewDataSource, TOGridViewDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) TOGridView *grid;
@property (nonatomic, strong) GridPrefetchRecorder *recorder;
@property (nonatomic) NSUInteger itemCount;
@property (nonatomic) NSUInteger configurations;
@end

@implementation GridPrefetchTests
- (void)setUp
{
    [super setUp];
    self.itemCount = 200;
    self.recorder = [GridPrefetchRecorder new];
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    self.grid = [[TOGridView alloc] initWithFrame:CGRectMake(0, 0, 300, 300)];
    self.grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.window.rootViewController.view addSubview:self.grid];
    [self.grid layoutIfNeeded];
}
- (void)tearDown
{
    self.recorder.onRequest = nil;
    self.recorder.onCancel = nil;
    self.grid.prefetchDataSource = nil;
    [self.grid removeFromSuperview];
    self.grid = nil;
    self.window.hidden = YES;
    self.window = nil;
    self.recorder = nil;
    [super tearDown];
}
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)grid { return self.itemCount; }
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)grid { return 3; }
- (CGSize)sizeOfCellsForGridView:(TOGridView *)grid { return CGSizeMake(100, 80); }
- (TOGridViewCell *)gridView:(TOGridView *)grid cellForIndex:(NSInteger)index
{
    self.configurations++;
    return [grid dequeueReusableCell];
}
- (void)drainCallbacks
{
    // Two queue turns also drain a reconciliation requested from inside a callback.
    XCTestExpectation *drained = [self expectationWithDescription:@"Deferred callbacks"];
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
    });
    [self waitForExpectations:@[drained] timeout:2];
}
- (void)enablePrefetching
{
    self.grid.prefetchDataSource = self.recorder;
    [self drainCallbacks];
}
- (void)scrollTo:(CGFloat)offset
{
    self.grid.contentOffset = CGPointMake(0, offset);
    [self.grid layoutIfNeeded];
    [self.grid layoutCells];
    [self drainCallbacks];
}
- (void)testOptInIsDeferredAndDoesNotConfigureOffscreenCells
{
    XCTAssertNil(self.grid.prefetchDataSource);
    XCTAssertEqual(self.grid.prefetchRowCount, 2);
    NSUInteger configurations = self.configurations;
    self.grid.prefetchDataSource = self.recorder;
    XCTAssertEqual(self.recorder.requests.count, 0);
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.requests, (@[@[@12, @13, @14, @15, @16, @17]]));
    XCTAssertEqual(self.configurations, configurations);
    XCTAssertNil([self.grid cellForIndex:12]);
    for (NSUInteger i = 1; i <= 10; i++) {
        self.grid.contentOffset = CGPointMake(0, i);
        [self.grid layoutCells];
    }
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 1);
    XCTAssertEqual(self.recorder.cancellations.count, 0);
}
- (void)testEnteringCellsConsumeRequestsWithoutCancellation
{
    [self enablePrefetching];
    [self scrollTo:80];
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@0, @1, @2, @18, @19, @20]));
    XCTAssertEqual(self.recorder.cancellations.count, 0);
    [self scrollTo:800];
    XCTAssertEqualObjects(self.recorder.cancellations.lastObject, (@[@0, @1, @2, @15, @16, @17, @18, @19, @20]));
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@24, @25, @26, @27, @28, @29, @42, @43, @44, @45, @46, @47]));
}
- (void)testReversingDirectionKeepsOverlappingRequests
{
    [self enablePrefetching];
    [self scrollTo:800];
    [self scrollTo:720];
    XCTAssertEqualObjects(self.recorder.cancellations.lastObject, (@[@45, @46, @47]));
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@21, @22, @23, @39, @40, @41]));
}
- (void)testRapidScrollChangesCoalesceToFinalViewport
{
    [self enablePrefetching];
    for (NSNumber *offset in @[@800, @1600, @2400]) {
        self.grid.contentOffset = CGPointMake(0, offset.doubleValue);
        [self.grid layoutCells];
    }
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 2);
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@84, @85, @86, @87, @88, @89, @102, @103, @104, @105, @106, @107]));
}
- (void)testRowCountChangesAndZeroDisable
{
    [self enablePrefetching];
    self.grid.prefetchRowCount = 1;
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.cancellations.lastObject, (@[@15, @16, @17]));
    self.grid.prefetchRowCount = 0;
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.cancellations.lastObject, (@[@12, @13, @14]));
    [self scrollTo:800];
    XCTAssertEqual(self.recorder.requests.count, 1);
    self.grid.prefetchRowCount = 1;
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@27, @28, @29, @42, @43, @44]));
}
- (void)testProviderReplacementCancelsWithOriginalProvider
{
    [self enablePrefetching];
    GridPrefetchRecorder *replacement = [GridPrefetchRecorder new];
    self.grid.prefetchDataSource = replacement;
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.cancellations, self.recorder.requests);
    XCTAssertEqualObjects(replacement.requests, self.recorder.requests);
    self.grid.prefetchDataSource = nil;
    [self drainCallbacks];
    XCTAssertEqualObjects(replacement.cancellations, replacement.requests);
}
- (void)testWeakProviderAndQueuedUpdateDoNotExtendLifetimes
{
    __weak GridPrefetchRecorder *weakProvider;
    @autoreleasepool {
        GridPrefetchRecorder *provider = [GridPrefetchRecorder new];
        weakProvider = provider;
        self.grid.prefetchDataSource = provider;
    }
    XCTAssertNil(weakProvider);
    [self drainCallbacks];
    XCTAssertNil(self.grid.prefetchDataSource);
    // A detached grid isolates queue ownership from UIKit's temporary window/layout retains.
    __weak TOGridView *weakGrid;
    @autoreleasepool {
        TOGridView *grid = [[TOGridView alloc] initWithFrame:CGRectZero];
        weakGrid = grid;
        grid.prefetchDataSource = self.recorder;
    }
    XCTAssertNil(weakGrid);
    [self drainCallbacks];
}
- (void)testReloadCancelsBeforeReissuingSameIndices
{
    [self enablePrefetching];
    __block BOOL cancelled = NO;
    self.recorder.onCancel = ^(TOGridView *grid, NSArray<NSNumber *> *indices) { cancelled = YES; };
    self.recorder.onRequest = ^(TOGridView *grid, NSArray<NSNumber *> *indices) { XCTAssertTrue(cancelled); };
    [self.grid reloadGrid];
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 2);
    XCTAssertEqualObjects(self.recorder.requests.firstObject, self.recorder.cancellations.lastObject);
    [self.grid reloadCellAtIndex:15]; // Offscreen content changed without changing the item count.
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 3);
    XCTAssertEqual(self.recorder.cancellations.count, 2);
}
- (void)testInsertAndDeleteInvalidateOriginalIndexRequests
{
    [self enablePrefetching];
    self.itemCount++;
    [self.grid insertCellAtIndex:0 animated:NO];
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.cancellations.lastObject, (@[@12, @13, @14, @15, @16, @17]));
    self.itemCount--;
    [self.grid deleteCellAtIndex:0 animated:NO];
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 3);
    XCTAssertEqual(self.recorder.cancellations.count, 2);
}
- (void)testAnimatedInsertionSuspendsRequestsUntilFinished
{
    [self enablePrefetching];
    XCTestExpectation *finished = [self expectationWithDescription:@"Insertion finished"];
    self.itemCount++;
    [self.grid insertCellAtIndex:0 animated:YES completionHandler:^{ [finished fulfill]; }];
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 1);
    XCTAssertEqual(self.recorder.cancellations.count, 1);
    [self waitForExpectations:@[finished] timeout:3];
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 2);
}
- (void)testDetachmentCancelsAndReattachmentRestarts
{
    [self enablePrefetching];
    [self.grid removeFromSuperview];
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.cancellations, self.recorder.requests);
    [self.window.rootViewController.view addSubview:self.grid];
    [self.grid layoutIfNeeded];
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 2);
}
- (void)testEmptyGridPartialLastRowAndOversizedLookahead
{
    self.itemCount = 14;
    [self.grid reloadGrid];
    [self enablePrefetching];
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@12, @13]));
    self.grid.prefetchRowCount = NSUIntegerMax;
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 1);
    self.itemCount = 0;
    [self.grid reloadGrid];
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.cancellations.lastObject, (@[@12, @13]));
    XCTAssertEqual(self.recorder.requests.count, 1);
}
- (void)testHeaderResizeAndEmptyViewportKeepRequestsInBounds
{
    self.grid.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 160)];
    [self enablePrefetching];
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@6, @7, @8, @9, @10, @11]));
    self.grid.frame = CGRectMake(0, 0, 300, 380);
    [self.grid layoutIfNeeded];
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@12, @13, @14]));
    XCTAssertEqual(self.recorder.cancellations.count, 0);
    self.grid.frame = CGRectZero;
    [self drainCallbacks];
    XCTAssertGreaterThan(self.recorder.cancellations.count, 0);
}
- (void)testCancellationCanReplaceProviderWithoutSendingStaleRequests
{
    [self enablePrefetching];
    GridPrefetchRecorder *replacement = [GridPrefetchRecorder new];
    self.recorder.onCancel = ^(TOGridView *grid, NSArray<NSNumber *> *indices) { grid.prefetchDataSource = replacement; };
    [self scrollTo:800];
    XCTAssertEqual(self.recorder.requests.count, 1);
    XCTAssertEqual(replacement.requests.count, 1);
}
- (void)testRequestCanDisablePrefetchingAndCancellationIsOptional
{
    self.recorder.onRequest = ^(TOGridView *grid, NSArray<NSNumber *> *indices) { grid.prefetchRowCount = 0; };
    [self enablePrefetching];
    XCTAssertEqualObjects(self.recorder.requests, self.recorder.cancellations);
    GridPrefetchOnlyProvider *provider = [GridPrefetchOnlyProvider new];
    self.grid.prefetchDataSource = provider;
    self.grid.prefetchRowCount = 2;
    [self drainCallbacks];
    [self scrollTo:800];
    XCTAssertEqual(provider.requests, 2);
}

- (void)testCancellationCanClearProviderWithoutIssuingMoreRequests
{
    [self enablePrefetching];
    self.recorder.onCancel = ^(TOGridView *grid, NSArray<NSNumber *> *indices) { grid.prefetchDataSource = nil; };
    [self scrollTo:800];
    XCTAssertEqual(self.recorder.cancellations.count, 1);
    XCTAssertEqual(self.recorder.requests.count, 1);
    XCTAssertNil(self.grid.prefetchDataSource);
}

- (void)testDataSourceReplacementWaitsForReloadedMetrics
{
    [self enablePrefetching];
    self.grid.dataSource = nil;
    self.itemCount = 14;
    self.grid.dataSource = self;
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.cancellations.count, 1);
    XCTAssertEqual(self.recorder.requests.count, 1);
    [self.grid reloadGrid];
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.requests.lastObject, (@[@12, @13]));
}

- (void)testDragLayoutSuspensionCancelsEvenWhenIndicesMoveAndResumeInOneTurn
{
    [self enablePrefetching];
    [self.grid setValue:@YES forKey:@"pauseCellLayout"];
    [self drainCallbacks];
    XCTAssertEqualObjects(self.recorder.cancellations, self.recorder.requests);
    [self.grid setValue:@NO forKey:@"pauseCellLayout"];
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.requests.count, 2);
    [self.grid setValue:@YES forKey:@"pauseCellLayout"];
    [self.grid setValue:@NO forKey:@"pauseCellLayout"];
    [self drainCallbacks];
    XCTAssertEqual(self.recorder.cancellations.count, 2);
    XCTAssertEqual(self.recorder.requests.count, 3);
}

- (void)testPrefetchCallbackCanReloadWithoutDuplicateOutstandingRequests
{
    __block NSUInteger callbacks = 0;
    self.recorder.onRequest = ^(TOGridView *grid, NSArray<NSNumber *> *indices) {
        if (++callbacks == 1) [grid reloadGrid];
    };
    [self enablePrefetching];
    XCTAssertEqual(callbacks, 2);
    XCTAssertEqual(self.recorder.cancellations.count, 1);
    XCTAssertEqualObjects(self.recorder.cancellations.firstObject, self.recorder.requests.firstObject);
}
@end
