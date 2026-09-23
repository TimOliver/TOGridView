// Copyright 2013-2026 Timothy Oliver. All rights reserved.

#import "TOGridViewTestCell.h"

@interface TOGridViewTestCell ()
@property (nonatomic, strong) UIView *bottomSeparator;
@property (nonatomic, strong) UIView *trailingSeparator;
@property (nonatomic, strong) UIImageView *selectionIndicator;
@property (nonatomic, strong) UIImageView *reorderIndicator;
@property (nonatomic) NSUInteger editingAnimationGeneration;
@property (nonatomic) BOOL editingTransitionInFlight;
@end

@implementation TOGridViewTestCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.systemBackgroundColor;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        self.highlightedBackgroundView = [UIView new];
        self.highlightedBackgroundView.backgroundColor = UIColor.tertiarySystemFillColor;
        self.selectedBackgroundView = [UIView new];
        self.selectedBackgroundView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.12];

        _textLabel = [UILabel new];
        _textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        _textLabel.adjustsFontForContentSizeCategory = YES;
        _textLabel.textColor = UIColor.labelColor;
        [self.contentView addSubview:_textLabel];

        _selectionIndicator = [UIImageView new];
        _selectionIndicator.contentMode = UIViewContentModeScaleAspectFit;
        _selectionIndicator.hidden = YES;
        _selectionIndicator.alpha = 0;
        [self.contentView addSubview:_selectionIndicator];
        _reorderIndicator = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
        _reorderIndicator.contentMode = UIViewContentModeScaleAspectFit;
        _reorderIndicator.tintColor = UIColor.tertiaryLabelColor;
        _reorderIndicator.hidden = YES;
        _reorderIndicator.alpha = 0;
        [self.contentView addSubview:_reorderIndicator];

        _bottomSeparator = [UIView new];
        _trailingSeparator = [UIView new];
        for (UIView *separator in @[_bottomSeparator, _trailingSeparator]) {
            separator.backgroundColor = UIColor.separatorColor;
            separator.userInteractionEnabled = NO;
            [self.contentView addSubview:separator];
        }
        [self updateSelectionAppearance];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGFloat pixel = 1.0 / MAX(self.traitCollection.displayScale, 1.0);
    CGFloat leading = self.editing ? 52 : 16;
    CGFloat trailing = self.editing ? 48 : 16;
    self.textLabel.frame = CGRectMake(leading, 0, MAX(0, width - leading - trailing), height);
    self.selectionIndicator.frame = CGRectMake(16, floor((height - 24) / 2), 24, 24);
    self.reorderIndicator.frame = CGRectMake(width - 36, floor((height - 20) / 2), 20, 20);
    self.bottomSeparator.frame = CGRectMake(16, height - pixel, MAX(0, width - 16), pixel);
    self.trailingSeparator.frame = CGRectMake(width - pixel, 0, pixel, height);
    self.trailingSeparator.hidden = !self.showsTrailingSeparator;
}

- (void)setShowsTrailingSeparator:(BOOL)showsTrailingSeparator
{
    _showsTrailingSeparator = showsTrailingSeparator;
    [self setNeedsLayout];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    BOOL changed = self.editing != editing;
    BOOL animates = animated && UIView.areAnimationsEnabled;
    // A same-value nonanimated call still settles an active transition immediately.
    if (!changed && (animates || !self.editingTransitionInFlight))
        return;
    [self layoutIfNeeded];
    [super setEditing:editing animated:animated];
    self.accessibilityHint = editing ? @"Double-tap to select. Touch and hold to reorder." : nil;
    [self updateSelectionAppearance];

    if (!animates) {
        self.editingAnimationGeneration++;
        self.editingTransitionInFlight = NO;
        [UIView performWithoutAnimation:^{
            for (UIView *indicator in @[self.selectionIndicator, self.reorderIndicator]) {
                [indicator.layer removeAllAnimations];
                indicator.alpha = editing ? 1 : 0;
                indicator.hidden = !editing;
            }
            [self.textLabel.layer removeAllAnimations];
            [self setNeedsLayout];
            [self layoutIfNeeded];
        }];
        return;
    }
    NSUInteger generation = ++self.editingAnimationGeneration;
    self.editingTransitionInFlight = YES;
    self.selectionIndicator.hidden = NO;
    self.reorderIndicator.hidden = NO;
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    // Opacity uses a linear fade independently of the content's spring movement.
    [UIView animateWithDuration:0.2 delay:0 options:options | UIViewAnimationOptionCurveLinear animations:^{
        self.selectionIndicator.alpha = editing ? 1 : 0;
        self.reorderIndicator.alpha = editing ? 1 : 0;
    } completion:^(BOOL finished) {
        if (generation == self.editingAnimationGeneration && !self.editing) {
            self.selectionIndicator.hidden = YES;
            self.reorderIndicator.hidden = YES;
        }
    }];

    [self setNeedsLayout];
    void (^layout)(void) = ^{ [self layoutIfNeeded]; };
    void (^completion)(BOOL) = ^(BOOL finished) {
        if (generation == self.editingAnimationGeneration)
            self.editingTransitionInFlight = NO;
    };
    if (@available(iOS 17.0, *)) {
        [UIView animateWithSpringDuration:0.35 bounce:0 initialSpringVelocity:0 delay:0
                                 options:options animations:layout completion:completion];
    } else {
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                            options:options animations:layout completion:completion];
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    [self updateSelectionAppearance];
}

- (void)updateSelectionAppearance
{
    self.selectionIndicator.image = [UIImage systemImageNamed:self.selected ? @"checkmark.circle.fill" : @"circle"];
    self.selectionIndicator.tintColor = self.selected ? self.tintColor : UIColor.tertiaryLabelColor;
    self.accessibilityTraits = UIAccessibilityTraitButton | (self.selected ? UIAccessibilityTraitSelected : 0);
}

- (void)setNeedsTransparentContent:(BOOL)transparent
{
    self.textLabel.backgroundColor = UIColor.clearColor;
}

- (BOOL)accessibilityActivate
{
    if (self.activationHandler == nil)
        return NO;
    self.activationHandler();
    return YES;
}

@end
