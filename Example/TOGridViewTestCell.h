#import "TOGridViewCell.h"

@interface TOGridViewTestCell : TOGridViewCell
@property (nonatomic, readonly) UILabel *textLabel;
@property (nonatomic) BOOL showsTrailingSeparator;
@property (nonatomic, copy) void (^activationHandler)(void);
@end
