/*
 * This is the source code of Telegram for iOS v. 1.1
 * It is licensed under GNU GPL v. 2 or later.
 * You should have received a copy of the license in this archive (see LICENSE).
 *
 * Copyright Peter Iakovlev, 2013.
 */

#import <UIKit/UIKit.h>

#import "ActionStage.h"

#import "TGViewController.h"

#import "TGUser.h"

typedef enum {
    TGContactsModeRegistered = 1,
    TGContactsModePhonebook = 2,
    TGContactsModeSearchDisabled = 4,
    TGContactsModeMainContacts = 8,
    TGContactsModeInvite = 16 | 2,
    TGContactsModeSelectModal = 32,
    TGContactsModeHideSelf = 64,
    TGContactsModeClearSelectionImmediately = 128,
    TGContactsModeCompose = 256 | 1 | 4,
    TGContactsModeModalInvite = 512 | 16 | 2,
    TGContactsModeModalInviteWithBack = 1024 | 512 | 16 | 2,
    TGContactsModeCreateGroupOption = 2048
} TGContactsMode;

@interface TGContactsController : TGViewController <TGViewControllerNavigationBarAppearance, ASWatcher>

@property (nonatomic) bool loginStyle;

@property (nonatomic, strong, readonly) ASHandle *actionHandle;
@property (nonatomic, strong) ASHandle *watcherHandle;

@property (nonatomic) int contactListVersion;
@property (nonatomic) int phonebookVersion;

@property (nonatomic, strong) NSString *customTitle;

@property (nonatomic, readonly) int contactsMode;
@property (nonatomic) int usersSelectedLimit;

@property (nonatomic, strong) NSArray *disabledUsers;

@property (nonatomic, strong) UITableView *tableView;

- (id)initWithContactsMode:(int)contactsMode;

- (void)clearData;

- (void)deselectRow;

- (int)selectedContactsCount;
- (NSArray *)selectedComposeUsers;
- (NSArray *)selectedContactsList;
- (void)setUsersSelected:(NSArray *)users selected:(NSArray *)selected callback:(bool)callback;
- (void)contactSelected:(TGUser *)user;
- (void)contactDeselected:(TGUser *)user;
- (void)actionItemSelected;
- (void)encryptionItemSelected;
- (void)singleUserSelected:(TGUser *)user;

- (void)contactActionButtonPressed:(TGUser *)user;

- (void)deleteUserFromList:(int)uid;

@end
