/*
 * This is the source code of Telegram for iOS v. 1.1
 * It is licensed under GNU GPL v. 2 or later.
 * You should have received a copy of the license in this archive (see LICENSE).
 *
 * Copyright Peter Iakovlev, 2013.
 */

#import <UIKit/UIKit.h>

#import "TGNavigationController.h"
#import "TGMainTabsController.h"
#import "TGDialogListController.h"
#import "TGContactsController.h"
#import "TGAddContactsController.h"
#import "TGTimelineController.h"
#import "TGProfileController.h"

#import "ActionStage.h"

#import "TGAppManager.h"

extern CFAbsoluteTime applicationStartupTimestamp;
extern CFAbsoluteTime mainLaunchTimestamp;

@class TGAppDelegate;
extern TGAppDelegate *TGAppDelegateInstance;

@protocol TGDeviceTokenListener <NSObject>

@required

- (void)deviceTokenRequestCompleted:(NSString *)deviceToken;

@end

@interface TGAppDelegate : UIResponder <UIApplicationDelegate, ASWatcher, TGAppManager>

+ (void)beginEarlyInitialization;

@property (nonatomic, strong, readonly) ASHandle *actionHandle;

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIWindow *contentWindow;
@property (nonatomic) bool keyboardVisible;
@property (nonatomic) float keyboardHeight;

// Settings
@property (nonatomic) bool soundEnabled;
@property (nonatomic) bool outgoingSoundEnabled;
@property (nonatomic) bool vibrationEnabled;
@property (nonatomic) bool bannerEnabled;
@property (nonatomic) bool locationTranslationEnabled;
@property (nonatomic) bool exclusiveConversationControllers;

@property (nonatomic) bool autosavePhotos;
@property (nonatomic) bool customChatBackground;

@property (nonatomic) bool autoDownloadPhotosInGroups;
@property (nonatomic) bool autoDownloadPhotosInPrivateChats;

@property (nonatomic) bool useDifferentBackend;

@property (nonatomic, strong) TGNavigationController *loginNavigationController;
@property (nonatomic, strong) TGNavigationController *mainNavigationController;

@property (nonatomic, strong) TGMainTabsController *mainTabsController;

@property (nonatomic, strong) TGDialogListController *dialogListController;
@property (nonatomic, strong) TGContactsController *contactsController;
@property (nonatomic, strong) TGProfileController *myAccountController;

@property (nonatomic) CFAbsoluteTime enteredBackgroundTime;

@property (nonatomic) bool disableBackgroundMode;

- (void)performPhoneCall:(NSURL *)url;

- (void)presentMainController;

- (void)presentLoginController:(bool)clearControllerStates showWelcomeScreen:(bool)showWelcomeScreen phoneNumber:(NSString *)phoneNumber phoneCode:(NSString *)phoneCode phoneCodeHash:(NSString *)phoneCodeHash profileFirstName:(NSString *)profileFirstName profileLastName:(NSString *)profileLastName;
- (void)presentContentController:(UIViewController *)controller;
- (void)dismissContentController;

- (void)saveSettings;
- (void)loadSettings;

- (NSDictionary *)loadLoginState;
- (void)resetLoginState;
- (void)saveLoginStateWithDate:(int)date phoneNumber:(NSString *)phoneNumber phoneCode:(NSString *)phoneCode phoneCodeHash:(NSString *)phoneCodeHash firstName:(NSString *)firstName lastName:(NSString *)lastName photo:(NSData *)photo;

- (NSArray *)alertSoundTitles;

- (void)playSound:(NSString *)name vibrate:(bool)vibrate;
- (void)playNotificationSound:(NSString *)name;
- (void)displayNotification:(NSString *)identifier timeout:(NSTimeInterval)timeout constructor:(UIView *(^)(UIView *existingView))constructor watcher:(ASHandle *)watcher watcherAction:(NSString *)watcherAction watcherOptions:(NSDictionary *)watcherOptions;
- (void)dismissNotification;
- (UIView *)currentNotificationView;

- (void)requestDeviceToken:(id<TGDeviceTokenListener>)listener;

@end
