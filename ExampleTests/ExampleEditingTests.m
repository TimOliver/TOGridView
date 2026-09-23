#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>
#import "TOGridViewTestCell.h"

@interface EditingLayoutCell : TOGridViewTestCell
@property (nonatomic) NSUInteger layoutCount;
@end
@implementation EditingLayoutCell
- (void)layoutSubviews { [super layoutSubviews]; self.layoutCount++; }
@end

@interface ExampleEditingTests : XCTestCase
@property (nonatomic, strong) EditingLayoutCell *cell;
@end

@implementation ExampleEditingTests

- (void)setUp
{
    [super setUp];
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    self.cell = [[EditingLayoutCell alloc] initWithFrame:CGRectMake(0, 0, 320, 72)];
    self.cell.textLabel.text = @"Cell 0";
    [scene.keyWindow.rootViewController.view addSubview:self.cell];
    [self.cell layoutIfNeeded];
    [CATransaction flush];
}

- (void)tearDown
{
    [self.cell setEditing:NO animated:NO];
    [self.cell removeFromSuperview];
    self.cell = nil;
    [super tearDown];
}

- (void)assertLinearIndicatorFades
{
    for (NSString *key in @[@"selectionIndicator", @"reorderIndicator"]) {
        UIView *indicator = [self.cell valueForKey:key];
        CAAnimation *fade = [indicator.layer animationForKey:@"opacity"];
        XCTAssertNotNil(fade);
        XCTAssertFalse([fade isKindOfClass:CASpringAnimation.class]);
        XCTAssertEqualWithAccuracy(fade.duration, 0.2, 0.001);
        XCTAssertNotNil(fade.timingFunction);
        for (NSUInteger i = 1; i <= 2; i++) {
            float point[2] = { -1, -2 };
            [fade.timingFunction getControlPointAtIndex:i values:point];
            XCTAssertEqualWithAccuracy(point[0], point[1], 0.001);
        }
        XCTAssertFalse(indicator.hidden);
    }
    XCTAssertTrue([[self.cell.textLabel.layer animationForKey:@"position"] isKindOfClass:CASpringAnimation.class]);
}

- (void)testEnteringAndLeavingEditingSeparatesFadesFromSpringMovement
{
    [self.cell setEditing:YES animated:YES];
    [CATransaction flush];
    [self assertLinearIndicatorFades];
    XCTAssertEqualWithAccuracy(self.cell.textLabel.frame.origin.x, 52, 0.001);

    XCTestExpectation *exit = [self expectationWithDescription:@"Exit uses a linear fade and a content spring"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.cell setEditing:NO animated:YES];
        [CATransaction flush];
        [self assertLinearIndicatorFades];
        XCTAssertEqualWithAccuracy(self.cell.textLabel.frame.origin.x, 16, 0.001);
        [exit fulfill];
    });
    [self waitForExpectations:@[exit] timeout:3];
}

- (void)testQuickEditingReversalDoesNotHideVisibleIndicators
{
    [self.cell setEditing:YES animated:NO];
    [self.cell setEditing:NO animated:YES];
    XCTestExpectation *settled = [self expectationWithDescription:@"The interrupted fade-out cannot hide edit controls"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.cell setEditing:YES animated:YES];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (NSString *key in @[@"selectionIndicator", @"reorderIndicator"]) {
            UIView *indicator = [self.cell valueForKey:key];
            XCTAssertFalse(indicator.hidden);
            XCTAssertEqualWithAccuracy(indicator.alpha, 1, 0.001);
        }
        XCTAssertTrue(self.cell.editing);
        [settled fulfill];
    });
    [self waitForExpectations:@[settled] timeout:3];
}

- (void)testNonanimatedEditingImmediatelyResetsActiveTransitions
{
    [self.cell setEditing:YES animated:YES];
    [self.cell setEditing:NO animated:NO];
    for (NSString *key in @[@"selectionIndicator", @"reorderIndicator"]) {
        UIView *indicator = [self.cell valueForKey:key];
        XCTAssertTrue(indicator.hidden);
        XCTAssertEqualWithAccuracy(indicator.alpha, 0, 0.001);
        XCTAssertNil([indicator.layer animationForKey:@"opacity"]);
    }
    XCTAssertNil([self.cell.textLabel.layer animationForKey:@"position"]);
    XCTAssertEqualWithAccuracy(self.cell.textLabel.frame.origin.x, 16, 0.001);
    [self.cell setEditing:YES animated:NO];
    XCTAssertEqualWithAccuracy(self.cell.textLabel.frame.origin.x, 52, 0.001);
    XCTAssertFalse([[self.cell valueForKey:@"selectionIndicator"] isHidden]);
    XCTAssertFalse([[self.cell valueForKey:@"reorderIndicator"] isHidden]);
}

- (void)testUnchangedSettledEditingDoesNotForceMoreLayout
{
    for (NSNumber *editing in @[@YES, @NO]) {
        [self.cell setEditing:editing.boolValue animated:NO];
        NSUInteger layouts = self.cell.layoutCount;
        for (NSUInteger i = 0; i < 10; i++)
            [self.cell setEditing:editing.boolValue animated:NO];
        XCTAssertEqual(self.cell.layoutCount, layouts);
    }
}

- (void)testSameValueNonanimatedEditingStillSettlesActiveTransition
{
    [self.cell setEditing:YES animated:YES];
    [CATransaction flush];
    [self.cell setEditing:YES animated:NO];
    for (NSString *key in @[@"selectionIndicator", @"reorderIndicator"]) {
        UIView *indicator = [self.cell valueForKey:key];
        XCTAssertFalse(indicator.hidden);
        XCTAssertEqualWithAccuracy(indicator.alpha, 1, 0.001);
        XCTAssertNil([indicator.layer animationForKey:@"opacity"]);
    }
    XCTAssertNil([self.cell.textLabel.layer animationForKey:@"position"]);
    XCTAssertEqualWithAccuracy(self.cell.textLabel.frame.origin.x, 52, 0.001);
}

@end
