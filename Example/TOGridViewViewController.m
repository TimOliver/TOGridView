// Copyright 2013-2026 Timothy Oliver. All rights reserved.

#import "TOGridViewViewController.h"
#import "TOGridViewTestCell.h"

@interface TOGridViewViewController () <TOGridViewDataSource, TOGridViewDelegate>
@property (nonatomic, strong) TOGridView *gridView;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *numbers;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIBarButtonItem *addButton;
@property (nonatomic, strong) UIBarButtonItem *deleteButton;
@property (nonatomic) NSUInteger nextNumber;
@property (nonatomic) BOOL updatingCells;
@end

@implementation TOGridViewViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"TOGridView";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.edgesForExtendedLayout = UIRectEdgeNone;

    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;

    self.numbers = [NSMutableArray array];
    for (NSUInteger i = 0; i < 256; i++)
        [self.numbers addObject:@(i)];
    self.nextNumber = self.numbers.count;

    self.gridView = [[TOGridView alloc] initWithFrame:self.view.bounds withCellClass:TOGridViewTestCell.class];
    self.gridView.backgroundColor = UIColor.systemBackgroundColor;
    self.gridView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.gridView.accessibilityIdentifier = @"grid";
    self.gridView.delegate = self;
    self.gridView.dataSource = self;
    self.gridView.crossfadeCellsOnRotation = YES;
    self.gridView.allowsSelectionDuringEditing = YES;
    [self.view addSubview:self.gridView];
    [self installHeaderView];

    self.addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonTapped:)];
    self.addButton.accessibilityIdentifier = @"add";
    self.deleteButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteButtonTapped:)];
    self.deleteButton.accessibilityIdentifier = @"delete";
    self.navigationItem.leftBarButtonItem = self.addButton;
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    [self updateControls];
}

- (void)installHeaderView
{
    CGFloat height = ceil([[UIFontMetrics defaultMetrics] scaledValueForValue:144 compatibleWithTraitCollection:self.traitCollection]);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.gridView.bounds), height)];
    header.backgroundColor = UIColor.secondarySystemBackgroundColor;

    self.countLabel = [UILabel new];
    self.countLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2 compatibleWithTraitCollection:self.traitCollection];
    self.countLabel.adjustsFontForContentSizeCategory = YES;
    self.countLabel.textColor = UIColor.labelColor;
    self.countLabel.accessibilityIdentifier = @"item-count";

    UILabel *instructions = [UILabel new];
    instructions.text = @"Use Edit to select cells.\nTouch and hold to reorder.";
    instructions.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline compatibleWithTraitCollection:self.traitCollection];
    instructions.adjustsFontForContentSizeCategory = YES;
    instructions.textColor = UIColor.secondaryLabelColor;
    instructions.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.countLabel, instructions]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:stack];

    UIView *separator = [UIView new];
    separator.backgroundColor = UIColor.separatorColor;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [stack.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0 / MAX(self.traitCollection.displayScale, 1.0)]
    ]];
    self.gridView.headerView = header;
    [self updateControls];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    // Use the window's available area. Explicit frames preserve the grid's rotation animation.
    self.gridView.frame = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    [self.gridView layoutIfNeeded];
    NSRange range = self.gridView.visibleCellRange;
    for (NSUInteger i = 0; i < range.length; i++) {
        NSInteger index = range.location + i;
        TOGridViewTestCell *cell = (TOGridViewTestCell *)[self.gridView cellForIndex:index];
        cell.showsTrailingSeparator = (index + 1) % self.gridView.numberOfCellsPerRow != 0;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if (![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory] && self.isViewLoaded) {
        [self installHeaderView];
        [self.gridView reloadGrid];
        [self.view setNeedsLayout];
    }
}

#pragma mark - Grid layout

- (UIEdgeInsets)boundaryInsetsForGridView:(TOGridView *)gridView
{
    return UIEdgeInsetsZero;
}

- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView
{
    CGFloat minimumWidth = [[UIFontMetrics defaultMetrics] scaledValueForValue:280 compatibleWithTraitCollection:self.traitCollection];
    return MAX(1, (NSUInteger)floor(CGRectGetWidth(gridView.bounds) / minimumWidth));
}

- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView
{
    CGFloat scale = MAX(self.traitCollection.displayScale, 1.0);
    CGFloat width = floor(CGRectGetWidth(gridView.bounds) * scale / [self numberOfCellsPerRowForGridView:gridView]) / scale;
    CGFloat height = ceil(MAX(72, [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline compatibleWithTraitCollection:self.traitCollection].lineHeight + 40));
    return CGSizeMake(width, height);
}

#pragma mark - Grid content and interactions

- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView
{
    return self.numbers.count;
}

- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)index
{
    TOGridViewTestCell *cell = (TOGridViewTestCell *)[gridView dequeReusableCell];
    NSNumber *number = self.numbers[index];
    cell.textLabel.text = [NSString stringWithFormat:@"Cell %@", number];
    cell.accessibilityLabel = cell.textLabel.text;
    cell.accessibilityIdentifier = [NSString stringWithFormat:@"cell-%@", number];
    cell.showsTrailingSeparator = (index + 1) % gridView.numberOfCellsPerRow != 0;
    __weak typeof(self) weakSelf = self;
    cell.activationHandler = ^{
        typeof(self) self = weakSelf;
        if (self == nil || self.updatingCells)
            return;
        NSUInteger currentIndex = [self.numbers indexOfObject:number];
        if (currentIndex == NSNotFound)
            return;
        if (self.editing) {
            if ([self.gridView.indicesOfSelectedCells containsObject:@(currentIndex)])
                [self.gridView deselectCellAtIndex:currentIndex];
            else
                [self.gridView selectCellAtIndex:currentIndex animated:YES];
            [self updateControls];
        } else {
            [self gridView:self.gridView didTapCellAtIndex:currentIndex];
        }
    };
    return cell;
}

- (BOOL)gridView:(TOGridView *)gridView canMoveCellAtIndex:(NSInteger)index { return YES; }
- (BOOL)gridView:(TOGridView *)gridView canEditCellAtIndex:(NSInteger)index { return YES; }

- (void)gridView:(TOGridView *)gridView didTapCellAtIndex:(NSUInteger)index
{
    [gridView unhighlightCellAtIndex:index animated:YES];
}

- (void)gridView:(TOGridView *)gridView didSelectCellAtIndex:(NSInteger)index { [self updateControls]; }
- (void)gridView:(TOGridView *)gridView didDeselectCellAtIndex:(NSInteger)index { [self updateControls]; }

- (void)gridView:(TOGridView *)gridView didMoveCellAtIndex:(NSInteger)previousIndex toIndex:(NSInteger)newIndex
{
    NSNumber *number = self.numbers[previousIndex];
    [self.numbers removeObjectAtIndex:previousIndex];
    [self.numbers insertObject:number atIndex:newIndex];
    [self updateControls];
}

#pragma mark - Editing

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [super setEditing:editing animated:animated];
    [self.gridView setEditing:editing animated:animated];
    self.navigationItem.leftBarButtonItem = editing ? self.deleteButton : self.addButton;
    [self updateControls];
}

- (void)updateControls
{
    self.countLabel.text = [NSString stringWithFormat:@"%lu cells", (unsigned long)self.numbers.count];
    self.addButton.enabled = !self.updatingCells;
    self.deleteButton.enabled = !self.updatingCells && self.gridView.indicesOfSelectedCells.count > 0;
    self.editButtonItem.enabled = !self.updatingCells;
    [self.view setNeedsLayout];
}

- (void)addButtonTapped:(id)sender
{
    self.updatingCells = YES;
    [self.numbers insertObject:@(self.nextNumber++) atIndex:0];
    [self updateControls];
    [self.gridView insertCellAtIndex:0 animated:YES completionHandler:^{
        self.updatingCells = NO;
        [self updateControls];
    }];
}

- (void)deleteButtonTapped:(id)sender
{
    NSArray<NSNumber *> *selectedIndices = [self.gridView.indicesOfSelectedCells copy];
    if (selectedIndices.count == 0)
        return;
    NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
    for (NSNumber *index in selectedIndices)
        [indices addIndex:index.unsignedIntegerValue];
    self.updatingCells = YES;
    [self.numbers removeObjectsAtIndexes:indices];
    [self updateControls];
    [self.gridView deleteCellsAtIndices:selectedIndices animated:YES completionHandler:^{
        self.updatingCells = NO;
        [self updateControls];
    }];
}

@end
