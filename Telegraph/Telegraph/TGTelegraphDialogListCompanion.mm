#import "TGTelegraphDialogListCompanion.h"

#import "TGAppDelegate.h"

#import "TGDialogListController.h"

#import "SGraphObjectNode.h"
#import "SGraphListNode.h"

#import "TGDatabase.h"

#import "TGInterfaceManager.h"
#import "TGInterfaceAssets.h"

#import "TGSelectContactController.h"

#import "TGConversationController.h"

#import "TGTelegraph.h"

#import "TGForwardTargetController.h"

#import "TGTelegraphConversationMessageAssetsSource.h"
#import "TGConversationMessageItemView.h"

#include <map>
#include <set>

typedef enum {
    TGDialogListStateNormal = 0,
    TGDialogListStateConnecting = 1,
    TGDialogListStateUpdating = 2,
    TGDialogListStateWaitingForNetwork = 3
} TGDialogListState;

@interface TGTelegraphDialogListCompanion ()

@property (nonatomic, strong) NSMutableArray *conversationList;

@property (nonatomic, strong) NSString *searchString;

@property (nonatomic) TGDialogListState state;

@end

@implementation TGTelegraphDialogListCompanion

@synthesize actionHandle = _actionHandle;

@synthesize conversatioSelectedWatcher = _conversatioSelectedWatcher;

@synthesize conversationList = _conversationList;

@synthesize searchString = _searchString;

@synthesize state = _state;

- (id)init
{
    self = [super init];
    if (self != nil)
    {
        _conversationList = [[NSMutableArray alloc] init];
        
        _actionHandle = [[ASHandle alloc] initWithDelegate:self releaseOnMainThread:false];
        
        self.showListEditingControl = true;

        [self resetWatchedNodePaths];
    }
    return self;
}

- (void)dealloc
{
    [_actionHandle reset];
    [ActionStageInstance() removeWatcher:self];
}

- (id<TGDialogListCellAssetsSource>)dialogListCellAssetsSource
{
    return [TGInterfaceAssets instance];
}

- (void)dialogListReady
{
    [[TGInterfaceManager instance] preload];
}

- (void)updateLeftBarItem:(bool)animated
{
    [TGAppDelegateInstance.mainTabsController updateLeftBarButtonForCurrentController:animated];
}

- (void)updateTitle:(bool)animated
{
    [TGAppDelegateInstance.mainTabsController updateTitleForController:TGAppDelegateInstance.mainTabsController.selectedViewController switchingTabs:false animateText:animated];
}

- (void)resetWatchedNodePaths
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [ActionStageInstance() removeWatcher:self];

        [ActionStageInstance() watchForPath:@"/tg/conversations" watcher:self];
        [ActionStageInstance() watchForGenericPath:@"/tg/dialoglist/@" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/userdatachanges" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/unreadCount" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/conversation/*/typing" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/contactlist" watcher:self];
        
        [ActionStageInstance() watchForGenericPath:@"/tg/peerSettings/@" watcher:self];
        
        [ActionStageInstance() watchForPath:@"/tg/service/synchronizationstate" watcher:self];
        [ActionStageInstance() requestActor:@"/tg/service/synchronizationstate" options:nil watcher:self];
        
        int unreadCount = [TGDatabaseInstance() databaseState].unreadCount;
        [self actionStageResourceDispatched:@"/tg/unreadCount" resource:[[SGraphObjectNode alloc] initWithObject:[NSNumber numberWithInt:unreadCount]] arguments:nil];
    }];
}

- (void)clearData
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [_conversationList removeAllObjects];
        
        [self resetWatchedNodePaths];
        
        dispatch_async(dispatch_get_main_queue(), ^
        {
            TGDialogListController *controller = self.dialogListController;
            if (controller != nil)
            {
                controller.canLoadMore = false;
                [controller dialogListFullyReloaded:[[NSArray alloc] init]];
                [controller resetState];
            }
        });
    }];
}

- (void)composeMessage
{
    TGSelectContactController *selectController = [[TGSelectContactController alloc] initWithCreateGroup:false createEncrypted:false];
    [TGAppDelegateInstance.mainNavigationController pushViewController:selectController animated:true];
}

- (void)conversationSelected:(TGConversation *)conversation
{
    if (self.forwardMode)
    {
        [_conversatioSelectedWatcher requestAction:@"conversationSelected" options:[[NSDictionary alloc] initWithObjectsAndKeys:conversation, @"conversation", nil]];
    }
    else
    {
        int64_t conversationId = conversation.conversationId;
        [[TGInterfaceManager instance] navigateToConversationWithId:conversationId conversation:nil];
    }
}

- (void)searchResultSelectedConversation:(TGConversation *)conversation
{
    [self conversationSelected:conversation];
}

- (void)searchResultSelectedConversation:(TGConversation *)conversation atMessageId:(int)messageId
{
    if (!self.forwardMode)
    {
        int64_t conversationId = conversation.conversationId;
        [[TGInterfaceManager instance] navigateToConversationWithId:conversationId conversation:nil forwardMessages:nil atMessageId:messageId clearStack:true openKeyboard:false animated:true];
    }
}

- (void)searchResultSelectedMessage:(TGMessage *)__unused message
{
    
}

- (bool)shouldDisplayEmptyListPlaceholder
{
    return TGTelegraphInstance.clientUserId != 0;
}

- (void)wakeUp
{
    /*TGMessage *incomingMessage = [[TGMessage alloc] init];
    incomingMessage.text = @"test";
    incomingMessage.fromUid = TGTelegraphInstance.clientUserId;
    incomingMessage.outgoing = false;
    
    TGMessage *outgoingMessage = [[TGMessage alloc] init];
    outgoingMessage.text = @"test";
    outgoingMessage.fromUid = TGTelegraphInstance.clientUserId;
    outgoingMessage.outgoing = false;
    
    TGConversationMessageItem *incomingMessageItem = [[TGConversationMessageItem alloc] initWithMessage:incomingMessage];
    sizeForConversationMessage(incomingMessageItem, TGConversationMessageMetricsPortrait, [TGTelegraphConversationMessageAssetsSource instance]);

    TGConversationMessageItem *outgoingMessageItem = [[TGConversationMessageItem alloc] initWithMessage:outgoingMessage];
    sizeForConversationMessage(outgoingMessageItem, TGConversationMessageMetricsPortrait, [TGTelegraphConversationMessageAssetsSource instance]);*/
}

- (void)deleteItem:(TGConversation *)conversation animated:(bool)animated
{
    int64_t conversationId = conversation.conversationId;
    
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        for (int i = 0; i < (int)self.conversationList.count; i++)
        {
            TGConversation *conversation = [self.conversationList objectAtIndex:i];
            if (conversation.conversationId == conversationId)
            {
                [self.conversationList removeObjectAtIndex:i];
                
                NSNumber *removedIndex = [[NSNumber alloc] initWithInt:i];
                
                [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/conversation/(%lld)/delete", conversationId] options:[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:conversationId] forKey:@"conversationId"] watcher:self];
                
                dispatch_async(dispatch_get_main_queue(), ^
                {
                    if (!animated)
                        [UIView setAnimationsEnabled:false];
                    TGDialogListController *dialogListController = self.dialogListController;
                    [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:nil updatedItems:nil removedIndices:[NSArray arrayWithObject:removedIndex]];
                    if (!animated)
                        [UIView setAnimationsEnabled:true];
                });
                
                break;
            }
        }
    }];
}

- (void)clearItem:(TGConversation *)conversation animated:(bool)animated
{
    int64_t conversationId = conversation.conversationId;
 
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        for (int i = 0; i < (int)self.conversationList.count; i++)
        {
            TGConversation *conversation = [self.conversationList objectAtIndex:i];
            if (conversation.conversationId == conversationId)
            {
                [self.conversationList removeObjectAtIndex:i];
                
                [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/conversation/(%lld)/clearHistory", conversationId] options:[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:conversationId] forKey:@"conversationId"] watcher:self];
                
                conversation = [conversation copy];

                conversation.outgoing = false;
                conversation.text = nil;
                conversation.media = nil;
                conversation.unread = false;
                conversation.unreadCount = 0;
                conversation.fromUid = 0;
                conversation.deliveryError = false;
                conversation.deliveryState = TGMessageDeliveryStateDelivered;
                
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:conversation.dialogListData];
                dict[@"authorName"] = @"";
                
                dispatch_async(dispatch_get_main_queue(), ^
                {
                    if (!animated)
                        [UIView setAnimationsEnabled:false];
                    TGDialogListController *dialogListController = self.dialogListController;
                    [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:@[@(i)] updatedItems:@[conversation] removedIndices:nil];
                    if (!animated)
                        [UIView setAnimationsEnabled:true];
                });
                
                break;
            }
        }
    }];
}

- (void)loadMoreItems
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        NSMutableArray *currentConversationIds = [[NSMutableArray alloc] initWithCapacity:_conversationList.count];
        
        int minDate = INT_MAX;
        for (TGConversation *conversation in _conversationList)
        {
            if (conversation.date < minDate)
                minDate = conversation.date;
            
            [currentConversationIds addObject:[[NSNumber alloc] initWithLongLong:conversation.conversationId]];
        }
        
        if (minDate != INT_MAX)
        {
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/dialoglist/(%d)", minDate] options:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:40], @"limit", [NSNumber numberWithInt:minDate], @"date", currentConversationIds, @"excludeConversationIds", nil] watcher:self];
        }
        else
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                
                dialogListController.canLoadMore = false;
                [dialogListController dialogListFullyReloaded:[NSArray array]];
            });
        }
    }];
}

- (void)beginSearch:(NSString *)queryString inMessages:(bool)inMessages
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [self resetWatchedNodePaths];

        self.searchString = [[queryString stringByReplacingOccurrencesOfString:@" +" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, queryString.length)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (self.searchString.length == 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                [dialogListController searchResultsReloaded:nil searchString:nil];
            });
        }
        else
        {
            if (inMessages)
            {
                [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/search/messages/(%d)", [self.searchString hash]] options:[NSDictionary dictionaryWithObject:self.searchString forKey:@"query"] watcher:self];
            }
            else
            {
                [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/search/dialogs/(%d)", [self.searchString hash]] options:[NSDictionary dictionaryWithObject:self.searchString forKey:@"query"] watcher:self];
            }
        }
    }];
}

- (void)searchResultSelectedUser:(TGUser *)user
{
    if (self.forwardMode)
    {
        [_conversatioSelectedWatcher requestAction:@"userSelected" options:[[NSDictionary alloc] initWithObjectsAndKeys:user, @"user", nil]];
    }
    else
    {
        int64_t conversationId = user.uid;
        [[TGInterfaceManager instance] navigateToConversationWithId:conversationId conversation:nil];
    }
}

- (void)initializeDialogListData:(TGConversation *)conversation customUser:(TGUser *)customUser selfUser:(TGUser *)selfUser
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    
    if (!conversation.isChat || conversation.isEncrypted)
    {
        int32_t userId = 0;
        if (conversation.isEncrypted)
        {
            if (conversation.chatParticipants.chatParticipantUids.count != 0)
                userId = [conversation.chatParticipants.chatParticipantUids[0] intValue];       
        }
        else
            userId = (int)conversation.conversationId;
        
        TGUser *user = nil;
        if (customUser != nil && customUser.uid == userId)
            user = customUser;
        else
            user = [[TGDatabase instance] loadUser:(int)userId];
        
        NSString *title = nil;
        
        if ((user.phoneNumber.length != 0 && ![TGDatabaseInstance() uidIsRemoteContact:user.uid]) && user.uid != 333000)
            title = user.formattedPhoneNumber;
        else
            title = [user displayName];
        
        if (title != nil)
            [dict setObject:title forKey:@"title"];
        
        dict[@"isEncrypted"] = [[NSNumber alloc] initWithBool:conversation.isEncrypted];
        if (conversation.isEncrypted)
        {
            dict[@"encryptionStatus"] = [[NSNumber alloc] initWithInt:conversation.encryptedData.handshakeState];
            dict[@"encryptionOutgoing"] = [[NSNumber alloc] initWithBool:conversation.chatParticipants.chatAdminId == TGTelegraphInstance.clientUserId];
            NSString *firstName = user.displayFirstName;
            dict[@"encryptionFirstName"] = firstName != nil ? firstName : @"";
        }
        dict[@"encryptedUserId"] = [[NSNumber alloc] initWithInt:userId];
        
        if (user.photoUrlSmall != nil)
            [dict setObject:user.photoUrlSmall forKey:@"avatarUrl"];
        [dict setObject:[NSNumber numberWithBool:false] forKey:@"isChat"];
        
        NSString *authorAvatarUrl = nil;
        if (selfUser != nil)
            authorAvatarUrl = selfUser.photoUrlSmall;
        
        if (authorAvatarUrl != nil)
            [dict setObject:authorAvatarUrl forKey:@"authorAvatarUrl"];
        
        if (conversation.media.count != 0)
        {
            NSString *authorName = nil;
            if (conversation.fromUid == selfUser.uid)
            {
                static NSString *youString = nil;
                if (youString == nil)
                    youString = TGLocalized(@"DialogList.You");
                
                authorName = youString;
            }
            else
            {
                if (conversation.fromUid != 0)
                {
                    TGUser *authorUser = [[TGDatabase instance] loadUser:conversation.fromUid];
                    if (authorUser != nil)
                    {
                        authorName = authorUser.displayName;
                    }
                }
            }
            
            if (authorName != nil)
                [dict setObject:authorName forKey:@"authorName"];
        }
    }
    else
    {
        [dict setObject:(conversation.chatTitle == nil ? @"" : conversation.chatTitle) forKey:@"title"];
        
        if (conversation.chatPhotoSmall.length != 0)
            [dict setObject:conversation.chatPhotoSmall forKey:@"avatarUrl"];
        
        [dict setObject:[NSNumber numberWithBool:true] forKey:@"isChat"];
        
        NSString *authorName = nil;
        NSString *authorAvatarUrl = nil;
        if (conversation.fromUid == selfUser.uid)
        {
            authorAvatarUrl = selfUser.photoUrlSmall;
            
            static NSString *youString = nil;
            if (youString == nil)
                youString = TGLocalized(@"DialogList.You");
            
            if (conversation.text.length != 0 || conversation.media.count != 0)
                authorName = youString;
        }
        else
        {
            if (conversation.fromUid != 0)
            {
                TGUser *authorUser = [[TGDatabase instance] loadUser:conversation.fromUid];
                if (authorUser != nil)
                {
                    authorAvatarUrl = authorUser.photoUrlSmall;
                    authorName = authorUser.displayName;
                }
            }
        }
        
        if (authorAvatarUrl != nil)
            [dict setObject:authorAvatarUrl forKey:@"authorAvatarUrl"];
        if (authorName != nil)
            [dict setObject:authorName forKey:@"authorName"];
    }
    
    NSMutableDictionary *messageUsers = [[NSMutableDictionary alloc] init];
    for (TGMediaAttachment *attachment in conversation.media)
    {
        if (attachment.type == TGActionMediaAttachmentType)
        {
            TGActionMediaAttachment *actionAttachment = (TGActionMediaAttachment *)attachment;
            if (actionAttachment.actionType == TGMessageActionChatAddMember || actionAttachment.actionType == TGMessageActionChatDeleteMember)
            {
                NSNumber *nUid = [actionAttachment.actionData objectForKey:@"uid"];
                if (nUid != nil)
                {
                    TGUser *user = [TGDatabaseInstance() loadUser:[nUid intValue]];
                    if (user != nil)
                        [messageUsers setObject:user forKey:nUid];
                }
            }
            
            TGUser *user = conversation.fromUid == selfUser.uid ? selfUser : [TGDatabaseInstance() loadUser:(int)conversation.fromUid];
            if (user != nil)
            {
                [messageUsers setObject:user forKey:[[NSNumber alloc] initWithInt:user.uid]];
                [messageUsers setObject:user forKey:@"author"];
            }
        }
    }
    
    [dict setObject:[[NSNumber alloc] initWithBool:[TGDatabaseInstance() isPeerMuted:conversation.conversationId]] forKey:@"mute"];
    
    [dict setObject:messageUsers forKey:@"users"];
    conversation.dialogListData = dict;
}

- (void)actorCompleted:(int)resultCode path:(NSString *)path result:(id)result
{
    if ([path isEqualToString:[NSString stringWithFormat:@"/tg/search/dialogs/(%d)", [_searchString hash]]])
    {
        NSDictionary *dict = ((SGraphObjectNode *)result).object;
        
        NSArray *users = [dict objectForKey:@"users"];
        NSArray *chats = [dict objectForKey:@"chats"];
        
        NSMutableArray *result = [[NSMutableArray alloc] init];
        if (chats != nil)
        {
            TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
            
            bool forwardMode = self.forwardMode;
            
            for (id object in chats)
            {
                if ([object isKindOfClass:[TGConversation class]])
                {
                    TGConversation *conversation = (TGConversation *)object;
                    if (forwardMode && conversation.conversationId <= INT_MIN)
                        continue;
                    
                    [self initializeDialogListData:conversation customUser:nil selfUser:selfUser];
                    [result addObject:conversation];
                }
                else
                {
                    [result addObject:object];
                }
            }
        }
        if (users != nil)
            [result addObjectsFromArray:users];
        
        NSString *searchString = _searchString;

        dispatch_async(dispatch_get_main_queue(), ^
        {
            TGDialogListController *dialogListController = self.dialogListController;
            [dialogListController searchResultsReloaded:result searchString:searchString];
        });
    }
    else if ([path isEqualToString:[NSString stringWithFormat:@"/tg/search/messages/(%d)", [_searchString hash]]])
    {
        NSArray *conversations = ((SGraphObjectNode *)result).object;
        
        NSMutableArray *result = [[NSMutableArray alloc] init];
        
        TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
        
        CFAbsoluteTime dialogListDataStartTime = CFAbsoluteTimeGetCurrent();
        
        for (TGConversation *conversation in conversations)
        {
            [self initializeDialogListData:conversation customUser:nil selfUser:selfUser];
            [result addObject:conversation];
        }
        
        NSString *searchString = _searchString;
        
        TGLog(@"Dialog list data parsing time: %f s", CFAbsoluteTimeGetCurrent() - dialogListDataStartTime);
        
        dispatch_async(dispatch_get_main_queue(), ^
        {
            TGDialogListController *dialogListController = self.dialogListController;
            [dialogListController searchResultsReloaded:result searchString:searchString];
        });
    }
    else if ([path hasPrefix:@"/tg/dialoglist"])
    {
        if (resultCode == 0)
        {
            SGraphListNode *listNode = (SGraphListNode *)result;
            NSMutableArray *loadedItems = [[listNode items] mutableCopy];
            bool canLoadMore = false;
            bool forwardMode = self.forwardMode;
            
            TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
            
            if (forwardMode)
            {
                for (int i = 0; i < (int)loadedItems.count; i++)
                {
                    if (((TGConversation *)loadedItems[i]).conversationId <= INT_MIN)
                    {
                        [loadedItems removeObjectAtIndex:i];
                        i--;
                    }
                }
            }
            
            for (TGConversation *conversation in loadedItems)
            {
                [self initializeDialogListData:conversation customUser:nil selfUser:selfUser];
            }
            
            if (_conversationList.count == 0)
            {
                [_conversationList addObjectsFromArray:loadedItems];
                canLoadMore = loadedItems.count != 0;
            }
            else
            {
                std::set<int64_t> existingConversations;
                for (TGConversation *conversation in _conversationList)
                {
                    existingConversations.insert(conversation.conversationId);
                }
                
                for (int i = 0; i < (int)loadedItems.count; i++)
                {
                    TGConversation *conversation = [loadedItems objectAtIndex:i];
                    if (existingConversations.find(conversation.conversationId) != existingConversations.end())
                    {
                        [loadedItems removeObjectAtIndex:i];
                        i--;
                    }
                }
                
                canLoadMore = loadedItems.count != 0;
                
                [_conversationList addObjectsFromArray:loadedItems];
            }
            
            [_conversationList sortUsingComparator:^NSComparisonResult(TGConversation *conversation1, TGConversation *conversation2)
            {
                int date1 = conversation1.date;
                int date2 = conversation2.date;
                
                if (date1 > date2)
                    return NSOrderedAscending;
                else if (date1 < date2)
                    return NSOrderedDescending;
                else
                    return NSOrderedSame;
            }];
            
            NSArray *items = [NSArray arrayWithArray:_conversationList];
            
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *controller = self.dialogListController;
                if (controller != nil)
                {
                    controller.canLoadMore = canLoadMore;
                    [controller dialogListFullyReloaded:items];
                }
            });
            
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^
            {
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void)
                {
                    [self dialogListReady];
                    
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^
                    {
                        [TGConversationController preloadGraphics]; 
                    });
                });
            });
        }
        else
        {
        }
    }
    else if ([path isEqualToString:@"/tg/service/synchronizationstate"])
    {
        int state = [((SGraphObjectNode *)result).object intValue];
        
        TGDialogListState newState;
        
        if (state & 2)
        {
            if (state & 4)
                newState = TGDialogListStateWaitingForNetwork;
            else
                newState = TGDialogListStateConnecting;
        }
        else if (state & 1)
            newState = TGDialogListStateUpdating;
        else
            newState = TGDialogListStateNormal;

        if (newState != _state)
        {
            _state = newState;
            dispatch_async(dispatch_get_main_queue(), ^
            {
                NSString *title =TGLocalized(@"DialogList.Title");
                if (newState == TGDialogListStateConnecting)
                    title = TGLocalized(@"State.Connecting");
                else if (newState == TGDialogListStateUpdating)
                    title = TGLocalized(@"State.Updating");
                else if (newState == TGDialogListStateWaitingForNetwork)
                    title = TGLocalized(@"State.WaitingForNetwork");
                
                TGDialogListController *dialogListController = self.dialogListController;
                [dialogListController titleStateUpdated:title isLoading:newState != TGDialogListStateNormal];
            });
        }
    }
}

- (void)actionStageResourceDispatched:(NSString *)path resource:(id)resource arguments:(id)__unused arguments
{
    if ([path hasPrefix:@"/tg/dialoglist"])
    {
        [self actorCompleted:ASStatusSuccess path:path result:resource];
    }
    else if ([path isEqualToString:@"/tg/conversations"])
    {
        NSMutableArray *conversations = [((SGraphObjectNode *)resource).object mutableCopy];
        
        TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
        
        if (self.forwardMode)
        {
            for (int i = 0; i < (int)conversations.count; i++)
            {
                if (((TGConversation *)conversations[i]).conversationId <= INT_MIN)
                {
                    [conversations removeObjectAtIndex:i];
                    i--;
                }
            }
        }
        
        if (conversations.count == 0)
            return;
        
        [conversations sortUsingComparator:^NSComparisonResult(id obj1, id obj2)
        {
            int date1 = (int)((TGConversation *)obj1).date;
            int date2 = (int)((TGConversation *)obj2).date;

            if (date1 < date2)
                return NSOrderedAscending;
            else if (date1 > date2)
                return NSOrderedDescending;
            else
                return NSOrderedSame;
        }];
        
        if (conversations.count == 1 && _conversationList.count != 0)
        {
            TGConversation *singleConversation = [conversations objectAtIndex:0];
            TGConversation *topConversation = ((TGConversation *)[_conversationList objectAtIndex:0]);
            if (!singleConversation.isDeleted && _conversationList.count > 0 && topConversation.conversationId == singleConversation.conversationId && topConversation.date <= singleConversation.date)
            {
                [self initializeDialogListData:singleConversation customUser:nil selfUser:selfUser];
                [_conversationList replaceObjectAtIndex:0 withObject:singleConversation];
                
                dispatch_async(dispatch_get_main_queue(), ^
                {
                    TGDialogListController *dialogListController = self.dialogListController;
                    
                    [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:[NSArray arrayWithObject:[[NSNumber alloc] initWithInt:0]] updatedItems:[NSArray arrayWithObject:singleConversation] removedIndices:nil];
                });
                
                return;
            }
        }
        
        std::map<int64_t, int> conversationIdToIndex;
        int index = -1;
        for (TGConversation *conversation in _conversationList)
        {
            index++;
            int64_t conversationId = conversation.conversationId;
            conversationIdToIndex.insert(std::pair<int64_t, int>(conversationId, index));
        }
        
        for (int i = 0; i < (int)conversations.count; i++)
        {
            TGConversation *conversation = [conversations objectAtIndex:i];
            int64_t conversationId = conversation.conversationId;
            std::map<int64_t, int>::iterator it = conversationIdToIndex.find(conversationId);
            if (it != conversationIdToIndex.end())
            {
                TGConversation *newConversation = [conversation copy];
                if (!newConversation.isDeleted)
                    [self initializeDialogListData:newConversation customUser:nil selfUser:selfUser];
                
                [_conversationList replaceObjectAtIndex:(it->second) withObject:newConversation];
                [conversations removeObjectAtIndex:i];
                i--;
            }
        }
        
#warning optimize
        
        for (int i = 0; i < (int)_conversationList.count; i++)
        {
            TGConversation *conversation = [_conversationList objectAtIndex:i];
            if (conversation.isDeleted)
            {
                TGLog(@"===== Removing item at %d", i);
                
                [_conversationList removeObjectAtIndex:i];
                i--;
            }
        }
        
        for (TGConversation *conversation in conversations)
        {
            TGConversation *newConversation = [conversation copy];
            if (!newConversation.isDeleted)
            {
                [self initializeDialogListData:newConversation customUser:nil selfUser:selfUser];
                
                [_conversationList addObject:newConversation];
            }
        }
        
        [_conversationList sortUsingComparator:^NSComparisonResult(id obj1, id obj2)
        {
            int date1 = (int)((TGConversation *)obj1).date;
            int date2 = (int)((TGConversation *)obj2).date;
            
            if (date1 < date2)
                return NSOrderedDescending;
            else if (date1 > date2)
                return NSOrderedAscending;
            else
                return NSOrderedSame;
        }];
        
        NSArray *items = [NSArray arrayWithArray:_conversationList];
        
        dispatch_async(dispatch_get_main_queue(), ^
        {
            TGDialogListController *controller = self.dialogListController;
            if (controller != nil)
                [controller dialogListFullyReloaded:items];
        });
    }
    else if ([path isEqualToString:@"/tg/userdatachanges"])
    {
        std::map<int, int> userIdToIndex;
        int index = -1;
        NSArray *users = (((SGraphObjectNode *)resource).object);
        for (TGUser *user in users)
        {
            index++;
            userIdToIndex.insert(std::pair<int, int>(user.uid, index));
        }
        
        TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
        
        NSMutableArray *updatedIndices = [[NSMutableArray alloc] init];
        NSMutableArray *updatedItems = [[NSMutableArray alloc] init];
        
        bool updateAllOutgoing = userIdToIndex.find(TGTelegraphInstance.clientUserId) != userIdToIndex.end();
        
        for (index = 0; index < (int)_conversationList.count; index++)
        {
            TGConversation *conversation = [_conversationList objectAtIndex:index];
            
            int userId = 0;
            if (conversation.isEncrypted)
            {
                if (conversation.chatParticipants.chatParticipantUids.count != 0)
                    userId = [conversation.chatParticipants.chatParticipantUids[0] intValue];
            }
            else if (conversation.isChat)
                userId = conversation.outgoing ? TGTelegraphInstance.clientUserId : conversation.fromUid;
            else
                userId = (int)conversation.conversationId;

            std::map<int, int>::iterator it = userIdToIndex.find(userId);
            if (it != userIdToIndex.end() || (updateAllOutgoing && conversation.outgoing))
            {
                TGConversation *newConversation = [conversation copy];
                [self initializeDialogListData:newConversation customUser:(it != userIdToIndex.end() ? [users objectAtIndex:it->second] : nil) selfUser:selfUser];
                [_conversationList replaceObjectAtIndex:index withObject:newConversation];
                [updatedIndices addObject:[NSNumber numberWithInt:index]];
                [updatedItems addObject:newConversation];
            }
        }
        
        if (updatedIndices.count != 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *controller = self.dialogListController;
                if (controller != nil)
                    [controller dialogListItemsChanged:nil insertedItems:nil updatedIndices:updatedIndices updatedItems:updatedItems removedIndices:nil];
            });
        }
    }
    else if ([path isEqualToString:@"/tg/conversation/*/typing"])
    {
        NSDictionary *dict = ((SGraphObjectNode *)resource).object;
        int64_t conversationId = [[dict objectForKey:@"conversationId"] longLongValue];
        if (conversationId != 0)
        {
            NSArray *typingUsers = [dict objectForKey:@"typingUsers"];
            NSString *typingString = nil;
            if (conversationId < 0)
            {
                if (typingUsers.count == 1)
                {
                    TGUser *user = [TGDatabaseInstance() loadUser:[(NSNumber *)[typingUsers objectAtIndex:0] intValue]];
                    NSString *firstName = user.firstName;
                    if (firstName.length == 0)
                        firstName = user.lastName;
                    typingString = [[NSString alloc] initWithFormat:TGLocalized(@"DialogList.SingleTypingSuffix"), firstName];
                }
                else if (typingUsers.count > 1)
                    typingString = [[NSString alloc] initWithFormat:TGLocalized(@"DialogList.MultipleTypingSuffix"), typingUsers.count];
            }
            else if (typingUsers.count != 0)
                typingString = TGLocalized(@"DialogList.Typing");
            
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                
                [dialogListController userTypingInConversationUpdated:conversationId typingString:typingString];
            });
        }
    }
    else if ([path isEqualToString:@"/tg/service/synchronizationstate"])
    {
        [self actorCompleted:ASStatusSuccess path:path result:resource];
    }
    else if ([path isEqualToString:@"/tg/unreadCount"])
    {
        int unreadCount = [((SGraphObjectNode *)resource).object intValue];
        dispatch_async(dispatch_get_main_queue(), ^
        {
            [[UIApplication sharedApplication] setApplicationIconBadgeNumber:unreadCount];
            if (unreadCount == 0)
                [[UIApplication sharedApplication] cancelAllLocalNotifications];
            
            self.unreadCount = unreadCount;
            [TGAppDelegateInstance.mainTabsController setUnreadCount:unreadCount];
            
            TGDialogListController *dialogListController = self.dialogListController;
            dialogListController.tabBarItem.badgeValue = unreadCount == 0 ? nil : [[NSString alloc] initWithFormat:@"%d", unreadCount];
        });
    }
    else if ([path hasPrefix:@"/tg/peerSettings/"])
    {
        NSDictionary *dict = ((SGraphObjectNode *)resource).object;
        
        NSMutableArray *updatedIndices = [[NSMutableArray alloc] init];
        NSMutableArray *updatedItems = [[NSMutableArray alloc] init];
        
        int64_t peerId = [[path substringWithRange:NSMakeRange(18, path.length - 1 - 18)] longLongValue];
        
        int count = _conversationList.count;
        for (int i = 0; i < count; i++)
        {
            TGConversation *conversation = [_conversationList objectAtIndex:i];
            if (conversation.conversationId == peerId)
            {
                TGConversation *newConversation = [conversation copy];
                NSMutableDictionary *newData = [conversation.dialogListData mutableCopy];
                [newData setObject:[[NSNumber alloc] initWithBool:[dict[@"muteUntil"] intValue] != 0] forKey:@"mute"];
                newConversation.dialogListData = newData;
                
                [_conversationList replaceObjectAtIndex:i withObject:newConversation];
                
                [updatedIndices addObject:[[NSNumber alloc] initWithInt:i]];
                [updatedItems addObject:newConversation];
                
                break;
            }
        }
        
        if (updatedItems.count != 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:updatedIndices updatedItems:updatedItems removedIndices:nil];
            });
        }
    }
    else if ([path isEqualToString:@"/tg/contactlist"])
    {
        NSMutableArray *updatedIndices = [[NSMutableArray alloc] init];
        NSMutableArray *updatedItems = [[NSMutableArray alloc] init];
        
        int index = -1;
        int count = _conversationList.count;
        for (int i = 0; i < count; i++)
        {
            index++;
            
            TGConversation *conversation = [_conversationList objectAtIndex:i];
            
            if (!conversation.isChat)
            {
                TGUser *user = [TGDatabaseInstance() loadUser:(int)conversation.conversationId];
                if (user == nil)
                    continue;
                
                NSString *title = nil;
                
                if (user.phoneNumber.length != 0 && ![TGDatabaseInstance() uidIsRemoteContact:user.uid] && user.uid != 333000)
                    title = user.formattedPhoneNumber;
                else
                    title = [user displayName];
                
                if (title != nil && ![title isEqualToString:[conversation.dialogListData objectForKey:@"title"]])
                {
                    TGConversation *newConversation = [conversation copy];
                    NSMutableDictionary *newData = [conversation.dialogListData mutableCopy];
                    [newData setObject:title forKey:@"title"];
                    newConversation.dialogListData = newData;
                    
                    [_conversationList replaceObjectAtIndex:i withObject:newConversation];
                    
                    [updatedIndices addObject:[[NSNumber alloc] initWithInt:index]];
                    [updatedItems addObject:newConversation];
                }
            }
        }
        
        if (updatedItems.count != 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:updatedIndices updatedItems:updatedItems removedIndices:nil];
            });
        }
    }
}

@end
