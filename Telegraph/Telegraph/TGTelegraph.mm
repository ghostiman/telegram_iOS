#import "TGTelegraph.h"

#import "TGAppDelegate.h"

#import "TGTransport.h"

#import "UIDevice+PlatformInfo.h"

#import "AFNetworking.h"
#import "JSONKit.h"

#import "SGraphObjectNode.h"

#import "TGSchema.h"

#import "TGRawHttpRequest.h"

#import <AddressBook/AddressBook.h>

#import "TGDatabase.h"

#import "TGUser+Telegraph.h"

#import "TGDatacenterHandshakeActor.h"
#import "TGExportDatacenterAuthorizationActor.h"
#import "TGUpdateDatacenterDataActor.h"
#import "TGFutureSaltsRequestActor.h"

#import "TGLogoutRequestBuilder.h"
#import "TGSendCodeRequestBuilder.h"
#import "TGSignInRequestBuilder.h"
#import "TGSignUpRequestBuilder.h"
#import "TGSendInvitesActor.h"
#import "TGPushActionsRequestBuilder.h"
#import "TGUpdatePresenceActor.h"
#import "TGRevokeSessionsActor.h"

#import "TGApplyUpdatesActor.h"
#import "TGUpdateStateRequestBuilder.h"
#import "TGApplyStateRequestBuilder.h"
#import "TGSynchronizationStateRequestActor.h"
#import "TGSynchronizeActionQueueActor.h"
#import "TGSynchronizeServiceActionsActor.h"

#import "TGUserDataRequestBuilder.h"
#import "TGExtendedUserDataRequestActor.h"
#import "TGBlockListRequestActor.h"
#import "TGChangePeerBlockStatusActor.h"
#import "TGChangeNameActor.h"
#import "TGPrivacySettingsRequestActor.h"
#import "TGChangePrivacySettingsActor.h"
#import "TGUpdateUserStatusesActor.h"

#import "TGDialogListRequestBuilder.h"
#import "TGDialogListSearchActor.h"
#import "TGMessagesSearchActor.h"

#import "TGSynchronizeContactsActor.h"
#import "TGContactListRequestBuilder.h"
#import "TGContactListSearchActor.h"
#import "TGContactRequestActionActor.h"
#import "TGLiveNearbyActor.h"
#import "TGExclusiveLiveNearbyActor.h"
#import "TGLocationServicesStateActor.h"

#import "TGConversationHistoryAsyncRequestActor.h"
#import "TGConversationHistoryRequestActor.h"
#import "TGConversationMediaHistoryRequestActor.h"
#import "TGConversationChatInfoRequestActor.h"
#import "TGConversationSendMessageActor.h"
#import "TGConversationReadHistoryActor.h"
#import "TGReportDeliveryActor.h"
#import "TGConversationActivityRequestBuilder.h"
#import "TGConversationChangeTitleRequestActor.h"
#import "TGConversationChangePhotoActor.h"
#import "TGConversationCreateChatRequestActor.h"
#import "TGConversationAddMemberRequestActor.h"
#import "TGConversationDeleteMemberRequestActor.h"
#import "TGConversationSetStateActor.h"
#import "TGConversationStateRequestActor.h"
#import "TGConversationDeleteMessagesActor.h"
#import "TGConversationDeleteActor.h"
#import "TGConversationClearHistoryActor.h"
#import "TGConversationUsersTypingActor.h"

#import "TGTimelineHistoryRequestBuilder.h"
#import "TGTimelineUploadPhotoRequestBuilder.h"
#import "TGTimelineRemoveItemsRequestActor.h"
#import "TGTimelineAssignProfilePhotoActor.h"
#import "TGDeleteUserAvatarActor.h"

#import "TGUserDataRequestBuilder.h"
#import "TGPeerSettingsActor.h"
#import "TGChangePeerSettingsActor.h"
#import "TGResetPeerNotificationsActor.h"
#import "TGExtendedChatDataRequestActor.h"

#import "TGProfilePhotoListActor.h"
#import "TGDeleteProfilePhotoActor.h"

#import "TGConversationAddMessagesActor.h"
#import "TGConversationReadMessagesActor.h"

#import "TGLocationRequestActor.h"
#import "TGLocationReverseGeocodeActor.h"
#import "TGSaveGeocodingResultActor.h"

#import "TGFileDownloadActor.h"
#import "TGFileUploadActor.h"

#import "TGCheckImageStoredActor.h"

#import "TGVideoDownloadActor.h"
#import "TGHttpServerActor.h"

#import "TGCheckUpdatesActor.h"
#import "TGWallpaperListRequestActor.h"
#import "TGImageSearchActor.h"

#import "TGSynchronizePreferencesActor.h"

#import "TGRequestEncryptedChatActor.h"
#import "TGEncryptedChatResponseActor.h"
#import "TGDiscardEncryptedChatActor.h"

#import "TGRemoteImageView.h"
#import "TGImageUtils.h"
#import "TGStringUtils.h"
#import "TGInterfaceAssets.h"

#import "TGInterfaceManager.h"

#import "TGSession.h"
#import "TGTcpTransport.h"

#import "TGTimer.h"

#import <libkern/OSAtomic.h>

#include <set>
#include <map>

static CGSize extractSize(NSString *string, NSString *prefix)
{
    CGSize size = CGSizeZero;
    int n = prefix.length;
    bool invalid = false;
    for (int i = n; i < (int)string.length; i++)
    {
        unichar c = [string characterAtIndex:i];
        if (c == 'x')
        {
            if (i == n)
                invalid = true;
            else
            {
                size.width = [[string substringWithRange:NSMakeRange(n, i - n)] intValue];
                n = i + 1;
            }
            break;
        }
        else if (c < '0' || c > '9')
        {
            invalid = true;
            break;
        }
    }
    if (!invalid)
    {
        for (int i = n; i < (int)string.length; i++)
        {
            unichar c = [string characterAtIndex:i];
            if (c < '0' || c > '9')
            {
                invalid = true;
                break;
            }
            else if (i == (int)string.length - 1)
            {
                size.height = [[string substringFromIndex:n] intValue];
            }
        }
    }
    if (!invalid)
    {
        return size;
    }
    
    return CGSizeZero;
}

static bool readIntFromString(NSString *string, int &offset, unichar delimiter, int *pResult)
{
    int length = string.length;
    for (int i = offset; i < length; i++)
    {
        unichar c = [string characterAtIndex:i];
        if (c == delimiter || i == length - 1)
        {
            if (pResult != NULL)
                *pResult = [[string substringWithRange:NSMakeRange(offset, i - offset + (i == length - 1 ? 1 : 0))] intValue];
            offset = i + 1;
            
            return true;
        }
        else if (c < '0' || c > '9')
        {
            return false;
        }
    }
    
    return false;
}

static bool extractTwoSizes(NSString *string, NSString *prefix, CGSize *firstSize, CGSize *secondSize)
{
    int value = 0;
    CGSize size = CGSizeZero;
    
    int offset = prefix.length;
    
    if (readIntFromString(string, offset, 'x', &value))
        size.width = value;
    else
        return false;
    
    if (readIntFromString(string, offset, ',', &value))
        size.height = value;
    else
        return false;
    
    if (firstSize != NULL)
        *firstSize = size;
    
    value = 0;
    size = CGSizeZero;
    
    if (readIntFromString(string, offset, 'x', &value))
        size.width = value;
    else
        return false;
    
    if (readIntFromString(string, offset, 0, &value))
        size.height = value;
    else
        return false;
    
    if (secondSize != NULL)
        *secondSize = size;
    
    return true;
}

TGTelegraph *TGTelegraphInstance = nil;

typedef std::map<int, std::pair<TGUser *, int > >::iterator UserDataToDispatchIterator;

@interface TGTelegraph ()
{
    std::map<int, TGUserPresence> _userPresenceToDispatch;
    std::map<int, std::pair<TGUser *, int> > _userDataToDispatch;
    
    std::map<int, int> _userPresenceExpiration;
    
    std::map<int, int> _userLinksToDispatch;
}

@property (nonatomic, strong) NSMutableArray *runningRequests;
@property (nonatomic, strong) NSMutableArray *retryRequestTimers;

@property (nonatomic, strong) NSMutableArray *userDataUpdatesSubscribers;
@property (nonatomic, strong) TGTimer *userUpdatesSubscriptionTimer;

@property (nonatomic, strong) TGTimer *updatePresenceTimer;
@property (nonatomic, strong) TGTimer *updateRelativeTimestampsTimer;

@property (nonatomic) bool willDispatchUserData;
@property (nonatomic) bool willDispatchUserPresence;
@property (nonatomic, strong) TGTimer *userPresenceExpirationTimer;

@property (nonatomic, strong) TGTimer *usersTypingServiceTimer;
@property (nonatomic, strong) NSMutableDictionary *typingUsersByConversation;

@end

@implementation TGTelegraph

- (id)init
{
    self = [super initWithBaseURL:nil];
    if (self != nil)
    {
        TGTelegraphInstance = self;
        
        self.stringEncoding = NSUTF8StringEncoding;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];

        _actionHandle = [[ASHandle alloc] initWithDelegate:self releaseOnMainThread:false];
        
        [ActionStageInstance() dispatchOnStageQueue:^
        {
            NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
            TGLog(@"Running with %@ (version %@)", bundleIdentifier, [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]);
            
            _apiId = @"2899";
            _apiHash = @"36722c72256a24c1225de00eb6a1ca74";
            
            _runningRequests = [[NSMutableArray alloc] init];
            
            _retryRequestTimers = [[NSMutableArray alloc] init];
            
            [TGDatabaseInstance() setMessageCleanupBlock:^(TGMediaAttachment *attachment)
            {
                if ([attachment isKindOfClass:[TGLocalMessageMetaMediaAttachment class]])
                {
                    TGLocalMessageMetaMediaAttachment *messageMeta = (TGLocalMessageMetaMediaAttachment *)attachment;
                    [ActionStageInstance() dispatchOnStageQueue:^
                    {
                        static NSFileManager *fileManager = [[NSFileManager alloc] init];
                        
                        [messageMeta.imageUrlToDataFile enumerateKeysAndObjectsUsingBlock:^(__unused NSString *imageUrl, NSString *filePath, __unused BOOL *stop)
                        {
                            NSError *error = nil;
                            [fileManager removeItemAtPath:filePath error:&error];
                        }];
                    }];
                }
            }];

            [TGDatabaseInstance() setCleanupEverythingBlock:^
            {
                NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true) objectAtIndex:0];
                NSString *videosPath = [documentsDirectory stringByAppendingPathComponent:@"video"];
                
                NSFileManager *fileManager = [[NSFileManager alloc] init];
                for (NSString *fileName in [fileManager contentsOfDirectoryAtPath:videosPath error:nil])
                {
                    [fileManager removeItemAtPath:[videosPath stringByAppendingPathComponent:fileName] error:nil];
                }
            }];
            
            _updatePresenceTimer = [[TGTimer alloc] initWithTimeout:60.0 repeat:true completion:^
            {
                [self updatePresenceNow];
            } queue:[ActionStageInstance() globalStageDispatchQueue]];
            [_updatePresenceTimer start];
            
            _updateRelativeTimestampsTimer = [[TGTimer alloc] initWithTimeout:30.0 repeat:true completion:^
            {
                [ActionStageInstance() dispatchResource:@"/as/updateRelativeTimestamps" resource:nil];
            } queue:[ActionStageInstance() globalStageDispatchQueue]];
            if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground)
                [_updateRelativeTimestampsTimer start];
            
            _typingUsersByConversation = [[NSMutableDictionary alloc] init];
            _usersTypingServiceTimer = [[TGTimer alloc] initWithTimeout:1.0 repeat:false completion:^
            {
                [self updateUserTypingStatuses];
            } queue:[ActionStageInstance() globalStageDispatchQueue]];
            
            _userDataUpdatesSubscribers = [[NSMutableArray alloc] init];
            _userUpdatesSubscriptionTimer = [[TGTimer alloc] initWithTimeout:10 * 60.0 repeat:true completion:^
            {
                [self updateUserUpdatesSubscriptions];
            } queue:[ActionStageInstance() globalStageDispatchQueue]];
            
            [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:true];
            
            NSURLCache *sharedCache = [[NSURLCache alloc] initWithMemoryCapacity:(256) diskCapacity:0 diskPath:nil];
            [NSURLCache setSharedURLCache:sharedCache];

            [ASActor registerRequestBuilder:[TGDatacenterHandshakeActor class]];
            [ASActor registerRequestBuilder:[TGExportDatacenterAuthorizationActor class]];
            [ASActor registerRequestBuilder:[TGUpdateDatacenterDataActor class]];
            [ASActor registerRequestBuilder:[TGFutureSaltsRequestActor class]];
            
            [ASActor registerRequestBuilder:[TGLogoutRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGSendCodeRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGSignInRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGSignUpRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGSendInvitesActor class]];
            [ASActor registerRequestBuilder:[TGPushActionsRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGUpdatePresenceActor class]];
            [ASActor registerRequestBuilder:[TGRevokeSessionsActor class]];
            
            [ASActor registerRequestBuilder:[TGApplyUpdatesActor class]];
            
            [ASActor registerRequestBuilder:[TGFileDownloadActor class]];
            [ASActor registerRequestBuilder:[TGFileUploadActor class]];
            
            [ASActor registerRequestBuilder:[TGCheckImageStoredActor class]];
            
            [ASActor registerRequestBuilder:[TGUpdateStateRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGApplyStateRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGSynchronizationStateRequestActor class]];
            [ASActor registerRequestBuilder:[TGSynchronizeActionQueueActor class]];
            [ASActor registerRequestBuilder:[TGSynchronizeServiceActionsActor class]];
            
            [ASActor registerRequestBuilder:[TGUserDataRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGExtendedUserDataRequestActor class]];
            [ASActor registerRequestBuilder:[TGPeerSettingsActor class]];
            [ASActor registerRequestBuilder:[TGChangePeerSettingsActor class]];
            [ASActor registerRequestBuilder:[TGResetPeerNotificationsActor class]];
            [ASActor registerRequestBuilder:[TGExtendedChatDataRequestActor class]];
            [ASActor registerRequestBuilder:[TGBlockListRequestActor class]];
            [ASActor registerRequestBuilder:[TGChangePeerBlockStatusActor class]];
            [ASActor registerRequestBuilder:[TGChangeNameActor class]];
            [ASActor registerRequestBuilder:[TGPrivacySettingsRequestActor class]];
            [ASActor registerRequestBuilder:[TGChangePrivacySettingsActor class]];
            [ASActor registerRequestBuilder:[TGUpdateUserStatusesActor class]];
            
            [ASActor registerRequestBuilder:[TGDialogListRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGDialogListSearchActor class]];
            [ASActor registerRequestBuilder:[TGMessagesSearchActor class]];
            
            [ASActor registerRequestBuilder:[TGSynchronizeContactsActor class]];
            [ASActor registerRequestBuilder:[TGContactListRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGContactListSearchActor class]];
            [ASActor registerRequestBuilder:[TGContactRequestActionActor class]];
            [ASActor registerRequestBuilder:[TGLiveNearbyActor class]];
            [ASActor registerRequestBuilder:[TGExclusiveLiveNearbyActor class]];
            [ASActor registerRequestBuilder:[TGLocationServicesStateActor class]];
            
            [ASActor registerRequestBuilder:[TGConversationHistoryAsyncRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationHistoryRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationMediaHistoryRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationChatInfoRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationSendMessageActor class]];
            [ASActor registerRequestBuilder:[TGConversationReadHistoryActor class]];
            [ASActor registerRequestBuilder:[TGReportDeliveryActor class]];
            [ASActor registerRequestBuilder:[TGConversationActivityRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGConversationChangeTitleRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationChangePhotoActor class]];
            [ASActor registerRequestBuilder:[TGConversationCreateChatRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationAddMemberRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationDeleteMemberRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationSetStateActor class]];
            [ASActor registerRequestBuilder:[TGConversationStateRequestActor class]];
            [ASActor registerRequestBuilder:[TGConversationDeleteMessagesActor class]];
            [ASActor registerRequestBuilder:[TGConversationDeleteActor class]];
            [ASActor registerRequestBuilder:[TGConversationClearHistoryActor class]];
            [ASActor registerRequestBuilder:[TGConversationUsersTypingActor class]];
            
            [ASActor registerRequestBuilder:[TGProfilePhotoListActor class]];
            [ASActor registerRequestBuilder:[TGDeleteProfilePhotoActor class]];
            
            [ASActor registerRequestBuilder:[TGTimelineHistoryRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGTimelineUploadPhotoRequestBuilder class]];
            [ASActor registerRequestBuilder:[TGTimelineRemoveItemsRequestActor class]];
            [ASActor registerRequestBuilder:[TGTimelineAssignProfilePhotoActor class]];
            [ASActor registerRequestBuilder:[TGDeleteUserAvatarActor class]];
            
            [ASActor registerRequestBuilder:[TGConversationAddMessagesActor class]];
            [ASActor registerRequestBuilder:[TGConversationReadMessagesActor class]];

            [ASActor registerRequestBuilder:[TGLocationRequestActor class]];
            [ASActor registerRequestBuilder:[TGLocationReverseGeocodeActor class]];
            [ASActor registerRequestBuilder:[TGSaveGeocodingResultActor class]];
            
            [ASActor registerRequestBuilder:[TGVideoDownloadActor class]];
            [ASActor registerRequestBuilder:[TGHttpServerActor class]];
            
            [ASActor registerRequestBuilder:[TGCheckUpdatesActor class]];
            [ASActor registerRequestBuilder:[TGWallpaperListRequestActor class]];
            [ASActor registerRequestBuilder:[TGImageSearchActor class]];
            
            [ASActor registerRequestBuilder:[TGSynchronizePreferencesActor class]];

            [ASActor registerRequestBuilder:[TGRequestEncryptedChatActor class]];
            [ASActor registerRequestBuilder:[TGEncryptedChatResponseActor class]];
            [ASActor registerRequestBuilder:[TGDiscardEncryptedChatActor class]];
        }];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCorners(source, CGSizeMake(56, 56), CGSizeZero, 5, nil, false, nil);
        } withName:@"avatar56"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
         {
             return TGScaleAndRoundCornersWithOffset(source, CGSizeMake(30, 30), CGPointMake(2, 2), CGSizeMake(32, 32), 5, nil, false, nil);
         } withName:@"avatarAuthor"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCorners(source, CGSizeMake(40, 40), CGSizeZero, 4, nil, false, nil);
        } withName:@"avatar40"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCorners(source, CGSizeMake(27, 27), CGSizeZero, 0, nil, true, nil);
        } withName:@"avatar27"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCorners(source, CGSizeMake(56, 56), CGSizeMake(27, 56), 0, nil, true, nil);
        } withName:@"avatar56_half"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCornersWithOffsetAndFlags(source, CGSizeMake(69, 69), CGPointMake(0.5f, 0), CGSizeMake(70, 70), 10, [TGInterfaceAssets profileAvatarOverlay], false, nil, TGScaleImageScaleOverlay);
        } withName:@"profileAvatar"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCornersWithOffset(source, CGSizeMake(69, 69), CGPointMake(1, 0.5f), CGSizeMake(71, 71), 9, [UIImage imageNamed:@"LoginProfilePhotoOverlay.png"], false, nil);
        } withName:@"signupProfileAvatar"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            UIImage *rawImage = [UIImage imageNamed:@"LoginBigPhotoOverlay.png"];
            return TGScaleAndRoundCornersWithOffsetAndFlags(source, CGSizeMake(180, 180), CGPointMake(3.5f, 3.0f), CGSizeMake(187, 187), 8, [rawImage stretchableImageWithLeftCapWidth:(int)(rawImage.size.width / 2) topCapHeight:(int)(rawImage.size.height / 2)], false, nil, TGScaleImageScaleOverlay);
        } withName:@"inactiveAvatar"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCornersWithOffset(source, CGSizeMake(35, 35), CGPointZero, CGSizeMake(35, 35), 4, nil, false, nil);
        } withName:@"titleAvatar"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCornersWithOffset(source, CGSizeMake(40, 40), CGPointMake(2, 2), CGSizeMake(44, 44), 4, [TGInterfaceAssets memberListAvatarOverlay], false, nil);
        } withName:@"memberListAvatar"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCornersWithOffset(source, CGSizeMake(37, 37), CGPointMake(0.5f, 0.0f), CGSizeMake(38, 38), 19, [TGInterfaceAssets conversationAvatarOverlay], false, nil);
        } withName:@"conversationAvatar"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCornersWithOffset(source, CGSizeMake(33, 33), CGPointMake(0.5f, 0.0f), CGSizeMake(34, 34), 4, [TGInterfaceAssets notificationAvatarOverlay], false, nil);
        } withName:@"notificationAvatar"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCornersWithOffset(source, CGSizeMake(30, 30), CGPointZero, CGSizeMake(30, 30), 3, nil, false, nil);
        } withName:@"inlineMessageAvatar"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleAndRoundCornersWithOffsetAndFlags(source, CGSizeMake(149.5f, 149), CGPointMake(0.5f, 0.5f), CGSizeMake(150, 150), 8, [[TGInterfaceAssets instance] conversationUserPhotoOverlay], false, nil, TGScaleImageScaleOverlay);
        } withName:@"conversationUserPhoto"];
        
        [TGRemoteImageView registerImageUniversalProcessor:^UIImage *(NSString *name, UIImage *source)
        {
            CGSize size = CGSizeZero;
            int n = 6;
            bool invalid = false;
            for (int i = n; i < (int)name.length; i++)
            {
                unichar c = [name characterAtIndex:i];
                if (c == 'x')
                {
                    if (i == n)
                        invalid = true;
                    else
                    {
                        size.width = [[name substringWithRange:NSMakeRange(n, i - n)] intValue];
                        n = i + 1;
                    }
                    break;
                }
                else if (c < '0' || c > '9')
                {
                    invalid = true;
                    break;
                }
            }
            if (!invalid)
            {
                for (int i = n; i < (int)name.length; i++)
                {
                    unichar c = [name characterAtIndex:i];
                    if (c < '0' || c > '9')
                    {
                        invalid = true;
                        break;
                    }
                    else if (i == (int)name.length - 1)
                    {
                        size.height = [[name substringFromIndex:n] intValue];
                    }
                }
            }
            if (!invalid)
            {
                if (CGSizeEqualToSize(source.size, size))
                    return source;
                return TGScaleImage(source, size);
            }
            
            return nil;
        } withBaseName:@"scale"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            CGSize imageSize = source.screenSize;
            if (imageSize.width < 1)
                imageSize.width = 1;
            if (imageSize.height < 1)
                imageSize.height = 1;
            
            if (imageSize.width < imageSize.height)
            {
                imageSize.height = (int)(imageSize.height * 90.0f / imageSize.width);
                imageSize.width = 90;
            }
            else
            {
                imageSize.width = (int)(imageSize.width * 90.0f / imageSize.height);
                imageSize.height = 90;
            }
            imageSize = TGFitSize(imageSize, CGSizeMake(200, 200));
            return TGScaleAndRoundCorners(source, imageSize, imageSize, 0, nil, true, nil);
        } withName:@"mediaListImage"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            CGSize imageSize = source.screenSize;
            if (imageSize.width < 1)
                imageSize.width = 1;
            if (imageSize.height < 1)
                imageSize.height = 1;
            
            if (imageSize.width < imageSize.height)
            {
                imageSize.height = (int)(imageSize.height * 75.0f / imageSize.width);
                imageSize.width = 75.0f;
            }
            else
            {
                imageSize.width = (int)(imageSize.width * 75.0f / imageSize.height);
                imageSize.height = 75.0f;
            }
            
            //imageSize = TGFitSize(imageSize, CGSizeMake(200, 200));
            
            return TGScaleAndRoundCorners(source, imageSize, CGSizeMake(75, 75), 0, nil, true, nil);
        } withName:@"mediaGridImage"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            CGSize imageSize = source.screenSize;
            if (imageSize.width < 1)
                imageSize.width = 1;
            if (imageSize.height < 1)
                imageSize.height = 1;
            
            const float imageSide = 100.0f;
            
            if (imageSize.width < imageSize.height)
            {
                imageSize.height = (int)(imageSize.height * imageSide / imageSize.width);
                imageSize.width = imageSide;
            }
            else
            {
                imageSize.width = (int)(imageSize.width * imageSide / imageSize.height);
                imageSize.height = imageSide;
            }
            
            //imageSize = TGFitSize(imageSize, CGSizeMake(200, 200));
            
            return TGScaleAndRoundCorners(source, imageSize, CGSizeMake(imageSide, imageSide), 0, nil, true, nil);
        } withName:@"mediaGridImageLarge"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
         {
             CGSize imageSize = source.screenSize;
             if (imageSize.width < 1)
                 imageSize.width = 1;
             if (imageSize.height < 1)
                 imageSize.height = 1;
             
             const float imageSide = 118.0f;
             
             if (imageSize.width < imageSize.height)
             {
                 imageSize.height = (int)(imageSize.height * imageSide / imageSize.width);
                 imageSize.width = imageSide;
             }
             else
             {
                 imageSize.width = (int)(imageSize.width * imageSide / imageSize.height);
                 imageSize.height = imageSide;
             }
             
             return TGScaleAndRoundCornersWithOffsetAndFlags(source, imageSize, CGPointZero, CGSizeMake(imageSide, imageSide), 8, nil, false, nil, TGScaleImageRoundCornersByOuterBounds);
         } withName:@"downloadingOverlayImage"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGScaleImage(source, TGFitSize(source.screenSize, CGSizeMake(568, 568)));
        } withName:@"maybeScale"];
        
        /*[TGRemoteImageView registerImageUniversalProcessor:^UIImage *(NSString *name, UIImage *source)
        {
            CGSize size = extractSize(name, @"attachmentImageIncoming:");
            if (size.width > 0 && size.height > 0)
                return TGAttachmentImage(source, size, size, true, false);
            return nil;
        } withBaseName:@"attachmentImageIncoming"];*/
        
        [TGRemoteImageView registerImageUniversalProcessor:^UIImage *(NSString *name, UIImage *source)
        {
            CGSize resultSize = CGSizeZero;
            CGSize imageSize = CGSizeZero;
            if (extractTwoSizes(name, @"attachmentImageOutgoing:", &resultSize, &imageSize))
                return TGAttachmentImage(source, imageSize, resultSize, false, false);
            
            return nil;
        } withBaseName:@"attachmentImageOutgoing"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGAttachmentImage(source, CGSizeZero, CGSizeMake(100, 100), true, true);
        } withName:@"attachmentLocationIncoming"];
        
        [TGRemoteImageView registerImageProcessor:^UIImage *(UIImage *source)
        {
            return TGAttachmentImage(source, CGSizeZero, CGSizeMake(100, 100), false, true);
        } withName:@"attachmentLocationOutgoing"];
    }
    return self;
}

- (void)doLogout
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [TGAppDelegateInstance resetLoginState];
        
        TGLiveNearbyActor *liveNearby = (TGLiveNearbyActor *)[ActionStageInstance() executingActorWithPath:@"/tg/liveNearby"];
        if (liveNearby != nil)
            liveNearby.cancelTimeout = 0;
        [ActionStageInstance() removeWatcher:self];
        [ActionStageInstance() cancelActorTimeout:@"/tg/liveNearby"];
        //[ActionStageInstance() requestActor:@"/tg/service/settings/push/(unsubscribe)" options:nil watcher:self];
        
        [[TGInterfaceAssets instance] clearColorMapping];
        
        self.clientUserId = 0;
        self.clientIsActivated = false;
        [TGAppDelegateInstance saveSettings];
        
        [[TGDatabase instance] dropDatabase];
        [[TGSession instance] clearSessionAndTakeOff];
        
        _userLinksToDispatch.clear();
        _userDataToDispatch.clear();
        _userPresenceToDispatch.clear();
        
        dispatch_async(dispatch_get_main_queue(), ^
        {
            [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
            [[UIApplication sharedApplication] cancelAllLocalNotifications];
            
            [TGAppDelegateInstance presentLoginController:true showWelcomeScreen:false phoneNumber:nil phoneCode:nil phoneCodeHash:nil profileFirstName:nil profileLastName:nil];
        });
    }];
}

- (void)stateUpdateRequired
{
    if (_clientUserId != 0)
        [ActionStageInstance() requestActor:@"/tg/service/updatestate" options:nil watcher:self];
}

- (void)setClientUserId:(int)clientUserId
{
    _clientUserId = clientUserId;
    
    [TGDatabaseInstance() setLocalUserId:clientUserId];
}

#pragma mark - Dispatch

- (void)didEnterBackground:(NSNotification *)__unused notification
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [_updateRelativeTimestampsTimer invalidate];
    }];
}

- (void)willEnterForeground:(NSNotification *)__unused notification
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [self updateUserTypingStatuses];
        
        [TGApplyUpdatesActor clearDelayedNotifications];
        
        [ActionStageInstance() dispatchResource:@"/as/updateRelativeTimestamps" resource:nil];
        
        [_updateRelativeTimestampsTimer invalidate];
        [_updateRelativeTimestampsTimer start];
    }];
}

- (void)dispatchUserDataChanges:(TGUser *)user changes:(int)changes
{
    if (user == nil)
        return;
    
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        _userDataToDispatch[user.uid] = std::pair<TGUser *, int>(user, changes);
        
        if (!_willDispatchUserData)
        {
            _willDispatchUserData = true;
            
            dispatch_async([ActionStageInstance() globalStageDispatchQueue], ^
            {
                _willDispatchUserData = false;
                
                bool updatedPresenceExpiration = false;

                NSMutableArray *changedUsers = [[NSMutableArray alloc] init];
                NSMutableArray *userPresenceChanges = [[NSMutableArray alloc] init];
                
                for (UserDataToDispatchIterator it = _userDataToDispatch.begin(); it != _userDataToDispatch.end(); it++)
                {
                    TGUser *user = it->second.first;
                    int difference = it->second.second;
                    
                    if (difference != 0)
                    {
                        if ((difference & TGUserFieldsAllButPresenceMask) != 0 || (difference & TGUserFieldPresenceOnline) != 0)
                        {
                            [changedUsers addObject:user];
                            
                            if (user.presence.online)
                            {
                                updatedPresenceExpiration = true;
                                _userPresenceExpiration[user.uid] = user.presence.lastSeen;
                            }
                            else
                                _userPresenceExpiration.erase(user.uid);
                        }
                        else if ((difference & TGUserFieldsAllButPresenceMask) == 0)
                        {
                            [userPresenceChanges addObject:user];
                            
                            if (user.presence.online)
                            {
                                updatedPresenceExpiration = true;
                                _userPresenceExpiration[user.uid] = user.presence.lastSeen;
                            }
                            else
                                _userPresenceExpiration.erase(user.uid);
                        }
                    }
                }
                
                if (changedUsers.count != 0)
                {
                    //TGLog(@"===== %d users changed", changedUsers.count);
                    [ActionStageInstance() dispatchResource:@"/tg/userdatachanges" resource:[[SGraphObjectNode alloc] initWithObject:changedUsers]];
                }
                
                if (userPresenceChanges.count != 0)
                {
                    [ActionStageInstance() dispatchResource:@"/tg/userpresencechanges" resource:[[SGraphObjectNode alloc] initWithObject:userPresenceChanges]];
                }
                
                _userDataToDispatch.clear();
                
                if (updatedPresenceExpiration)
                    [self updateUsersPresences:false];
            });
        }
    }];
}

- (void)dispatchUserPresenceChanges:(int64_t)userId presence:(TGUserPresence)presence
{
    std::tr1::shared_ptr<std::map<int, TGUserPresence> > presenceMap(new std::map<int, TGUserPresence>());
    presenceMap->insert(std::make_pair((int)userId, presence));
    [self dispatchMultipleUserPresenceChanges:presenceMap];
}

- (void)dispatchMultipleUserPresenceChanges:(std::tr1::shared_ptr<std::map<int, TGUserPresence> >)presenceMap
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        for (std::map<int, TGUserPresence>::const_iterator it = presenceMap->begin(); it != presenceMap->end(); it++)
        {
            _userPresenceToDispatch[it->first] = it->second;
        }

        if (!_willDispatchUserPresence)
        {
            _willDispatchUserPresence = true;
            dispatch_async([ActionStageInstance() globalStageDispatchQueue], ^
            {
                _willDispatchUserPresence = false;

                [self dispatchMultipleUserPresenceChangesNow];
            });
        }
    }];
}

- (void)dispatchMultipleUserPresenceChangesNow
{
    NSMutableArray *userPresenceChanges = [[NSMutableArray alloc] init];
    
    NSMutableArray *storeUsers = [[NSMutableArray alloc] init];
    
    bool updatedPresenceExpiration = false;
    
    int clientUserId = TGTelegraphInstance.clientUserId;
    
    for (std::map<int, TGUserPresence>::iterator it = _userPresenceToDispatch.begin(); it != _userPresenceToDispatch.end(); it++)
    {
        TGUser *databaseUser = [[TGDatabase instance] loadUser:(int)(it->first)];
        if (databaseUser != nil)
        {
            if (databaseUser.presence.online != it->second.online || databaseUser.presence.lastSeen != it->second.lastSeen)
            {
                //TGLog(@"===== Presence (%@): %s, %d -> %s, %d", databaseUser.displayName, databaseUser.presence.online ? "online" : "offline", databaseUser.presence.lastSeen, it->second.online ? "online" : "offline", it->second.lastSeen);
                
                TGUser *user = [databaseUser copy];
                
                TGUserPresence presence = it->second;
                if (it->first == clientUserId)
                {
                    presence.online = true;
                    presence.lastSeen = INT_MAX;
                }
                
                user.presence = presence;
                
                if (user.presence.online)
                {
                    updatedPresenceExpiration = true;
                    _userPresenceExpiration[user.uid] = user.presence.lastSeen;
                }
                else
                    _userPresenceExpiration.erase(user.uid);
                
                [storeUsers addObject:user];
                
                //if (databaseUser.presence.online != it->second.online || databaseUser.presence.lastSeen != it->second.lastSeen)
                    [userPresenceChanges addObject:user];
            }
        }
    }
    
    if (storeUsers.count != 0)
        [[TGDatabase instance] storeUsers:storeUsers];
    
    if (userPresenceChanges.count != 0)
        [ActionStageInstance() dispatchResource:@"/tg/userpresencechanges" resource:[[SGraphObjectNode alloc] initWithObject:userPresenceChanges]];
    
    _userPresenceToDispatch.clear();
    
    if (updatedPresenceExpiration)
        [self updateUsersPresences:false];
}

- (void)updateUsersPresences:(bool)nonRecursive
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        int currentUnixTime = (int)(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970) + [[TGSession instance] timeDifference];
        
        int nextPresenceExpiration = INT_MAX;
        for (std::map<int, int>::iterator it = _userPresenceExpiration.begin(); it != _userPresenceExpiration.end(); it++)
        {
            if (it->second < nextPresenceExpiration)
                nextPresenceExpiration = it->second;
            
#ifdef DEBUG
            __unused int delay = it->second - currentUnixTime;
            //TGLog(@"%@ will go offline in %d m %d s", [TGDatabaseInstance() loadUser:it->first].displayName, delay / 60, delay % 60);
#endif
        }
        
        if (nextPresenceExpiration != INT_MAX)
        {
            if (nextPresenceExpiration - currentUnixTime < 0)
            {
                if (nonRecursive)
                {
                    dispatch_async([ActionStageInstance() globalStageDispatchQueue], ^
                    {
                        [self updateUsersPresencesNow];
                    });
                }
                else
                    [self updateUsersPresencesNow];
            }
            else
            {
                if (_userPresenceExpirationTimer == nil || _userPresenceExpirationTimer.timeoutDate < nextPresenceExpiration - 1)
                {
                    //if (_userPresenceExpirationTimer != nil)
                    //TGLog(@"%d < %d", (int)(_userPresenceExpirationTimer.timeoutDate), nextPresenceExpiration - 1);
                    _userPresenceExpirationTimer = [[TGTimer alloc] initWithTimeout:(nextPresenceExpiration - currentUnixTime) repeat:false completion:^
                    {
                        [self updateUsersPresencesNow];
                    } queue:[ActionStageInstance() globalStageDispatchQueue]];
                    [_userPresenceExpirationTimer start];
                }
                else if (_userPresenceExpirationTimer != nil)
                {
                    //TGLog(@"Use running expiration timer");
                }
            }
        }
    }];
}

- (void)updateUsersPresencesNow
{
    _userPresenceExpirationTimer = nil;
    
    int currentUnixTime = (int)(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970) + [[TGSession instance] timeDifference];
    
    std::vector<std::pair<int, TGUserPresence> > expired;
    for (std::map<int, int>::iterator it = _userPresenceExpiration.begin(); it != _userPresenceExpiration.end(); it++)
    {
        if (it->second <= currentUnixTime + 1)
        {
            TGUserPresence presence;
            presence.online = false;
            presence.lastSeen = it->second;
            expired.push_back(std::pair<int, TGUserPresence>(it->first, presence));
            
#ifdef DEBUG
            TGLog(@"%@ did go offline", [TGDatabaseInstance() loadUser:it->first].displayName);
#endif
        }
    }
    
    for (std::vector<std::pair<int, TGUserPresence> >::iterator it = expired.begin(); it != expired.end(); it++)
    {
        _userPresenceExpiration.erase(it->first);
        
        _userPresenceToDispatch[it->first] = it->second;
    }
    
    if (!_userPresenceToDispatch.empty())
    {
        [self dispatchMultipleUserPresenceChangesNow];
    }
    
    [self updateUsersPresences:true];
}

- (void)updateUserTypingStatuses
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        TGLog(@"===== Updating typing statuses");
        NSTimeInterval currentTime = CFAbsoluteTimeGetCurrent();
        
        std::set<int64_t> conversationsWithoutTypingUsers;
        std::set<int64_t> *pConversationsWithoutTypingUsers = &conversationsWithoutTypingUsers;
        
        __block NSTimeInterval nextTypingUpdate = DBL_MAX;
        
        [_typingUsersByConversation enumerateKeysAndObjectsUsingBlock:^(NSNumber *nConversationId, NSMutableDictionary *typingUsers, __unused BOOL *stop)
        {
            int64_t conversationId = [nConversationId longLongValue];
            
            std::set<int> usersStoppedTyping;
            std::set<int> *pUsersStoppedTyping = &usersStoppedTyping;
            
            [typingUsers enumerateKeysAndObjectsUsingBlock:^(NSNumber *nUid, NSNumber *startedTypingDate, __unused BOOL *stop)
            {
                if (ABS(currentTime - [startedTypingDate doubleValue]) > 6.0)
                {
                    pUsersStoppedTyping->insert([nUid intValue]);
                }
                else if ([startedTypingDate longLongValue] + 6.0 < nextTypingUpdate)
                    nextTypingUpdate = [startedTypingDate doubleValue] + 6.0;
            }];
            
            if (!usersStoppedTyping.empty())
            {
                for (std::set<int>::iterator it = usersStoppedTyping.begin(); it != usersStoppedTyping.end(); it++)
                {
                    [typingUsers removeObjectForKey:[NSNumber numberWithInt:*it]];
                }
                
                NSMutableArray *typingUsersArray = [[NSMutableArray alloc] init];
                [typingUsers enumerateKeysAndObjectsUsingBlock:^(NSNumber *nUid, __unused id obj, __unused BOOL *stop)
                {
                    [typingUsersArray addObject:nUid];
                }];
                
                if (typingUsers.count == 0)
                    pConversationsWithoutTypingUsers->insert(conversationId);
                
                [ActionStageInstance() dispatchResource:[[NSString alloc] initWithFormat:@"/tg/conversation/(%lld)/typing", conversationId] resource:[[SGraphObjectNode alloc] initWithObject:typingUsersArray]];
                [ActionStageInstance() dispatchResource:@"/tg/conversation/*/typing" resource:[[SGraphObjectNode alloc] initWithObject:[[NSDictionary alloc] initWithObjectsAndKeys:[[NSNumber alloc] initWithLongLong:conversationId], @"conversationId", typingUsersArray, @"typingUsers", nil]]];
            }
        }];
        
        for (std::set<int64_t>::iterator it = conversationsWithoutTypingUsers.begin(); it != conversationsWithoutTypingUsers.end(); it++)
        {
            [_typingUsersByConversation removeObjectForKey:[NSNumber numberWithLongLong:*it]];
        }
        
        if (nextTypingUpdate < DBL_MAX - DBL_EPSILON && nextTypingUpdate - CFAbsoluteTimeGetCurrent() > 0)
        {
            [_usersTypingServiceTimer resetTimeout:nextTypingUpdate - CFAbsoluteTimeGetCurrent()];
        }
    }];
}

- (void)dispatchUserTyping:(int)uid inConversation:(int64_t)conversationId typing:(bool)typing
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        NSNumber *key = [[NSNumber alloc] initWithLongLong:conversationId];
        NSMutableDictionary *typingUsers = [_typingUsersByConversation objectForKey:key];
        NSNumber *userKey = [[NSNumber alloc] initWithInt:uid];
        
        if (typing)
        {
            if (typingUsers == nil)
            {
                typingUsers = [[NSMutableDictionary alloc] init];
                [_typingUsersByConversation setObject:typingUsers forKey:key];
            }
            
            bool updated = false;
            if ([typingUsers objectForKey:userKey] == nil)
                updated = true;
                
            [typingUsers setObject:[NSNumber numberWithDouble:CFAbsoluteTimeGetCurrent()] forKey:userKey];
            
            if (updated)
            {
                NSMutableArray *typingUsersArray = [[NSMutableArray alloc] init];
                [typingUsers enumerateKeysAndObjectsUsingBlock:^(NSNumber *nUid, __unused id obj, __unused BOOL *stop)
                {
                    [typingUsersArray addObject:nUid];
                }];
                
                [ActionStageInstance() dispatchResource:[[NSString alloc] initWithFormat:@"/tg/conversation/(%lld)/typing", conversationId] resource:[[SGraphObjectNode alloc] initWithObject:typingUsersArray]];
                [ActionStageInstance() dispatchResource:@"/tg/conversation/*/typing" resource:[[SGraphObjectNode alloc] initWithObject:[[NSDictionary alloc] initWithObjectsAndKeys:[[NSNumber alloc] initWithLongLong:conversationId], @"conversationId", typingUsersArray, @"typingUsers", nil]]];
            }
        }
        else
        {
            if (typingUsers != nil && [typingUsers objectForKey:userKey] != nil)
            {
                [typingUsers removeObjectForKey:userKey];
            }
            
            NSMutableArray *typingUsersArray = [[NSMutableArray alloc] init];
            [typingUsers enumerateKeysAndObjectsUsingBlock:^(NSNumber *nUid, __unused id obj, __unused BOOL *stop)
            {
                [typingUsersArray addObject:nUid];
            }];
            
            [ActionStageInstance() dispatchResource:[[NSString alloc] initWithFormat:@"/tg/conversation/(%lld)/typing", conversationId] resource:[[SGraphObjectNode alloc] initWithObject:typingUsersArray]];
            [ActionStageInstance() dispatchResource:@"/tg/conversation/*/typing" resource:[[SGraphObjectNode alloc] initWithObject:[[NSDictionary alloc] initWithObjectsAndKeys:[[NSNumber alloc] initWithLongLong:conversationId], @"conversationId", typingUsersArray, @"typingUsers", nil]]];
            
            if (typingUsers.count == 0)
                [_typingUsersByConversation removeObjectForKey:key];
        }
        
        [self updateUserTypingStatuses];
    }];
}

- (void)updatePresenceNow
{
    dispatch_async(dispatch_get_main_queue(), ^
    {
        bool online = [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
        
        [ActionStageInstance() dispatchOnStageQueue:^
        {
            if (_clientUserId != 0)
            {
                if (online)
                {
                    [ActionStageInstance() removeWatcher:self fromPath:@"/tg/service/updatepresence/(offline)"];
                    [ActionStageInstance() removeWatcher:self fromPath:@"/tg/service/updatepresence/(timeout)"];
                    [ActionStageInstance() requestActor:@"/tg/service/updatepresence/(online)" options:nil watcher:self];
                }
                else
                {
                    [ActionStageInstance() removeWatcher:self fromPath:@"/tg/service/updatepresence/(online)"];
                    [ActionStageInstance() removeWatcher:self fromPath:@"/tg/service/updatepresence/(timeout)"];
                    [ActionStageInstance() requestActor:@"/tg/service/updatepresence/(offline)" options:nil watcher:self];
                }
            }
        }];
    });
}

- (int)serviceUserUid
{
    return 333000;
}

- (int)createServiceUserIfNeeded
{
    if ([TGDatabaseInstance() loadUser:[self serviceUserUid]] == nil)
    {
        TGUser *user = [[TGUser alloc] init];
        user.uid = [self serviceUserUid];
        user.phoneNumber = @"333";
        user.firstName = @"Telegram";
        user.lastName = @"";
        
        [TGDatabaseInstance() storeUsers:[[NSArray alloc] initWithObjects:user, nil]];
    }
    
    return [self serviceUserUid];
}

- (void)locationTranslationSettingsUpdated
{
    bool locationTranslationEnabled = TGAppDelegateInstance.locationTranslationEnabled;
    
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        if (locationTranslationEnabled)
        {
            [ActionStageInstance() requestActor:@"/tg/liveNearby" options:nil watcher:self];
        }
        else
        {
            [ActionStageInstance() removeWatcher:self fromPath:@"/tg/liveNearby"];
        }
    }];
}

- (NSArray *)userIdsTypingInConversation:(int64_t)conversationId
{
    NSNumber *key = [[NSNumber alloc] initWithLongLong:conversationId];
    NSMutableDictionary *typingUsers = [_typingUsersByConversation objectForKey:key];
    if (typingUsers == nil)
    {
        return [[NSArray alloc] init];
    }
    
    NSMutableArray *typingUsersArray = [[NSMutableArray alloc] init];
    [typingUsers enumerateKeysAndObjectsUsingBlock:^(NSNumber *nUid, __unused id obj, __unused BOOL *stop)
    {
        [typingUsersArray addObject:nUid];
    }];
    
    return typingUsersArray;
}

- (void)dispatchUserLinkChanged:(int)uid link:(int)link
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        _userLinksToDispatch[uid] = link;
        
        dispatch_async([ActionStageInstance() globalStageDispatchQueue], ^
        {
            for (std::map<int, int>::iterator it = _userLinksToDispatch.begin(); it != _userLinksToDispatch.end(); it++)
            {
                [ActionStageInstance() dispatchResource:[[NSString alloc] initWithFormat:@"/tg/userLink/(%d)", it->first] resource:[[SGraphObjectNode alloc] initWithObject:[[NSNumber alloc] initWithInt:it->second]]];
            }
            
            _userLinksToDispatch.clear();
        });
    }];
}

- (void)subscribeToUserUpdates:(ASHandle *)watcherHandle
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        if (![_userDataUpdatesSubscribers containsObject:watcherHandle]);
            [_userDataUpdatesSubscribers addObject:watcherHandle];
    }];
}

- (void)unsubscribeFromUserUpdates:(ASHandle *)watcherHandle
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [_userDataUpdatesSubscribers removeObject:watcherHandle];
    }];
}

- (void)updateUserUpdatesSubscriptions
{
    NSMutableArray *freeOnMainThreadObjects = [[NSMutableArray alloc] init];
    
    NSMutableSet *uidSet = [[NSMutableSet alloc] init];
    
    int count = _userDataUpdatesSubscribers.count;
    for (int i = 0; i < count; i++)
    {
        ASHandle *watcherHandle = [_userDataUpdatesSubscribers objectAtIndex:i];
        
        id<ASWatcher> watcher = watcherHandle.delegate;
        if (watcher != nil)
            [freeOnMainThreadObjects addObject:watcher];
        else
        {
            [_userDataUpdatesSubscribers removeObjectAtIndex:i];
            i--;
            count--;
            
            continue;
        }
        
        if ([watcher respondsToSelector:@selector(actionStageActionRequested:options:)])
        {
            [watcher actionStageActionRequested:@"updateUserDataSubscription" options:[[NSDictionary alloc] initWithObjectsAndKeys:uidSet, @"uidSet", nil]];
        }
    }
    
    if (uidSet.count != 0)
    {
        
    }
    
    if (freeOnMainThreadObjects.count != 0)
    {
        dispatch_async(dispatch_get_main_queue(), ^
        {
            [freeOnMainThreadObjects removeAllObjects];
        });
    }
}

#pragma mark - Common logic

- (void)setClientIsActivated:(bool)clientIsActivated
{
    if (clientIsActivated)
    {
        TGLog(@"Activating user");
    }
    
    _clientIsActivated = clientIsActivated;
}

- (void)processAuthorizedWithUserId:(int)uid clientIsActivated:(bool)clientIsActivated
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        TGLog(@"Starting with user id %d activated: %d", uid, clientIsActivated ? 1 : 0);
        
        self.clientUserId = uid;
        self.clientIsActivated = clientIsActivated;
        [TGAppDelegateInstance saveSettings];
        
        if (_clientUserId != 0)
        {
            [TGAppDelegateInstance resetLoginState];
            
            TGUser *user = [[TGDatabase instance] loadUser:uid];
            
            if (user != nil)
            {
                TGUserPresence presence;
                presence.online = true;
                presence.lastSeen = (int)(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970);
                user.presence = presence;
                [[TGDatabase instance] storeUsers:[NSArray arrayWithObject:user]];
            }
            
            [TGUpdateStateRequestBuilder scheduleInitialUpdates];
            
            [ActionStageInstance() requestActor:@"/tg/service/updatestate" options:nil watcher:self];
            
            [ActionStageInstance() requestActor:@"/tg/synchronizeContacts/(sync)" options:nil watcher:TGTelegraphInstance];
            
            [TGAppDelegateInstance.myAccountController switchToUid:uid];
            
            if (TGAppDelegateInstance.locationTranslationEnabled)
                [ActionStageInstance() requestActor:@"/tg/liveNearby" options:nil watcher:self];
        }
    }];
}

#pragma mark - Protocol

- (NSMutableDictionary *)operationTimeoutTimers
{
    static NSMutableDictionary *dictionary = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        dictionary = [[NSMutableDictionary alloc] init];
    });
    
    return dictionary;
}

- (void)registerTimeout:(AFHTTPRequestOperation *)operation duration:(NSTimeInterval)duration
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        NSTimer *timer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:duration] interval:0.0 target:self selector:@selector(timeoutTimerEvent:) userInfo:operation repeats:false];
        [[self operationTimeoutTimers] setObject:timer forKey:[NSNumber numberWithInt:[operation hash]]];
        dispatch_async(dispatch_get_main_queue(), ^
        {
            [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        });
    }];
}

- (void)removeTimeout:(AFHTTPRequestOperation *)operation
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        NSNumber *key = [NSNumber numberWithInt:[operation hash]];
        NSTimer *timer = [[self operationTimeoutTimers] objectForKey:key];
        if (timer != nil)
        {
            [[self operationTimeoutTimers] removeObjectForKey:key];
            dispatch_async(dispatch_get_main_queue(), ^
            {
                [timer invalidate];
            });
        }
        else
        {
            //TGLog(@"***** removeTimeout: timer not found");
        }
    }];
}

- (void)timeoutTimerEvent:(NSTimer *)timer
{
    AFHTTPRequestOperation *operation = timer.userInfo;
    TGLog(@"===== Request timeout: %@", operation.request.URL);
    
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        if ([operation isKindOfClass:[AFHTTPRequestOperation class]])
        {
            [operation cancel];
        }
        else
        {
            TGLog(@"***** timeoutTimerEvent: invalid operation key");
        }
        
        [[self operationTimeoutTimers] removeObjectForKey:[NSNumber numberWithInt:[operation hash]]];
    }];
}

#pragma mark - Request processing

- (void)cancelRequestByToken:(NSObject *)token
{
    [self cancelRequestByToken:token softCancel:false];
}

- (void)cancelRequestByToken:(NSObject *)token softCancel:(bool)softCancel
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        if ([token isKindOfClass:[TGRawHttpRequest class]])
        {
            [(TGRawHttpRequest *)token cancel];
        }
        else
        {
            [[TGSession instance] cancelRpc:token notifyServer:!softCancel];
        }
    }];
}

- (NSString *)extractErrorType:(TLError *)error
{
    if ([error isKindOfClass:[TLError$richError class]])
    {
        if (((TLError$richError *)error).type.length != 0)
            return ((TLError$richError *)error).type;
        
        NSString *errorDescription = ((TLError$richError *)error).description;
        
        NSMutableString *errorString = [[NSMutableString alloc] init];
        for (int i = 0; i < (int)errorDescription.length; i++)
        {
            unichar c = [errorDescription characterAtIndex:i];
            if (c == ':')
                break;
            
            [errorString appendString:[[NSString alloc] initWithCharacters:&c length:1]];
        }
        
        if (errorString.length != 0)
            return errorString;
    }
    
    return nil;
}

#pragma mark - Requests

- (void)rawHttpRequestCompleted:(TGRawHttpRequest *)request response:(NSData *)response error:(NSError *)error
{
    if (request.cancelled)
    {
        [request dispose];
        return;
    }
    
    if (error != nil)
    {
        request.retryCount++;
        
        if (request.retryCount >= request.maxRetryCount && request.maxRetryCount > 0)
        {
            if (request.completionBlock)
                request.completionBlock(nil);
            [request dispose];
        }
        else
        {
            TGLog(@"Http error: %@", error);
            
            int64_t delayInSeconds = 1.0;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
            dispatch_after(popTime, [ActionStageInstance() globalStageDispatchQueue], ^
            {
                [self enqueueRawHttpRequest:request];
            });
        }
    }
    else
    {
        if (request.completionBlock)
            request.completionBlock(response);
        [request dispose];
    }
}

- (void)enqueueRawHttpRequest:(TGRawHttpRequest *)request
{
    NSMutableURLRequest *urlRequest = nil;
    urlRequest = [self requestWithMethod:@"GET" path:request.url parameters:nil];
    if (request.httpAuth != nil)
    {
        NSString *authValue = [[NSString alloc] initWithFormat:@"Basic %@", [TGStringUtils stringByEncodingInBase64:request.httpAuth]];
        [urlRequest setValue:authValue forHTTPHeaderField:@"Authorization"];
    }
    
    AFHTTPRequestOperation *httpOperation = [[AFHTTPRequestOperation alloc] initWithRequest:urlRequest];
    
    NSMutableIndexSet *acceptableCodes = [[NSMutableIndexSet alloc] initWithIndexSet:httpOperation.acceptableStatusCodes];
    for (NSNumber *nCode in request.acceptCodes)
    {
        [acceptableCodes addIndex:[nCode intValue]];
    }
    httpOperation.acceptableStatusCodes = acceptableCodes;
    
    [httpOperation setSuccessCallbackQueue:[ActionStageInstance() globalStageDispatchQueue]];
    [httpOperation setFailureCallbackQueue:[ActionStageInstance() globalStageDispatchQueue]];
    
    [httpOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, __unused id responseObject)
    {
        NSData *receivedData = [operation responseData];

        //NSString *receivedString = [[NSString alloc] initWithBytes:receivedData.bytes length:receivedData.length encoding:NSASCIIStringEncoding];
        //TGLog(@"Response: %@", receivedString);

        [self rawHttpRequestCompleted:request response:receivedData error:nil];
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error)
    {
        [self rawHttpRequestCompleted:request response:nil error:error];
    }];
    
    if (request.progressBlock != nil)
    {
        [httpOperation setDownloadProgressBlock:^(__unused NSInteger bytesRead, NSInteger totalBytesRead, NSInteger totalBytesExpectedToRead)
        {
            if (totalBytesExpectedToRead > 0 && totalBytesRead > 0)
            {
                request.progressBlock(((float)totalBytesRead) / ((float)totalBytesExpectedToRead));
            }
        }];
    }
    
    request.operation = httpOperation;
    [self enqueueHTTPRequestOperation:httpOperation];
}

- (id)doGetAppPrefs:(TGSynchronizePreferencesActor *)actor
{
    TLRPChelp_getAppPrefs$help_getAppPrefs *getAppPrefs = [[TLRPChelp_getAppPrefs$help_getAppPrefs alloc] init];
    getAppPrefs.api_id = [_apiId intValue];
    getAppPrefs.api_hash = _apiHash;
    
    return [[TGSession instance] performRpc:getAppPrefs completionBlock:^(TLhelp_AppPrefs *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor preferencesRequestSuccess:result];
        }
        else
        {
            [actor preferencesRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator | TGRequestClassEnableUnauthorized datacenterId:TG_DEFAULT_DATACENTER_ID];
}

- (NSObject *)doRequestRawHttp:(NSString *)url maxRetryCount:(int)maxRetryCount acceptCodes:(NSArray *)acceptCodes actor:(id<TGRawHttpActor>)actor
{
    return [self doRequestRawHttp:url maxRetryCount:maxRetryCount acceptCodes:acceptCodes httpAuth:nil actor:actor];
}

- (NSObject *)doRequestRawHttp:(NSString *)url maxRetryCount:(int)maxRetryCount acceptCodes:(NSArray *)acceptCodes httpAuth:(NSData *)httpAuth actor:(id<TGRawHttpActor>)actor
{
    TGRawHttpRequest *request = [[TGRawHttpRequest alloc] init];
    request.url = url;
    request.acceptCodes = acceptCodes;
    request.httpAuth = httpAuth;
    request.maxRetryCount = maxRetryCount;
    request.completionBlock = ^(NSData *response)
    {
        if (response != nil)
        {
            [actor httpRequestSuccess:url response:response];
        }
        else
        {
            [actor httpRequestFailed:url];
        }
    };
    
    if ([actor respondsToSelector:@selector(httpRequestProgress:progress:)])
    {
        request.progressBlock = ^(float progress)
        {
            [actor httpRequestProgress:url progress:progress];
        };
    }
    
    [self enqueueRawHttpRequest:request];
    
    return request;
}

- (NSObject *)doRequestRawHttpFile:(NSString *)url actor:(id<TGRawHttpFileActor>)__unused actor
{
    NSMutableURLRequest *urlRequest = nil;
    urlRequest = [self requestWithMethod:@"GET" path:url parameters:nil];
    AFHTTPRequestOperation *httpOperation = [[AFHTTPRequestOperation alloc] initWithRequest:urlRequest];
    [httpOperation setSuccessCallbackQueue:[ActionStageInstance() globalStageDispatchQueue]];
    [httpOperation setFailureCallbackQueue:[ActionStageInstance() globalStageDispatchQueue]];
    
    [httpOperation setOutputStream:[NSOutputStream outputStreamToFileAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"test.bin"] append:false]];

    TGLog(@"Request started");
    [httpOperation setCompletionBlockWithSuccess:^(__unused AFHTTPRequestOperation *operation, __unused id responseObject)
    {
        TGLog(@"Request completed");
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error)
    {
        TGLog(@"Request failed: %@", error);
    }];
    
    [self enqueueHTTPRequestOperation:httpOperation];
    
    return nil;
}

- (NSObject *)doUploadFilePart:(int64_t)fileId partId:(int)partId data:(NSData *)data actor:(id<TGFileUploadActor>)actor
{
    TLRPCupload_saveFilePart$upload_saveFilePart *saveFilePart = [[TLRPCupload_saveFilePart$upload_saveFilePart alloc] init];
    saveFilePart.file_id = fileId;
    saveFilePart.file_part = partId;
    saveFilePart.bytes = data;
    
    return [[TGSession instance] performRpc:saveFilePart completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil && [((NSNumber *)response) boolValue])
        {
            [actor filePartUploadSuccess:partId];
        }
        else
        {
            [actor filePartUploadFailed:partId];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassUploadMedia | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doDownloadFile:(int)datacenterId volumeId:(int64_t)volumeId fileId:(int)fileId secret:(int64_t)secret actor:(id<TGFileDownloadActor>)actor
{
    TLRPCupload_getFile$upload_getFile *getFile = [[TLRPCupload_getFile$upload_getFile alloc] init];

    TLInputFileLocation$inputFileLocation *location = [[TLInputFileLocation$inputFileLocation alloc] init];
    location.volume_id = volumeId;
    location.local_id = fileId;
    location.secret = secret;
    
    getFile.location = location;
    
    return [[TGSession instance] performRpc:getFile completionBlock:^(TLupload_File *response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor fileDownloadSuccess:volumeId fileId:fileId secret:secret data:response.bytes];
        }
        else
        {
            [actor fileDownloadFailed:volumeId fileId:fileId secret:secret];
        }
    } progressBlock:^(__unused int length, float progress)
    {
        [actor fileDownloadProgress:volumeId fileId:fileId secret:secret progress:progress];
    } requiresCompletion:true requestClass:TGRequestClassDownloadMedia datacenterId:datacenterId];
}

- (NSObject *)doDownloadVideoPart:(int)datacenterId videoId:(int64_t)videoId accessHash:(int64_t)accessHash offset:(int)offset length:(int)length actor:(TGVideoDownloadActor *)actor
{
    TLRPCupload_getFile$upload_getFile *getFile = [[TLRPCupload_getFile$upload_getFile alloc] init];
    
    TLInputFileLocation$inputVideoFileLocation *inputVideoLocation = [[TLInputFileLocation$inputVideoFileLocation alloc] init];
    inputVideoLocation.n_id = videoId;
    inputVideoLocation.access_hash = accessHash;
    
    getFile.location = inputVideoLocation;
    
    getFile.offset = offset;
    getFile.limit = length;
    
    return [[TGSession instance] performRpc:getFile completionBlock:^(TLupload_File *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor videoPartDownloadSuccess:offset length:length data:result.bytes];
        }
        else
        {
            [actor videoPartDownloadFailed:offset length:length];
        }
    } progressBlock:^(int packetLength, float progress)
    {
        [actor videoPartDownloadProgress:offset packetLength:packetLength progress:progress];
    } requiresCompletion:true requestClass:TGRequestClassDownloadMedia | TGRequestClassEnableMerging datacenterId:datacenterId == 0 ? TG_DEFAULT_DATACENTER_ID : datacenterId];
}

- (id)doDownloadFilePart:(int)datacenterId location:(TLInputFileLocation *)location offset:(int)offset length:(int)length actor:(id<TGFileDownloadActor>)actor
{
    TLRPCupload_getFile$upload_getFile *getFile = [[TLRPCupload_getFile$upload_getFile alloc] init];
    
    getFile.location = location;
    getFile.offset = offset;
    getFile.limit = length;
    
    return [[TGSession instance] performRpc:getFile completionBlock:^(TLupload_File *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor filePartDownloadSuccess:location offset:offset length:length data:result.bytes];
        }
        else
        {
            [actor filePartDownloadFailed:location offset:offset length:length];
        }
    } progressBlock:^(int packetLength, float progress)
    {
        [actor filePartDownloadProgress:location offset:offset length:length packetLength:packetLength progress:progress];
    } requiresCompletion:true requestClass:TGRequestClassDownloadMedia datacenterId:datacenterId == 0 ? TG_DEFAULT_DATACENTER_ID : datacenterId];
}

- (NSObject *)doSendConfirmationCode:(NSString *)phoneNumber requestBuilder:(TGSendCodeRequestBuilder *)requestBuilder
{
    TLRPCauth_sendCode$auth_sendCode *sendCode = [[TLRPCauth_sendCode$auth_sendCode alloc] init];
    sendCode.phone_number = phoneNumber;
    sendCode.sms_type = 1;
    sendCode.api_id = [_apiId intValue];
    sendCode.api_hash = _apiHash;
    
    return [[TGSession instance] performRpc:sendCode completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder sendCodeRequestSuccess:(TLauth_SentCode *)response];
        }
        else
        {
            TGSendCodeError errorCode = TGSendCodeErrorUnknown;
            
            NSString *errorType = [self extractErrorType:error];
            if ([errorType isEqualToString:@"PHONE_NUMBER_INVALID"])
                errorCode = TGSendCodeErrorInvalidPhone;
            else if ([errorType hasPrefix:@"FLOOD_WAIT"])
                errorCode = TGSendCodeErrorFloodWait;

            [requestBuilder sendCodeRequestFailed:errorCode];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doSendPhoneCall:(NSString *)phoneNumber phoneHash:(NSString *)phoneHash requestBuilder:(TGSendCodeRequestBuilder *)requestBuilder
{
    TLRPCauth_sendCall$auth_sendCall *sendCall = [[TLRPCauth_sendCall$auth_sendCall alloc] init];
    sendCall.phone_number = phoneNumber;
    sendCall.phone_code_hash = phoneHash;
    
    return [[TGSession instance] performRpc:sendCall completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder sendCallRequestSuccess];
        }
        else
        {
            [requestBuilder sendCallRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doSignUp:(NSString *)phoneNumber phoneHash:(NSString *)phoneHash phoneCode:(NSString *)phoneCode firstName:(NSString *)firstName lastName:(NSString *)lastName emailAddress:(NSString *)__unused emailAddress requestBuilder:(TGSignUpRequestBuilder *)requestBuilder
{
    TLRPCauth_signUp$auth_signUp *signUp = [[TLRPCauth_signUp$auth_signUp alloc] init];
    signUp.phone_number = phoneNumber;
    signUp.phone_code_hash = phoneHash;
    signUp.phone_code = phoneCode;
    signUp.first_name = firstName;
    signUp.last_name = lastName;
    
    return [[TGSession instance] performRpc:signUp completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder signUpSuccess:(TLauth_Authorization *)response];
        }
        else
        {
            NSString *errorType = [self extractErrorType:error];
            
            TGSignUpResult result = TGSignUpResultInternalError;
            
            if ([errorType isEqualToString:@"PHONE_CODE_INVALID"])
                result = TGSignUpResultInvalidToken;
            else if ([errorType isEqualToString:@"PHONE_CODE_EXPIRED"])
                result = TGSignUpResultTokenExpired;
            else if ([errorType hasPrefix:@"FLOOD_WAIT"])
                result = TGSignUpResultFloodWait;
            else if ([errorType hasPrefix:@"FIRSTNAME_INVALID"])
                result = TGSignUpResultInvalidFirstName;
            else if ([errorType hasPrefix:@"LASTNAME_INVALID"])
                result = TGSignUpResultInvalidLastName;
            
            [requestBuilder signUpFailed:result];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doSignIn:(NSString *)phoneNumber phoneHash:(NSString *)phoneHash phoneCode:(NSString *)phoneCode requestBuilder:(TGSignInRequestBuilder *)requestBuilder
{
    TLRPCauth_signIn$auth_signIn *signIn = [[TLRPCauth_signIn$auth_signIn alloc] init];
    signIn.phone_number = phoneNumber;
    signIn.phone_code_hash = phoneHash;
    signIn.phone_code = phoneCode;
    
    return [[TGSession instance] performRpc:signIn completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder signInSuccess:(TLauth_Authorization *)response];
        }
        else
        {
            NSString *errorType = [self extractErrorType:error];
            if ([errorType isEqualToString:@"PHONE_CODE_INVALID"])
                [requestBuilder signInFailed:TGSignInResultInvalidToken];
            else if ([errorType isEqualToString:@"PHONE_CODE_EXPIRED"])
                [requestBuilder signInFailed:TGSignInResultTokenExpired];
            else if ([errorType hasPrefix:@"PHONE_NUMBER_UNOCCUPIED"])
                [requestBuilder signInFailed:TGSignInResultNotRegistered];
            else if ([errorType hasPrefix:@"FLOOD_WAIT"])
                [requestBuilder signInFailed:TGSignInResultFloodWait];
            else
                [requestBuilder signInFailed:TGSignInResultInvalidToken];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doRequestLogout:(TGLogoutRequestBuilder *)actor
{
    TLRPCauth_logOut$auth_logOut *logout = [[TLRPCauth_logOut$auth_logOut alloc] init];
    
    return [[TGSession instance] performRpc:logout completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor logoutSuccess];
        }
        else
        {
            [actor logoutFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doSendInvites:(NSArray *)phones text:(NSString *)text actor:(TGSendInvitesActor *)actor
{
    TLRPCauth_sendInvites$auth_sendInvites *sendInvites = [[TLRPCauth_sendInvites$auth_sendInvites alloc] init];
    sendInvites.phone_numbers = phones;
    sendInvites.message = text;
    
    return [[TGSession instance] performRpc:sendInvites completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor sendInvitesSuccess];
        }
        else
        {
            [actor sendInvitesFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator];
}

- (NSString *)currentDeviceModel
{
    return [[UIDevice currentDevice] platformString];
}

- (id)doCheckUpdates:(TGCheckUpdatesActor *)actor
{
    TLRPChelp_getAppUpdate$help_getAppUpdate *getAppUpdate = [[TLRPChelp_getAppUpdate$help_getAppUpdate alloc] init];
    
    getAppUpdate.device_model = [self currentDeviceModel];
    getAppUpdate.system_version = [[UIDevice currentDevice] systemVersion];
    getAppUpdate.app_version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    NSArray *preferredLocalizations = [[NSBundle mainBundle] preferredLocalizations];
    if (preferredLocalizations.count != 0)
        getAppUpdate.lang_code = [preferredLocalizations objectAtIndex:0];
    
    return [[TGSession instance] performRpc:getAppUpdate completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor checkUpdatesSuccess:response];
        }
        else
        {
            [actor checkUpdatesFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator];
}

- (NSObject *)doSetPresence:(bool)online actor:(TGUpdatePresenceActor *)actor
{
    //TGLog(@"===== Setting presence: %s", online ? "online" : "offline");
    TLRPCaccount_updateStatus$account_updateStatus *updateStatus = [[TLRPCaccount_updateStatus$account_updateStatus alloc] init];
    updateStatus.offline = !online;
    
    if (online)
    {
        int currentUnixTime = (int)(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970) + [[TGSession instance] timeDifference];
        
        TGUserPresence presence;
        presence.online = true;
        presence.lastSeen = currentUnixTime + 5 * 60;
        [TGTelegraphInstance dispatchUserPresenceChanges:TGTelegraphInstance.clientUserId presence:presence];
    }
    
    return [[TGSession instance] performRpc:updateStatus completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor updatePresenceSuccess];
        }
        else
        {
            [actor updatePresenceFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator];
}

- (NSObject *)doRevokeOtherSessions:(TGRevokeSessionsActor *)actor
{
    TLRPCauth_resetAuthorizations$auth_resetAuthorizations *resetAuthorizations = [[TLRPCauth_resetAuthorizations$auth_resetAuthorizations alloc] init];
    
    return [[TGSession instance] performRpc:resetAuthorizations completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor revokeSessionsSuccess];
        }
        else
        {
            [actor revokeSessionsFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doUpdatePushSubscription:(bool)subscribe deviceToken:(NSString *)deviceToken requestBuilder:(TGPushActionsRequestBuilder *)requestBuilder
{
    TLMetaRpc *rpcRequest = nil;
    
    if (subscribe)
    {
        TLRPCaccount_registerDevice$account_registerDevice *registerDevice = [[TLRPCaccount_registerDevice$account_registerDevice alloc] init];
        
        registerDevice.token_type = 1;
        registerDevice.token = deviceToken;
        
        registerDevice.device_model = [self currentDeviceModel];
        registerDevice.system_version = [[UIDevice currentDevice] systemVersion];
        registerDevice.app_version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
#ifdef DEBUG
        registerDevice.app_sandbox = true;
#else
        registerDevice.app_sandbox = false;
#endif
        rpcRequest = registerDevice;
    }
    else
    {
        TLRPCaccount_unregisterDevice$account_unregisterDevice *unregisterDevice = [[TLRPCaccount_unregisterDevice$account_unregisterDevice alloc] init];
        
        unregisterDevice.token_type = 1;
        unregisterDevice.token = deviceToken;
        
        rpcRequest = unregisterDevice;
    }
    
    return [[TGSession instance] performRpc:rpcRequest completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder pushSubscriptionUpdateSuccess];
        }
        else
        {
            [requestBuilder pushSubscriptionUpdateFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestUserData:(int)uid requestBuilder:(TGUserDataRequestBuilder *)requestBuilder
{
    TLRPCusers_getUsers$users_getUsers *getUsers = [[TLRPCusers_getUsers$users_getUsers alloc] init];
    getUsers.n_id = [NSArray arrayWithObject:[self createInputUserForUid:uid]];
    
    return [[TGSession instance] performRpc:getUsers completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder userDataRequestSuccess:(NSArray *)response];
        }
        else
        {
            [requestBuilder userDataRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestExtendedUserData:(int)uid actor:(TGExtendedUserDataRequestActor *)actor
{
    TLRPCusers_getFullUser$users_getFullUser *getFullUser = [[TLRPCusers_getFullUser$users_getFullUser alloc] init];
    getFullUser.n_id = [self createInputUserForUid:uid];
    
    return [[TGSession instance] performRpc:getFullUser completionBlock:^(TLUserFull *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor extendedUserDataRequestSuccess:result];
        }
        else
        {
            [actor extendedUserDataRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (id)doRequestContactStatuses:(TGUpdateUserStatusesActor *)actor
{
    return [[TGSession instance] performRpc:[[TLRPCcontacts_getStatuses$contacts_getStatuses alloc] init] completionBlock:^(id response, int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor contactStatusesRequestSuccess:response currentDate:(int)(responseTime / 4294967296L)];
        }
        else
        {
            [actor contactStatusesRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestState:(TGUpdateStateRequestBuilder *)requestBuilder
{
    TLRPCupdates_getState$updates_getState *getState = [[TLRPCupdates_getState$updates_getState alloc] init];
    
    return [[TGSession instance] performRpc:getState completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder stateRequestSuccess:(TLupdates_State *)response];
        }
        else
        {
            [requestBuilder stateRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestStateDelta:(int)pts date:(int)date qts:(int)qts requestBuilder:(TGUpdateStateRequestBuilder *)requestBuilder
{
    TLRPCupdates_getDifference$updates_getDifference *getDifference = [[TLRPCupdates_getDifference$updates_getDifference alloc] init];
    getDifference.pts = pts;
    getDifference.date = date;
    getDifference.qts = qts;
    
    if (pts == 0)
    {
        TGLog(@"Something bad happens...");
    }
    
    return [[TGSession instance] performRpc:getDifference completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder stateDeltaRequestSuccess:(TLupdates_Difference *)response];
        }
        else
        {
            [requestBuilder stateDeltaRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestDialogsList:(int)offset limit:(int)limit requestBuilder:(TGDialogListRequestBuilder *)requestBuilder
{
    TLRPCmessages_getDialogs$messages_getDialogs *getDialogs = [[TLRPCmessages_getDialogs$messages_getDialogs alloc] init];
    getDialogs.offset = offset;
    getDialogs.limit = limit;
    
    return [[TGSession instance] performRpc:getDialogs completionBlock:^(TLmessages_Dialogs *dialogs, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestBuilder dialogListRequestSuccess:dialogs];
        }
        else
        {
            [requestBuilder dialogListRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doExportContacts:(NSArray *)contacts requestBuilder:(TGSynchronizeContactsActor *)requestActor
{
    NSMutableString *debugContactsString = [[NSMutableString alloc] init];
    
    NSMutableArray *contactsArray = [[NSMutableArray alloc] initWithCapacity:contacts.count];
    
    int index = -1;
    for (TGContactBinding *binding in contacts)
    {
        index++;
        
        TLInputContact$inputPhoneContact *inputContact = [[TLInputContact$inputPhoneContact alloc] init];
        inputContact.client_id = index;
        inputContact.phone = binding.phoneNumber;
        inputContact.first_name = binding.firstName;
        inputContact.last_name = binding.lastName;
        [contactsArray addObject:inputContact];
        
        [debugContactsString appendFormat:@"%@\t%@\t%@\n", binding.phoneNumber, binding.firstName, binding.lastName];
    }
    TGLog(@"Exporting %d contacts: %@", contacts.count, debugContactsString);
    
    TLRPCcontacts_importContacts$contacts_importContacts *importContacts = [[TLRPCcontacts_importContacts$contacts_importContacts alloc] init];
    
    importContacts.contacts = contactsArray;
    
    return [[TGSession instance] performRpc:importContacts completionBlock:^(TLcontacts_ImportedContacts *importedContacts, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            NSMutableString *debugImportedString = [[NSMutableString alloc] init];
            
            NSMutableArray *importedArray = [[NSMutableArray alloc] initWithCapacity:importedContacts.imported.count];
            for (TLImportedContact *importedContact in importedContacts.imported)
            {
                if (importedContact.client_id >= 0 && importedContact.client_id < contactsArray.count)
                {
                    NSString *clientPhone = ((TLInputContact *)[contactsArray objectAtIndex:(int)importedContact.client_id]).phone;
                    
                    TGImportedPhone *importedPhone = [[TGImportedPhone alloc] init];
                    importedPhone.phone = clientPhone;
                    importedPhone.user_id = importedContact.user_id;
                    
                    [debugImportedString appendFormat:@"%@ -> %d\n", clientPhone, importedContact.user_id];
                    
                    [importedArray addObject:importedPhone];
                }
            }
            
            TGLog(@"Server imported: %@", debugImportedString);
            
            [requestActor exportContactsSuccess:importedArray users:importedContacts.users];
        }
        else
        {
            [requestActor exportContactsFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestContactList:(NSString *)hash actor:(TGSynchronizeContactsActor *)actor
{
    TLRPCcontacts_getContacts$contacts_getContacts *getContacts = [[TLRPCcontacts_getContacts$contacts_getContacts alloc] init];
    getContacts.hash = hash;
    
    return [[TGSession instance] performRpc:getContacts completionBlock:^(TLcontacts_Contacts *contacts, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor contactListRequestSuccess:contacts];
        }
        else
        {
            [actor contactListRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestContactIdList:(TGSynchronizeContactsActor *)actor
{
    TLRPCcontacts_getContactIDs$contacts_getContactIDs *getContactIds = [[TLRPCcontacts_getContactIDs$contacts_getContactIDs alloc] init];
    
    return [[TGSession instance] performRpc:getContactIds completionBlock:^(id<TLObject> result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor contactIdsRequestSuccess:(NSArray *)result];
        }
        else
        {
            [actor contactIdsRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}
- (NSObject *)doLocateContacts:(double)latitude longitude:(double)longitude radius:(int)radius discloseLocation:(bool)discloseLocation actor:(id<TGLocateContactsProtocol>)actor
{
    TLRPCcontacts_getLocated$contacts_getLocated *getLocated = [[TLRPCcontacts_getLocated$contacts_getLocated alloc] init];
    TLInputGeoPoint$inputGeoPoint *geoPoint = [[TLInputGeoPoint$inputGeoPoint alloc] init];
    geoPoint.lat = latitude;
    geoPoint.n_long = longitude;
    getLocated.geo_point = geoPoint;
    getLocated.radius = radius;
    getLocated.limit = 100;
    getLocated.hidden = !discloseLocation;
    
    return [[TGSession instance] performRpc:getLocated completionBlock:^(TLcontacts_Located *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor locateSuccess:result];
        }
        else
        {
            [actor locateFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doSendContactRequest:(int)uid actor:(TGContactRequestActionActor *)actor
{
    TLRPCcontacts_sendRequest$contacts_sendRequest *sendRequest = [[TLRPCcontacts_sendRequest$contacts_sendRequest alloc] init];
    sendRequest.n_id = [self createInputUserForUid:uid];
    
    return [[TGSession instance] performRpc:sendRequest completionBlock:^(TLcontacts_SentLink *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor sendRequestSuccess:result];
        }
        else
        {
            [actor sendRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doAcceptContactRequest:(int)uid actor:(TGContactRequestActionActor *)actor
{
    TLRPCcontacts_acceptRequest$contacts_acceptRequest *acceptRequest = [[TLRPCcontacts_acceptRequest$contacts_acceptRequest alloc] init];
    acceptRequest.n_id = [self createInputUserForUid:uid];
    
    return [[TGSession instance] performRpc:acceptRequest completionBlock:^(TLcontacts_Link *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor acceptRequestSuccess:result];
        }
        else
        {
            [actor acceptRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doDeclineContactRequest:(int)uid actor:(TGContactRequestActionActor *)actor
{
    TLRPCcontacts_declineRequest$contacts_declineRequest *declineRequest = [[TLRPCcontacts_declineRequest$contacts_declineRequest alloc] init];
    declineRequest.n_id = [self createInputUserForUid:uid];
    
    return [[TGSession instance] performRpc:declineRequest completionBlock:^(TLcontacts_Link *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor declineRequestSuccess:result];
        }
        else
        {
            [actor declineRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doDeleteContacts:(NSArray *)uids actor:(id<TGContactDeleteActorProtocol>)actor
{
    TLRPCcontacts_deleteContacts$contacts_deleteContacts *deleteContacts = [[TLRPCcontacts_deleteContacts$contacts_deleteContacts alloc] init];
    NSMutableArray *inputUsers = [[NSMutableArray alloc] init];
    
    for (NSNumber *nUid in uids)
    {
        TLInputUser *inputUser = [self createInputUserForUid:[nUid intValue]];
        if (inputUser != nil)
            [inputUsers addObject:inputUser];
    }
    
    deleteContacts.n_id = inputUsers;
    
    id concreteRpc = deleteContacts;
    
/*#if defined(DEBUG)
    TLRPCcontacts_clearContact$contacts_clearContact *clearContact = [[TLRPCcontacts_clearContact$contacts_clearContact alloc] init];
    clearContact.n_id = [inputUsers objectAtIndex:0];
    concreteRpc = clearContact;
#endif*/

    return [[TGSession instance] performRpc:concreteRpc completionBlock:^(__unused id<TLObject> result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
/*#if defined(DEBUG)
            if ([concreteRpc isKindOfClass:[TLRPCcontacts_clearContact class]])
            {
                TLcontacts_Link *link = result;
                TGUser *user = [[TGUser alloc] initWithTelegraphUserDesc:link.user];
                [TGUserDataRequestBuilder executeUserObjectsUpdate:[NSArray arrayWithObject:user]];
                
                int userLink = extractUserLink(link);
                [TGUserDataRequestBuilder executeUserLinkUpdates:[[NSArray alloc] initWithObjects:[[NSArray alloc] initWithObjects:[[NSNumber alloc] initWithInt:link.user.n_id], [[NSNumber alloc] initWithInt:userLink], nil], nil]];
            }
#endif*/
            
            [actor deleteContactsSuccess:uids];
        }
        else
        {
            [actor deleteContactsFailed:uids];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (TLInputPeer *)createInputPeerForConversation:(int64_t)conversationId
{
    if (conversationId < 0)
    {
        TLInputPeer$inputPeerChat *chatPeer = [[TLInputPeer$inputPeerChat alloc] init];
        chatPeer.chat_id = -(int)conversationId;
        return chatPeer;
    }
    else if (conversationId == _clientUserId)
    {
        TLInputPeer$inputPeerSelf *selfPeer = [[TLInputPeer$inputPeerSelf alloc] init];
        return selfPeer;
    }
    else
    {
        TGUser *user = [TGDatabaseInstance() loadUser:(int)conversationId];
        if (user != nil)
        {
            if (user.phoneNumberHash != 0)
            {
                TLInputPeer$inputPeerForeign *foreignPeer = [[TLInputPeer$inputPeerForeign alloc] init];
                foreignPeer.user_id = (int)conversationId;
                foreignPeer.access_hash = user.phoneNumberHash;
                return foreignPeer;
            }
            else if (user.phoneNumber != nil && user.phoneNumber.length != 0)
            {
                TLInputPeer$inputPeerContact *contactPeer = [[TLInputPeer$inputPeerContact alloc] init];
                contactPeer.user_id = (int)conversationId;
                return contactPeer;
            }
        }

        TLInputPeer$inputPeerContact *contactPeer = [[TLInputPeer$inputPeerContact alloc] init];
        contactPeer.user_id = (int)conversationId;
        return contactPeer;
    }
}

- (TLInputUser *)createInputUserForUid:(int)uid
{
    if (uid == _clientUserId)
    {
        TLInputUser$inputUserSelf *selfUser = [[TLInputUser$inputUserSelf alloc] init];
        return selfUser;
    }
    else
    {
        TGUser *user = [TGDatabaseInstance() loadUser:uid];
        if (user != nil)
        {
            if (user.phoneNumberHash != 0)
            {
                TLInputUser$inputUserForeign *foreignUser = [[TLInputUser$inputUserForeign alloc] init];
                foreignUser.user_id = uid;
                foreignUser.access_hash = user.phoneNumberHash;
                return foreignUser;
            }
            else if (user.phoneNumber != nil && user.phoneNumber.length != 0)
            {
                TLInputUser$inputUserContact *contactUser = [[TLInputUser$inputUserContact alloc] init];
                contactUser.user_id = uid;
                return contactUser;
            }
        }
        
        TLInputUser$inputUserContact *contactUser = [[TLInputUser$inputUserContact alloc] init];
        contactUser.user_id = uid;
        return contactUser;
    }
}

- (NSObject *)doRequestConversationHistory:(int64_t)conversationId maxMid:(int)maxMid orOffset:(int)offset limit:(int)limit actor:(TGConversationHistoryAsyncRequestActor *)actor
{
    TLRPCmessages_getHistory$messages_getHistory *getHistory = [[TLRPCmessages_getHistory$messages_getHistory alloc] init];
    getHistory.peer = [self createInputPeerForConversation:conversationId];
    if (maxMid >= 0)
        getHistory.max_id = maxMid;
    getHistory.offset = offset;
    getHistory.limit = limit;
    
    return [[TGSession instance] performRpc:getHistory completionBlock:^(TLmessages_Messages *messages, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor conversationHistoryRequestSuccess:messages];
        }
        else
        {
            [actor conversationHistoryRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestConversationMediaHistory:(int64_t)conversationId maxMid:(int)maxMid maxDate:(int)maxDate limit:(int)limit actor:(TGConversationMediaHistoryRequestActor *)actor
{
    TLRPCmessages_search$messages_search *search = [[TLRPCmessages_search$messages_search alloc] init];
    search.peer = [self createInputPeerForConversation:conversationId];
    search.q = @"";
    search.min_date = 0;
    search.max_date = maxDate;
    search.offset = 0;
    search.max_id = maxMid;
    search.limit = limit;
    search.filter = [[TLMessagesFilter$inputMessagesFilterPhotoVideo alloc] init];
    
    return [[TGSession instance] performRpc:search completionBlock:^(TLmessages_Messages *messages, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor mediaHistoryRequestSuccess:messages];
        }
        else
        {
            [actor mediaHistoryRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doConversationSendMessage:(int64_t)conversationId messageText:(NSString *)messageText geo:(TLInputGeoPoint *)geo messageGuid:(NSString *)__unused messageGuid tmpId:(int64_t)tmpId actor:(TGConversationSendMessageActor *)actor
{
    if (geo != nil && [geo isKindOfClass:[TLInputGeoPoint$inputGeoPoint class]])
    {
        TLInputMedia$inputMediaGeoPoint *geoMedia = [[TLInputMedia$inputMediaGeoPoint alloc] init];
        geoMedia.geo_point = geo;
        
        return [self doConversationSendMedia:conversationId media:geoMedia messageGuid:messageGuid tmpId:tmpId actor:actor];
    }
    else
    {
        TLRPCmessages_sendMessage$messages_sendMessage *sendMessage = [[TLRPCmessages_sendMessage$messages_sendMessage alloc] init];
        sendMessage.peer = [self createInputPeerForConversation:conversationId];
        sendMessage.message = messageText;
        sendMessage.random_id = tmpId;
        
        return [[TGSession instance] performRpc:sendMessage completionBlock:^(TLmessages_SentMessage *sentMessage, __unused int64_t responseTime, TLError *error)
        {
            if (error == nil)
            {
                [actor conversationSendMessageRequestSuccess:sentMessage];
            }
            else
            {
                [actor conversationSendMessageRequestFailed];
            }
        } progressBlock:nil quickAckBlock:^
        {
            [actor conversationSendMessageQuickAck];
        } requiresCompletion:true requestClass:TGRequestClassGeneric datacenterId:TG_DEFAULT_DATACENTER_ID];
    }
}

- (NSObject *)doConversationSendMedia:(int64_t)conversationId media:(TLInputMedia *)media messageGuid:(NSString *)__unused messageGuid tmpId:(int64_t)tmpId actor:(TGConversationSendMessageActor *)actor
{
    TLRPCmessages_sendMedia$messages_sendMedia *sendMedia = [[TLRPCmessages_sendMedia$messages_sendMedia alloc] init];
    sendMedia.peer = [self createInputPeerForConversation:conversationId];
    sendMedia.media = media;
    sendMedia.random_id = tmpId;
    
    return [[TGSession instance] performRpc:sendMedia completionBlock:^(id message, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor conversationSendMessageRequestSuccess:message];
        }
        else
        {
            [actor conversationSendMessageRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doConversationForwardMessage:(int64_t)conversationId messageId:(int)messageId tmpId:(int64_t)tmpId actor:(TGConversationSendMessageActor *)actor
{
    TLRPCmessages_forwardMessage$messages_forwardMessage *forwardMessage = [[TLRPCmessages_forwardMessage$messages_forwardMessage alloc] init];
    forwardMessage.peer = [self createInputPeerForConversation:conversationId];
    forwardMessage.n_id = messageId;
    forwardMessage.random_id = tmpId;
    
    return [[TGSession instance] performRpc:forwardMessage completionBlock:^(TLmessages_StatedMessage *message, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor conversationSendMessageRequestSuccess:message];
        }
        else
        {
            [actor conversationSendMessageRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doBroadcastSendMessage:(NSArray *)uids messageText:(NSString *)messageText media:(TLInputMedia *)media actor:(TGConversationSendMessageActor *)actor
{
    TLRPCmessages_sendBroadcast$messages_sendBroadcast *sendBroadcast = [[TLRPCmessages_sendBroadcast$messages_sendBroadcast alloc] init];
    NSMutableArray *inputUsers = [[NSMutableArray alloc] init];
    for (NSNumber *nUid in uids)
    {
        TLInputUser *inputUser = [self createInputUserForUid:[nUid intValue]];
        if (inputUser != nil)
            [inputUsers addObject:inputUser];
    }
    
    sendBroadcast.contacts = inputUsers;
    sendBroadcast.message = messageText;
    sendBroadcast.media = media == nil ? [[TLInputMedia$inputMediaEmpty alloc] init] : media;
    
    return [[TGSession instance] performRpc:sendBroadcast completionBlock:^(id<TLObject> result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor conversationSendBroadcastSuccess:(NSArray *)result];
        }
        else
        {
            [actor conversationSendBroadcastFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doConversationReadHistory:(int64_t)conversationId maxMid:(int)maxMid offset:(int)offset actor:(TGSynchronizeActionQueueActor *)actor
{
    TLRPCmessages_readHistory$messages_readHistory *readHistory = [[TLRPCmessages_readHistory$messages_readHistory alloc] init];
    readHistory.peer = [self createInputPeerForConversation:conversationId];
    readHistory.max_id = maxMid;
    readHistory.offset = offset;
    
    return [[TGSession instance] performRpc:readHistory completionBlock:^(TLmessages_AffectedHistory *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor readMessagesSuccess:result];
        }
        else
        {
            [actor readMessagesFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator];
}

- (NSObject *)doReportDelivery:(int)maxMid actor:(TGReportDeliveryActor *)actor
{
    TLRPCmessages_receivedMessages$messages_receivedMessages *receivedMessages = [[TLRPCmessages_receivedMessages$messages_receivedMessages alloc] init];
    receivedMessages.max_id = maxMid;
    
    return [[TGSession instance] performRpc:receivedMessages completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor reportDeliverySuccess:maxMid mids:(NSArray *)response];
        }
        else
        {
            [actor reportDeliveryFailed:maxMid];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator];
}

- (NSObject *)doReportConversationTypingActivity:(int64_t)conversationId requestBuilder:(TGConversationActivityRequestBuilder *)requestActor
{
    TLRPCmessages_setTyping$messages_setTyping *setTyping = [[TLRPCmessages_setTyping$messages_setTyping alloc] init];
    setTyping.peer = [self createInputPeerForConversation:conversationId];
    setTyping.typing = true;
    
    return [[TGSession instance] performRpc:setTyping completionBlock:^(__unused id<TLObject> result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestActor reportTypingActivitySuccess];
        }
        else
        {
            [requestActor reportTypingActivityFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator];
}

- (NSObject *)doChangeConversationTitle:(int64_t)conversationId title:(NSString *)title actor:(TGConversationChangeTitleRequestActor *)requestActor
{
    TLRPCmessages_editChatTitle$messages_editChatTitle *editChatTitle = [[TLRPCmessages_editChatTitle$messages_editChatTitle alloc] init];
    editChatTitle.chat_id = -conversationId;
    editChatTitle.title = title;
    
    return [[TGSession instance] performRpc:editChatTitle completionBlock:^(TLmessages_StatedMessage *message, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [requestActor conversationTitleChangeSuccess:message];
        }
        else
        {
            [requestActor conversationTitleChangeFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doChangeConversationPhoto:(int64_t)conversationId photo:(TLInputChatPhoto *)photo actor:(TGConversationChangePhotoActor *)actor
{
    TLRPCmessages_editChatPhoto$messages_editChatPhoto *editChatPhoto = [[TLRPCmessages_editChatPhoto$messages_editChatPhoto alloc] init];
    editChatPhoto.chat_id = -conversationId;
    editChatPhoto.photo = photo;
    
    return [[TGSession instance] performRpc:editChatPhoto completionBlock:^(TLmessages_StatedMessage *message, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor conversationUpdateAvatarSuccess:message];
        }
        else
        {
            [actor conversationUpdateAvatarFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doCreateChat:(NSArray *)uidList title:(NSString *)title actor:(TGConversationCreateChatRequestActor *)actor
{
    TLRPCmessages_createChat$messages_createChat *createChat = [[TLRPCmessages_createChat$messages_createChat alloc] init];
    createChat.title = title;
    
    NSMutableArray *inputUsers = [[NSMutableArray alloc] init];
    for (NSNumber *nUid in uidList)
    {
        int uid = [nUid intValue];
        [inputUsers addObject:[self createInputUserForUid:uid]];
    }
    createChat.users = inputUsers;
    
    return [[TGSession instance] performRpc:createChat completionBlock:^(TLmessages_StatedMessage *message, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor createChatSuccess:message];
        }
        else
        {
            [actor createChatFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doAddConversationMember:(int64_t)conversationId uid:(int)uid actor:(TGConversationAddMemberRequestActor *)actor
{
    TLRPCmessages_addChatUser$messages_addChatUser *addChatUser = [[TLRPCmessages_addChatUser$messages_addChatUser alloc] init];
    addChatUser.chat_id = -(int)conversationId;
    
    addChatUser.user_id = [self createInputUserForUid:uid];
    addChatUser.fwd_limit = 120;
    
    return [[TGSession instance] performRpc:addChatUser completionBlock:^(TLmessages_StatedMessage *message, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor addMemberSuccess:message];
        }
        else
        {
            int reason = -1;
            if ([error.description rangeOfString:@"USER_LEFT_CHAT"].location != NSNotFound)
                reason = -2;
            else if ([error.description rangeOfString:@"USERS_TOO_MUCH"].location != NSNotFound)
                reason = -3;
            [actor addMemberFailed:reason];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doDeleteConversationMember:(int64_t)conversationId uid:(int)uid actor:(id<TGDeleteChatMemberProtocol>)actor
{
    TLRPCmessages_deleteChatUser$messages_deleteChatUser *deleteChatUser = [[TLRPCmessages_deleteChatUser$messages_deleteChatUser alloc] init];
    deleteChatUser.chat_id = -(int)conversationId;
    
    deleteChatUser.user_id = [self createInputUserForUid:uid];
    
    return [[TGSession instance] performRpc:deleteChatUser completionBlock:^(TLmessages_StatedMessage *message, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor deleteMemberSuccess:message];
        }
        else
        {
            [actor deleteMemberFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doDeleteMessages:(NSArray *)messageIds actor:(TGSynchronizeActionQueueActor *)actor
{
    TLRPCmessages_deleteMessages$messages_deleteMessages *deleteMessages = [[TLRPCmessages_deleteMessages$messages_deleteMessages alloc] init];
    deleteMessages.n_id = messageIds;
    
    return [[TGSession instance] performRpc:deleteMessages completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor deleteMessagesSuccess:(NSArray *)response];
        }
        else
        {
            [actor deleteMessagesFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doDeleteConversation:(int64_t)conversationId offset:(int)offset actor:(TGSynchronizeActionQueueActor *)actor
{
    TLRPCmessages_deleteHistory$messages_deleteHistory *deleteHistory = [[TLRPCmessages_deleteHistory$messages_deleteHistory alloc] init];
    deleteHistory.peer = [self createInputPeerForConversation:conversationId];
    deleteHistory.offset = offset;
    
    return [[TGSession instance] performRpc:deleteHistory completionBlock:^(TLmessages_AffectedHistory *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor deleteHistorySuccess:result];
        }
        else
        {
            [actor deleteHistoryFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doRequestTimeline:(int)timelineId maxItemId:(int64_t)maxItemId limit:(int)limit actor:(TGTimelineHistoryRequestBuilder *)actor
{
    TLRPCphotos_getWall$photos_getWall *getWall = [[TLRPCphotos_getWall$photos_getWall alloc] init];

    getWall.user_id = [self createInputUserForUid:timelineId];
    
    getWall.limit = limit;
    getWall.max_id = maxItemId;
    
    return [[TGSession instance] performRpc:getWall completionBlock:^(TLphotos_Photos *photos, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor timelineHistoryRequestSuccess:photos];
        }
        else
        {
            [actor timelineHistoryRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doUploadTimelinePhoto:(int64_t)localFileId parts:(int)parts md5:(NSString *)md5 hasLocation:(bool)hasLocation latitude:(double)latitude longitude:(double)longitude actor:(TGTimelineUploadPhotoRequestBuilder *)actor
{
    TLRPCphotos_uploadProfilePhoto$photos_uploadProfilePhoto *uploadProfilePhoto = [[TLRPCphotos_uploadProfilePhoto$photos_uploadProfilePhoto alloc] init];
    TLInputFile$inputFile *inputFile = [[TLInputFile$inputFile alloc] init];
    inputFile.n_id = localFileId;
    inputFile.parts = parts;
    inputFile.md5_checksum = md5;
    inputFile.name = @"photo.jpg";
    
    if (hasLocation)
    {
        TLInputGeoPoint$inputGeoPoint *geoPoint = [[TLInputGeoPoint$inputGeoPoint alloc] init];
        geoPoint.lat = latitude;
        geoPoint.n_long = longitude;
        uploadProfilePhoto.geo_point = geoPoint;
    }
    else
    {
        TLInputGeoPoint$inputGeoPointEmpty *geoPoint = [[TLInputGeoPoint$inputGeoPointEmpty alloc] init];
        uploadProfilePhoto.geo_point = geoPoint;
    }
    
    uploadProfilePhoto.file = inputFile;
    uploadProfilePhoto.caption = @"";
    uploadProfilePhoto.crop = [[TLInputPhotoCrop$inputPhotoCropAuto alloc] init];
    
    return [[TGSession instance] performRpc:uploadProfilePhoto completionBlock:^(TLphotos_Photo *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor timelineUploadPhotoSuccess:result];
        }
        else
        {
            [actor timelineUploadPhotoFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors];
}

- (NSObject *)doDeleteProfilePhotos:(NSArray *)items actor:(TGSynchronizeServiceActionsActor *)actor
{
    TLRPCphotos_deletePhotos$photos_deletePhotos *deletePhotos = [[TLRPCphotos_deletePhotos$photos_deletePhotos alloc] init];
    
    NSMutableArray *idsArray = [[NSMutableArray alloc] init];
    for (NSDictionary *itemDesc in items)
    {
        TLInputPhoto$inputPhoto *inputPhoto = [[TLInputPhoto$inputPhoto alloc] init];
        inputPhoto.n_id = [itemDesc[@"imageId"] longLongValue];
        inputPhoto.access_hash = [itemDesc[@"accessHash"] longLongValue];
        [idsArray addObject:inputPhoto];
    }
    deletePhotos.n_id = idsArray;
    
    return [[TGSession instance] performRpc:deletePhotos completionBlock:^(__unused id<TLObject> result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor deleteProfilePhotosSucess:items];
        }
        else
        {
            [actor deleteProfilePhotosFailed:items];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doAssignProfilePhoto:(int64_t)itemId accessHash:(int64_t)accessHash actor:(TGTimelineAssignProfilePhotoActor *)actor
{
    TLRPCphotos_updateProfilePhoto$photos_updateProfilePhoto *updateProfilePhoto = [[TLRPCphotos_updateProfilePhoto$photos_updateProfilePhoto alloc] init];
    TLInputPhoto$inputPhoto *inputPhoto = [[TLInputPhoto$inputPhoto alloc] init];
    inputPhoto.n_id = itemId;
    inputPhoto.access_hash = accessHash;
    updateProfilePhoto.n_id = inputPhoto;
    updateProfilePhoto.crop = [[TLInputPhotoCrop$inputPhotoCropAuto alloc] init];
    
    return [[TGSession instance] performRpc:updateProfilePhoto completionBlock:^(TLUserProfilePhoto *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor assignProfilePhotoRequestSuccess:result];
        }
        else
        {
            [actor assignProfilePhotoRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doSaveGeocodingResult:(double)latitude longitude:(double)longitude components:(NSDictionary *)components actor:(TGSaveGeocodingResultActor *)actor
{
    TLRPCgeo_saveGeoPlace$geo_saveGeoPlace *savePlace = [[TLRPCgeo_saveGeoPlace$geo_saveGeoPlace alloc] init];
    
    TLInputGeoPoint$inputGeoPoint *geoPoint = [[TLInputGeoPoint$inputGeoPoint alloc] init];
    geoPoint.lat = latitude;
    geoPoint.n_long = longitude;
    
    savePlace.geo_point = geoPoint;
    
    TLInputGeoPlaceName$inputGeoPlaceName *placeName = [[TLInputGeoPlaceName$inputGeoPlaceName alloc] init];
    placeName.country = [components objectForKey:@"country"];
    placeName.state = [components objectForKey:@"state"];
    placeName.city = [components objectForKey:@"city"];
    placeName.district = [components objectForKey:@"district"];
    placeName.street = [components objectForKey:@"street"];
    savePlace.place_name = placeName;
    
    return [[TGSession instance] performRpc:savePlace completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor saveGeocodingResultSuccess];
        }
        else
        {
            [actor saveGeocodingResultFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestPeerNotificationSettings:(int64_t)peerId actor:(id<TGPeerSettingsActorProtocol>)actor
{
    TLRPCaccount_getNotifySettings$account_getNotifySettings *getPeerNotifySettings = [[TLRPCaccount_getNotifySettings$account_getNotifySettings alloc] init];
    
    if (peerId == INT_MAX - 1)
    {
        getPeerNotifySettings.peer = [[TLInputNotifyPeer$inputNotifyUsers alloc] init];
    }
    else if (peerId == INT_MAX - 2)
    {
        getPeerNotifySettings.peer = [[TLInputNotifyPeer$inputNotifyChats alloc] init];
    }
    else
    {
        TLInputNotifyPeer$inputNotifyPeer *inputPeer = [[TLInputNotifyPeer$inputNotifyPeer alloc] init];
        inputPeer.peer = [self createInputPeerForConversation:peerId];
        getPeerNotifySettings.peer = inputPeer;
    }
    
    return [[TGSession instance] performRpc:getPeerNotifySettings completionBlock:^(TLPeerNotifySettings *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor peerNotifySettingsRequestSuccess:result];
        }
        else
        {
            [actor peerNotifySettingsRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestConversationData:(int64_t)conversationId actor:(TGExtendedChatDataRequestActor *)actor
{
    TLRPCmessages_getFullChat$messages_getFullChat *getFullChat = [[TLRPCmessages_getFullChat$messages_getFullChat alloc] init];
    getFullChat.chat_id = (int)(-conversationId);
    
    return [[TGSession instance] performRpc:getFullChat completionBlock:^(TLmessages_ChatFull *chatFull, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor chatFullRequestSuccess:chatFull];
        }
        else
        {
            [actor chatFullRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (id)doRequestPeerProfilePhotoList:(int64_t)peerId actor:(TGProfilePhotoListActor *)actor
{
    TLRPCphotos_getUserPhotos$photos_getUserPhotos *getPhotos = [[TLRPCphotos_getUserPhotos$photos_getUserPhotos alloc] init];
    
    getPhotos.user_id = [self createInputUserForUid:(int)peerId];
    getPhotos.offset = 0;
    getPhotos.limit = 80;
    getPhotos.max_id = 0;
    
    return [[TGSession instance] performRpc:getPhotos completionBlock:^(TLphotos_Photos *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor photoListRequestSuccess:result];
        }
        else
        {
            [actor photoListRequestFailed];
        }
    } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric datacenterId:TG_DEFAULT_DATACENTER_ID];
}

- (NSObject *)doChangePeerNotificationSettings:(int64_t)peerId muteUntil:(int)muteUntil soundId:(int)soundId previewText:(bool)previewText photoNotificationsEnabled:(bool)photoNotificationsEnabled actor:(TGSynchronizeServiceActionsActor *)actor
{
    TLRPCaccount_updateNotifySettings$account_updateNotifySettings *updatePeerNotifySettings = [[TLRPCaccount_updateNotifySettings$account_updateNotifySettings alloc] init];
    
    if (peerId == INT_MAX - 1)
    {
        updatePeerNotifySettings.peer = [[TLInputNotifyPeer$inputNotifyUsers alloc] init];
    }
    else if (peerId == INT_MAX - 2)
    {
        updatePeerNotifySettings.peer = [[TLInputNotifyPeer$inputNotifyChats alloc] init];
    }
    else
    {
        TLInputNotifyPeer$inputNotifyPeer *inputPeer = [[TLInputNotifyPeer$inputNotifyPeer alloc] init];
        inputPeer.peer = [self createInputPeerForConversation:peerId];
        updatePeerNotifySettings.peer = inputPeer;
    }
    
    TLInputPeerNotifySettings$inputPeerNotifySettings *peerNotifySettings = [[TLInputPeerNotifySettings$inputPeerNotifySettings alloc] init];
    
    NSString *stringSoundId = nil;
    if (soundId == 0)
        stringSoundId = @"";
    else if (soundId == 1)
        stringSoundId = @"default";
    else
        stringSoundId = [[NSString alloc] initWithFormat:@"%d.m4a", soundId];
    
    peerNotifySettings.mute_until = muteUntil;
    peerNotifySettings.sound = stringSoundId;
    peerNotifySettings.events_mask = photoNotificationsEnabled ? 1 : 0;
    peerNotifySettings.show_previews = previewText;
    
    updatePeerNotifySettings.settings = peerNotifySettings;
    
    return [[TGSession instance] performRpc:updatePeerNotifySettings completionBlock:^(TLPeerNotifySettings *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor changePeerNotificationSettingsSuccess:result];
        }
        else
        {
            [actor changePeerNotificationSettingsFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doResetPeerNotificationSettings:(TGSynchronizeServiceActionsActor *)actor
{
    TLRPCaccount_resetNotifySettings$account_resetNotifySettings *resetPeerNotifySettings = [[TLRPCaccount_resetNotifySettings$account_resetNotifySettings alloc] init];
    
    return [[TGSession instance] performRpc:resetPeerNotifySettings completionBlock:^(id<TLObject> __unused response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor resetPeerNotificationSettingsSuccess];
        }
        else
        {
            [actor resetPeerNotificationSettingsFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestBlockList:(TGBlockListRequestActor *)actor
{
    TLRPCcontacts_getBlocked$contacts_getBlocked *getBlocked = [[TLRPCcontacts_getBlocked$contacts_getBlocked alloc] init];
    getBlocked.offset = 0;
    getBlocked.limit = 10000;
    
    return [[TGSession instance] performRpc:getBlocked completionBlock:^(TLcontacts_Blocked *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor blockListRequestSuccess:result];
        }
        else
        {
            [actor blockListRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doChangePeerBlockStatus:(int64_t)peerId block:(bool)block actor:(TGSynchronizeServiceActionsActor *)actor
{
    TLMetaRpc *method = nil;
    
    if (block)
    {
        TLRPCcontacts_block$contacts_block *blockMethod = [[TLRPCcontacts_block$contacts_block alloc] init];
        blockMethod.n_id = [self createInputUserForUid:(int)peerId];
        method = blockMethod;
    }
    else
    {
        TLRPCcontacts_unblock$contacts_unblock *unblockMethod = [[TLRPCcontacts_unblock$contacts_unblock alloc] init];
        unblockMethod.n_id = [self createInputUserForUid:(int)peerId];
        method = unblockMethod;
    }
    
    return [[TGSession instance] performRpc:method completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor changePeerBlockStatusSuccess];
        }
        else
        {
            [actor changePeerBlockStatusFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doChangeName:(NSString *)firstName lastName:(NSString *)lastName actor:(TGChangeNameActor *)actor
{
    TLRPCaccount_updateProfile$account_updateProfile *updateProfile = [[TLRPCaccount_updateProfile$account_updateProfile alloc] init];
    updateProfile.first_name = firstName;
    updateProfile.last_name = lastName;
    
    return [[TGSession instance] performRpc:updateProfile completionBlock:^(TLUser *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor changeNameSuccess:result];
        }
        else
        {
            [actor changeNameFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doRequestPrivacySettings:(TGPrivacySettingsRequestActor *)actor
{
    TLRPCaccount_getGlobalPrivacySettings$account_getGlobalPrivacySettings *getGlobalPrivacySettings = [[TLRPCaccount_getGlobalPrivacySettings$account_getGlobalPrivacySettings alloc] init];
    
    return [[TGSession instance] performRpc:getGlobalPrivacySettings completionBlock:^(TLGlobalPrivacySettings *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor privacySettingsRequestSuccess:result];
        }
        else
        {
            [actor privacySettingsRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (NSObject *)doChangePrivacySettings:(bool)disableSuggestions hideContacts:(bool)hideContacts hideLastVisit:(bool)hideLastVisit hideLocation:(bool)hideLocation actor:(TGSynchronizeServiceActionsActor *)actor
{
    TLRPCaccount_updateGlobalPrivacySettings$account_updateGlobalPrivacySettings *updateGlobalPrivacySettings = [[TLRPCaccount_updateGlobalPrivacySettings$account_updateGlobalPrivacySettings alloc] init];
    updateGlobalPrivacySettings.no_suggestions = disableSuggestions;
    updateGlobalPrivacySettings.hide_contacts = hideContacts;
    updateGlobalPrivacySettings.hide_last_visit = hideLastVisit;
    updateGlobalPrivacySettings.hide_located = hideLocation;
    
    return [[TGSession instance] performRpc:updateGlobalPrivacySettings completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor changePrivacySettingsSuccess];
        }
        else
        {
            [actor changePrivacySettingsFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (id)doRequestWallpaperList:(TGWallpaperListRequestActor *)actor
{
    TLRPCaccount_getWallPapers$account_getWallPapers *getWallpapers = [[TLRPCaccount_getWallPapers$account_getWallPapers alloc] init];
    return [[TGSession instance] performRpc:getWallpapers completionBlock:^(id<TLObject> result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor wallpaperListRequestSuccess:(NSArray *)result];
        }
        else
        {
            [actor wallpaperListRequestFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric];
}

- (id)doRequestEncryptionConfig:(TGRequestEncryptedChatActor *)actor version:(int)version
{
    TLRPCmessages_getDhConfig$messages_getDhConfig *getDhConfig = [[TLRPCmessages_getDhConfig$messages_getDhConfig alloc] init];
    getDhConfig.version = version;
    getDhConfig.random_length = 256;
    
    return [[TGSession instance] performRpc:getDhConfig completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor dhRequestSuccess:response];
        }
        else
        {
            [actor dhRequestFailed];
        }
    } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric datacenterId:TG_DEFAULT_DATACENTER_ID];
}

- (id)doRequestEncryptedChat:(int)uid randomId:(int64_t)randomId gABytes:(NSData *)gABytes actor:(TGRequestEncryptedChatActor *)actor
{
    TLRPCmessages_requestEncryption$messages_requestEncryption *requestEncryption = [[TLRPCmessages_requestEncryption$messages_requestEncryption alloc] init];
    requestEncryption.user_id = [self createInputUserForUid:uid];
    requestEncryption.random_id = randomId;
    requestEncryption.g_a = gABytes;
    
    return [[TGSession instance] performRpc:requestEncryption completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor encryptedChatRequestSuccess:response date:(int)(responseTime / 4294967296L)];
        }
        else
        {
            NSString *errorType = [self extractErrorType:error];
            
            bool versionOutdated = false;
            if ([errorType isEqualToString:@"PARTICIPANT_VERSION_OUTDATED"])
                versionOutdated = true;
            
            [actor encryptedChatRequestFailed:versionOutdated];
        }
    } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors datacenterId:TG_DEFAULT_DATACENTER_ID];
}

- (id)doAcceptEncryptedChat:(int64_t)encryptedChatId accessHash:(int64_t)accessHash gBBytes:(NSData *)gBBytes keyFingerprint:(int64_t)keyFingerprint actor:(TGEncryptedChatResponseActor *)actor
{
    TLRPCmessages_acceptEncryption$messages_acceptEncryption *acceptEncryption = [[TLRPCmessages_acceptEncryption$messages_acceptEncryption alloc] init];
    
    TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
    inputEncryptedChat.chat_id = encryptedChatId;
    inputEncryptedChat.access_hash = accessHash;
    
    acceptEncryption.peer = inputEncryptedChat;
    acceptEncryption.g_b = gBBytes;
    acceptEncryption.key_fingerprint = keyFingerprint;
    
    return [[TGSession instance] performRpc:acceptEncryption completionBlock:^(id<TLObject> response, int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor acceptEncryptedChatSuccess:response date:(int)(responseTime / 4294967296L)];
        }
        else
        {
            [actor acceptEncryptedChatFailed];
        }
    } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors datacenterId:TG_DEFAULT_DATACENTER_ID];
}

- (id)doRejectEncryptedChat:(int64_t)encryptedConversationId actor:(TGSynchronizeActionQueueActor *)actor
{
    TLRPCmessages_discardEncryption$messages_discardEncryption *discardEncryption = [[TLRPCmessages_discardEncryption$messages_discardEncryption alloc] init];
    discardEncryption.chat_id = (int32_t)encryptedConversationId;
    
    return [[TGSession instance] performRpc:discardEncryption completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor rejectEncryptedChatSuccess];
        }
        else
        {
            [actor rejectEncryptedChatFailed];
        }
    } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors datacenterId:TG_DEFAULT_DATACENTER_ID];
}

- (id)doReportEncryptedConversationTypingActivity:(int64_t)encryptedConversationId accessHash:(int64_t)accessHash actor:(TGConversationActivityRequestBuilder *)actor
{
    TLRPCmessages_setEncryptedTyping$messages_setEncryptedTyping *setEncryptedTyping = [[TLRPCmessages_setEncryptedTyping$messages_setEncryptedTyping alloc] init];
    setEncryptedTyping.typing = true;
    
    TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
    inputEncryptedChat.chat_id = encryptedConversationId;
    inputEncryptedChat.access_hash = accessHash;
    setEncryptedTyping.peer = inputEncryptedChat;
    
    return [[TGSession instance] performRpc:setEncryptedTyping completionBlock:^(__unused id<TLObject> result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor reportTypingActivitySuccess];
        }
        else
        {
            [actor reportTypingActivityFailed];
        }
    } progressBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator];
}

- (id)doSendEncryptedMessage:(int64_t)encryptedChatId accessHash:(int64_t)accessHash randomId:(int64_t)randomId data:(NSData *)data encryptedFile:(TLInputEncryptedFile *)encryptedFile actor:(TGConversationSendMessageActor *)actor
{
    if (encryptedFile == nil)
    {
        TLRPCmessages_sendEncrypted$messages_sendEncrypted *sendEncrypted = [[TLRPCmessages_sendEncrypted$messages_sendEncrypted alloc] init];

        TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
        inputEncryptedChat.chat_id = encryptedChatId;
        inputEncryptedChat.access_hash = accessHash;
        sendEncrypted.peer = inputEncryptedChat;
        
        sendEncrypted.random_id = randomId;
        sendEncrypted.data = data;
        
        return [[TGSession instance] performRpc:sendEncrypted completionBlock:^(TLmessages_SentEncryptedMessage *result, __unused int64_t responseTime, TLError *error)
        {
            if (error == nil)
            {
                [actor sendEncryptedMessageSuccess:result.date encryptedFile:nil];
            }
            else
            {
                [actor sendEncryptedMessageFailed];
            }
        } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors datacenterId:TG_DEFAULT_DATACENTER_ID];
    }
    else
    {
        TLRPCmessages_sendEncryptedFile$messages_sendEncryptedFile *sendEncrypted = [[TLRPCmessages_sendEncryptedFile$messages_sendEncryptedFile alloc] init];
        
        TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
        inputEncryptedChat.chat_id = encryptedChatId;
        inputEncryptedChat.access_hash = accessHash;
        sendEncrypted.peer = inputEncryptedChat;
        
        sendEncrypted.random_id = randomId;
        sendEncrypted.data = data;
        
        sendEncrypted.file = encryptedFile;
        
        return [[TGSession instance] performRpc:sendEncrypted completionBlock:^(TLmessages_SentEncryptedMessage *result, __unused int64_t responseTime, TLError *error)
        {
            if (error == nil)
            {
                [actor sendEncryptedMessageSuccess:result.date encryptedFile:[result isKindOfClass:[TLmessages_SentEncryptedMessage$messages_sentEncryptedFile class]] ? [(TLmessages_SentEncryptedMessage$messages_sentEncryptedFile *)result file] : nil];
            }
            else
            {
                [actor sendEncryptedMessageFailed];
            }
        } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors datacenterId:TG_DEFAULT_DATACENTER_ID];
    }
}

- (id)doSendEncryptedServiceMessage:(int64_t)encryptedChatId accessHash:(int64_t)accessHash randomId:(int64_t)randomId data:(NSData *)data actor:(TGSynchronizeServiceActionsActor *)actor
{
    TLRPCmessages_sendEncryptedService$messages_sendEncryptedService *sendEncryptedService = [[TLRPCmessages_sendEncryptedService$messages_sendEncryptedService alloc] init];
    
    TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
    inputEncryptedChat.chat_id = encryptedChatId;
    inputEncryptedChat.access_hash = accessHash;
    sendEncryptedService.peer = inputEncryptedChat;
    
    sendEncryptedService.random_id = randomId;
    sendEncryptedService.data = data;
    
    return [[TGSession instance] performRpc:sendEncryptedService completionBlock:^(TLmessages_SentEncryptedMessage *result, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor sendEncryptedServiceMessageSuccess:result.date];
        }
        else
        {
            [actor sendEncryptedServiceMessageFailed];
        }
    } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors datacenterId:TG_DEFAULT_DATACENTER_ID];
}

- (id)doReadEncrytedHistory:(int64_t)encryptedConversationId accessHash:(int64_t)accessHash maxDate:(int32_t)maxDate actor:(TGSynchronizeActionQueueActor *)actor
{
    TLRPCmessages_readEncryptedHistory$messages_readEncryptedHistory *readEncryptedHistory = [[TLRPCmessages_readEncryptedHistory$messages_readEncryptedHistory alloc] init];

    TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
    inputEncryptedChat.chat_id = encryptedConversationId;
    inputEncryptedChat.access_hash = accessHash;
    readEncryptedHistory.peer = inputEncryptedChat;
    
    readEncryptedHistory.max_date = maxDate;
    
    return [[TGSession instance] performRpc:readEncryptedHistory completionBlock:^(__unused id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor readEncryptedSuccess];
        }
        else
        {
            [actor readEncryptedFailed];
        }
    } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassFailOnServerErrors datacenterId:TG_DEFAULT_DATACENTER_ID];
}

- (id)doReportQtsReceived:(int32_t)qts actor:(TGReportDeliveryActor *)actor
{
    TLRPCmessages_receivedQueue$messages_receivedQueue *receivedQueue = [[TLRPCmessages_receivedQueue$messages_receivedQueue alloc] init];
    receivedQueue.max_qts = qts;
    
    return [[TGSession instance] performRpc:receivedQueue completionBlock:^(id<TLObject> response, __unused int64_t responseTime, TLError *error)
    {
        if (error == nil)
        {
            [actor reportQtsSuccess:qts randomIds:(NSArray *)response];
        }
        else
        {
            [actor reportQtsFailed:qts];
        }
    } progressBlock:nil quickAckBlock:nil requiresCompletion:true requestClass:TGRequestClassGeneric | TGRequestClassHidesActivityIndicator datacenterId:TG_DEFAULT_DATACENTER_ID];
}

@end
