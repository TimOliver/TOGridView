#import "TOGridViewSceneDelegate.h"
#import "TOGridViewViewController.h"

@implementation TOGridViewSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[TOGridViewViewController new]];
    [self.window makeKeyAndVisible];
}

@end
