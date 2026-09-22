// Copyright 2013-2026 Timothy Oliver. All rights reserved.

#import "TOGridViewTestCell.h"

@interface TOGridViewTestCell ()
@property (nonatomic, strong) UIView *bottomSeparator;
@property (nonatomic, strong) UIView *trailingSeparator;
@property (nonatomic, strong) UIImageView *selectionIndicator;
@property (nonatomic, strong) UIImageView *reorderIndicator;
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
        [self.contentView addSubview:_selectionIndicator];
        _reorderIndicator = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
        _reorderIndicator.contentMode = UIViewContentModeScaleAspectFit;
        _reorderIndicator.tintColor = UIColor.tertiaryLabelColor;
        _reorderIndicator.hidden = YES;
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
    [super setEditing:editing animated:animated];
    self.selectionIndicator.hidden = !editing;
    self.reorderIndicator.hidden = !editing;
    self.accessibilityHint = editing ? @"Double-tap to select. Touch and hold to reorder." : nil;
    [self setNeedsLayout];
    [self updateSelectionAppearance];
    if (animated)
        [UIView animateWithDuration:0.2 animations:^{ [self layoutIfNeeded]; }];
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
