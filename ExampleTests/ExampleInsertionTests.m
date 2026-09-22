#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>
#import "TOGridView.h"
#import "TOGridViewCell.h"

@interface TOGridView (AnimationTesting)
- (void)updateCellsLayoutWithDraggedCellAtPoint:(CGPoint)point;
- (void)setCell:(TOGridViewCell *)cell atIndex:(NSInteger)index dragging:(BOOL)dragging animated:(BOOL)animated;
@end

@interface ExampleInsertionTests : XCTestCase <TOGridViewDataSource, TOGridViewDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) TOGridView *grid;
@property (nonatomic) NSUInteger itemCount;
@property (nonatomic) NSUInteger dataSourceRequests;
@end

@implementation ExampleInsertionTests

- (void)setUp
{
    [super setUp];
    self.itemCount = 30;
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    self.grid = [[TOGridView alloc] initWithFrame:CGRectMake(0, 0, 300, 400) withCellClass:TOGridViewCell.class];
    self.grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.window.rootViewController.view addSubview:self.grid];
    [self.grid layoutIfNeeded];
    [CATransaction flush];
}

- (void)tearDown
{
    [self.grid reloadGrid];
    [self.grid removeFromSuperview];
    self.grid.dataSource = nil;
    self.grid.delegate = nil;
    self.grid = nil;
    self.window.hidden = YES;
    self.window = nil;
    [super tearDown];
}

- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView { self.dataSourceRequests++; return self.itemCount; }
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView { return 3; }
- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView { return CGSizeMake(100, 80); }
- (UIEdgeInsets)boundaryInsetsForGridView:(TOGridView *)gridView { return UIEdgeInsetsZero; }
- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)index { return [gridView dequeReusableCell]; }

- (void)assertInsertionFinished
{
    XCTAssertEqual(self.grid.numberOfCells, self.itemCount);
    XCTAssertNil([self.grid valueForKey:@"insertingCells"]);
    XCTAssertFalse([[self.grid valueForKey:@"pauseCellLayout"] boolValue]);
    NSRange range = self.grid.visibleCellRange;
    for (NSUInteger index = range.location; index < NSMaxRange(range); index++) {
        TOGridViewCell *cell = [self.grid cellForIndex:index];
        XCTAssertNotNil(cell);
        XCTAssertTrue(CGRectEqualToRect(cell.frame, [self.grid rectOfCellAtIndex:index]));
        XCTAssertFalse(cell.hidden);
        XCTAssertEqualWithAccuracy(cell.alpha, 1, 0.001);
        XCTAssertTrue(CGAffineTransformIsIdentity(cell.transform));
    }
}

- (void)testInsertionRevealsNewCellWhileCascadedSpringsAreStillMoving
{
    XCTestExpectation *completion = [self expectationWithDescription:@"Insertion completes after the cascade and reveal"];
    completion.assertForOverFulfill = YES;
    XCTestExpectation *overlap = [self expectationWithDescription:@"The new cell appears before the movement finishes"];
    __block BOOL completed = NO;
    TOGridViewCell *first = [self.grid cellForIndex:0];
    TOGridViewCell *firstWrap = [self.grid cellForIndex:2];
    TOGridViewCell *sameRow = [self.grid cellForIndex:3];
    TOGridViewCell *secondWrap = [self.grid cellForIndex:5];
    self.itemCount++;
    [self.grid insertCellAtIndex:0 animated:YES completionHandler:^{
        completed = YES;
        [self assertInsertionFinished];
        for (TOGridViewCell *cell in @[first, firstWrap, sameRow, secondWrap])
            XCTAssertNil([cell.layer animationForKey:@"position"]);
        [completion fulfill];
    }];
    XCTAssertTrue([self.grid cellForIndex:0].hidden);
    XCTAssertEqual([self.grid cellForIndex:1], first);
    [CATransaction flush];
    CAAnimation *firstAnimation = [first.layer animationForKey:@"position"];
    CAAnimation *wrapAnimation = [firstWrap.layer animationForKey:@"position"];
    CAAnimation *sameRowAnimation = [sameRow.layer animationForKey:@"position"];
    CAAnimation *secondWrapAnimation = [secondWrap.layer animationForKey:@"position"];
    XCTAssertNotNil(firstAnimation);
    XCTAssertNotNil(wrapAnimation);
    XCTAssertNotNil(sameRowAnimation);
    XCTAssertNotNil(secondWrapAnimation);
    XCTAssertTrue([firstAnimation isKindOfClass:CASpringAnimation.class]);
    if ([firstAnimation isKindOfClass:CASpringAnimation.class]) {
        CASpringAnimation *spring = (CASpringAnimation *)firstAnimation;
        CGFloat dampingRatio = spring.damping / (2 * sqrt(spring.mass * spring.stiffness));
        XCTAssertEqualWithAccuracy(dampingRatio, 1.0, 0.01);
        XCTAssertEqualWithAccuracy(spring.initialVelocity, 0.0, 0.001);
    }
    XCTAssertEqualWithAccuracy(wrapAnimation.beginTime - firstAnimation.beginTime, 0.03, 0.01);
    XCTAssertEqualWithAccuracy(sameRowAnimation.beginTime, wrapAnimation.beginTime, 0.01);
    XCTAssertEqualWithAccuracy(secondWrapAnimation.beginTime - wrapAnimation.beginTime, 0.03, 0.01);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.26 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TOGridViewCell *insertedCell = [self.grid cellForIndex:0];
        XCTAssertFalse(insertedCell.hidden);
        XCTAssertFalse(completed);
        XCTAssertNotNil([secondWrap.layer animationForKey:@"position"]);
        CAAnimation *reveal = [insertedCell.layer animationForKey:@"opacity"];
        XCTAssertNotNil(reveal);
        XCTAssertEqualWithAccuracy(reveal.beginTime - firstAnimation.beginTime, 0.2, 0.04);
        [overlap fulfill];
    });
    [self waitForExpectations:@[overlap, completion] timeout:3];
}

- (void)testReloadCancelsPendingRevealWithoutChangingReusedCell
{
    __block NSUInteger completions = 0;
    self.itemCount++;
    [self.grid insertCellAtIndex:0 animated:YES completionHandler:^{ completions++; }];
    TOGridViewCell *insertedCell = [self.grid cellForIndex:0];
    [self.grid reloadGrid];
    XCTAssertEqual(completions, 1u);
    insertedCell.alpha = 0.6;
    XCTestExpectation *cancelled = [self expectationWithDescription:@"The stale reveal does not touch a recycled cell"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertEqualWithAccuracy(insertedCell.alpha, 0.6, 0.001);
        XCTAssertNil([insertedCell.layer animationForKey:@"opacity"]);
        XCTAssertEqual(completions, 1u);
        insertedCell.alpha = 1;
        [self assertInsertionFinished];
        [cancelled fulfill];
    });
    [self waitForExpectations:@[cancelled] timeout:3];
}

- (void)testReorderingUsesSpringsWhenDirectionChangesAndCellDrops
{
    TOGridViewCell *dragged = [self.grid cellForIndex:0];
    TOGridViewCell *neighbor = [self.grid cellForIndex:2];
    [self.grid setValue:dragged forKey:@"draggingCell"];
    [self.grid setValue:@0 forKey:@"draggingOverIndex"];
    [self.grid setValue:@YES forKey:@"pauseCellLayout"];
    [self.grid setCell:dragged atIndex:0 dragging:YES animated:YES];
    CGRect target = [self.grid rectOfCellAtIndex:4];
    [self.grid updateCellsLayoutWithDraggedCellAtPoint:CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target))];
    [CATransaction flush];
    XCTAssertTrue([[neighbor.layer animationForKey:@"position"] isKindOfClass:CASpringAnimation.class]);
    XCTAssertTrue([[dragged.layer animationForKey:@"transform"] isKindOfClass:CASpringAnimation.class]);
    XCTAssertEqual([self.grid cellForIndex:1], neighbor);

    XCTestExpectation *retargeted = [self expectationWithDescription:@"The moving cell reverses direction with a spring"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGRect before = neighbor.layer.presentationLayer.frame;
        CGRect target = [self.grid rectOfCellAtIndex:1];
        [self.grid updateCellsLayoutWithDraggedCellAtPoint:CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target))];
        [CATransaction flush];
        CGRect after = neighbor.layer.presentationLayer.frame;
        XCTAssertEqualWithAccuracy(after.origin.x, before.origin.x, 10);
        XCTAssertEqualWithAccuracy(after.origin.y, before.origin.y, 10);
        XCTAssertTrue(CGSizeEqualToSize(neighbor.bounds.size, CGSizeMake(100, 80)));
        XCTAssertTrue([[neighbor.layer animationForKey:@"position"] isKindOfClass:CASpringAnimation.class]);
        XCTAssertEqual([self.grid cellForIndex:2], neighbor);
        [self.grid setCell:dragged atIndex:1 dragging:NO animated:YES];
        [CATransaction flush];
        XCTAssertTrue([[dragged.layer animationForKey:@"transform"] isKindOfClass:CASpringAnimation.class]);
        [self.grid setValue:nil forKey:@"draggingCell"];
        [self.grid setValue:@NO forKey:@"pauseCellLayout"];
        [retargeted fulfill];
    });
    [self waitForExpectations:@[retargeted] timeout:3];
}

- (void)testOffscreenInsertionCompletesWithoutMovingVisibleCells
{
    NSArray *visibleCells = self.grid.visibleCellViews;
    XCTestExpectation *completion = [self expectationWithDescription:@"Offscreen insertion completes once"];
    completion.assertForOverFulfill = YES;
    self.itemCount++;
    [self.grid insertCellAtIndex:self.itemCount - 1 animated:YES completionHandler:^{ [completion fulfill]; }];
    [self waitForExpectations:@[completion] timeout:3];
    XCTAssertEqualObjects([NSSet setWithArray:visibleCells], [NSSet setWithArray:self.grid.visibleCellViews]);
    [self assertInsertionFinished];
}

- (void)testInsertionIntoEmptyGridRevealsCellsWithoutAMovementPhase
{
    self.itemCount = 0;
    [self.grid reloadGrid];
    self.itemCount = 3;
    XCTestExpectation *completion = [self expectationWithDescription:@"New cells appear without waiting for existing cells"];
    completion.assertForOverFulfill = YES;
    [self.grid insertCellsAtIndices:@[@2, @0, @1] animated:YES completionHandler:^{ [completion fulfill]; }];
    [self waitForExpectations:@[completion] timeout:3];
    [self assertInsertionFinished];
}

- (void)testOffscreenInsertionWaitsForFooterMovement
{
    self.grid.footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 20)];
    CGFloat previousY = self.grid.footerView.frame.origin.y;
    XCTestExpectation *completion = [self expectationWithDescription:@"Footer finishes moving before completion"];
    completion.assertForOverFulfill = YES;
    self.itemCount++;
    [self.grid insertCellAtIndex:self.itemCount - 1 animated:YES completionHandler:^{
        XCTAssertGreaterThan(self.grid.footerView.frame.origin.y, previousY);
        XCTAssertNil([self.grid.footerView.layer animationForKey:@"position"]);
        [completion fulfill];
    }];
    [self waitForExpectations:@[completion] timeout:3];
    [self assertInsertionFinished];
}

- (void)testInsertionCompletesOnceWhenAnimationsAreDisabled
{
    XCTestExpectation *completion = [self expectationWithDescription:@"Disabled animations still complete the insertion once"];
    completion.assertForOverFulfill = YES;
    [UIView setAnimationsEnabled:NO];
    @try {
        self.itemCount++;
        [self.grid insertCellAtIndex:0 animated:YES completionHandler:^{ [completion fulfill]; }];
        [self waitForExpectations:@[completion] timeout:3];
        XCTAssertFalse(UIView.areAnimationsEnabled);
        [self assertInsertionFinished];
    } @finally {
        [UIView setAnimationsEnabled:YES];
    }
}

- (void)testRemovingGridDoesNotReloadItsDataSource
{
    NSUInteger requests = self.dataSourceRequests;
    [self.grid removeFromSuperview];
    XCTAssertEqual(self.dataSourceRequests, requests);
    [self.window.rootViewController.view addSubview:self.grid];
    XCTAssertGreaterThan(self.dataSourceRequests, requests);
}

@end
