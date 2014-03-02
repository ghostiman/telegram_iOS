#import "TGConversationAddMessagesActor.h"

#import "ActionStage.h"

#import "TGTelegraph.h"
#import "TGDatabase.h"
#import "TGMessage.h"

#import "TGAppDelegate.h"

#import "SGraphObjectNode.h"

#import "TGInterfaceManager.h"

#import "TGSession.h"

#include <set>

@interface TGConversationAddMessagesActor ()

@end

@implementation TGConversationAddMessagesActor

+ (NSString *)genericPath
{
    return @"/tg/addmessage/@";
}

- (id)initWithPath:(NSString *)path
{
    self = [super initWithPath:path];
    if (self != nil)
    {
        self.requestQueueName = @"messages";
        self.cancelTimeout = 0;
    }
    return self;
}

- (void)execute:(NSDictionary *)options
{
    NSArray *messages = [options objectForKey:@"messages"];
    NSMutableDictionary *chats = [options objectForKey:@"chats"];
    
    if (messages == nil && chats.count != 0)
    {
        if ([chats respondsToSelector:@selector(allKeys)])
        {
            [chats enumerateKeysAndObjectsUsingBlock:^(__unused id key, TGConversation *conversation, __unused BOOL *stop)
            {
                [[TGDatabase instance] addMessagesToConversation:nil conversationId:conversation.conversationId updateConversation:conversation dispatch:true countUnread:false];
            }];
        }
        else
        {
            for (TGConversation *conversation in chats)
            {
                [[TGDatabase instance] addMessagesToConversation:nil conversationId:conversation.conversationId updateConversation:conversation dispatch:true countUnread:false];
            }
        }
        
        [ActionStageInstance() actionCompleted:self.path result:nil];
        
        return;
    }
    
    int currentTime = (int)(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970 + [[TGSession instance] timeDifference]);
    
    bool playNotification = false;
    bool needsSound = false;
    
    std::tr1::shared_ptr<std::map<int64_t, std::set<int> > > pProcessedUsersStoppedTyping(new std::map<int64_t, std::set<int> >());

    NSMutableDictionary *messagesByConversation = [[NSMutableDictionary alloc] init];
    std::set<int64_t> conversationsWithNotification;
    
    int maxMid = 0;
    
    for (TGMessage *message in messages)
    {
        if (!message.outgoing && message.unread && message.toUid != message.fromUid)
        {
            if (message.mid < TGMessageLocalMidBaseline && message.actionInfo == nil)
            {
                playNotification = true;
                needsSound = true;
                conversationsWithNotification.insert(message.cid);
            }
            else
            {
                if (message.actionInfo.actionType == TGMessageActionUserChangedPhoto)
                {
                    playNotification = true;
                    conversationsWithNotification.insert(message.cid);
                }
            }
        }
        
        int64_t conversationId = message.cid;
        NSNumber *nConversationId = [NSNumber numberWithLongLong:conversationId];
        NSMutableArray *array = [messagesByConversation objectForKey:nConversationId];
        if (array == nil)
        {
            array = [[NSMutableArray alloc] init];
            [messagesByConversation setObject:array forKey:nConversationId];
        }
        
        if (message.date > currentTime - 20)
        {
            std::map<int64_t, std::set<int> >::iterator it = pProcessedUsersStoppedTyping->find(conversationId);
            if (it == pProcessedUsersStoppedTyping->end())
            {
                std::set<int> usersStoppedTypingInConversation;
                usersStoppedTypingInConversation.insert((int)message.fromUid);
                pProcessedUsersStoppedTyping->insert(std::make_pair(conversationId, usersStoppedTypingInConversation));
            }
            else
            {
                it->second.insert((int)message.fromUid);
            }
        }
        
        if (conversationId <= INT_MIN)
        {
            if (message.mediaAttachments != nil)
            {
                for (TGMediaAttachment *attachment in message.mediaAttachments)
                {
                    if (attachment.type == TGActionMediaAttachmentType)
                    {
                        TGActionMediaAttachment *actionAttachment = (TGActionMediaAttachment *)attachment;
                        if (actionAttachment.actionType == TGMessageActionEncryptedChatMessageLifetime)
                        {
                            [TGDatabaseInstance() setMessageLifetimeForPeerId:conversationId encryptedConversationId:0 messageLifetime:[actionAttachment.actionData[@"messageLifetime"] intValue] writeToActionQueue:false];
                            
                            [ActionStageInstance() dispatchResource:[[NSString alloc] initWithFormat:@"/tg/encrypted/messageLifetime/(%lld)", conversationId] resource:actionAttachment.actionData[@"messageLifetime"]];
                        }
                        
                        break;
                    }
                }
            }
        }
        
        int mid = message.mid;
        if (!message.outgoing && mid < TGMessageLocalMidBaseline && mid > maxMid)
            maxMid = mid;
        
        [array addObject:message];
    }
    
    NSMutableArray *lastMessages = [[NSMutableArray alloc] init];
    TGMessage *lastIncomingMessage = nil;
    NSTimeInterval lastIncomingMessageDate = 0;
    
    for (NSNumber *nConversationId in messagesByConversation)
    {
        NSArray *conversationMessages = [messagesByConversation objectForKey:nConversationId];
        
        TGMessage *lastMessage = nil;
        NSTimeInterval lastMessageDate = 0;
        for (TGMessage *message in conversationMessages)
        {
            NSTimeInterval messageDate = message.date;
            
            if (lastMessage == nil || messageDate > lastMessageDate || ((int)(lastMessageDate) == (int)(messageDate) && message.mid > lastMessage.mid))
            {
                lastMessage = message;
                lastMessageDate = messageDate;
            }
            
            if (!message.outgoing && (lastIncomingMessage == nil || messageDate > lastIncomingMessageDate || ((int)(lastIncomingMessageDate) == (int)(messageDate) && message.mid > lastIncomingMessage.mid)))
            {
                lastIncomingMessage = message;
                lastIncomingMessageDate = messageDate;
            }
        }
        if (lastMessage != nil)
            [lastMessages addObject:lastMessage];
        
        TGConversation *conversation = [chats objectForKey:nConversationId];
        [[TGDatabase instance] addMessagesToConversation:conversationMessages conversationId:[nConversationId longLongValue] updateConversation:conversation dispatch:true countUnread:true];
        
        [ActionStageInstance() dispatchResource:[NSString stringWithFormat:@"/tg/conversation/(%lld)/messages", [nConversationId longLongValue]] resource:[[SGraphObjectNode alloc] initWithObject:conversationMessages]];
    }
    
    bool playChatSound = false;
    
    if (playNotification)
    {
        playNotification = false;
        bool supposedToPlaySound = needsSound;
        needsSound = false;
        for (std::set<int64_t>::iterator it = conversationsWithNotification.begin(); it != conversationsWithNotification.end(); it++)
        {
            int64_t notificationPeerId = *it <= INT_MIN ? [TGDatabaseInstance() encryptedParticipantIdForConversationId:*it] : *it;
            if (![TGDatabaseInstance() isPeerMuted:notificationPeerId])
            {
                if (notificationPeerId < 0)
                    playChatSound = true;
                playNotification = true;
                needsSound = supposedToPlaySound;
                break;
            }
        }
    }
    
    if (playNotification)
    {
        if (needsSound)
            [TGAppDelegateInstance playSound:TGAppDelegateInstance.soundEnabled ? (playChatSound ? @"notification.caf" : @"notification.caf") : nil vibrate:true];
        if (lastIncomingMessage != nil)
        {
            [[TGInterfaceManager instance] displayBannerIfNeeded:lastIncomingMessage conversationId:lastIncomingMessage.cid];
        }
    }
    
    dispatch_async([ActionStageInstance() globalStageDispatchQueue], ^
    {
        if (!pProcessedUsersStoppedTyping->empty())
        {
            for (std::map<int64_t, std::set<int> >::iterator it = pProcessedUsersStoppedTyping->begin(); it != pProcessedUsersStoppedTyping->end(); it++)
            {
                for (std::set<int>::iterator it2 = it->second.begin(); it2 != it->second.end(); it2++)
                {
                    [TGTelegraphInstance dispatchUserTyping:*it2 inConversation:it->first typing:false];
                }
            }
        }
    });
    
    if (maxMid > 0)
    {
        [TGDatabaseInstance() updateLatestMessageId:maxMid applied:false completion:^(int greaterMidForSynchronization)
        {
            if (greaterMidForSynchronization > 0)
            {
                [ActionStageInstance() requestActor:[[NSString alloc] initWithFormat:@"/tg/messages/reportDelivery/(messages)"] options:[[NSDictionary alloc] initWithObjectsAndKeys:[[NSNumber alloc] initWithInt:maxMid], @"mid", nil] watcher:TGTelegraphInstance];
            }
        }];
    }
    
    [ActionStageInstance() actionCompleted:self.path result:nil];
}

- (void)cancel
{
    [super cancel];
}

@end
