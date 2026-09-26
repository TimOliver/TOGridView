#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>
#import "TOGridView+Private.h"

// Opt-in device benchmark. Timing probes are test-only; no instrumentation ships in the grid.
typedef struct {
    double layout, preparation, bookkeeping;
    NSUInteger lookups, updates, configurations, allocations, cellLayouts;
} GridWork;
static NSUInteger overheadAllocations, overheadCellLayouts;

@interface OverheadCell : TOGridViewCell
@end
@implementation OverheadCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) overheadAllocations++;
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; overheadCellLayouts++; }
@end

@interface OverheadGrid : TOGridView {
@public GridWork work;
}
@end
@implementation OverheadGrid
- (void)layoutCells {
    CFTimeInterval start = CACurrentMediaTime();
    [super layoutCells];
    work.layout += CACurrentMediaTime() - start;
}
- (void)prepareNextCell:(CADisplayLink *)link {
    CFTimeInterval start = CACurrentMediaTime();
    [super prepareNextCell:link];
    work.preparation += CACurrentMediaTime() - start;
}
- (void)updateCellPreparation {
    CFTimeInterval start = CACurrentMediaTime();
    [super updateCellPreparation];
    work.bookkeeping += CACurrentMediaTime() - start;
    work.updates++;
}
- (TOGridViewCell *)cellForIndex:(NSInteger)index {
    work.lookups++;
    return [super cellForIndex:index];
}
@end

@interface GridOverheadBenchmarks : XCTestCase <TOGridViewDataSource, TOGridViewDelegate> {
    double _layout[240], _preparation[240], _bookkeeping[240], _cadence[240];
    GridWork _previous, _measured;
    CFTimeInterval _previousTimestamp;
}
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) OverheadGrid *grid;
@property (nonatomic, strong) CADisplayLink *driver;
@property (nonatomic, strong) XCTestExpectation *finished;
@property (nonatomic) NSUInteger columns;
@property (nonatomic) NSUInteger tick;
@property (nonatomic, copy) NSString *scenario;
@end

@implementation GridOverheadBenchmarks
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)grid { return 100000; }
- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)grid { return self.columns; }
- (CGSize)sizeOfCellsForGridView:(TOGridView *)grid {
    return CGSizeMake(floor(grid.bounds.size.width / self.columns), 24);
}
- (TOGridViewCell *)gridView:(TOGridView *)grid cellForIndex:(NSInteger)index {
    self.grid->work.configurations++;
    TOGridViewCell *cell = [grid dequeueReusableCell];
    cell.tag = index;
    return cell;
}
- (void)advance:(CADisplayLink *)link {
    GridWork current = self.grid->work;
    current.allocations = overheadAllocations;
    current.cellLayouts = overheadCellLayouts;
    if (self.tick >= 60) {
        NSUInteger sample = self.tick - 60;
        _layout[sample] = (current.layout - _previous.layout) * 1000;
        _preparation[sample] = (current.preparation - _previous.preparation) * 1000;
        _bookkeeping[sample] = (current.bookkeeping - _previous.bookkeeping) * 1000;
        _cadence[sample] = (link.timestamp - _previousTimestamp) * 1000;
        _measured.lookups += current.lookups - _previous.lookups;
        _measured.updates += current.updates - _previous.updates;
        _measured.configurations += current.configurations - _previous.configurations;
        _measured.allocations += current.allocations - _previous.allocations;
        _measured.cellLayouts += current.cellLayouts - _previous.cellLayouts;
    }
    _previous = current;
    _previousTimestamp = link.timestamp;
    if (++self.tick == 300) {
        [self.driver invalidate]; self.driver = nil;
        [self.finished fulfill];
        return;
    }
    CGFloat y = 2400;
    if ([self.scenario isEqualToString:@"same-range"]) y += self.tick % 10;
    else if ([self.scenario isEqualToString:@"row-crossing"]) y += self.tick * 24;
    else if ([self.scenario isEqualToString:@"boundary-reversal"]) y += self.tick % 2 ? 23 : 25;
    else if ([self.scenario isEqualToString:@"distant-jumps"]) y += (self.tick % 2) * 24000;
    else if ([self.scenario isEqualToString:@"direction-reversal"]) y += (self.tick % 40 < 20 ? self.tick % 20 : 20 - self.tick % 20) * 24;
    self.grid.contentOffset = CGPointMake(0, y);
    [self.grid layoutIfNeeded];
}
static int compareDouble(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
- (NSDictionary *)statistics:(double *)values {
    double sorted[240], sum = 0;
    for (NSUInteger i = 0; i < 240; i++) { sorted[i] = values[i]; sum += values[i]; }
    qsort(sorted, 240, sizeof(double), compareDouble);
    return @{@"mean_ms": @(sum / 240), @"p95_ms": @(sorted[227]), @"p99_ms": @(sorted[237]), @"max_ms": @(sorted[239])};
}
- (void)testLibraryWorkloads {
    XCTSkipUnless([NSProcessInfo.processInfo.environment[@"TOGRID_RUN_BENCHMARKS"] isEqualToString:@"1"], @"Opt-in physical-device benchmark");
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    NSMutableArray *results = [NSMutableArray array];
    for (NSNumber *columns in @[@2, @20]) {
        self.columns = columns.unsignedIntegerValue;
        for (NSString *scenario in @[@"same-range", @"row-crossing", @"boundary-reversal", @"direction-reversal", @"distant-jumps", @"idle"]) {
            self.scenario = scenario;
            self.grid = [[OverheadGrid alloc] initWithFrame:CGRectMake(0, 0, 800, 960) withCellClass:OverheadCell.class];
            self.grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
            self.grid.dataSource = self; self.grid.delegate = self;
            self.grid.cellPrefetchingEnabled = YES;
            [self.window.rootViewController.view addSubview:self.grid];
            [self.grid reloadGrid];
            [self.grid layoutIfNeeded];
            self.tick = 0; _previous = (GridWork){0}; _measured = (GridWork){0};
            self.finished = [self expectationWithDescription:scenario];
            self.driver = [CADisplayLink displayLinkWithTarget:self selector:@selector(advance:)];
            float maximum = self.window.screen.maximumFramesPerSecond;
            self.driver.preferredFrameRateRange = CAFrameRateRangeMake(maximum, maximum, maximum);
            [self.driver addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            [self waitForExpectations:@[self.finished] timeout:20];
            [self.driver invalidate]; self.driver = nil;
            NSDictionary *result = @{@"scenario": scenario, @"columns": columns,
                @"visible_cells": @(self.grid.visibleCellViews.count), @"maximum_hz": @(maximum),
                @"thermal_state": @(NSProcessInfo.processInfo.thermalState),
                @"layout": [self statistics:_layout], @"preparation": [self statistics:_preparation],
                @"bookkeeping": [self statistics:_bookkeeping], @"callback_interval": [self statistics:_cadence],
                @"lookups": @(_measured.lookups), @"preparation_updates": @(_measured.updates),
                @"configurations": @(_measured.configurations), @"cell_allocations": @(_measured.allocations),
                @"cell_layouts": @(_measured.cellLayouts)};
            [results addObject:result];
            NSData *rowJSON = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
            if (rowJSON != nil)
                NSLog(@"GRID_OVERHEAD %@", [[NSString alloc] initWithData:rowJSON encoding:NSUTF8StringEncoding]);
            NSRange range = self.grid.visibleCellRange;
            XCTAssertEqual(self.grid.visibleCellViews.count, range.length);
            for (NSUInteger index = range.location; index < NSMaxRange(range); index++) {
                TOGridViewCell *cell = [self.grid cellForIndex:index];
                XCTAssertEqual(cell.tag, index);
                XCTAssertTrue(CGRectEqualToRect(cell.frame, [self.grid rectOfCellAtIndex:index]));
            }
            if ([scenario isEqualToString:@"idle"]) {
                XCTAssertEqual(_measured.configurations, 0);
                XCTAssertEqual(_measured.cellLayouts, 0);
                XCTAssertNil([self.grid valueForKey:@"cellPreparationDisplayLink"]);
            }
            self.grid.cellPrefetchingEnabled = NO;
            [self.grid removeFromSuperview]; self.grid = nil;
        }
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:nil];
    XCTAttachment *attachment = [XCTAttachment attachmentWithData:json uniformTypeIdentifier:@"public.json"];
    attachment.name = @"grid-overhead.json"; attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
    self.window.hidden = YES; self.window = nil;
}
@end
