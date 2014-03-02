#import "TGDatabase.h"

#import "FMDatabase.h"

#import "TGUser.h"
#import "TGMessage.h"

#import "NSObject+TGLock.h"

#import "TGStringUtils.h"

#import "ActionStage.h"
#import "SGraphObjectNode.h"

#import "TGCache.h"

#include <map>
#include <set>
#include <tr1/unordered_map>
#include <tr1/memory>

#import <CommonCrypto/CommonDigest.h>

#define TGCustomPeerSettingsKey ((int)0x374BF349)

#ifdef DEBUG_DATABASE_INVOKATIONS
#define dispatchOnDatabaseThread dispatchOnDatabaseThreadDebug:__FILE__ line:__LINE__ block
#endif

static const char *databaseQueueSpecific = "com.actionstage.databasequeue";
static const char *databaseIndexQueueSpecific = "com.actionstage.databaseindexqueue";
static const char *filesQueueSpecific = "com.actionstage.filesqueue";

static dispatch_queue_t databaseDispatchQueue = nil;
static dispatch_queue_t databaseIndexDispatchQueue = nil;
static dispatch_queue_t filesDispatchQueue = nil;

static TGDatabase *TGDatabaseSingleton = nil;

static NSString *databaseName = nil;

static NSString *_liveMessagesDispatchPath = nil;
static NSString *_liveUnreadCountDispatchPath = nil;

static TGFutureAction *futureActionDeserializer(int type)
{
    static TGChangeNotificationSettingsFutureAction *TGChangeNotificationSettingsFutureActionDeserializer = nil;
    static TGClearNotificationsFutureAction *TGClearNotificationsFutureActionDeserializer = nil;
    static TGChangePrivacySettingsFutureAction *TGChangePrivacySettingsFutureActionDeserializer = nil;
    static TGChangePeerBlockStatusFutureAction *TGChangePeerBlockStatusFutureActionDeserializer = nil;
    static TGUploadAvatarFutureAction *TGUploadAvatarFutureActionDeserializer = nil;
    static TGDeleteProfilePhotoFutureAction *TGDeleteProfilePhotoFutureActionDeserializer = nil;
    static TGRemoveContactFutureAction *TGRemoveContactFutureActionDeserializer = nil;
    static TGExportContactFutureAction *TGExportContactFutureActionDeserializer = nil;
    static TGSynchronizeEncryptedChatSettingsFutureAction *TGSynchronizeEncryptedChatSettingsFutureActionDeserializer = nil;
    static TGAcceptEncryptionFutureAction *TGAcceptEncryptionFutureActionDeserializer = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        TGChangeNotificationSettingsFutureActionDeserializer = [[TGChangeNotificationSettingsFutureAction alloc] init];
        TGClearNotificationsFutureActionDeserializer = [[TGClearNotificationsFutureAction alloc] init];
        TGChangePrivacySettingsFutureActionDeserializer = [[TGChangePrivacySettingsFutureAction alloc] init];
        TGChangePeerBlockStatusFutureActionDeserializer = [[TGChangePeerBlockStatusFutureAction alloc] init];
        TGUploadAvatarFutureActionDeserializer = [[TGUploadAvatarFutureAction alloc] init];
        TGDeleteProfilePhotoFutureActionDeserializer = [[TGDeleteProfilePhotoFutureAction alloc] init];
        TGRemoveContactFutureActionDeserializer = [[TGRemoveContactFutureAction alloc] init];
        TGExportContactFutureActionDeserializer = [[TGExportContactFutureAction alloc] init];
        TGSynchronizeEncryptedChatSettingsFutureActionDeserializer = [[TGSynchronizeEncryptedChatSettingsFutureAction alloc] init];
        TGAcceptEncryptionFutureActionDeserializer = [[TGAcceptEncryptionFutureAction alloc] init];
    });
    
    switch (type)
    {
        case TGChangeNotificationSettingsFutureActionType:
            return TGChangeNotificationSettingsFutureActionDeserializer;
        case TGClearNotificationsFutureActionType:
            return TGClearNotificationsFutureActionDeserializer;
        case TGChangePrivacySettingsFutureActionType:
            return TGChangePrivacySettingsFutureActionDeserializer;
        case TGChangePeerBlockStatusFutureActionType:
            return TGChangePeerBlockStatusFutureActionDeserializer;
        case TGUploadAvatarFutureActionType:
            return TGUploadAvatarFutureActionDeserializer;
        case TGDeleteProfilePhotoFutureActionType:
            return TGDeleteProfilePhotoFutureActionDeserializer;
        case TGRemoveContactFutureActionType:
            return TGRemoveContactFutureActionDeserializer;
        case TGExportContactFutureActionType:
            return TGExportContactFutureActionDeserializer;
        case TGSynchronizeEncryptedChatSettingsFutureActionType:
            return TGSynchronizeEncryptedChatSettingsFutureActionDeserializer;
        case TGAcceptEncryptionFutureActionType:
            return TGAcceptEncryptionFutureActionDeserializer;
        default:
            break;
    }
    
    return nil;
}

@interface TGDatabase ()
{
    TG_SYNCHRONIZED_DEFINE(_userByUid);
    TG_SYNCHRONIZED_DEFINE(_contactsByPhoneId);
    TG_SYNCHRONIZED_DEFINE(_phonebookContacts);
    TG_SYNCHRONIZED_DEFINE(_mutedPeers);
    TG_SYNCHRONIZED_DEFINE(_nextLocalMid);
    TG_SYNCHRONIZED_DEFINE(_userLinks);
    TG_SYNCHRONIZED_DEFINE(_cachedUnreadCount);
    TG_SYNCHRONIZED_DEFINE(_unreadCountByConversation);
    TG_SYNCHRONIZED_DEFINE(_minAutosaveMessageIdForConversations);
    TG_SYNCHRONIZED_DEFINE(_containsConversation);
    TG_SYNCHRONIZED_DEFINE(_remoteContactUids);
    TG_SYNCHRONIZED_DEFINE(_peerCustomSettings);
    TG_SYNCHRONIZED_DEFINE(_encryptedConversationIds);
    TG_SYNCHRONIZED_DEFINE(_conversationEncryptionKeys);
    TG_SYNCHRONIZED_DEFINE(_encryptedParticipantIds);
    TG_SYNCHRONIZED_DEFINE(_encryptedConversationAccessHash);
    TG_SYNCHRONIZED_DEFINE(_messageLifetimeByPeerId);
    
    std::tr1::unordered_map<int, TGUser *> _userByUid;
    std::map<int, TGContactBinding *> _contactsByPhoneId;
    std::map<int, int> _phoneIdByUid;
    std::set<int> _remoteContactUids;
    
    std::map<int, TGPhonebookContact *> _phonebookContacts;
    std::map<int, int> _phoneIdToNativeId;
    
    std::map<int64_t, int> _mutedPeers;
    
    std::map<int64_t, int> _minAutosaveMessageIdForConversations;
    
    std::map<int, std::pair<int, int> > _userLinks;
    
    std::map<int64_t, int> _unreadCountByConversation;
    std::set<int64_t> _containsConversation;
    int _cachedUnreadCount;
    
    std::map<int64_t, TGPeerCustomSettings> _peerCustomSettings;
    
    std::map<int64_t, int64_t> _encryptedConversationIds;
    std::map<int64_t, int64_t> _peerIdsForEncryptedConversationIds;
    std::map<int64_t, std::pair<int64_t, NSData *> > _conversationEncryptionKeys;
    std::map<int64_t, int32_t> _encryptedParticipantIds;
    std::map<int64_t, int64_t> _encryptedConversationAccessHash;
    std::map<int64_t, int32_t> _messageLifetimeByPeerId;
}

@property (nonatomic, strong) NSString *databasePath;
@property (nonatomic, strong) NSString *indexDatabasePath;

@property (nonatomic, strong) FMDatabase *database;
@property (nonatomic, strong) FMDatabase *indexDatabase;
@property (nonatomic, strong) FMDatabase *filesDatabase;

@property (nonatomic) TGDatabaseState cachedDatabaseState;

@property (nonatomic) int schemaVersion;
@property (nonatomic, strong) NSString *serviceTableName;
@property (nonatomic, strong) NSString *usersTableName;
@property (nonatomic, strong) NSString *conversationListTableName;
@property (nonatomic, strong) NSString *messagesTableName;
@property (nonatomic, strong) NSString *conversationMediaTableName;
@property (nonatomic, strong) NSString *conversationsStatesTableName;
@property (nonatomic, strong) NSString *contactListTableName;
@property (nonatomic, strong) NSString *actionQueueTableName;
@property (nonatomic, strong) NSString *peerPropertiesTableName;
@property (nonatomic, strong) NSString *peerProfilePhotosTableName;
@property (nonatomic, strong) NSString *outgoingMessagesTableName;
@property (nonatomic, strong) NSString *futureActionsTableName;

@property (nonatomic, strong) NSString *assetsTableName;
@property (nonatomic, strong) NSString *videosTableName;
@property (nonatomic, strong) NSString *localFilesTableName;

@property (nonatomic, strong) NSString *serverAssetsTableName;

@property (nonatomic, strong) NSString *blockedUsersTableName;
@property (nonatomic, strong) NSString *userLinksTableName;

@property (nonatomic, strong) NSString *temporaryMessageIdsTableName;
@property (nonatomic, strong) NSString *randomIdsTableName;
@property (nonatomic, strong) NSString *selfDestructTableName;

@property (nonatomic, strong) NSString *encryptedConversationIdsTableName;

@property (nonatomic, strong) NSString *messageIndexTableName;

@property (nonatomic) int serviceLastCleanTimeKey;
@property (nonatomic) int serviceLastMidKey;
@property (nonatomic) int servicePtsKey;
@property (nonatomic) int serviceContactListStateKey;
@property (nonatomic) int serviceLatestSynchronizedMidKey;
@property (nonatomic) int serviceLatestSynchronizedQtsKey;
@property (nonatomic) int serviceEncryptedConversationCount;

@property (nonatomic) int nextLocalMid;

@property (nonatomic) int localUserId;
@property (nonatomic) bool contactListPreloaded;

@property (nonatomic) int userLinksVersion;

@property (nonatomic, strong) TGTimer *selfDestructTimer;

- (void)initDatabase;

@end

TGDatabase *TGDatabaseInstance()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        TGDatabaseSingleton = [[TGDatabase alloc] init];
        
        [TGDatabaseSingleton dispatchOnDatabaseThread:^
        {
            [TGDatabaseSingleton initDatabase];
        } synchronous:false];
    });
    
    return TGDatabaseSingleton;
}

@implementation TGDatabase

+ (void)setDatabaseName:(NSString *)name
{
    databaseName = name;
}

+ (void)setLiveMessagesDispatchPath:(NSString *)path
{
    _liveMessagesDispatchPath = path;
}

+ (void)setLiveUnreadCountDispatchPath:(NSString *)path
{
    _liveUnreadCountDispatchPath = path;
}

+ (TGDatabase *)instance
{
    return TGDatabaseInstance();
}

- (dispatch_queue_t)databaseQueue
{
    if (databaseDispatchQueue == NULL)
    {
        databaseDispatchQueue = dispatch_queue_create("com.actionstage.databasequeue", 0);
        
        if (dispatch_queue_set_specific != NULL)
        {
            dispatch_queue_set_specific(databaseDispatchQueue, databaseQueueSpecific, (void *)databaseQueueSpecific, NULL);
        }
    }
    return databaseDispatchQueue;
}

- (bool)isCurrentQueueDatabaseQueue
{
    if (dispatch_get_specific != NULL)
    {
        return dispatch_get_specific(databaseQueueSpecific) != NULL;
    }
    else
    {
        dispatch_queue_t queue = dispatch_get_current_queue();
        if (queue == [self databaseQueue])
            return true;
    }
    
    return false;
}

- (dispatch_queue_t)databaseIndexQueue
{
    if (databaseIndexDispatchQueue == NULL)
    {
        databaseIndexDispatchQueue = dispatch_queue_create("com.actionstage.databaseindexqueue", 0);
        
        if (dispatch_queue_set_specific != NULL)
        {
            dispatch_queue_set_specific(databaseIndexDispatchQueue, databaseIndexQueueSpecific, (void *)databaseIndexQueueSpecific, NULL);
        }
    }
    return databaseIndexDispatchQueue;
}

- (bool)isCurrentQueueDatabaseIndexQueue
{
    if (dispatch_get_specific != NULL)
    {
        return dispatch_get_specific(databaseIndexQueueSpecific) != NULL;
    }
    else
    {
        dispatch_queue_t queue = dispatch_get_current_queue();
        if (queue == [self databaseIndexQueue])
            return true;
    }
    
    return false;
}

- (dispatch_queue_t)filesQueue
{
    if (filesDispatchQueue == NULL)
    {
        filesDispatchQueue = dispatch_queue_create("com.actionstage.filesqueue", 0);
        
        if (dispatch_queue_set_specific != NULL)
        {
            dispatch_queue_set_specific(filesDispatchQueue, filesQueueSpecific, (void *)filesQueueSpecific, NULL);
        }
    }
    return filesDispatchQueue;
}

- (bool)isCurrentQueueFilesQueue
{
    if (dispatch_get_specific != NULL)
    {
        return dispatch_get_specific(filesQueueSpecific) != NULL;
    }
    else
    {
        dispatch_queue_t queue = dispatch_get_current_queue();
        if (queue == [self filesQueue])
            return true;
    }
    
    return false;
}

#ifdef DEBUG_DATABASE_INVOKATIONS
- (void)dispatchOnDatabaseThreadDebug:(const char *)file line:(int)line block:(dispatch_block_t)block synchronous:(bool)synchronous
#else
- (void)dispatchOnDatabaseThread:(dispatch_block_t)block synchronous:(bool)synchronous
#endif
{
    if ([self isCurrentQueueDatabaseQueue])
    {
        @autoreleasepool
        {
            block();
        }
    }
    else
    {
        if (synchronous)
        {
            dispatch_sync([self databaseQueue], ^
            {
                @autoreleasepool
                {
                    block();
                }
            });
        }
        else
        {
            dispatch_async([self databaseQueue], ^
            {
                @autoreleasepool
                {
                    block();
                }
            });
        }
    }
}

- (void)dispatchOnIndexThread:(dispatch_block_t)block synchronous:(bool)synchronous
{
    if ([self isCurrentQueueDatabaseIndexQueue])
    {
        @autoreleasepool
        {
            block();
        }
    }
    else
    {
        if (synchronous)
        {
            dispatch_sync([self databaseIndexQueue], ^
            {
                @autoreleasepool
                {
                    block();
                }
            });
        }
        else
        {
            dispatch_async([self databaseIndexQueue], ^
            {
                @autoreleasepool
                {
                    block();
                }
            });
        }
    }
}

- (void)dispatchOnFilesThread:(dispatch_block_t)block synchronous:(bool)synchronous
{
    if ([self isCurrentQueueFilesQueue])
    {
        @autoreleasepool
        {
            block();
        }
    }
    else
    {
        if (synchronous)
        {
            dispatch_sync([self filesQueue], ^
            {
                @autoreleasepool
                {
                    block();
                }
            });
        }
        else
        {
            dispatch_async([self filesQueue], ^
            {
                @autoreleasepool
                {
                    block();
                }
            });
        }
    }
}

static void addVideoMid(TGDatabase *database, int mid, int64_t videoId, bool isLocal)
{
    NSString *tableName = isLocal ? database.localFilesTableName : database.videosTableName;
    
    FMResultSet *result = [database.database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mids FROM %@ WHERE vid=?", tableName], [[NSNumber alloc] initWithLongLong:videoId]];
    if ([result next])
    {
        bool found = false;
        
        NSMutableData *midsData = [[result dataForColumn:@"mids"] mutableCopy];
        int *mids = (int *)[midsData bytes];
        int numMids = midsData.length / 4;
        for (int i = 0; i < numMids; i++)
        {
            if (mids[i] == mid)
            {
                found = true;
                break;
            }
        }
        
        if (!found)
        {
            [midsData appendBytes:&mid length:4];
            [database.database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET mids=? WHERE vid=?", tableName], midsData, [[NSNumber alloc] initWithLongLong:videoId]];
        }
    }
    else
    {
        [database.database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT INTO %@ (vid, mids) VALUES(?, ?)", tableName], [[NSNumber alloc] initWithLongLong:videoId], [[NSData alloc] initWithBytes:&mid length:4]];
    }
}

static void removeVideoMid(TGDatabase *database, int mid, int64_t videoId, bool isLocal)
{
    NSString *tableName = isLocal ? database.localFilesTableName : database.videosTableName;
    
    FMResultSet *result = [database.database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mids FROM %@ WHERE vid=?", tableName], [[NSNumber alloc] initWithLongLong:videoId]];
    if ([result next])
    {
        NSMutableData *midsData = [[result dataForColumn:@"mids"] mutableCopy];
        int *mids = (int *)[midsData bytes];
        int numMids = midsData.length / 4;
        for (int i = 0; i < numMids; i++)
        {
            if (mids[i] == mid)
            {
                [midsData replaceBytesInRange:NSMakeRange(i * 4, 4) withBytes:NULL length:0];
                break;
            }
        }
        
        if (midsData.length == 0)
        {
            [database.database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE vid=?", tableName], [[NSNumber alloc] initWithLongLong:videoId]];
            
            dispatch_async([TGCache diskCacheQueue], ^
            {
                static NSString *videosPath = nil;
                if (videosPath == nil)
                {
                    videosPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true) objectAtIndex:0] stringByAppendingPathComponent:@"video"];
                }
                
                if (isLocal)
                {
                    [[TGCache diskFileManager] removeItemAtPath:[videosPath stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"local%llx.mov", videoId]] error:nil];
                }
                else
                {
                    [[TGCache diskFileManager] removeItemAtPath:[videosPath stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"remote%llx.mov", videoId]] error:nil];
                    [[TGCache diskFileManager] removeItemAtPath:[videosPath stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"remote%llx.mp4", videoId]] error:nil];
                    [[TGCache diskFileManager] removeItemAtPath:[videosPath stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"remote%llx.part", videoId]] error:nil];
                }
            });
        }
        else
        {
            [database.database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET mids=? WHERE vid=?", tableName], midsData, [[NSNumber alloc] initWithLongLong:videoId]];
        }
    }
}

static void cleanupMessage(TGDatabase *database, int mid, NSArray *attachments, TGDatabaseMessageCleanupBlock cleanupBlock)
{
    for (TGMediaAttachment *attachment in attachments)
    {
        if ([attachment isKindOfClass:[TGVideoMediaAttachment class]])
        {
            TGVideoMediaAttachment *videoAttachment = (TGVideoMediaAttachment *)attachment;
            
            if (videoAttachment.videoId != 0)
                removeVideoMid(database, mid, videoAttachment.videoId, false);
            else if (videoAttachment.localVideoId != 0)
                removeVideoMid(database, mid, videoAttachment.localVideoId, true);
        }
        
        if (cleanupBlock)
            cleanupBlock((TGMediaAttachment *)attachment);
    }
}

- (id)init
{
    self = [super init];
    if (self != nil)
    {
        TG_SYNCHRONIZED_INIT(_userByUid);
        TG_SYNCHRONIZED_INIT(_contactsByPhoneId);
        TG_SYNCHRONIZED_INIT(_phonebookContacts);
        TG_SYNCHRONIZED_INIT(_mutedPeers);
        TG_SYNCHRONIZED_INIT(_minAutosaveMessageIdForConversations);
        TG_SYNCHRONIZED_INIT(_nextLocalMid);
        TG_SYNCHRONIZED_INIT(_userLinks);
        TG_SYNCHRONIZED_INIT(_cachedUnreadCount);
        TG_SYNCHRONIZED_INIT(_unreadCountByConversation);
        TG_SYNCHRONIZED_INIT(_containsConversation);
        TG_SYNCHRONIZED_INIT(_remoteContactUids);
        TG_SYNCHRONIZED_INIT(_peerCustomSettings);
        TG_SYNCHRONIZED_INIT(_encryptedConversationIds);
        TG_SYNCHRONIZED_INIT(_conversationEncryptionKeys);
        TG_SYNCHRONIZED_INIT(_encryptedParticipantIds);
        TG_SYNCHRONIZED_INIT(_encryptedConversationAccessHash);
        TG_SYNCHRONIZED_INIT(_messageLifetimeByPeerId);
        
        _userLinksVersion = 1;
        
        _schemaVersion = 29;
        
        _cachedUnreadCount = INT_MIN;
        
        _databasePath = [[self documentsPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.db", (databaseName == nil ? @"tgdatabasedata" : databaseName)]];
        _indexDatabasePath = [[self documentsPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_index.db", (databaseName == nil ? @"tgdatabasedata" : databaseName)]];
        
        _serviceLastCleanTimeKey = [@"lastCleanTime" hash];
        _servicePtsKey = [@"pts" hash];
        _serviceLastMidKey = [@"lastMid" hash];
        _serviceContactListStateKey = [@"contactListState" hash];
        _serviceLatestSynchronizedMidKey = [@"latestSynchronizedMid" hash];
        _serviceLatestSynchronizedQtsKey = [@"latestSynchronizedQts" hash];
        _serviceEncryptedConversationCount = [@"serviceEncryptedConversationCount" hash];
        
        _serviceTableName = [NSString stringWithFormat:@"service_v%d", _schemaVersion];
        _usersTableName = [NSString stringWithFormat:@"users_v%d", _schemaVersion];
        _conversationListTableName = [NSString stringWithFormat:@"convesations_v%d", _schemaVersion];
        _messagesTableName = [NSString stringWithFormat:@"messages_v%d", _schemaVersion];
        _conversationMediaTableName = [NSString stringWithFormat:@"media_v%d", _schemaVersion];
        _conversationsStatesTableName = [NSString stringWithFormat:@"cstates_v%d", _schemaVersion];
        _contactListTableName = [NSString stringWithFormat:@"contacts_v%d", _schemaVersion];
        _actionQueueTableName = [NSString stringWithFormat:@"actions_v%d", _schemaVersion];
        _peerPropertiesTableName = [NSString stringWithFormat:@"peers_v%d", _schemaVersion];
        _peerProfilePhotosTableName = [NSString stringWithFormat:@"peer_photos_v%d", _schemaVersion];
        _outgoingMessagesTableName = [NSString stringWithFormat:@"outbox_v%d", _schemaVersion];
        _futureActionsTableName = [NSString stringWithFormat:@"future_v%d", _schemaVersion];
        _messageIndexTableName = [NSString stringWithFormat:@"messageIndex_v%d", _schemaVersion];
        
        _assetsTableName = [NSString stringWithFormat:@"assets_v%d", _schemaVersion];
        _videosTableName = [[NSString alloc] initWithFormat:@"files_v%d", _schemaVersion];
        _localFilesTableName = [[NSString alloc] initWithFormat:@"local_files_v%d", _schemaVersion];
        
        _serverAssetsTableName = [[NSString alloc] initWithFormat:@"server_assets_v%d", _schemaVersion];
        
        _blockedUsersTableName = [NSString stringWithFormat:@"blacklist_v%d", _schemaVersion];
        _userLinksTableName = [NSString stringWithFormat:@"links_v%d", _schemaVersion];
        
        _temporaryMessageIdsTableName = [NSString stringWithFormat:@"tempMessages_v%d", _schemaVersion];
        _randomIdsTableName = [[NSString alloc] initWithFormat:@"random_ids_v%d", _schemaVersion];
        _selfDestructTableName = [[NSString alloc] initWithFormat:@"selfdestruct_v%d", _schemaVersion];
        
        _encryptedConversationIdsTableName = [NSString stringWithFormat:@"encrypted_cids_v%d", _schemaVersion];
    }
    return self;
}

- (void)explainQuery:(NSString *)query
{
    FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"EXPLAIN QUERY PLAN %@", query]];
    while ([result next])
    {
        TGLog(@"%d %d %d :: %@", [result intForColumnIndex:0], [result intForColumnIndex:1], [result intForColumnIndex:2],
              [result stringForColumnIndex:3]);
    }
}

- (NSString *)documentsPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = [paths objectAtIndex:0];
    return documentsPath;
}

- (void)upgradeTables
{
    //[_database executeUpdate:[[NSString alloc] initWithFormat:@"DROP TABLE %@", _selfDestructTableName]];
    for (int i = _schemaVersion - 2; i < _schemaVersion + 2; i++)
    {
        if (i != _schemaVersion)
        {
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"service_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"users_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"convesations_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"messages_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"media_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"cstates_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"contacts_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"actions_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"peers_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"peer_photos_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"outbox_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"future_v%d", i]]];
            
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"assets_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"files_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"local_files_v%d", i]]];
            
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"server_assets_v%d", i]]];
            
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"blacklist_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"links_v%d", i]]];
            
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"tempMessages_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"random_ids_v%d", i]]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"selfdestruct_v%d", i]]];
            
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"encrypted_cids_%d", i]]];
        }
    }
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (key INTEGER PRIMARY KEY, value BLOB)", _serviceTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (uid INTEGER PRIMARY KEY, first_name TEXT, last_name TEXT, local_first_name TEXT, local_last_name TEXT, phone_number TEXT, access_hash INTEGER, sex INTEGER, photo_small TEXT, photo_medium TEXT, photo_big TEXT, last_seen INTEGER)", _usersTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (cid INTEGER PRIMARY KEY, date INTEGER, from_uid INTEGER, message TEXT, media BLOB, unread_count INTEGER, flags INTEGER, chat_title TEXT, chat_photo BLOB, participants BLOB, participants_count INTEGER, chat_version INTEGER, service_unread INTEGER)", _conversationListTableName]];
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS date ON %@ (date DESC)", _conversationListTableName]];
    
    FMResultSet *serviceUnreadResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT service_unread FROM %@ LIMIT 1", _conversationListTableName]];
    if (![serviceUnreadResult next])
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"ALTER TABLE %@ ADD COLUMN service_unread INTEGER", _conversationListTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (mid INTEGER PRIMARY KEY, cid INTEGER, localMid INTEGER, message TEXT, media BLOB, from_id INTEGER, to_id INTEGER, outgoing INTEGER, unread INTEGER, dstate INTEGER, date INTEGER)", _messagesTableName]];
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS cid ON %@ (cid)", _messagesTableName]];
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS cid_date ON %@ (cid, date)", _messagesTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (cid INTEGER PRIMARY KEY, message_text TEXT)", _conversationsStatesTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (uid INTEGER PRIMARY KEY)", _contactListTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (action_type INTEGER, action_subject INTEGER, arg0 INTEGER, arg1 INTEGER, PRIMARY KEY(action_type, action_subject))", _actionQueueTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (mid INTEGER PRIMARY KEY, cid INTEGER, date INTEGER, from_id INTEGER, type INTEGER, media BLOB)", _conversationMediaTableName]];
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS cid_date_idx ON %@ (cid, date DESC)", _conversationMediaTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (pid INTEGER PRIMARY KEY, last_mid INTEGER, last_media INTEGER, notification_type INTEGER, mute INTEGER, preview_text INTEGER, custom_properties BLOB)", _peerPropertiesTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (photo_id INTEGER PRIMARY KEY, peer_id INTEGER, date INTEGER, data BLOB)", _peerProfilePhotosTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (mid INTEGER PRIMARY KEY, cid INTEGER, dstate INTEGER, local_media_id INTEGER)", _outgoingMessagesTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (id INTEGER, type INTEGER, data BLOB, insert_date INTEGER, random_id INTEGER, PRIMARY KEY(id, type))", _futureActionsTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (hash_high INTEGER, hash_low INTEGER, PRIMARY KEY(hash_high, hash_low))", _assetsTableName]];
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (vid INTEGER PRIMARY KEY, mids BLOB)", _videosTableName]];
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (vid INTEGER PRIMARY KEY, mids BLOB, remote_data BLOB)", _localFilesTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (hash_high INTEGER, hash_low INTEGER, data BLOB, PRIMARY KEY(hash_high, hash_low))", _serverAssetsTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (pid INTEGER, date INTEGER)", _blockedUsersTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (pid INTEGER PRIMARY KEY, link INTEGER)", _userLinksTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (tmp_id INTEGER PRIMARY KEY, mid INTEGER)", _temporaryMessageIdsTableName]];
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (random_id INTEGER PRIMARY KEY, mid INTEGER)", _randomIdsTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (mid INTEGER PRIMARY KEY, date INTEGER)", _selfDestructTableName]];
    [_database executeUpdate:[[NSString alloc] initWithFormat:@"CREATE INDEX IF NOT EXISTS selfdestruct_date ON %@ (date)", _selfDestructTableName]];
    
    [_database executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (encrypted_id INTEGER PRIMARY KEY, cid INTEGER)", _encryptedConversationIdsTableName]];
    
    [self dispatchOnIndexThread:^
    {
        for (int i = _schemaVersion - 2; i < _schemaVersion + 2; i++)
        {
            if (i != _schemaVersion)
            {
                [_indexDatabase executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [NSString stringWithFormat:@"messageIndex_v%d", i]]];
            }
        }
        
        [_indexDatabase executeUpdate:[NSString stringWithFormat:@"CREATE VIRTUAL TABLE IF NOT EXISTS %@ USING fts4(text TEXT, matchinfo=fts3)", _messageIndexTableName]];
    } synchronous:false];
}

- (void)initDatabase
{
    _database = [FMDatabase databaseWithPath:_databasePath];
    
    if (![_database open])
    {
        NSLog(@"***** Error: couldn't open database! *****");
        [[[NSFileManager alloc] init] removeItemAtPath:_databasePath error:nil];
        
        [self initDatabase];
        
        return;
    }    
    
    [_database setShouldCacheStatements:true];
    [_database setLogsErrors:true];
    
    sqlite3_exec([_database sqliteHandle], "PRAGMA encoding=\"UTF-8\"", NULL, NULL, NULL);
    sqlite3_exec([_database sqliteHandle], "PRAGMA synchronous=NORMAL", NULL, NULL, NULL);
    sqlite3_exec([_database sqliteHandle], "PRAGMA journal_mode=MEMORY", NULL, NULL, NULL);
    sqlite3_exec([_database sqliteHandle], "PRAGMA temp_store=MEMORY", NULL, NULL, NULL);
    
    [self dispatchOnIndexThread:^
    {
        _indexDatabase = [FMDatabase databaseWithPath:_indexDatabasePath];
        if (![_indexDatabase open])
        {
            NSLog(@"***** Error: couldn't open index database! *****");
            [[[NSFileManager alloc] init] removeItemAtPath:_indexDatabasePath error:nil];
        }
        else
        {
            [_indexDatabase setShouldCacheStatements:true];
            [_indexDatabase setLogsErrors:true];
            
            sqlite3_exec([_indexDatabase sqliteHandle], "PRAGMA encoding=\"UTF-8\"", NULL, NULL, NULL);
            sqlite3_exec([_indexDatabase sqliteHandle], "PRAGMA synchronous=NORMAL", NULL, NULL, NULL);
            sqlite3_exec([_indexDatabase sqliteHandle], "PRAGMA journal_mode=MEMORY", NULL, NULL, NULL);
            sqlite3_exec([_indexDatabase sqliteHandle], "PRAGMA temp_store=MEMORY", NULL, NULL, NULL);
        }
    } synchronous:false];
    
    [self upgradeTables];
}

- (void)closeDatabase
{
    [self dispatchOnDatabaseThread:^
    {
        [_database close];
    } synchronous:true];
    
    [self dispatchOnIndexThread:^
    {
        [_indexDatabase close];
    } synchronous:true];
}

- (void)dropDatabase
{
    [self dropDatabase:true];
}

- (void)dropDatabase:(bool)fullDrop
{
    [self dispatchOnDatabaseThread:^
    {
        if (fullDrop)
        {
            [[NSFileManager defaultManager] removeItemAtPath:_databasePath error:nil];
            
            [self dispatchOnIndexThread:^
            {
                [[NSFileManager defaultManager] removeItemAtPath:_indexDatabasePath error:nil];
            } synchronous:false];
            
            [self initDatabase];
        }
        else
        {
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _serviceTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _usersTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _conversationListTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _messagesTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _conversationMediaTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _conversationsStatesTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _contactListTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _actionQueueTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _peerPropertiesTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _peerProfilePhotosTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _outgoingMessagesTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _futureActionsTableName]];
            
            //[_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _assetsTableName]];
            
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"DROP TABLE IF EXISTS %@", _serverAssetsTableName]];
            
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _videosTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _localFilesTableName]];
            
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _blockedUsersTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _userLinksTableName]];
            
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _temporaryMessageIdsTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _randomIdsTableName]];
            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _selfDestructTableName]];

            [_database executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _encryptedConversationIdsTableName]];
            
            [self dispatchOnIndexThread:^
            {
                [_indexDatabase executeUpdate:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", _messageIndexTableName]];
            } synchronous:false];
        }
        
        if (_cleanupEverythingBlock)
            _cleanupEverythingBlock();

        TG_SYNCHRONIZED_BEGIN(_cachedUnreadCount);
        _cachedUnreadCount = 0;
        TG_SYNCHRONIZED_END(_cachedUnreadCount);

        _cachedDatabaseState.pts = 0;
        _cachedDatabaseState.date = 0;
        _cachedDatabaseState.seq = 0;
        _cachedDatabaseState.unreadCount = 0;
        
        if (_liveUnreadCountDispatchPath != nil)
        {
            [ActionStageInstance() dispatchOnStageQueue:^
            {
                [ActionStageInstance() dispatchResource:_liveUnreadCountDispatchPath resource:[[SGraphObjectNode alloc] initWithObject:[[NSNumber alloc] initWithInt:0]]];
            }];
        }
        
        TG_SYNCHRONIZED_BEGIN(_mutedPeers);
        _mutedPeers.clear();
        TG_SYNCHRONIZED_END(_mutedPeers);
        
        TG_SYNCHRONIZED_BEGIN(_userByUid);
        _userByUid.clear();
        TG_SYNCHRONIZED_END(_userByUid);

        TG_SYNCHRONIZED_BEGIN(_contactsByPhoneId);
        _contactsByPhoneId.clear();
        TG_SYNCHRONIZED_END(_contactsByPhoneId);
        
        TG_SYNCHRONIZED_BEGIN(_phonebookContacts);
        _phonebookContacts.clear();
        TG_SYNCHRONIZED_END(_phonebookContacts);
        
        TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
        _unreadCountByConversation.clear();
        TG_SYNCHRONIZED_END(_unreadCountByConversation);
        
        TG_SYNCHRONIZED_BEGIN(_containsConversation);
        _containsConversation.clear();
        TG_SYNCHRONIZED_END(_containsConversation);
        
        TG_SYNCHRONIZED_BEGIN(_remoteContactUids);
        _remoteContactUids.clear();
        TG_SYNCHRONIZED_END(_remoteContactUids);
        
        TG_SYNCHRONIZED_BEGIN(_peerCustomSettings);
        _peerCustomSettings.clear();
        TG_SYNCHRONIZED_END(_peerCustomSettings);
        
        TG_SYNCHRONIZED_BEGIN(_encryptedConversationIds);
        _encryptedConversationIds.clear();
        _peerIdsForEncryptedConversationIds.clear();
        TG_SYNCHRONIZED_END(_encryptedConversationIds);
        
        TG_SYNCHRONIZED_BEGIN(_conversationEncryptionKeys);
        _conversationEncryptionKeys.clear();
        TG_SYNCHRONIZED_END(_conversationEncryptionKeys);
        
        TG_SYNCHRONIZED_BEGIN(_encryptedParticipantIds);
        _encryptedParticipantIds.clear();
        TG_SYNCHRONIZED_END(_encryptedParticipantIds);
        
        TG_SYNCHRONIZED_BEGIN(_encryptedConversationAccessHash);
        _encryptedConversationAccessHash.clear();
        TG_SYNCHRONIZED_END(_encryptedConversationAccessHash);
        
        TG_SYNCHRONIZED_BEGIN(_messageLifetimeByPeerId);
        _messageLifetimeByPeerId.clear();
        TG_SYNCHRONIZED_END(_messageLifetimeByPeerId);
        
        [self clearCachedUserLinks];
        
        _nextLocalMid = 0;
        
        [self upgradeTables];
    } synchronous:false];
}

inline static void storeUserToDatabase(TGDatabase *instance, FMDatabase *database, TGUser *user)
{
    static NSString *queryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (uid, first_name, last_name, local_first_name, local_last_name, phone_number, access_hash, sex, photo_small, photo_medium, photo_big, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", instance.usersTableName];
    
    [database executeUpdate:queryFormat, [[NSNumber alloc] initWithInt:user.uid], user.realFirstName, user.realLastName, user.phonebookFirstName, user.phonebookLastName, user.phoneNumber, [[NSNumber alloc] initWithLongLong:user.phoneNumberHash], [[NSNumber alloc] initWithInt:user.sex], user.photoUrlSmall, user.photoUrlMedium, user.photoUrlBig, [[NSNumber alloc] initWithInt:((int)user.presence.lastSeen)]];
}

inline static TGUser *loadUserFromDatabase(FMResultSet *result)
{
    TGUser *user = [[TGUser alloc] init];
    
    user.uid = [result intForColumn:@"uid"];
    user.firstName = [result stringForColumn:@"first_name"];
    user.lastName = [result stringForColumn:@"last_name"];
    user.phonebookFirstName = [result stringForColumn:@"local_first_name"];
    user.phonebookLastName = [result stringForColumn:@"local_last_name"];
    user.phoneNumber = [result stringForColumn:@"phone_number"];
    user.phoneNumberHash = [result longLongIntForColumn:@"access_hash"];
    user.sex = (TGUserSex)[result intForColumn:@"sex"];
    user.photoUrlSmall = [result stringForColumn:@"photo_small"];
    user.photoUrlMedium = [result stringForColumn:@"photo_medium"];
    user.photoUrlBig = [result stringForColumn:@"photo_big"];
    TGUserPresence presence;
    presence.online = false;
    presence.lastSeen = [result intForColumn:@"last_seen"];
    user.presence = presence;
    
    return user;
}

- (void)storeUsers:(NSArray *)userList
{
    TG_SYNCHRONIZED_BEGIN(_userByUid);
    {
        for (TGUser *user in userList)
        {
            _userByUid[user.uid] = user;
            if (user.contactId != 0)
                _phoneIdByUid.insert(std::pair<int, int>(user.uid, user.contactId));
        }
    }
    TG_SYNCHRONIZED_END(_userByUid);
    
    [self dispatchOnDatabaseThread:^
    {
        [_database beginTransaction];
        FMDatabase *database = _database;
        for (TGUser *user in userList)
        {
            storeUserToDatabase(self, database, user);
        }
        [_database commit];
    } synchronous:false];
}

- (void)storeUsersPresences:(std::map<int, TGUserPresence> *)presenceMap
{
    NSMutableArray *usersToStore = nil;
    std::tr1::shared_ptr<std::map<int, TGUserPresence> > unloadedUsersPresenceMap;
    
    TG_SYNCHRONIZED_BEGIN(_userByUid);
    {
        for (std::map<int, TGUserPresence>::iterator it = presenceMap->begin(); it != presenceMap->end(); it++)
        {
            std::tr1::unordered_map<int, TGUser *>::iterator userIt = _userByUid.find(it->first);
            if (userIt != _userByUid.end())
            {
                bool lastSeenChanged = userIt->second.presence.lastSeen != it->second.lastSeen;
                if (lastSeenChanged || userIt->second.presence.online != it->second.online)
                {
                    TGUser *newUser = [userIt->second copy];
                    newUser.presence = it->second;
                    _userByUid[newUser.uid] = newUser;
                    
                    if (lastSeenChanged)
                    {
                        if (usersToStore == nil)
                            usersToStore = [[NSMutableArray alloc] init];
                        [usersToStore addObject:newUser];
                    }
                }
            }
            else
            {
                if (unloadedUsersPresenceMap == NULL)
                    unloadedUsersPresenceMap = std::tr1::shared_ptr<std::map<int, TGUserPresence> >(new std::map<int, TGUserPresence>());
                
                unloadedUsersPresenceMap->insert(std::pair<int, TGUserPresence>(it->first, it->second));
            }
        }
    }
    TG_SYNCHRONIZED_END(_userByUid);
    
    if (unloadedUsersPresenceMap != NULL && !unloadedUsersPresenceMap->empty())
    {
        [self dispatchOnDatabaseThread:^
        {
            NSString *queryFormat = [NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET last_seen=? WHERE uid=? LIMIT 1", _usersTableName];
            
            for (std::map<int, TGUserPresence>::iterator it = unloadedUsersPresenceMap->begin(); it != unloadedUsersPresenceMap->end(); it++)
            {
                [_database executeQuery:queryFormat, [[NSNumber alloc] initWithInt:it->second.lastSeen], [[NSNumber alloc] initWithInt:it->first]];
            }
        } synchronous:false];
    }
    
    if (usersToStore != nil && usersToStore.count != 0)
    {
        [self dispatchOnDatabaseThread:^
        {
            [_database beginTransaction];
            FMDatabase *database = _database;
            for (TGUser *user in usersToStore)
            {
                storeUserToDatabase(self, database, user);
            }
            [_database commit];
        } synchronous:false];
    }
}

- (void)setLocalUserId:(int)localUserId
{
    [self dispatchOnDatabaseThread:^
    {
        _localUserId = localUserId;
    } synchronous:false];
}

- (TGUser *)loadUser:(int)uid
{
    __block TGUser *user = nil;
    
    TG_SYNCHRONIZED_BEGIN(_userByUid);
    {
        std::tr1::unordered_map<int, TGUser *>::iterator it = _userByUid.find(uid);
        if (it != _userByUid.end())
        {
            user = [it->second copy];
        }
    }
    TG_SYNCHRONIZED_END(_userByUid);
    
    if (user == nil)
    {
        [self dispatchOnDatabaseThread:^
        {
             FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE uid=?", _usersTableName], [[NSNumber alloc] initWithInt:uid]];
             if ([result next])
             {
                 user = loadUserFromDatabase(result);
             }
        } synchronous:true];
        
        if (user != nil)
        {
            TG_SYNCHRONIZED_BEGIN(_userByUid);
            {
                _userByUid[user.uid] = user;
                if (user.contactId != 0)
                    _phoneIdByUid.insert(std::pair<int, int>(uid, user.contactId));
            }
            TG_SYNCHRONIZED_END(_userByUid);
            
            if (uid == _localUserId)
            {
                user.phonebookFirstName = nil;
                user.phonebookLastName = nil;
            }
            else if (user.contactId != 0)
            {
                TGContactBinding *binding = [self contactBindingWithId:user.contactId];
                if (binding != nil)
                {
                    user.phonebookFirstName = binding.firstName;
                    user.phonebookLastName = binding.lastName;
                }
                else if (_contactListPreloaded)
                {
                    user.phonebookFirstName = nil;
                    user.phonebookLastName = nil;
                }
            }
            else if (_contactListPreloaded)
            {
                user.phonebookFirstName = nil;
                user.phonebookLastName = nil;
            }
        }
    }
    
    return user;
}

- (int)loadCachedPhoneIdByUid:(int)uid
{
    int contactId = 0;
    
    TG_SYNCHRONIZED_BEGIN(_userByUid);
    {
        std::map<int, int>::iterator it = _phoneIdByUid.find(uid);
        if (it != _phoneIdByUid.end())
            contactId = it->second;
    }
    TG_SYNCHRONIZED_END(_userByUid);
    
    return contactId;
}

- (void)loadCachedUsersWithContactIds:(std::set<int> const &)contactIds resultMap:(std::map<int, TGUser *> &)resultMap
{   
    TG_SYNCHRONIZED_BEGIN(_userByUid);
    {
        for (std::tr1::unordered_map<int, TGUser *>::iterator it = _userByUid.begin(); it != _userByUid.end(); it++)
        {
            if (it->second.phoneNumber.length != 0)
            {
                std::set<int>::iterator contactIdIt = contactIds.find(it->second.contactId);
                if (contactIdIt != contactIds.end())
                {
                    resultMap.insert(std::pair<int, TGUser *>(*contactIdIt, it->second));
                }
            }
        }
    }
    TG_SYNCHRONIZED_END(_userByUid);
}

- (int)loadUsersOnlineCount:(NSArray *)uids alwaysOnlineUid:(int)alwaysOnlineUid
{
    int count = 0;
    
    std::vector<int> unknownUsers;
    
    TG_SYNCHRONIZED_BEGIN(_userByUid);
    for (NSNumber *nUid in uids)
    {
        int uid = [nUid intValue];
        if (uid == alwaysOnlineUid)
        {
            count++;
        }
        else
        {
            std::tr1::unordered_map<int, TGUser *>::iterator userIt = _userByUid.find(uid);
            if (userIt != _userByUid.end())
            {
                if (userIt->second.presence.online)
                    count++;
            }
            else
                unknownUsers.push_back(uid);
        }
    }
    TG_SYNCHRONIZED_END(_userByUid);
    
    if (!unknownUsers.empty())
    {
        __block int blockCount = 0;
        [self dispatchOnDatabaseThread:^
        {
            NSString *queryFormat = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE uid=? LIMIT 1", _usersTableName];
            
            NSMutableArray *foundUsers = [[NSMutableArray alloc] init];
            
            for (std::vector<int>::const_iterator it = unknownUsers.begin(); it != unknownUsers.end(); it++)
            {
                FMResultSet *result = [_database executeQuery:queryFormat, [[NSNumber alloc] initWithInt:*it]];
                if ([result next])
                {
                    TGUser *user = loadUserFromDatabase(result);
                    if (user.uid == _localUserId)
                    {
                        user.phonebookFirstName = nil;
                        user.phonebookLastName = nil;
                    }
                    else if (user.phoneNumber.length != 0)
                    {
                        TGContactBinding *binding = [self contactBindingWithId:user.contactId];
                        if (binding != nil)
                        {
                            user.phonebookFirstName = binding.firstName;
                            user.phonebookLastName = binding.lastName;
                        }
                        else if (_contactListPreloaded)
                        {
                            user.phonebookFirstName = nil;
                            user.phonebookLastName = nil;
                        }
                    }
                    
                    [foundUsers addObject:user];
                }
            }
            
            TG_SYNCHRONIZED_BEGIN(_userByUid);
            for (TGUser *user in foundUsers)
            {
                if (user.presence.online)
                    blockCount++;
                
                _userByUid[user.uid] = user;
                
                if (user.contactId != 0)
                    _phoneIdByUid.insert(std::pair<int, int>(user.uid, user.contactId));
            }
            TG_SYNCHRONIZED_END(_userByUid);
         } synchronous:true];
        
        count += blockCount;
    }
    
    return count;
}

- (std::tr1::shared_ptr<std::map<int, TGUser *> >)loadUsers:(std::vector<int> const &)uidList
{
    std::tr1::shared_ptr<std::map<int, TGUser *> > users(new std::map<int, TGUser *>());
    
    std::vector<int> unknownUsers;
    
    TG_SYNCHRONIZED_BEGIN(_userByUid);
    for (std::vector<int>::const_iterator it = uidList.begin(); it != uidList.end(); it++)
    {
        std::tr1::unordered_map<int, TGUser *>::iterator userIt = _userByUid.find(*it);
        if (userIt != _userByUid.end())
        {
            users->insert(std::pair<int, TGUser *>(*it, userIt->second));
        }
        else
            unknownUsers.push_back(*it);
    }
    TG_SYNCHRONIZED_END(_userByUid);
    
    if (!unknownUsers.empty())
    {
        [self dispatchOnDatabaseThread:^
        {
            NSString *queryFormat = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE uid=? LIMIT 1", _usersTableName];
            
            NSMutableArray *foundUsers = [[NSMutableArray alloc] init];
            
            for (std::vector<int>::const_iterator it = unknownUsers.begin(); it != unknownUsers.end(); it++)
            {   
                FMResultSet *result = [_database executeQuery:queryFormat, [[NSNumber alloc] initWithInt:*it]];
                if ([result next])
                {
                    TGUser *user = loadUserFromDatabase(result);
                    if (user.uid == _localUserId)
                    {
                        user.phonebookFirstName = nil;
                        user.phonebookLastName = nil;
                    }
                    else if (user.phoneNumber.length != 0)
                    {
                        TGContactBinding *binding = [self contactBindingWithId:user.contactId];
                        if (binding != nil)
                        {
                            user.phonebookFirstName = binding.firstName;
                            user.phonebookLastName = binding.lastName;
                        }
                        else if (_contactListPreloaded)
                        {
                            user.phonebookFirstName = nil;
                            user.phonebookLastName = nil;
                        }
                    }
                    
                    [foundUsers addObject:user];
                }
            }
            
            TG_SYNCHRONIZED_BEGIN(_userByUid);
            for (TGUser *user in foundUsers)
            {
                (*users)[user.uid] = user;
                _userByUid[user.uid] = user;
                
                if (user.contactId != 0)
                    _phoneIdByUid.insert(std::pair<int, int>(user.uid, user.contactId));
            }
            TG_SYNCHRONIZED_END(_userByUid);
        } synchronous:true];
    }
    
    return users;
}

- (int)loadUserLink:(int)uid outdated:(bool *)outdated
{
    int link = 0;
    bool foundCached = false;
    bool valueOutdated = false;
    
    TG_SYNCHRONIZED_BEGIN(_userLinks);
    std::map<int, std::pair<int, int> >::iterator it = _userLinks.find(uid);
    if (it != _userLinks.end())
    {
        link = it->second.first;
        valueOutdated = it->second.second != _userLinksVersion;
        foundCached = true;
    }
    TG_SYNCHRONIZED_END(_userLinks);
    
    if (!foundCached)
    {
        valueOutdated = true;
        
        __block int blockLink = 0;
        
        [self dispatchOnDatabaseThread:^
        {
            FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT link FROM %@ WHERE pid=?", _userLinksTableName], [[NSNumber alloc] initWithInt:uid]];
            if ([result next])
            {
                blockLink = [result intForColumn:@"link"];
            }
        } synchronous:true];
        
        link = blockLink;
        
        if (link != 0)
        {
            TG_SYNCHRONIZED_BEGIN(_userLinks);
            _userLinks[uid] = std::pair<int, int>(link, -1);
            TG_SYNCHRONIZED_END(_userLinks);
        }
    }
    
    if (outdated != NULL)
        *outdated = valueOutdated;
    
    return link;
}

- (void)storeUserLink:(int)uid link:(int)link
{
    TG_SYNCHRONIZED_BEGIN(_userLinks);
    _userLinks[uid] = std::pair<int, int>(link, _userLinksVersion);
    TG_SYNCHRONIZED_END(_userLinks);
    
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ (pid, link) VALUES (?, ?)", _userLinksTableName], [[NSNumber alloc] initWithInt:uid], [[NSNumber alloc] initWithInt:link]];
    } synchronous:false];
}

- (void)clearCachedUserLinks
{
    TG_SYNCHRONIZED_BEGIN(_userLinks);
    _userLinks.clear();
    TG_SYNCHRONIZED_END(_userLinks);
}

- (void)upgradeUserLinks
{
    TG_SYNCHRONIZED_BEGIN(_userLinks);
    _userLinksVersion++;
    TG_SYNCHRONIZED_END(_userLinks);
}

static inline void storeConversationToDatabase(TGDatabase *database, TGConversation *conversation)
{
    static NSString *queryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (cid, date, from_uid, message, media, unread_count, flags, chat_title, chat_photo, participants, participants_count, chat_version, service_unread) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", database.conversationListTableName];
    
    int flags = 0;
    if (conversation.outgoing)
        flags |= 1;
    if (conversation.isChat)
        flags |= 2;
    if (conversation.leftChat)
        flags |= 4;
    if (conversation.kickedFromChat)
        flags |= 8;
    if (conversation.unread)
        flags |= 16;
    if (conversation.deliveryError)
        flags |= 32;
    if (conversation.deliveryState == TGMessageDeliveryStatePending)
        flags |= 64;
    else if (conversation.deliveryState == TGMessageDeliveryStateFailed)
        flags |= 128;
    
    [database.database executeUpdate:queryFormat, [[NSNumber alloc] initWithLongLong:conversation.conversationId], [[NSNumber alloc] initWithInt:conversation.date], [[NSNumber alloc] initWithInt:conversation.fromUid], conversation.text, conversation.media == nil ? nil :  [TGMessage serializeMediaAttachments:false attachments:conversation.media], [[NSNumber alloc] initWithInt:conversation.unreadCount], [[NSNumber alloc] initWithInt:flags], conversation.chatTitle, !conversation.isChat ? nil : [conversation serializeChatPhoto], !conversation.isChat ? nil : [conversation.chatParticipants serializedData], [[NSNumber alloc] initWithInt:conversation.chatParticipantCount], [[NSNumber alloc] initWithInt:conversation.chatVersion], [[NSNumber alloc] initWithInt:conversation.serviceUnreadCount]];
}

static inline void storeConversationToDatabaseIfNotExists(TGDatabase *database, TGConversation *conversation)
{
    static NSString *queryFormat = [NSString stringWithFormat:@"INSERT OR IGNORE INTO %@ (cid, date, from_uid, message, media, unread_count, flags, chat_title, chat_photo, participants, participants_count, chat_version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", database.conversationListTableName];
    
    int flags = 0;
    if (conversation.outgoing)
        flags |= 1;
    if (conversation.isChat)
        flags |= 2;
    if (conversation.leftChat)
        flags |= 4;
    if (conversation.kickedFromChat)
        flags |= 8;
    if (conversation.unread)
        flags |= 16;
    if (conversation.deliveryError)
        flags |= 32;
    if (conversation.deliveryState == TGMessageDeliveryStatePending)
        flags |= 64;
    else if (conversation.deliveryState == TGMessageDeliveryStateFailed)
        flags |= 128;
    
    [database.database executeUpdate:queryFormat, [[NSNumber alloc] initWithLongLong:conversation.conversationId], [[NSNumber alloc] initWithInt:conversation.date], [[NSNumber alloc] initWithInt:conversation.fromUid], conversation.text, conversation.media == nil ? nil :  [TGMessage serializeMediaAttachments:false attachments:conversation.media], [[NSNumber alloc] initWithInt:conversation.unreadCount], [[NSNumber alloc] initWithInt:flags], conversation.chatTitle, !conversation.isChat ? nil : [conversation serializeChatPhoto], !conversation.isChat ? nil : [conversation.chatParticipants serializedData], [[NSNumber alloc] initWithInt:conversation.chatParticipantCount], [[NSNumber alloc] initWithInt:conversation.chatVersion]];
}

static inline TGConversation *loadConversationFromDatabase(FMResultSet *result)
{
    TGConversation *conversation = [[TGConversation alloc] init];
    
    conversation.conversationId = [result longLongIntForColumn:@"cid"];
    conversation.date = [result intForColumn:@"date"];
    conversation.fromUid = [result intForColumn:@"from_uid"];
    conversation.text = [result stringForColumn:@"message"];
    NSData *media = [result dataForColumn:@"media"];
    if (media != nil)
        conversation.media = [TGMessage parseMediaAttachments:media];
    conversation.unreadCount = [result intForColumn:@"unread_count"];
    conversation.serviceUnreadCount = [result intForColumn:@"service_unread"];
    
    int flags = [result intForColumn:@"flags"];
    
    conversation.outgoing = flags & 1;
    conversation.isChat = flags & 2;
    conversation.leftChat = flags & 4;
    conversation.kickedFromChat = flags & 8;
    conversation.unread = flags & 16;
    conversation.deliveryError = flags & 32;
    conversation.deliveryState = ((flags & 64) ? TGMessageDeliveryStatePending : ((flags & 128) ? TGMessageDeliveryStateFailed : TGMessageDeliveryStateDelivered));
    
    if (flags & 2)
    {
        conversation.chatTitle = [result stringForColumn:@"chat_title"];
        conversation.chatParticipantCount = [result intForColumn:@"participants_count"];
        conversation.chatVersion = [result intForColumn:@"chat_version"];
        conversation.chatParticipants = [TGConversationParticipantsData deserializeData:[result dataForColumn:@"participants"]];
        [conversation deserializeChatPhoto:[result dataForColumn:@"chat_photo"]];
    }
    
    return conversation;
}

- (void)storeConversationList:(NSArray *)conversations replace:(bool)replace
{
    [self dispatchOnDatabaseThread:^
    {
        [_database beginTransaction];
        
        if (replace)
        {
            [_database executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@", _conversationListTableName]];
        
            for (TGConversation *conversation in conversations)
            {
                storeConversationToDatabase(self, conversation);
            }
        }
        else
        {
            for (TGConversation *conversation in conversations)
            {
                storeConversationToDatabaseIfNotExists(self, conversation);
            }
        }
        
        [_database commit];
    } synchronous:false];
}

- (void)loadConversationListInitial:(void (^)(NSArray *dialogList, NSArray *userIds))completion
{
    [self dispatchOnDatabaseThread:^
    {
        NSMutableArray *uidsArray = [[NSMutableArray alloc] init];
        std::set<int> uidsSet;
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ ORDER BY date DESC LIMIT 20", _conversationListTableName]];
        NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:20];
        while ([result next])
        {
            TGConversation *conversation = loadConversationFromDatabase(result);
            if (conversation != nil)
            {
                TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
                _unreadCountByConversation[conversation.conversationId] = conversation.unreadCount;
                TG_SYNCHRONIZED_END(_unreadCountByConversation);
                
                int fromUid = conversation.fromUid;
                if (uidsSet.find(fromUid) == uidsSet.end())
                {
                    uidsSet.insert(fromUid);
                    [uidsArray addObject:[[NSNumber alloc] initWithInt:fromUid]];
                }
                if (!conversation.isChat)
                {
                    int userId = (int)conversation.conversationId;
                    if (uidsSet.find(userId) == uidsSet.end())
                    {
                        uidsSet.insert(userId);
                        [uidsArray addObject:[[NSNumber alloc] initWithInt:userId]];
                    }
                }
                [array addObject:conversation];
            }
        }
        
        if (completion)
            completion(array, uidsArray);
    } synchronous:false];
}

- (void)loadConversationListFromDate:(int)date limit:(int)limit excludeConversationIds:(NSArray *)excludeConversationIds completion:(void (^)(NSArray *))completion
{
    [self dispatchOnDatabaseThread:^
    {
        std::set<int64_t> excludeConversationIdsSet;
        for (NSNumber *nCid in excludeConversationIds)
        {
            excludeConversationIdsSet.insert([nCid longLongValue]);
        }
        
        NSMutableArray *array = [[NSMutableArray alloc] init];
        
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE date<=? ORDER BY date DESC LIMIT ?", _conversationListTableName], [[NSNumber alloc] initWithInt:date], [[NSNumber alloc] initWithInt:limit]];
        while ([result next])
        {
            TGConversation *conversation = loadConversationFromDatabase(result);
            if (conversation != nil)
            {
                TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
                _unreadCountByConversation[conversation.conversationId] = conversation.unreadCount;
                TG_SYNCHRONIZED_END(_unreadCountByConversation);
                
                if (excludeConversationIdsSet.find(conversation.conversationId) == excludeConversationIdsSet.end())
                    [array addObject:conversation];
            }
        }
        
        if (completion)
            completion(array);
    } synchronous:false];
}

- (int)loadConversationListRemoteOffset
{
    __block int offset = 0;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT cid FROM %@ ORDER BY date ASC", _conversationListTableName]];
        
        NSString *messageQuery = [[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE cid=? AND mid<%d LIMIT 1", _messagesTableName, TGMessageLocalMidBaseline];
        
        int cidIndex = [result columnIndexForName:@"cid"];
        
        while ([result next])
        {
            int64_t conversationId = [result intForColumnIndex:cidIndex];
            FMResultSet *messageResult = [_database executeQuery:messageQuery, [[NSNumber alloc] initWithLongLong:conversationId]];
            if ([messageResult next])
            {
                offset++;
            }
        }
    } synchronous:true];
    
    return offset;
}

- (TGConversation *)loadConversationWithId:(int64_t)conversationId
{
    __block TGConversation *conversation = nil;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=?", _conversationListTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        
        if ([result next])
        {
            conversation = loadConversationFromDatabase(result);
            if (conversation != nil)
            {
                TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
                _unreadCountByConversation[conversation.conversationId] = conversation.unreadCount;
                TG_SYNCHRONIZED_END(_unreadCountByConversation);
            }
        }
    } synchronous:true];
    
    if (conversation == nil)
    {
        TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
        _unreadCountByConversation[conversationId] = 0;
        TG_SYNCHRONIZED_END(_unreadCountByConversation);
    }
    
    return conversation;
}

- (BOOL)containsConversationWithId:(int64_t)conversationId
{
    __block bool contains = false;
    
    TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
    contains = _unreadCountByConversation.find(conversationId) != _unreadCountByConversation.end();
    TG_SYNCHRONIZED_END(_unreadCountByConversation);
    
    if (!contains)
    {
        TG_SYNCHRONIZED_BEGIN(_containsConversation);
        contains = _containsConversation.find(conversationId) != _containsConversation.end();
        TG_SYNCHRONIZED_END(_containsConversation);
        
        [self dispatchOnDatabaseThread:^
        {
            FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT cid FROM %@ WHERE cid=?", _conversationListTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
            
            if ([result next])
            {
                contains = true;
                
                TG_SYNCHRONIZED_BEGIN(_containsConversation);
                _containsConversation.insert(conversationId);
                TG_SYNCHRONIZED_END(_containsConversation);
            }
        } synchronous:true];
    }
    
    return contains;
}

- (void)storeConversationParticipantData:(int64_t)conversationId participantData:(TGConversationParticipantsData *)participantData
{
    [self dispatchOnDatabaseThread:^
    {
        TGConversation *listConversation = [self loadConversationWithId:conversationId];
        if (listConversation == nil)
        {
            TGLog(@"***** Conversation %lld not found", conversationId);
            return;
        }
        
        TGConversation *newConversation = [listConversation copy];
        
        if (participantData != nil)
        {
            newConversation.chatVersion = participantData.version;
            newConversation.chatParticipants = participantData;
            newConversation.chatParticipantCount = participantData.chatParticipantUids.count;
        }
        else
        {
            newConversation.chatVersion = -1;
        }
        
        if (![newConversation isEqualToConversation:listConversation])
        {
            storeConversationToDatabase(self, newConversation);
            [ActionStageInstance() dispatchResource:[NSString stringWithFormat:@"/tg/conversation/(%lld)/conversation", conversationId] resource:[[SGraphObjectNode alloc] initWithObject:newConversation]];
        }
    } synchronous:false];
}

- (void)actualizeConversation:(int64_t)conversationId dispatch:(bool)dispatch
{
    [self actualizeConversation:conversationId dispatch:dispatch conversation:nil forceUpdate:false addUnreadCount:0 addServiceUnreadCount:0 keepDate:false];
}

- (void)actualizeConversation:(int64_t)conversationId dispatch:(bool)dispatch conversation:(TGConversation *)conversation forceUpdate:(bool)forceUpdate addUnreadCount:(int)addUnreadCount addServiceUnreadCount:(int)addServiceUnreadCount keepDate:(bool)keepDate
{
    [self dispatchOnDatabaseThread:^
    {
        TGConversation *listConversation = [self loadConversationWithId:conversationId];
        
        if (listConversation == nil && conversation == nil && conversationId < 0)
        {
            TGLog(@"New message from chat, but chat wasn't found");
            return;
        }
        
        TGConversation *newConversation = nil;
        if (conversation != nil)
            newConversation = [conversation copy];
        else if (listConversation != nil)
        {
            newConversation = [listConversation copy];
        }
        else
        {
            newConversation = [[TGConversation alloc] initWithConversationId:conversationId unreadCount:0 serviceUnreadCount:0];
        }
        
        if (listConversation != nil)
        {
            newConversation.unreadCount = listConversation.unreadCount;
            newConversation.serviceUnreadCount = listConversation.serviceUnreadCount;
            if (newConversation.chatVersion < listConversation.chatVersion || newConversation.chatParticipants == nil)
            {
                newConversation.chatVersion = listConversation.chatVersion;
                newConversation.chatParticipants = listConversation.chatParticipants;
            }
        }
        
        newConversation.unreadCount += addUnreadCount;
        if (newConversation.unreadCount < 0)
            newConversation.unreadCount = 0;
        
        newConversation.serviceUnreadCount += addServiceUnreadCount;
        if (newConversation.serviceUnreadCount < 0)
            newConversation.serviceUnreadCount = 0;
        
        NSNumber *nConversationId = [[NSNumber alloc] initWithLongLong:conversationId];
        
        FMResultSet *deliveryErrorResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=? AND dstate=? LIMIT 1", _outgoingMessagesTableName], nConversationId, [[NSNumber alloc] initWithInt:TGMessageDeliveryStateFailed]];
        bool hasFailed = [deliveryErrorResult next];
        deliveryErrorResult = nil;
        
        FMResultSet *messageResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=? ORDER BY date DESC LIMIT ?", _messagesTableName], nConversationId, [[NSNumber alloc] initWithInt:hasFailed ? 4 : 1]];
        
        if ([messageResult next])
        {
            NSString *text = [messageResult stringForColumn:@"message"];
            NSData *media = [messageResult dataForColumn:@"media"];
            bool unread = [messageResult intForColumn:@"unread"] ? 1 : 0;
            int64_t fromUid = [messageResult longLongIntForColumn:@"from_id"];
            bool outgoing = [messageResult intForColumn:@"outgoing"];
            int date = [messageResult intForColumn:@"date"];
            TGMessageDeliveryState deliveryState = (TGMessageDeliveryState)[messageResult intForColumn:@"dstate"];
            
            int oldDate = newConversation.date;
            
            TGMessage *message = [[TGMessage alloc] init];
            message.text = text;
            message.mediaAttachments = [TGMessage parseMediaAttachments:media];
            message.outgoing = outgoing;
            message.date = date;
            message.fromUid = fromUid;
            message.unread = unread;
            message.deliveryState = deliveryState;
            [newConversation mergeMessage:message];
            
            if (keepDate && oldDate > newConversation.date)
                newConversation.date = oldDate;
            
            if (hasFailed)
            {
                bool anyFailed = false;

                int dstateIndex = [messageResult columnIndexForName:@"dstate"];
                
                while ([messageResult next])
                {
                    if ([messageResult intForColumnIndex:dstateIndex] == TGMessageDeliveryStateFailed)
                    {
                        anyFailed = true;
                        break;
                    }
                }
                
                if (!anyFailed)
                    hasFailed = false;
            }
            
            newConversation.deliveryError = hasFailed;
            
            if (forceUpdate || listConversation == nil || ![newConversation isEqualToConversation:listConversation])
            {
                TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
                _unreadCountByConversation[conversationId] = newConversation.unreadCount;
                TG_SYNCHRONIZED_END(_unreadCountByConversation);
                
                storeConversationToDatabase(self, newConversation);
                
                if (dispatch)
                {
                    //newConversation = [self loadConversationWithId:conversationId];
                    
                    [ActionStageInstance() dispatchResource:_liveMessagesDispatchPath resource:[[SGraphObjectNode alloc] initWithObject:[NSArray arrayWithObject:newConversation]]];
                    [ActionStageInstance() dispatchResource:[NSString stringWithFormat:@"/tg/conversation/(%lld)/conversation", conversationId] resource:[[SGraphObjectNode alloc] initWithObject:newConversation]];
                }
            }
        }
        else
        {
            newConversation.outgoing = false;
            newConversation.text = nil;
            newConversation.media = nil;
            newConversation.unread = false;
            newConversation.unreadCount = 0;
            newConversation.serviceUnreadCount = 0;
            newConversation.fromUid = 0;
            newConversation.deliveryError = false;
            newConversation.deliveryState = TGMessageDeliveryStateDelivered;
            newConversation.date = listConversation == nil ? conversation.date : listConversation.date;
            
            if (forceUpdate || listConversation == nil || ![newConversation isEqualToConversation:listConversation])
            {
                TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
                _unreadCountByConversation[conversationId] = newConversation.unreadCount;
                TG_SYNCHRONIZED_END(_unreadCountByConversation);
                
                storeConversationToDatabase(self, newConversation);
            }
            
            if (dispatch)
            {
                [ActionStageInstance() dispatchResource:_liveMessagesDispatchPath resource:[[SGraphObjectNode alloc] initWithObject:[NSArray arrayWithObject:newConversation]]];
                [ActionStageInstance() dispatchResource:[NSString stringWithFormat:@"/tg/conversation/(%lld)/conversation", conversationId] resource:[[SGraphObjectNode alloc] initWithObject:newConversation]];
            }
        }
    } synchronous:false];
}

bool searchDialogsResultComparator(const std::pair<id, int> &obj1, const std::pair<id, int> &obj2)
{
    return obj1.second > obj2.second;
}

- (void)searchDialogs:(NSString *)query ignoreUid:(int)ignoreUid completion:(void (^)(NSDictionary *))completion
{
    [self dispatchOnDatabaseThread:^
    {
        NSMutableDictionary *resultDict = [[NSMutableDictionary alloc] init];
        
        std::vector<std::pair<id, int> > searchResults;
        
        std::set<int> foundUids;
        
        {
            NSString *cleanQuery = [[query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
            
            FMResultSet *listResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ ORDER BY DATE DESC LIMIT 256", _conversationListTableName]];
            
            int cidIndex = [listResult columnIndexForName:@"cid"];
            int dateIndex = [listResult columnIndexForName:@"date"];
            int titleIndex = [listResult columnIndexForName:@"chat_title"];
            int participantsIndex = [listResult columnIndexForName:@"participants"];
            
            std::map<int, std::vector<std::pair<int, TGConversation *> > > userToDateAndConversations;
            std::vector<int> usersToLoad;
            
            while ([listResult next])
            {
                int64_t cid = [listResult longLongIntForColumnIndex:cidIndex];
                int date = [listResult intForColumnIndex:dateIndex];
                
                if (cid <= INT_MIN)
                {
                    NSData *participantsData = [listResult dataForColumnIndex:participantsIndex];
                    
                    TGConversationParticipantsData *participants = [TGConversationParticipantsData deserializeData:participantsData];
                    if (participants.chatParticipantUids.count != 0)
                    {
                        int uid = [participants.chatParticipantUids[0] intValue];
                        TGConversation *conversation = loadConversationFromDatabase(listResult);
                        
                        userToDateAndConversations[uid].push_back(std::pair<int, TGConversation *>(date, conversation));
                        usersToLoad.push_back(uid);
                    }
                }
                else if (cid < 0)
                {
                    NSString *chatTitle = [listResult stringForColumnIndex:titleIndex];
                    
                    if ([[chatTitle lowercaseString] hasPrefix:cleanQuery])
                    {
                        TGConversation *conversation = loadConversationFromDatabase(listResult);
                        searchResults.push_back(std::pair<id, int>(conversation, date));
                    }
                }
                else
                {
                    userToDateAndConversations[(int)cid].push_back(std::pair<int, TGConversation *>(date, nil));
                    usersToLoad.push_back((int)cid);
                }
            }
            
            NSMutableString *testString = [[NSMutableString alloc] initWithCapacity:128];
            NSMutableDictionary *cache = transliterationPartsCache();
            static NSMutableCharacterSet *characterSet = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^
            {
                characterSet = [[NSMutableCharacterSet alloc] init];
                [characterSet formUnionWithCharacterSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
                [characterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            });
            
            NSMutableString *mutableQuery = [[NSMutableString alloc] initWithString:cleanQuery];
            CFStringTransform((CFMutableStringRef)mutableQuery, NULL, kCFStringTransformToLatin, false);
            CFStringTransform((CFMutableStringRef)mutableQuery, NULL, kCFStringTransformStripCombiningMarks, false);
            
            NSArray *latinQueryParts = breakStringIntoParts(mutableQuery, characterSet);
            
            std::tr1::shared_ptr<std::map<int, TGUser *> > pUsers = [self loadUsers:usersToLoad];
            for (auto it : *pUsers)
            {
                bool failed = true;
                
                NSString *firstName = it.second.firstName;
                NSString *lastName = it.second.lastName;
                
                if (firstName.length != 0 || lastName.length != 0)
                {
                    [testString deleteCharactersInRange:NSMakeRange(0, testString.length)];
                    if (firstName.length != 0)
                    {
                        [testString appendString:firstName];
                        [testString appendString:@" "];
                    }
                    if (lastName.length != 0)
                        [testString appendString:lastName];
                    
                    NSArray *testParts = [cache objectForKey:testString];
                    if (testParts == nil)
                    {
                        NSString *originalString = [testString copy];
                        
                        CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformToLatin, false);
                        CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformStripCombiningMarks, false);
                        
                        testParts = breakStringIntoParts([testString lowercaseString], characterSet);
                        if (testParts != nil)
                            [cache setObject:testParts forKey:originalString];
                    }
                    
                    bool everyPartMatches = true;
                    for (NSString *queryPart in latinQueryParts)
                    {
                        bool hasMatches = false;
                        for (NSString *testPart in testParts)
                        {
                            if ([testPart hasPrefix:queryPart])
                            {
                                hasMatches = true;
                                break;
                            }
                        }
                        
                        if (!hasMatches)
                        {
                            everyPartMatches = false;
                            break;
                        }
                    }
                    if (everyPartMatches)
                        failed = false;
                }
                else
                    failed = true;
                
                if (!failed)
                {
                    auto conversationsIt = userToDateAndConversations.find(it.first);
                    if (conversationsIt != userToDateAndConversations.end())
                    {
                        for (auto itemIt : conversationsIt->second)
                        {
                            searchResults.push_back(std::pair<id, int>(itemIt.second == nil ? it.second : itemIt.second, itemIt.first));
                            if (itemIt.second == nil)
                                foundUids.insert(it.first);
                        }
                    }
                }
            }
            
            /*NSString *cleanQuery = [[[query stringByReplacingOccurrencesOfString:@" +" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, query.length)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
            
            NSString *likeString = [NSString stringWithFormat:@"%@%%", cleanQuery];
            
            FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT %@.cid, %@.date FROM %@ INNER JOIN %@ ON %@.cid=%@.uid WHERE %@.cid > 0 AND (%@.first_name LIKE ? OR %@.last_name LIKE ? OR (%@.first_name||' '||%@.last_name) LIKE ? OR (%@.last_name||' '||%@.first_name) LIKE ?)", _conversationListTableName, _conversationListTableName, _conversationListTableName, _usersTableName, _conversationListTableName, _usersTableName, _conversationListTableName, _usersTableName, _usersTableName, _usersTableName, _usersTableName, _usersTableName, _usersTableName], likeString, likeString, likeString, likeString];
            
            int cidIndex = [result columnIndexForName:@"cid"];
            int dateIndex = [result columnIndexForName:@"date"];
            
            while ([result next])
            {
                int uid = (int)[result longLongIntForColumnIndex:cidIndex];
                int date = [result intForColumnIndex:dateIndex];
                TGUser *user = [self loadUser:uid];
                if (user != nil)
                {
                    searchResults.push_back(std::pair<id, int>(user, date));
                    foundUids.insert(uid);
                }
            }*/
        }
        
        NSMutableArray *chatList = [[NSMutableArray alloc] init];
        
        /*NSString *likeString = [NSString stringWithFormat:@"%%%@%%", cleanQuery];
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid<0 AND chat_title LIKE ? ORDER BY date DESC", _conversationListTableName], likeString];
        
        
        while ([result next])
        {
            TGConversation *conversation = loadConversationFromDatabase(result);
            if (conversation != nil)
            {
                searchResults.push_back(std::pair<id, int>(conversation, conversation.date));
            }
        }*/
        
        std::sort(searchResults.begin(), searchResults.end(), &searchDialogsResultComparator);
        for (std::vector<std::pair<id, int> >::iterator it = searchResults.begin(); it != searchResults.end(); it++)
        {
            [chatList addObject:it->first];
        }
        
        std::set<int> *pFoundUids = &foundUids;
        [self searchContacts:query ignoreUid:ignoreUid searchPhonebook:false completion:^(NSDictionary *result)
        {
            if ([result objectForKey:@"users"] != nil)
            {
                for (TGUser *user in [result objectForKey:@"users"])
                {
                    if (pFoundUids->find(user.uid) == pFoundUids->end())
                    {
                        [chatList addObject:user];
                    }
                }
            }
        }];
        
        [resultDict setObject:chatList forKey:@"chats"];
        
        if (completion)
            completion(resultDict);
    } synchronous:true];
}

static NSArray *breakStringIntoParts(NSString *string, NSCharacterSet *characterSet)
{
    NSMutableArray *parts = [[NSMutableArray alloc] initWithCapacity:2];
    
    NSScanner *scanner = [[NSScanner alloc] initWithString:string];
    NSString *token;
    while ([scanner scanUpToCharactersFromSet:characterSet intoString:&token])
    {
        [parts addObject:token];
        [scanner scanCharactersFromSet:characterSet intoString:NULL];
    }
    
    return parts;
}

static NSMutableDictionary *transliterationPartsCache()
{
    static NSMutableDictionary *dict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        dict = [[NSMutableDictionary alloc] init];
    });
    return dict;
}

- (void)searchContacts:(NSString *)query ignoreUid:(int)ignoreUid searchPhonebook:(bool)searchPhonebook completion:(void (^)(NSDictionary *))completion
{
    [self dispatchOnDatabaseThread:^
    {
        [self buildTransliterationCache];
        
        __unused CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
        
        NSMutableDictionary *resultDict = [[NSMutableDictionary alloc] init];
        
        NSMutableArray *usersArray = [[NSMutableArray alloc] init];
        
        static NSMutableCharacterSet *characterSet = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^
        {
            characterSet = [[NSMutableCharacterSet alloc] init];
            [characterSet formUnionWithCharacterSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
            [characterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        });
     
        NSMutableString *mutableQuery = [[NSMutableString alloc] initWithString:query];
        CFStringTransform((CFMutableStringRef)mutableQuery, NULL, kCFStringTransformToLatin, false);
        CFStringTransform((CFMutableStringRef)mutableQuery, NULL, kCFStringTransformStripCombiningMarks, false);
        
        NSArray *latinQueryParts = breakStringIntoParts([mutableQuery lowercaseString], characterSet);
        
        NSMutableString *testString = [[NSMutableString alloc] initWithCapacity:128];
        
        NSMutableDictionary *cache = transliterationPartsCache();
        
        for (TGUser *user in [self loadContactUsers])
        {
            if (user.uid == ignoreUid)
                continue;
            
            bool failed = true;
            
            NSString *firstName = user.firstName;
            NSString *lastName = user.lastName;
            
            if (firstName.length != 0 || lastName.length != 0)
            {
                [testString deleteCharactersInRange:NSMakeRange(0, testString.length)];
                if (firstName.length != 0)
                {
                    [testString appendString:firstName];
                    [testString appendString:@" "];
                }
                if (lastName.length != 0)
                    [testString appendString:lastName];
                
                NSArray *testParts = [cache objectForKey:testString];
                if (testParts == nil)
                {
                    NSString *originalString = [testString copy];
                    
                    CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformToLatin, false);
                    CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformStripCombiningMarks, false);
                    
                    testParts = breakStringIntoParts([testString lowercaseString], characterSet);
                    if (testParts != nil)
                        [cache setObject:testParts forKey:originalString];
                }
                
                bool everyPartMatches = true;
                for (NSString *queryPart in latinQueryParts)
                {
                    bool hasMatches = false;
                    for (NSString *testPart in testParts)
                    {
                        if ([testPart hasPrefix:queryPart])
                        {
                            hasMatches = true;
                            break;
                        }
                    }
                    
                    if (!hasMatches)
                    {
                        everyPartMatches = false;
                        break;
                    }
                }
                if (everyPartMatches)
                    failed = false;
            }
            else
                failed = true;
            
            if (!failed)
                [usersArray addObject:user];
        }
        TGLog(@"Search time: %f ms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0);
        
        if (searchPhonebook)
        {
            startTime = CFAbsoluteTimeGetCurrent();
            NSArray *contactResults = [TGDatabaseInstance() searchPhonebookContacts:query contacts:[self loadPhonebookContacts]];
            
            std::set<int> remoteContactIds;
            
            for (TGUser *user in [TGDatabaseInstance() loadContactUsers])
            {
                if (user.contactId)
                    remoteContactIds.insert(user.contactId);
            }
            
            for (TGPhonebookContact *phonebookContact in contactResults)
            {
                //int phonesCount = phonebookContact.phoneNumbers.count;
                for (TGPhoneNumber *phoneNumber in phonebookContact.phoneNumbers)
                {
                    if (remoteContactIds.find(phoneNumber.phoneId) != remoteContactIds.end())
                        continue;
                    
                    TGUser *phonebookUser = [[TGUser alloc] init];
                    phonebookUser.firstName = phonebookContact.firstName;
                    phonebookUser.lastName = phonebookContact.lastName;
                    phonebookUser.uid = -phonebookContact.nativeId;
                    phonebookUser.phoneNumber = phoneNumber.number;
                    //if (phonesCount != 0)
                    //    phonebookUser.customProperties = [[NSDictionary alloc] initWithObjectsAndKeys:phoneNumber.label, @"label", nil];
                    [usersArray addObject:phonebookUser];
                    
                    break;
                }
            }
            
            TGLog(@"Phonebook time: +%f ms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0);
        }
        
        [resultDict setObject:usersArray forKey:@"users"];
        
        if (completion)
            completion(resultDict);
    } synchronous:false];
}

- (void)buildTransliterationCache
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        [self dispatchOnDatabaseThread:^
        {
            NSArray *users = [self loadContactUsers];
            NSArray *contacts = [self loadPhonebookContacts];
            
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            NSString *cacheFilename = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"translit.cache"];
            NSData *transliterationData = [[NSData alloc] initWithContentsOfFile:cacheFilename];
            if (transliterationData != nil)
            {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                
                NSInputStream *is = [[NSInputStream alloc] initWithData:transliterationData];
                [is open];
                int count = 0;
                [is read:(uint8_t *)&count maxLength:4];
                for (int i = 0; i < count; i++)
                {
                    int length = 0;
                    [is read:(uint8_t *)&length maxLength:4];
                    
                    uint8_t keyBytes[length];
                    [is read:keyBytes maxLength:length];
                    
                    NSString *key = [[NSString alloc] initWithBytes:keyBytes length:length encoding:NSUTF8StringEncoding];
                    
                    int valueCount = 0;
                    [is read:(uint8_t *)&valueCount maxLength:4];
                    NSMutableArray *values = [[NSMutableArray alloc] initWithCapacity:valueCount];
                    for (int j = 0; j < valueCount; j++)
                    {
                        length = 0;
                        [is read:(uint8_t *)&length maxLength:4];
                        uint8_t valueBytes[length];
                        [is read:valueBytes maxLength:length];
                        
                        NSString *value = [[NSString alloc] initWithBytes:valueBytes length:length encoding:NSUTF8StringEncoding];
                        if (value.length != 0)
                            [values addObject:value];
                    }
                    
                    if (key != nil && values.count != 0)
                        [dict setObject:values forKey:key];
                }
                [is close];
                
                [self dispatchOnDatabaseThread:^
                {
                    [transliterationPartsCache() addEntriesFromDictionary:dict];
                } synchronous:false];
            }
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
            {
                CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
                
                static NSMutableCharacterSet *characterSet = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^
                {
                    characterSet = [[NSMutableCharacterSet alloc] init];
                    [characterSet formUnionWithCharacterSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
                    [characterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                });
                
                NSMutableString *testString = [[NSMutableString alloc] initWithCapacity:128];
                
                NSMutableDictionary *cache = [[NSMutableDictionary alloc] init];
                
                for (TGUser *user in users)
                {            
                    NSString *firstName = user.firstName;
                    NSString *lastName = user.lastName;
                    
                    if (firstName.length != 0 || lastName.length != 0)
                    {
                        [testString deleteCharactersInRange:NSMakeRange(0, testString.length)];
                        if (firstName.length != 0)
                        {
                            [testString appendString:firstName];
                            [testString appendString:@" "];
                        }
                        if (lastName.length != 0)
                            [testString appendString:lastName];
                        
                        NSArray *testParts = [cache objectForKey:testString];
                        if (testParts == nil)
                        {
                            NSString *originalString = [testString copy];
                            
                            CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformToLatin, false);
                            CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformStripCombiningMarks, false);
                            
                            testParts = breakStringIntoParts([testString lowercaseString], characterSet);
                            if (testParts != nil)
                                [cache setObject:testParts forKey:originalString];
                        }
                    }
                }
                
                for (TGPhonebookContact *user in contacts)
                {
                    NSString *firstName = user.firstName;
                    NSString *lastName = user.lastName;
                    
                    if (firstName.length != 0 || lastName.length != 0)
                    {
                        [testString deleteCharactersInRange:NSMakeRange(0, testString.length)];
                        if (firstName.length != 0)
                        {
                            [testString appendString:firstName];
                            [testString appendString:@" "];
                        }
                        if (lastName.length != 0)
                            [testString appendString:lastName];
                        
                        NSArray *testParts = [cache objectForKey:testString];
                        if (testParts == nil)
                        {
                            NSString *originalString = [testString copy];
                            
                            CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformToLatin, false);
                            CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformStripCombiningMarks, false);
                            
                            testParts = breakStringIntoParts([testString lowercaseString], characterSet);
                            if (testParts != nil)
                                [cache setObject:testParts forKey:originalString];
                        }
                    }
                }
                
                TGLog(@"Contacts cache built in %fs", CFAbsoluteTimeGetCurrent() - startTime);
                
                [self dispatchOnDatabaseThread:^
                {
                    [transliterationPartsCache() addEntriesFromDictionary:cache];
                } synchronous:false];
                
                NSMutableData *data = [[NSMutableData alloc] init];
                int count = cache.count;
                [data appendBytes:&count length:4];
                
                [cache enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray *values, __unused BOOL *stop)
                {
                    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
                    int length = keyData.length;
                    [data appendBytes:&length length:4];
                    [data appendData:keyData];
                    
                    int valueCount = values.count;
                    [data appendBytes:&valueCount length:4];
                    for (NSString *value in values)
                    {
                        NSData *valueData = [value dataUsingEncoding:NSUTF8StringEncoding];
                        length = valueData.length;
                        [data appendBytes:&length length:4];
                        [data appendData:valueData];
                    }
                }];
                
                [data writeToFile:cacheFilename atomically:false];
            });
        } synchronous:false];
    });
}

- (NSArray *)searchPhonebookContacts:(NSString *)query contacts:(NSArray *)contacts
{    
    NSMutableArray *usersArray = [[NSMutableArray alloc] init];
    
    static NSMutableCharacterSet *characterSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        characterSet = [[NSMutableCharacterSet alloc] init];
        [characterSet formUnionWithCharacterSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
        [characterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    });
    
    NSMutableString *mutableQuery = [[NSMutableString alloc] initWithString:query];
    CFStringTransform((CFMutableStringRef)mutableQuery, NULL, kCFStringTransformToLatin, false);
    CFStringTransform((CFMutableStringRef)mutableQuery, NULL, kCFStringTransformStripCombiningMarks, false);
    
    NSArray *latinQueryParts = breakStringIntoParts([mutableQuery lowercaseString], characterSet);
    
    NSMutableString *testString = [[NSMutableString alloc] initWithCapacity:128];
    
    NSMutableDictionary *cache = transliterationPartsCache();
    
    for (TGPhonebookContact *user in contacts)
    {
        bool failed = true;
        
        NSString *firstName = user.firstName;
        NSString *lastName = user.lastName;
        
        if (firstName.length != 0 || lastName.length != 0)
        {
            [testString deleteCharactersInRange:NSMakeRange(0, testString.length)];
            if (firstName.length != 0)
            {
                [testString appendString:firstName];
                [testString appendString:@" "];
            }
            if (lastName.length != 0)
                [testString appendString:lastName];
            
            NSArray *testParts = [cache objectForKey:testString];
            if (testParts == nil)
            {
                NSString *originalString = [testString copy];
                
                CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformToLatin, false);
                CFStringTransform((CFMutableStringRef)testString, NULL, kCFStringTransformStripCombiningMarks, false);
                
                testParts = breakStringIntoParts([testString lowercaseString], characterSet);
                if (testParts != nil)
                    [cache setObject:testParts forKey:originalString];
            }
            
            bool everyPartMatches = true;
            for (NSString *queryPart in latinQueryParts)
            {
                bool hasMatches = false;
                for (NSString *testPart in testParts)
                {
                    if ([testPart hasPrefix:queryPart])
                    {
                        hasMatches = true;
                        break;
                    }
                }
                
                if (!hasMatches)
                {
                    everyPartMatches = false;
                    break;
                }
            }
            if (everyPartMatches)
                failed = false;
        }
        else
            failed = true;
        
        if (!failed)
        {
            [usersArray addObject:user];
        }
    }
    
    return usersArray;
}

- (void)searchMessages:(NSString *)query completion:(void (^)(NSArray *))completion
{
    [self dispatchOnIndexThread:^
    {
        NSString *cleanQuery = [NSString stringWithFormat:@"%@*", [[query lowercaseString] stringByReplacingOccurrencesOfString:@"*" withString:@""]];
        
        NSMutableArray *mids = [[NSMutableArray alloc] init];
        
        CFAbsoluteTime searchStartTime = CFAbsoluteTimeGetCurrent();
        FMResultSet *result = [_indexDatabase executeQuery:[NSString stringWithFormat:@"SELECT docid FROM %@ WHERE text MATCH ? ORDER BY docid DESC", _messageIndexTableName], cleanQuery];
        int docidIndex = [result columnIndexForName:@"docid"];
        while ([result next])
        {
            [mids addObject:[[NSNumber alloc] initWithInt:[result intForColumnIndex:docidIndex]]];
        }
        TGLog(@"Search time: %f s", CFAbsoluteTimeGetCurrent() - searchStartTime);
        
        if (mids.count == 0)
        {
            if (completion)
                completion([NSArray array]);
        }
        else
        {
            NSMutableArray *messages = [[NSMutableArray alloc] init];
            
            [self dispatchOnDatabaseThread:^
            {
                CFAbsoluteTime extractionStartTime = CFAbsoluteTimeGetCurrent();
                std::set<int64_t> conversationsToLoad;
                
                int midsCount = mids.count;
                
                NSMutableString *rangeString = [[NSMutableString alloc] init];
                for (int i = 0; i < midsCount; i++)
                {
                    if (rangeString.length != 0)
                        [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
                    
                    std::set<int> midsInRange;
                    
                    bool first = true;
                    int count = 0;
                    for (; count < 200 && i < midsCount; i++, count++)
                    {
                        if (first)
                            first = false;
                        else
                            [rangeString appendString:@","];
                        
                        int mid = [[mids objectAtIndex:i] intValue];
                        [rangeString appendFormat:@"%d", mid];
                        midsInRange.insert(mid);
                    }
                    
                    NSString *messagesQueryFormat = [[NSString alloc] initWithFormat:@"SELECT mid, cid, message, date, from_id, to_id, outgoing, dstate, unread FROM %@ WHERE mid IN (%@)", _messagesTableName, rangeString];
                    FMResultSet *result = [_database executeQuery:messagesQueryFormat];
                    
                    int midIndex = [result columnIndexForName:@"mid"];
                    int cidIndex = [result columnIndexForName:@"cid"];
                    int messageIndex = [result columnIndexForName:@"message"];
                    int dateIndex = [result columnIndexForName:@"date"];
                    int fromIdIndex = [result columnIndexForName:@"from_id"];
                    int toIdIndex = [result columnIndexForName:@"to_id"];
                    int outgoingIndex = [result columnIndexForName:@"outgoing"];
                    int dstateIndex = [result columnIndexForName:@"dstate"];
                    int unreadIndex = [result columnIndexForName:@"unread"];
                    
                    while ([result next])
                    {
                        int mid = [result intForColumnIndex:midIndex];
                        midsInRange.erase(mid);
                        
                        TGMessage *message = [[TGMessage alloc] init];
                        message.mid = mid;
                        if (mid >= TGMessageLocalMidBaseline)
                        {
                            message.local = true;
                            message.localMid = mid;
                        }
                        
                        message.cid = [result longLongIntForColumnIndex:cidIndex];
                        message.date = [result intForColumnIndex:dateIndex];
                        message.text = [result stringForColumnIndex:messageIndex];
                        message.fromUid = [result longLongIntForColumnIndex:fromIdIndex];
                        message.toUid = [result longLongIntForColumnIndex:toIdIndex];
                        message.outgoing = [result intForColumnIndex:outgoingIndex] != 0;
                        message.deliveryState = (TGMessageDeliveryState)[result intForColumnIndex:dstateIndex];
                        message.unread = [result intForColumnIndex:unreadIndex];
                        
                        conversationsToLoad.insert(message.cid);
                        
                        [messages addObject:message];
                    }
                    
                    if (!midsInRange.empty())
                    {
                        TGLog(@"***** Message index contains %ld non-existing rows, removing", midsInRange.size());
                        
                        NSMutableArray *deleteMids = [[NSMutableArray alloc] initWithCapacity:midsInRange.size()];
                        for (std::set<int>::iterator it = midsInRange.begin(); it != midsInRange.end(); it++)
                        {
                            [deleteMids addObject:[[NSNumber alloc] initWithInt:*it]];
                        }
                        
                        [self deleteMessagesFromIndex:deleteMids];
                    }
                }
                
                TGLog(@"Extraction time: %f s", CFAbsoluteTimeGetCurrent() - extractionStartTime);
                
                CFAbsoluteTime sortStartTime = CFAbsoluteTimeGetCurrent();
                
                [messages sortUsingComparator:^NSComparisonResult(TGMessage *message1, TGMessage *message2)
                {
                    if (message1.date > message2.date)
                        return NSOrderedAscending;
                    return NSOrderedDescending;
                }];
                
                TGLog(@"Sort time: %f s", CFAbsoluteTimeGetCurrent() - sortStartTime);
                
                const int maxMessages = 200;
                if (messages.count > maxMessages)
                    [messages removeObjectsInRange:NSMakeRange(maxMessages, messages.count - maxMessages)];
                
                CFAbsoluteTime conversationStartTime = CFAbsoluteTimeGetCurrent();
                std::map<int64_t, TGConversation *> loadedConversations;
                for (std::set<int64_t>::iterator it = conversationsToLoad.begin(); it != conversationsToLoad.end(); it++)
                {
                    TGConversation *conversation = [self loadConversationWithId:*it];
                    
                    if (conversation != nil)
                        loadedConversations.insert(std::pair<int64_t, TGConversation *>(*it, conversation));
                    else
                        TGLog(@"***** Couldn't find conversation %lld", *it);
                }
                
                TGLog(@"Conversation parsing time: %f s", CFAbsoluteTimeGetCurrent() - conversationStartTime);
                
                NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:messages.count];
                
                CFAbsoluteTime conversationMergingTime = CFAbsoluteTimeGetCurrent();
                for (TGMessage *message in messages)
                {
                    std::map<int64_t, TGConversation *>::iterator it = loadedConversations.find(message.cid);
                    if (it == loadedConversations.end())
                        continue;
                    
                    TGConversation *conversation = [it->second copy];
                    [conversation mergeMessage:message];
                    conversation.additionalProperties = [[NSDictionary alloc] initWithObjectsAndKeys:[[NSNumber alloc] initWithInt:message.mid], @"searchMessageId", nil];
                    [result addObject:conversation];
                }
                
                TGLog(@"Conversation merging time: %f s", CFAbsoluteTimeGetCurrent() - conversationMergingTime);
                
                if (completion)
                    completion(result);
            } synchronous:false];
        }
    } synchronous:false];
}

- (void)deleteMessagesFromIndex:(NSArray *)mids
{
    [self dispatchOnIndexThread:^
    {
        int midsCount = mids.count;
        
        NSMutableString *rangeString = [[NSMutableString alloc] init];
        for (int i = 0; i < midsCount; i++)
        {
            if (rangeString.length != 0)
                [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
            
            std::set<int> midsInRange;
            
            bool first = true;
            int count = 0;
            for (; count < 100 && i < midsCount; i++, count++)
            {
                if (first)
                    first = false;
                else
                    [rangeString appendString:@","];
                
                int mid = [[mids objectAtIndex:i] intValue];
                [rangeString appendFormat:@"%d", mid];
                midsInRange.insert(mid);
            }
            
            NSString *messagesQueryFormat = [[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE docid IN (%@)", _messageIndexTableName, rangeString];
            [_indexDatabase executeUpdate:messagesQueryFormat];
        }
    } synchronous:false];
}

- (void)markAllPendingMessagesAsFailed
{
    [self dispatchOnDatabaseThread:^
    {
        NSString *updateDeliveryStateFormat = [[NSString alloc] initWithFormat:@"UPDATE OR IGNORE %@ SET dstate=%d WHERE mid=?", _messagesTableName, TGMessageDeliveryStateFailed];
        
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE dstate=%d", _outgoingMessagesTableName, TGMessageDeliveryStatePending]];
        int midIndex = [result columnIndexForName:@"mid"];
        int cidIndex = [result columnIndexForName:@"cid"];
        
        std::set<int64_t> conversations;
        
        [_database beginTransaction];
        
        while ([result next])
        {
            int mid = [result intForColumnIndex:midIndex];
            int64_t conversationId = [result longLongIntForColumnIndex:cidIndex];
            conversations.insert(conversationId);
            
            [_database executeUpdate:updateDeliveryStateFormat, [[NSNumber alloc] initWithInt:mid]];
        }
        
        if (!conversations.empty())
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET dstate=%d", _outgoingMessagesTableName, TGMessageDeliveryStateFailed]];
        
        [_database commit];
        
        for (std::set<int64_t>::iterator it = conversations.begin(); it != conversations.end(); it++)
        {
            [self actualizeConversation:*it dispatch:false];
        }
    } synchronous:false];
}

- (void)applyPts:(int)pts date:(int)date seq:(int)seq qts:(int)qts unreadCount:(int)unreadCount
{
    [self dispatchOnDatabaseThread:^
    {
        TGDatabaseState currentState = [self databaseState];
        if (seq > 0)
            currentState.seq = seq;
        if (pts > 0)
            currentState.pts = pts;
        if (date > 0 && date > currentState.date)
            currentState.date = date;
        if (unreadCount >= 0)
            currentState.unreadCount = unreadCount;
        if (qts > 0)
            currentState.qts = qts;
        
        [self setPts:currentState.pts date:currentState.date seq:currentState.seq qts:currentState.qts unreadCount:currentState.unreadCount];
    } synchronous:false];
}

- (void)setPts:(int)pts date:(int)date seq:(int)seq qts:(int)qts unreadCount:(int)unreadCount
{   
    [self dispatchOnDatabaseThread:^
    {
        int lastUnreadCount = 0;
        
        _cachedDatabaseState.pts = pts;
        _cachedDatabaseState.date = date;
        _cachedDatabaseState.seq = seq;
        _cachedDatabaseState.qts = qts;
        lastUnreadCount = _cachedDatabaseState.unreadCount;
        _cachedDatabaseState.unreadCount = unreadCount;
        
        TG_SYNCHRONIZED_BEGIN(_cachedUnreadCount);
        _cachedUnreadCount = unreadCount;
        TG_SYNCHRONIZED_END(_cachedUnreadCount);
        
        if (lastUnreadCount != unreadCount && _liveUnreadCountDispatchPath != nil)
        {
            [ActionStageInstance() dispatchOnStageQueue:^
            {
                [ActionStageInstance() dispatchResource:_liveUnreadCountDispatchPath resource:[[SGraphObjectNode alloc] initWithObject:[[NSNumber alloc] initWithInt:unreadCount]]];
            }];
        }
        
        NSMutableData *data = [[NSMutableData alloc] initWithCapacity:4 * 4];
        [data appendBytes:&pts length:4];
        [data appendBytes:&date length:4];
        [data appendBytes:&seq length:4];
        [data appendBytes:&unreadCount length:4];
        [data appendBytes:&qts length:4];
        
        if (pts == 0)
        {
            TGLog(@"****pts = 0!");
        }
        
        [_database executeUpdate:[NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (key, value) VALUES (?, ?)", _serviceTableName], [[NSNumber alloc] initWithInt:_servicePtsKey], data];
    } synchronous:false];
}

- (void)setUnreadCount:(int)unreadCount
{
    [self dispatchOnDatabaseThread:^
    {
        TGDatabaseState state = [self databaseState];
        state.unreadCount = unreadCount;
        [self setPts:state.pts date:state.date seq:state.seq qts:state.qts unreadCount:state.unreadCount];
    } synchronous:false];
}

- (TGDatabaseState)databaseState
{   
    __block TGDatabaseState state;
    
    [self dispatchOnDatabaseThread:^
    {
        bool validState = false;
        
        TGDatabaseState resultState;
        if (_cachedDatabaseState.pts != 0)
        {
            validState = true;
            resultState = _cachedDatabaseState;
        }
        
        if (validState)
        {
            state = resultState;
            return;
        }
        
        NSData *value = nil;
        
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE key=%d", _serviceTableName, _servicePtsKey]];
        if ([result next])
        {
            value = [result dataForColumn:@"value"];
        }
        
        if (value == nil || value.length < 4 * 4)
        {
            state.pts = 0;
            state.seq = 0;
            state.date = 0;
            state.unreadCount = 0;
            state.qts = 0;
        }
        else
        {
            int ptr = 0;
            
            int pts = 0;
            [value getBytes:&pts range:NSMakeRange(ptr, 4)];
            ptr += 4;
            
            int date = 0;
            [value getBytes:&date range:NSMakeRange(ptr, 4)];
            ptr += 4;
            
            int seq = 0;
            [value getBytes:&seq range:NSMakeRange(ptr, 4)];
            ptr += 4;
            
            int unreadCount = 0;
            [value getBytes:&unreadCount range:NSMakeRange(ptr, 4)];
            ptr += 4;
            
            int qts = 0;
            if (value.length >= ptr + 4)
            {
                [value getBytes:&qts range:NSMakeRange(ptr, 4)];
                ptr += 4;
            }
            
            state.pts = pts;
            state.date = date;
            state.seq = seq;
            state.unreadCount = unreadCount;
            state.qts = qts;
        }
        
        _cachedDatabaseState = state;
    } synchronous:true];
    
    return state;
}

- (int)cachedUnreadCount
{
    int value = 0;
    TG_SYNCHRONIZED_BEGIN(_cachedUnreadCount);
    value = _cachedUnreadCount;
    TG_SYNCHRONIZED_END(_cachedUnreadCount);
    
    if (value != INT_MIN)
        return value;
    
    value = [self databaseState].unreadCount;
    TG_SYNCHRONIZED_BEGIN(_cachedUnreadCount);
    _cachedUnreadCount = value;
    TG_SYNCHRONIZED_END(_cachedUnreadCount);
    
    return value;
}

- (int)unreadCountForConversation:(int64_t)conversationId
{
    int unreadCount = 0;
    bool found = false;
    
    TG_SYNCHRONIZED_BEGIN(_unreadCountByConversation);
    std::map<int64_t, int>::iterator it = _unreadCountByConversation.find(conversationId);
    if (it != _unreadCountByConversation.end())
    {
        found = true;
        unreadCount = it->second;
    }
    TG_SYNCHRONIZED_END(_unreadCountByConversation);
    
    if (found)
        return unreadCount;
    
    TGLog(@"***** Suboptimal conversation unread count retrieval");
    unreadCount = [self loadConversationWithId:conversationId].unreadCount;
    return unreadCount;
}

- (void)setCustomProperty:(NSString *)key value:(NSData *)value
{
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ (key, value) VALUES (?, ?)", _serviceTableName], [[NSNumber alloc] initWithInt:murMurHash32(key)], value];
    } synchronous:false];
}

- (void)customProperty:(NSString *)key completion:(void (^)(NSData *value))completion
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT value FROM %@ WHERE key=?", _serviceTableName], [[NSNumber alloc] initWithInt:murMurHash32(key)]];
        if ([result next])
        {
            NSData *value = [result dataForColumn:@"value"];
            result = nil;
            
            if (completion)
                completion(value);
        }
        else
        {
            if (completion)
                completion(nil);
        }
    } synchronous:false];
}

- (NSData *)customProperty:(NSString *)key
{
    __block NSData *blockResult = nil;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT value FROM %@ WHERE key=?", _serviceTableName], [[NSNumber alloc] initWithInt:murMurHash32(key)]];
        if ([result next])
        {
            blockResult = [result dataForColumn:@"value"];
            result = nil;
        }
    } synchronous:true];
    
    return blockResult;
}

- (NSArray *)loadContactUsers
{
    NSMutableArray *users = [[NSMutableArray alloc] init];
    
    [self dispatchOnDatabaseThread:^
    {
        std::vector<int> uids;
        [self loadRemoteContactUids:uids];
        
        std::tr1::shared_ptr<std::map<int, TGUser *> > userMap = [self loadUsers:uids];
        for (std::map<int, TGUser *>::iterator it = userMap->begin(); it != userMap->end(); it++)
        {
            [users addObject:it->second];
        }
    } synchronous:true];
    
    return users;
}

- (void)loadRemoteContactUids:(std::vector<int> &)contactUids
{
    [self dispatchOnDatabaseThread:^
    {
        std::vector<int> uids;
        
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT uid FROM %@", _contactListTableName]];
        int uidIndex = [result columnIndexForName:@"uid"];
        while ([result next])
        {
            int uid = [result intForColumnIndex:uidIndex];
            contactUids.push_back(uid);
            uids.push_back(uid);
        }
        
        TG_SYNCHRONIZED_BEGIN(_remoteContactUids);
         _remoteContactUids.clear();
         _remoteContactUids.insert(uids.begin(), uids.end());
        TG_SYNCHRONIZED_END(_remoteContactUids);
    } synchronous:true];
}

- (void)loadRemoteContactUidsContactIds:(std::map<int, int> &)contactUidsAndIds
{
    [self dispatchOnDatabaseThread:^
    {
        std::vector<int> uids;
        [self loadRemoteContactUids:uids];
        
        std::tr1::shared_ptr<std::map<int, TGUser *> > userMap = [self loadUsers:uids];
        for (std::map<int, TGUser *>::iterator it = userMap->begin(); it != userMap->end(); it++)
        {
            int contactId = it->second.contactId;
            if (contactId != 0)
                contactUidsAndIds.insert(std::pair<int, int>(contactId, it->first));
        }
    } synchronous:true];
}

- (bool)haveRemoteContactUids
{
    bool haveCachedContacts = false;
    
    TG_SYNCHRONIZED_BEGIN(_remoteContactUids);
    haveCachedContacts = !_remoteContactUids.empty();
    TG_SYNCHRONIZED_END(_remoteContactUids);
    
    if (haveCachedContacts)
        return true;
    
    __block bool haveContacts = false;
    
    [self dispatchOnDatabaseThread:^
    {
        std::vector<int> uids;
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT uid FROM %@ LIMIT 1", _contactListTableName]];
        if ([result next])
        {
            haveContacts = true;
        }
        
        std::vector<int> v;
        [self loadRemoteContactUids:v];
    } synchronous:true];
    
    return haveContacts;
}

- (bool)uidIsRemoteContact:(int)uid
{
    bool haveCachedResults = false;
    bool cachedResult = false;
    
    TG_SYNCHRONIZED_BEGIN(_remoteContactUids);
    haveCachedResults = !_remoteContactUids.empty();
    if (haveCachedResults)
        cachedResult = _remoteContactUids.find(uid) != _remoteContactUids.end();
    TG_SYNCHRONIZED_END(_remoteContactUids);
    
    if (haveCachedResults)
        return cachedResult;
    
    __block bool isRemoteContact = false;
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT uid FROM %@ WHERE uid=?", _contactListTableName], [[NSNumber alloc] initWithInt:uid]];
        if ([result next])
        {
            isRemoteContact = true;
        }
        
        std::vector<int> v;
        [self loadRemoteContactUids:v];
    } synchronous:true];
    
    return isRemoteContact;
}

- (void)replaceRemoteContactUids:(NSArray *)uids
{
    TG_SYNCHRONIZED_BEGIN(_remoteContactUids);
    _remoteContactUids.clear();
    for (NSNumber *nUid in uids)
    {
        _remoteContactUids.insert([nUid intValue]);
    }
    TG_SYNCHRONIZED_END(_remoteContactUids);
    
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@", _contactListTableName]];
        [_database beginTransaction];
        NSString *queryFormat = [[NSString alloc] initWithFormat:@"INSERT INTO %@ (uid) VALUES (?)", _contactListTableName];
        for (NSNumber *nUid in uids)
        {
            [_database executeUpdate:queryFormat, nUid];
        }
        [_database commit];
    } synchronous:false];
}

- (void)addRemoteContactUids:(NSArray *)uids
{
    TG_SYNCHRONIZED_BEGIN(_remoteContactUids);
    for (NSNumber *nUid in uids)
    {
        _remoteContactUids.insert([nUid intValue]);
    }
    TG_SYNCHRONIZED_END(_remoteContactUids);
    
    [self dispatchOnDatabaseThread:^
    {
        [_database beginTransaction];
        NSString *queryFormat = [[NSString alloc] initWithFormat:@"INSERT OR IGNORE INTO %@ (uid) VALUES (?)", _contactListTableName];
        for (NSNumber *nUid in uids)
        {
            [_database executeUpdate:queryFormat, nUid];
        }
        [_database commit];
    } synchronous:false];
}

- (void)deleteRemoteContactUids:(NSArray *)uids
{
    TG_SYNCHRONIZED_BEGIN(_remoteContactUids);
    _remoteContactUids.clear();
    for (NSNumber *nUid in uids)
    {
        _remoteContactUids.erase([nUid intValue]);
    }
    TG_SYNCHRONIZED_END(_remoteContactUids);
    
    [self dispatchOnDatabaseThread:^
    {
        [_database beginTransaction];
        NSString *queryFormat = [[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE uid=?", _contactListTableName];
        for (NSNumber *nUid in uids)
        {
            [_database executeUpdate:queryFormat, nUid];
        }
        [_database commit];
    } synchronous:false];
}

- (void)addContactBindings:(NSArray *)contactBindings
{
    TG_SYNCHRONIZED_BEGIN(_contactsByPhoneId);
    for (TGContactBinding *binding in contactBindings)
    {
        _contactsByPhoneId[binding.phoneId] = binding;
    }
    TG_SYNCHRONIZED_END(_contactsByPhoneId);
}

- (void)deleteContactBinding:(int)phoneId
{
    TG_SYNCHRONIZED_BEGIN(_contactsByPhoneId);
    _contactsByPhoneId.erase(phoneId);
    TG_SYNCHRONIZED_END(_contactsByPhoneId);
}

- (void)replaceContactBindings:(NSArray *)contactBindings
{
    TG_SYNCHRONIZED_BEGIN(_contactsByPhoneId);
    _contactsByPhoneId.clear();
    for (TGContactBinding *binding in contactBindings)
    {
        _contactsByPhoneId.insert(std::pair<int, TGContactBinding *>(binding.phoneId, binding));
    }
    TG_SYNCHRONIZED_END(_contactsByPhoneId);
}

- (TGContactBinding *)contactBindingWithId:(int)phoneId
{
    TGContactBinding *result = nil;
    
    TG_SYNCHRONIZED_BEGIN(_contactsByPhoneId);
    std::map<int, TGContactBinding *>::iterator it = _contactsByPhoneId.find(phoneId);
    if (it != _contactsByPhoneId.end())
        result = it->second;
    TG_SYNCHRONIZED_END(_contactsByPhoneId);
    
    return result;
}

- (NSArray *)contactBindings
{
    NSMutableArray *array = nil;
    
    TG_SYNCHRONIZED_BEGIN(_contactsByPhoneId);
    array = [[NSMutableArray alloc] initWithCapacity:_contactsByPhoneId.size()];
    for (std::map<int, TGContactBinding *>::iterator it = _contactsByPhoneId.begin(); it != _contactsByPhoneId.end(); it++)
    {
        [array addObject:it->second];
    }
    TG_SYNCHRONIZED_END(_contactsByPhoneId);
    
    return array;
}

- (void)replacePhonebookContacts:(NSArray *)phonebookContacts
{
    TG_SYNCHRONIZED_BEGIN(_phonebookContacts);
    _phonebookContacts.clear();
    _phoneIdToNativeId.clear();
    
    for (TGPhonebookContact *contact in phonebookContacts)
    {
        _phonebookContacts.insert(std::pair<int, TGPhonebookContact *>(contact.nativeId, contact));
        [contact fillPhoneHashToNativeMap:&_phoneIdToNativeId replace:false];
    }
    TG_SYNCHRONIZED_END(_phonebookContacts);
}

- (TGPhonebookContact *)phonebookContactByNativeId:(int)nativeId
{
    TGPhonebookContact *result = nil;
    
    TG_SYNCHRONIZED_BEGIN(_phonebookContacts);
    std::map<int, TGPhonebookContact *>::iterator it = _phonebookContacts.find(nativeId);
    if (it != _phonebookContacts.end())
        result = it->second;
    TG_SYNCHRONIZED_END(_phonebookContacts);
    
    return result;
}

- (void)replacePhonebookContact:(int)nativeId phonebookContact:(TGPhonebookContact *)phonebookContact generateContactBindings:(bool)generateContactBindings
{
    std::vector<int> erasedPhoneIds;
    
    TG_SYNCHRONIZED_BEGIN(_phonebookContacts);
    if (nativeId != 0)
    {
        std::map<int, TGPhonebookContact *>::iterator it = _phonebookContacts.find(nativeId);
        if (it != _phonebookContacts.end())
        {
            for (TGPhoneNumber *numberDesc in it->second.phoneNumbers)
            {
                int phoneId = [numberDesc phoneId];
                _phoneIdToNativeId.erase(phoneId);
                erasedPhoneIds.push_back(phoneId);
            }
        }
        
        _phonebookContacts.erase(nativeId);
    }
    
    if (phonebookContact != nil)
    {
        _phonebookContacts[phonebookContact.nativeId] = phonebookContact;
        [phonebookContact fillPhoneHashToNativeMap:&_phoneIdToNativeId replace:true];
    }
    
    TG_SYNCHRONIZED_END(_phonebookContacts);
    
    if (generateContactBindings)
    {
        TG_SYNCHRONIZED_BEGIN(_contactsByPhoneId);
        for (std::vector<int>::iterator it = erasedPhoneIds.begin(); it != erasedPhoneIds.end(); it++)
        {
            _contactsByPhoneId.erase(*it);
        }
        
        if (phonebookContact != nil)
        {
            for (TGPhoneNumber *numberDesc in phonebookContact.phoneNumbers)
            {
                TGContactBinding *binding = [[TGContactBinding alloc] init];
                int phoneId = numberDesc.phoneId;
                if (phoneId != 0)
                {
                    binding.phoneId = numberDesc.phoneId;
                    binding.phoneNumber = numberDesc.number;
                    binding.firstName = phonebookContact.firstName;
                    binding.lastName = phonebookContact.lastName;
                    
                    _contactsByPhoneId[binding.phoneId] = binding;
                }
            }
        }
        TG_SYNCHRONIZED_END(_contactsByPhoneId);
    }
}

- (TGPhonebookContact *)phonebookContactByPhoneId:(int)phoneId
{
    TGPhonebookContact *result = nil;
    
    TG_SYNCHRONIZED_BEGIN(_phonebookContacts);
    std::map<int, int>::iterator it = _phoneIdToNativeId.find(phoneId);
    if (it != _phoneIdToNativeId.end())
    {
        std::map<int, TGPhonebookContact *>::iterator contactIt = _phonebookContacts.find(it->second);
        if (contactIt != _phonebookContacts.end())
            result = contactIt->second;
    }
    TG_SYNCHRONIZED_END(_phonebookContacts);
    
    return result;
}

- (NSArray *)loadPhonebookContacts
{
    NSMutableArray *array = nil;
    
    TG_SYNCHRONIZED_BEGIN(_phonebookContacts);
    array = [[NSMutableArray alloc] initWithCapacity:_phonebookContacts.size()];
    for (std::map<int, TGPhonebookContact *>::iterator it = _phonebookContacts.begin(); it != _phonebookContacts.end(); it++)
    {
        [array addObject:it->second];
    }
    TG_SYNCHRONIZED_END(_phonebookContacts);
    
    return array;
}

static inline TGMessage *loadMessageFromQueryResult(FMResultSet *result, int64_t conversationId, int indexMid, int indexMessage, int indexMedia, int indexFromId, int indexToId, int indexOutgoing, int indexUnread, int indexDeliveryState, int indexDate)
{
    TGMessage *message = [[TGMessage alloc] init];
    
    message.mid = [result intForColumnIndex:indexMid];
    message.cid = conversationId;
    message.localMid = message.mid >= TGMessageLocalMidBaseline ? message.mid : 0;
    message.local = message.localMid != 0;
    message.text = [result stringForColumnIndex:indexMessage];
    NSData *mediaData = [result dataForColumnIndex:indexMedia];
    if (mediaData != nil)
        message.mediaAttachments = [TGMessage parseMediaAttachments:mediaData];
    message.fromUid = [result longLongIntForColumnIndex:indexFromId];
    message.toUid = [result longLongIntForColumnIndex:indexToId];
    message.outgoing = [result intForColumnIndex:indexOutgoing];
    message.unread = [result intForColumnIndex:indexUnread];
    message.deliveryState = (TGMessageDeliveryState)[result intForColumnIndex:indexDeliveryState];
    message.date = [result intForColumnIndex:indexDate];
    
    return message;
}

static inline TGMessage *loadMessageFromQueryResult(FMResultSet *result)
{
    TGMessage *message = [[TGMessage alloc] init];
    
    message.mid = [result intForColumn:@"mid"];
    message.cid = [result longLongIntForColumn:@"cid"];
    message.localMid = message.mid >= TGMessageLocalMidBaseline ? message.mid : 0;
    message.local = message.localMid != 0;
    message.text = [result stringForColumn:@"message"];
    message.mediaAttachments = [TGMessage parseMediaAttachments:[result dataForColumn:@"media"]];
    message.fromUid = [result longLongIntForColumn:@"from_id"];
    message.toUid = [result longLongIntForColumn:@"to_id"];
    message.outgoing = [result intForColumn:@"outgoing"];
    message.unread = [result intForColumn:@"unread"];
    message.deliveryState = (TGMessageDeliveryState)[result intForColumn:@"dstate"];
    message.date = [result intForColumn:@"date"];
    
    return message;
}

- (TGMessage *)loadMediaMessageWithMid:(int)mid
{
    __block TGMessage *message = nil;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE mid=?", _conversationMediaTableName], [[NSNumber alloc] initWithInt:mid]];
        
        int dateIndex = [result columnIndexForName:@"date"];
        int midIndex = [result columnIndexForName:@"mid"];
        int mediaIndex = [result columnIndexForName:@"media"];
        int fromIdIndex = [result columnIndexForName:@"from_id"];
        
        if ([result next])
        {
            message = loadMessageMediaFromQueryResult(result, dateIndex, fromIdIndex, midIndex, mediaIndex);
        }
    } synchronous:true];
    
    return message;
}

- (TGMessage *)loadMessageWithMid:(int)mid
{
    __block TGMessage *message = nil;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE mid=?", _messagesTableName], [[NSNumber alloc] initWithInt:mid]];
        if ([result next])
            message = loadMessageFromQueryResult(result);
    } synchronous:true];
    
    return message;
}

- (void)loadMessagesFromConversation:(int64_t)conversationId maxMid:(int)argMaxMid maxDate:(int)argMaxDate maxLocalMid:(int)argMaxLocalMid atMessageId:(int)argAtMessageId limit:(int)argLimit extraUnread:(bool)extraUnread completion:(void (^)(NSArray *messages, bool historyExistsBelow))completion
{
    CFAbsoluteTime requestTime = CFAbsoluteTimeGetCurrent();
    
    [self dispatchOnDatabaseThread:^
    {
        int maxMid = argMaxMid;
        int maxDate = argMaxDate;
        int maxLocalMid = argMaxLocalMid;
        int atMessageId = argAtMessageId;
        int limit = argLimit;
        
        CFAbsoluteTime dbStartTime = CFAbsoluteTimeGetCurrent();
        
        NSMutableArray *array = [[NSMutableArray alloc] init];
        
        int extraLimit = 0;
        int extraOffset = 0;
        
        int downLimit = 0;
        int extraDownLimit = 0;
        int extraDownOffset = 0;
        
        NSNumber *nConversationId = [[NSNumber alloc] initWithLongLong:conversationId];
        
        if (atMessageId != 0)
        {
            FMResultSet *selectedMessageDateResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT date FROM %@ WHERE mid=?", _messagesTableName], [[NSNumber alloc] initWithInt:atMessageId]];
            if ([selectedMessageDateResult next])
            {
                downLimit = 10;
                limit = 18;
                maxDate = [selectedMessageDateResult intForColumn:@"date"];
            }
        }
        
        if (extraUnread)
        {
            int lastIncomingMid = 0;
            FMResultSet *lastIncomingResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE cid=? AND outgoing=0 ORDER BY date DESC LIMIT 1", _messagesTableName], nConversationId];
            if ([lastIncomingResult next])
                lastIncomingMid = [lastIncomingResult intForColumn:@"mid"];
            
            int lastUnreadMid = 0;
            FMResultSet *lastUnreadResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE cid=? AND unread=1 AND outgoing=0 ORDER BY date DESC LIMIT 1", _messagesTableName], nConversationId];
            if ([lastUnreadResult next])
                lastUnreadMid = [lastUnreadResult intForColumn:@"mid"];
            
            if (lastUnreadMid != 0 && lastIncomingMid != 0 && lastIncomingMid == lastUnreadMid)
            {   
                FMResultSet *dateResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT MIN(date) FROM %@ WHERE cid=? AND unread=1 AND outgoing=0", _messagesTableName], nConversationId];
                
                int minUnreadDate = INT_MAX;
                
                if ([dateResult next])
                    minUnreadDate = [dateResult intForColumn:@"MIN(date)"];
                
                if (minUnreadDate != INT_MAX)
                {
                    FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ WHERE cid=? AND date>=?", _messagesTableName], nConversationId, [[NSNumber alloc] initWithInt:minUnreadDate]];
                    int indexMid = [result columnIndexForName:@"mid"];
                    int indexMessage = [result columnIndexForName:@"message"];
                    int indexMedia = [result columnIndexForName:@"media"];
                    int indexFromId = [result columnIndexForName:@"from_id"];
                    int indexToId = [result columnIndexForName:@"to_id"];
                    int indexOutgoing = [result columnIndexForName:@"outgoing"];
                    int indexUnread = [result columnIndexForName:@"unread"];
                    int indexDeliveryState = [result columnIndexForName:@"dstate"];
                    int indexDate = [result columnIndexForName:@"date"];
                    
                    int loadedUnreadMessages = 0;
                    
                    while ([result next])
                    {
                        TGMessage *message = loadMessageFromQueryResult(result, conversationId, indexMid, indexMessage, indexMedia, indexFromId, indexToId, indexOutgoing, indexUnread, indexDeliveryState, indexDate);
                        
                        [array addObject:message];
                        
                        maxDate = MIN(maxDate, (int)message.date);
                        int mid = message.mid;
                        if (mid < TGMessageLocalMidBaseline)
                            maxMid = MIN(maxMid, mid);
                        else
                            maxLocalMid = MIN(maxLocalMid, mid);
                        
                        loadedUnreadMessages++;
                    }
                    
                    TGLog(@"Loaded %d unread messages", loadedUnreadMessages);
                }
            }
        }
        
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=? AND date<=? ORDER BY date DESC LIMIT ?", _messagesTableName], nConversationId, [[NSNumber alloc] initWithInt:maxDate], [[NSNumber alloc] initWithInt:limit + 1]];
        
        int indexMid = [result columnIndexForName:@"mid"];
        int indexMessage = [result columnIndexForName:@"message"];
        int indexMedia = [result columnIndexForName:@"media"];
        int indexFromId = [result columnIndexForName:@"from_id"];
        int indexToId = [result columnIndexForName:@"to_id"];
        int indexOutgoing = [result columnIndexForName:@"outgoing"];
        int indexUnread = [result columnIndexForName:@"unread"];
        int indexDeliveryState = [result columnIndexForName:@"dstate"];
        int indexDate = [result columnIndexForName:@"date"];
        
        while ([result next])
        {
            extraOffset++;
            
            int mid = [result intForColumnIndex:indexMid];
            if (mid >= TGMessageLocalMidBaseline)
            {
                if (mid >= maxLocalMid)
                {
                    extraLimit++;
                    continue;
                }
            }
            else if (mid >= maxMid)
            {
                extraLimit++;
                continue;
            }
            
            TGMessage *message = loadMessageFromQueryResult(result, conversationId, indexMid, indexMessage, indexMedia, indexFromId, indexToId, indexOutgoing, indexUnread, indexDeliveryState, indexDate);
            [array addObject:message];
        }
        
        
        if (extraLimit > 1)
        {
            TGLog(@"Loading %d extra messages", extraLimit);
            result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=? AND date<=? ORDER BY date DESC LIMIT ?, ?", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:maxDate], [[NSNumber alloc] initWithInt:extraOffset], [[NSNumber alloc] initWithInt:extraLimit]];
            
            indexMid = [result columnIndexForName:@"mid"];
            indexMessage = [result columnIndexForName:@"message"];
            indexMedia = [result columnIndexForName:@"media"];
            indexFromId = [result columnIndexForName:@"from_id"];
            indexToId = [result columnIndexForName:@"to_id"];
            indexOutgoing = [result columnIndexForName:@"outgoing"];
            indexUnread = [result columnIndexForName:@"unread"];
            indexDeliveryState = [result columnIndexForName:@"dstate"];
            indexDate = [result columnIndexForName:@"date"];
            
            while ([result next])
            {
                int mid = [result intForColumnIndex:indexMid];
                if (mid >= TGMessageLocalMidBaseline)
                {
                    if (mid >= maxLocalMid)
                        continue;
                }
                else if (mid >= maxMid)
                    continue;
                
                TGMessage *message = loadMessageFromQueryResult(result, conversationId, indexMid, indexMessage, indexMedia, indexFromId, indexToId, indexOutgoing, indexUnread, indexDeliveryState, indexDate);
                [array addObject:message];
            }
        }
        
        int loadedDownMessages = 0;
        
        if (downLimit > 0)
        {
            if (array.count < 18)
                downLimit = 30;
            
            int loadedMaxDate = INT_MIN;
            int loadedMaxMid = INT_MIN;
            int loadedMaxLocalMid = INT_MIN;
            
            for (TGMessage *message in array)
            {
                loadedMaxDate = MAX(loadedMaxDate, (int)message.date);
                int mid = message.mid;
                if (mid >= TGMessageLocalMidBaseline)
                    loadedMaxLocalMid = MAX(loadedMaxLocalMid, mid);
                else
                    loadedMaxMid = MAX(loadedMaxMid, mid);
            }
            
            if (loadedMaxDate != INT_MIN)
            {
                result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=? AND date>=? ORDER BY date ASC LIMIT ?", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:loadedMaxDate], [[NSNumber alloc] initWithInt:downLimit]];
                
                indexMid = [result columnIndexForName:@"mid"];
                indexMessage = [result columnIndexForName:@"message"];
                indexMedia = [result columnIndexForName:@"media"];
                indexFromId = [result columnIndexForName:@"from_id"];
                indexToId = [result columnIndexForName:@"to_id"];
                indexOutgoing = [result columnIndexForName:@"outgoing"];
                indexUnread = [result columnIndexForName:@"unread"];
                indexDeliveryState = [result columnIndexForName:@"dstate"];
                indexDate = [result columnIndexForName:@"date"];
                
                while ([result next])
                {
                    extraDownOffset++;
                    
                    int mid = [result intForColumnIndex:indexMid];
                    if (mid >= TGMessageLocalMidBaseline)
                    {
                        if (mid <= loadedMaxLocalMid)
                        {
                            extraDownLimit++;
                            continue;
                        }
                    }
                    else if (mid <= loadedMaxMid)
                    {
                        extraDownLimit++;
                        continue;
                    }
                    
                    loadedDownMessages++;
                    TGMessage *message = loadMessageFromQueryResult(result, conversationId, indexMid, indexMessage, indexMedia, indexFromId, indexToId, indexOutgoing, indexUnread, indexDeliveryState, indexDate);
                    [array addObject:message];
                }
            }
            
            if (extraDownLimit != 0)
            {
                result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=? AND date>=? ORDER BY date ASC LIMIT ?, ?", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:loadedMaxDate], [[NSNumber alloc] initWithInt:extraDownOffset], [[NSNumber alloc] initWithInt:extraDownLimit]];
                
                indexMid = [result columnIndexForName:@"mid"];
                indexMessage = [result columnIndexForName:@"message"];
                indexMedia = [result columnIndexForName:@"media"];
                indexFromId = [result columnIndexForName:@"from_id"];
                indexToId = [result columnIndexForName:@"to_id"];
                indexOutgoing = [result columnIndexForName:@"outgoing"];
                indexUnread = [result columnIndexForName:@"unread"];
                indexDeliveryState = [result columnIndexForName:@"dstate"];
                indexDate = [result columnIndexForName:@"date"];
                
                while ([result next])
                {
                    int mid = [result intForColumnIndex:indexMid];
                    if (mid >= TGMessageLocalMidBaseline)
                    {
                        if (mid <= loadedMaxLocalMid)
                            continue;
                    }
                    else if (mid <= loadedMaxMid)
                        continue;
                    
                    loadedDownMessages++;
                    TGMessage *message = loadMessageFromQueryResult(result, conversationId, indexMid, indexMessage, indexMedia, indexFromId, indexToId, indexOutgoing, indexUnread, indexDeliveryState, indexDate);
                    [array addObject:message];
                }
            }
        }
        
        TGLog(@"===== Parse time: %f ms (%f ms)", (CFAbsoluteTimeGetCurrent() - dbStartTime) * 1000.0, (CFAbsoluteTimeGetCurrent() - requestTime) * 1000.0);
        
        if (completion)
            completion(array, downLimit != 0 && loadedDownMessages != 0);
    } synchronous:false];
}

- (void)loadMessagesFromConversationDownwards:(int64_t)conversationId minMid:(int)argMinMid minLocalMid:(int)argMinLocalMid minDate:(int)argMinDate limit:(int)argLimit completion:(void (^)(NSArray *messages))completion
{
    [self dispatchOnDatabaseThread:^
    {
        int minMid = argMinMid;
        int minLocalMid = argMinLocalMid;
        int minDate = argMinDate;
        int limit = argLimit;
        
        NSMutableArray *array = [[NSMutableArray alloc] init];
        
        int extraLimit = 0;
        int extraOffset = 0;

        NSNumber *nConversationId = [[NSNumber alloc] initWithLongLong:conversationId];
        
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=? AND date>=? ORDER BY date ASC LIMIT ?", _messagesTableName], nConversationId, [[NSNumber alloc] initWithInt:minDate], [[NSNumber alloc] initWithInt:limit + 1]];
        
        int indexMid = [result columnIndexForName:@"mid"];
        int indexMessage = [result columnIndexForName:@"message"];
        int indexMedia = [result columnIndexForName:@"media"];
        int indexFromId = [result columnIndexForName:@"from_id"];
        int indexToId = [result columnIndexForName:@"to_id"];
        int indexOutgoing = [result columnIndexForName:@"outgoing"];
        int indexUnread = [result columnIndexForName:@"unread"];
        int indexDeliveryState = [result columnIndexForName:@"dstate"];
        int indexDate = [result columnIndexForName:@"date"];
        
        while ([result next])
        {
            extraOffset++;
            
            int mid = [result intForColumnIndex:indexMid];
            if (mid >= TGMessageLocalMidBaseline)
            {
                if (mid <= minLocalMid)
                {
                    extraLimit++;
                    continue;
                }
            }
            else if (mid <= minMid)
            {
                extraLimit++;
                continue;
            }
            
            TGMessage *message = loadMessageFromQueryResult(result, conversationId, indexMid, indexMessage, indexMedia, indexFromId, indexToId, indexOutgoing, indexUnread, indexDeliveryState, indexDate);
            [array addObject:message];
        }
        
        
        if (extraLimit > 1)
        {
            TGLog(@"Loading %d extra messages", extraLimit);
            result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=? AND date>=? ORDER BY date ASC LIMIT ?, ?", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:minDate], [[NSNumber alloc] initWithInt:extraOffset], [[NSNumber alloc] initWithInt:extraLimit]];
            
            indexMid = [result columnIndexForName:@"mid"];
            indexMessage = [result columnIndexForName:@"message"];
            indexMedia = [result columnIndexForName:@"media"];
            indexFromId = [result columnIndexForName:@"from_id"];
            indexToId = [result columnIndexForName:@"to_id"];
            indexOutgoing = [result columnIndexForName:@"outgoing"];
            indexUnread = [result columnIndexForName:@"unread"];
            indexDeliveryState = [result columnIndexForName:@"dstate"];
            indexDate = [result columnIndexForName:@"date"];
            
            while ([result next])
            {
                int mid = [result intForColumnIndex:indexMid];
                if (mid >= TGMessageLocalMidBaseline)
                {
                    if (mid <= minLocalMid)
                        continue;
                }
                else if (mid <= minMid)
                    continue;
                
                TGMessage *message = loadMessageFromQueryResult(result, conversationId, indexMid, indexMessage, indexMedia, indexFromId, indexToId, indexOutgoing, indexUnread, indexDeliveryState, indexDate);
                [array addObject:message];
            }
        }
        
        if (completion)
            completion(array);
    } synchronous:false];
}

- (void)renewLocalMessagesInConversation:(NSArray *)messages conversationId:(int64_t)conversationId
{
    bool needsData = false;
    for (TGMessage *message in messages)
    {
        if (message.local)
        {
            needsData = true;
            break;
        }
    }

    [self dispatchOnDatabaseThread:^
    {
        NSString *insertQueryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (mid, cid, localMid, message, media, from_id, to_id, outgoing, unread, dstate, date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", _messagesTableName];
        NSString *updateQueryFormat = [NSString stringWithFormat:@"UPDATE %@ SET mid=?, cid=?, message=?, media=?, from_id=?, to_id=?, outgoing=?, unread=?, dstate=?, date=? WHERE mid=?", _messagesTableName];
        
        NSString *mediaInsertQueryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (mid, cid, date, from_id, type, media) VALUES (?, ?, ?, ?, ?, ?)", _conversationMediaTableName];
        NSString *mediaUpdateQueryFormat = [NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET mid=?, cid=?, date=?, from_id=?, type=?, media=? WHERE mid=?", _conversationMediaTableName];
        NSString *outboxInsertQueryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (mid, cid, dstate, local_media_id) VALUES (?, ?, ?, ?)", _outgoingMessagesTableName];
        NSString *outboxUpdateQueryFormat = [NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET mid=?, cid=?, dstate=?, local_media_id=? WHERE mid=?", _outgoingMessagesTableName];
        
        int messageLifetime = 0;
        if (conversationId <= INT_MIN)
            messageLifetime = [self messageLifetimeForPeerId:conversationId];

        int localIdCount = 0;
        for (TGMessage *message in messages)
        {
            if (message.local)
            {
                localIdCount++;
            }
        }
        
        NSArray *localMids = [self generateLocalMids:localIdCount];
        
        int localMidIndex = 0;
        
        [_database beginTransaction];

        TGMessage *lastMesage = nil;
        
        NSMutableArray *changedMessageIds = [[NSMutableArray alloc] init];

        for (TGMessage *message in messages)
        {
            FMResultSet *existingResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ WHERE mid=?", _messagesTableName], [[NSNumber alloc] initWithInt:message.mid]];
            
            FMResultSet *existingMediaResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE mid=?", _conversationMediaTableName], [[NSNumber alloc] initWithInt:message.mid]];
            FMResultSet *existingOutboxResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE mid=?", _outgoingMessagesTableName], [[NSNumber alloc] initWithInt:message.mid]];
            
            bool update = [existingResult next];
            bool updateMedia = [existingMediaResult next];
            bool updateOutbox = [existingOutboxResult next];
            
            int previousMid = message.mid;

            if (needsData && message.local)
            {   
                message.mid = [[localMids objectAtIndex:localMidIndex++] intValue];
                message.localMid = message.mid;
                
                [changedMessageIds addObject:[[NSArray alloc] initWithObjects:[[NSNumber alloc] initWithInt:previousMid], [[NSNumber alloc] initWithInt:message.mid], nil]];
            }

            if (lastMesage == nil || message.date > lastMesage.date || (message.date == lastMesage.date && message.mid > lastMesage.mid))
            {
                lastMesage = message;
            }
            
            int localMediaId = 0;
            
#warning why is localmediaid not being used?
            
            NSData *mediaData = nil;
            
            int64_t localVideoId = 0;
            int64_t videoId = 0;
            
            int mediaType = 0;
            
            if (message.mediaAttachments != nil && message.mediaAttachments.count != 0)
            {   
                for (TGMediaAttachment *attachment in message.mediaAttachments)
                {
                    if (attachment.type == TGLocalMessageMetaMediaAttachmentType)
                    {
                        localMediaId = ((TGLocalMessageMetaMediaAttachment *)attachment).localMediaId;
                    }
                    else if (attachment.type == TGImageMediaAttachmentType)
                    {
                        mediaData = [TGMessage serializeAttachment:attachment];
                        mediaType = 0;
                    }
                    else if (attachment.type == TGVideoMediaAttachmentType)
                    {
                        TGVideoMediaAttachment *videoAttachment = (TGVideoMediaAttachment *)attachment;
                        videoId = videoAttachment.videoId;
                        localVideoId = videoAttachment.localVideoId;
                        mediaData = [TGMessage serializeAttachment:attachment];
                        mediaType = 1;
                    }
                }
            }
            
            if (update)
            {
                [_database executeUpdate:updateQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], message.text, [message serializeMediaAttachments:false], [[NSNumber alloc] initWithLongLong:message.fromUid], [[NSNumber alloc] initWithLongLong:message.toUid], [[NSNumber alloc] initWithInt:message.outgoing ? 1 : 0], [[NSNumber alloc] initWithInt:message.unread ? 1 : 0], [[NSNumber alloc] initWithInt:message.deliveryState], [[NSNumber alloc] initWithInt:(int)(message.date)], [[NSNumber alloc] initWithInt:previousMid]];
            }
            else
            {
                [_database executeUpdate:insertQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:messageLifetime], message.text, [message serializeMediaAttachments:false], [[NSNumber alloc] initWithLongLong:message.fromUid], [[NSNumber alloc] initWithLongLong:message.toUid], [[NSNumber alloc] initWithInt:message.outgoing ? 1 : 0], [[NSNumber alloc] initWithInt:message.unread ? 1 : 0], [[NSNumber alloc] initWithInt:message.deliveryState], [[NSNumber alloc] initWithInt:(int)(message.date)]];
            }
            
            if (videoId != 0)
            {
                addVideoMid(self, message.mid, videoId, false);
                removeVideoMid(self, previousMid, videoId, false);
            }
            
            if (localVideoId != 0)
            {
                addVideoMid(self, message.mid, videoId, true);
                removeVideoMid(self, previousMid, videoId, true);
            }
            
            if (updateMedia)
            {
                if (mediaData != nil && mediaData.length != 0)
                    [_database executeUpdate:mediaUpdateQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:(int)message.date], [[NSNumber alloc] initWithInt:(int)message.fromUid], [[NSNumber alloc] initWithInt:mediaType], mediaData, [[NSNumber alloc] initWithInt:previousMid]];
            }
            else
            {
                if (mediaData != nil && mediaData.length != 0)
                    [_database executeUpdate:mediaInsertQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:(int)message.date], [[NSNumber alloc] initWithInt:(int)message.fromUid], [[NSNumber alloc] initWithInt:mediaType], mediaData];
            }
            
            if (updateOutbox)
            {
                if (message.local && message.deliveryState == TGMessageDeliveryStatePending)
                    [_database executeUpdate:outboxUpdateQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:message.deliveryState], [[NSNumber alloc] initWithInt:previousMid], [[NSNumber alloc] initWithInt:previousMid]];
            }
            else
            {
                if (message.local && message.deliveryState == TGMessageDeliveryStatePending)
                    [_database executeUpdate:outboxInsertQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:message.deliveryState], [[NSNumber alloc] initWithInt:previousMid]];
            }
        }
        
        [_database commit];

        if (lastMesage != nil)
        {
            [self actualizeConversation:conversationId dispatch:true];
        }
        
        [self dispatchOnIndexThread:^
        {
            NSString *indexInsertFormat = [NSString stringWithFormat:@"UPDATE %@ SET docid=? WHERE docid=?", _messageIndexTableName];
            
            [_indexDatabase beginTransaction];
            for (NSArray *mids in changedMessageIds)
            {
                [_indexDatabase executeUpdate:indexInsertFormat, [mids objectAtIndex:1], [mids objectAtIndex:0]];
            }
            [_indexDatabase commit];
        } synchronous:false];
    } synchronous:needsData];
}

- (void)replaceMediaInMessagesWithLocalMediaId:(int)localMediaId media:(NSData *)media
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE local_media_id=?", _outgoingMessagesTableName], [[NSNumber alloc] initWithInt:localMediaId]];
        while ([result next])
        {
            int mid = [result intForColumn:@"mid"];
            
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET media=? WHERE mid=?", _messagesTableName], media, [[NSNumber alloc] initWithInt:mid]];
        }
    } synchronous:false];
}

- (NSArray *)generateLocalMids:(int)count
{
    NSMutableArray *result = [[NSMutableArray alloc] init];
    
    TG_SYNCHRONIZED_BEGIN(_nextLocalMid);
    
    if (_nextLocalMid == 0)
    {
        __block int databaseResult = 0;
        [self dispatchOnDatabaseThread:^
        {
            FMResultSet *nextLocalMidResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT * from %@ WHERE key=%d", _serviceTableName, _serviceLastMidKey]];
            if ([nextLocalMidResult next])
            {
                NSData *value = [nextLocalMidResult dataForColumn:@"value"];
                int intValue = 0;
                [value getBytes:&intValue range:NSMakeRange(0, 4)];
                databaseResult = intValue;
            }
            else
                databaseResult = 800000000;
        } synchronous:true];
        
        _nextLocalMid = databaseResult;
    }
    
    for (int i = 0; i < count; i++)
    {
        [result addObject:[[NSNumber alloc] initWithInt:_nextLocalMid++]];
    }
    
    int storeLocalMid = _nextLocalMid;
    NSData *storeData = [[NSData alloc] initWithBytes:&storeLocalMid length:4];
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (key, value) VALUES (?, ?)", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceLastMidKey], storeData];
    } synchronous:false];
    
    TG_SYNCHRONIZED_END(_nextLocalMid);
    
    return result;
}

- (void)addMessagesToConversation:(NSArray *)argMessages conversationId:(int64_t)conversationId updateConversation:(TGConversation *)conversation dispatch:(bool)dispatch countUnread:(bool)countUnread
{
    int localIdCount = 0;
    for (TGMessage *message in argMessages)
    {
        if (message.mid == 0 || message.mid == INT_MIN)
        {
            localIdCount++;
        }
    }
    if (localIdCount != 0)
    {
        NSArray *localMids = [self generateLocalMids:localIdCount];
        //TGLog(@"Local mids: %@", localMids);
        int localMidIndex = 0;
        for (TGMessage *message in argMessages)
        {
            if (message.mid == 0)
            {
                message.mid = [[localMids objectAtIndex:localMidIndex++] intValue];
                message.localMid = message.mid;
            }
            else if (message.mid == INT_MIN)
            {
                message.mid = INT_MIN + 1 + ([[localMids objectAtIndex:localMidIndex++] intValue] - 800000000);
            }
        }
    }
    
    [self dispatchOnDatabaseThread:^
    {
        NSArray *messages = argMessages;
        
        std::map<int64_t, int> randomIdToPosition;
        
        int positionIndex = -1;
        for (TGMessage *message in argMessages)
        {
            positionIndex++;
            if (message.randomId != 0)
                randomIdToPosition.insert(std::pair<int64_t, int>(message.randomId, positionIndex));
        }
        
        if (!randomIdToPosition.empty())
        {
            NSMutableArray *modifiedMessages = [[NSMutableArray alloc] initWithArray:argMessages];
            messages = modifiedMessages;
            
            [_database setSoftShouldCacheStatements:false];
            NSMutableString *rangeString = [[NSMutableString alloc] init];
            
            NSMutableIndexSet *removeIndices = [[NSMutableIndexSet alloc] init];
            
            const int batchSize = 256;
            for (auto it = randomIdToPosition.begin(); it != randomIdToPosition.end(); )
            {
                [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
                bool first = true;
                
                for (int i = 0; i < batchSize && it != randomIdToPosition.end(); i++, it++)
                {
                    if (first)
                    {
                        first = false;
                        [rangeString appendFormat:@"%lld", it->first];
                    }
                    else
                        [rangeString appendFormat:@",%lld", it->first];
                }
                
                FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT random_id FROM %@ WHERE random_id IN (%@)", _randomIdsTableName, rangeString]];
                int randomIdIndex = [result columnIndexForName:@"random_id"];
                while ([result next])
                {
                    int64_t randomId = [result longLongIntForColumnIndex:randomIdIndex];
                    
                    auto indexIt = randomIdToPosition.find(randomId);
                    if (indexIt != randomIdToPosition.end())
                        [removeIndices addIndex:indexIt->second];
                }
            }
            [_database setSoftShouldCacheStatements:true];
            
            if (removeIndices.count != 0)
            {
                TGLog(@"(not adding %d duplicate messages by random id)", removeIndices.count);
                [modifiedMessages removeObjectsAtIndexes:removeIndices];
            }
        }
        
        int messageLifetime = 0;
        if (conversationId <= INT_MIN)
            messageLifetime = [self messageLifetimeForPeerId:conversationId];
        
        NSString *queryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (mid, cid, localMid, message, media, from_id, to_id, outgoing, unread, dstate, date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", _messagesTableName];
        
        NSString *mediaInsertQueryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (mid, cid, date, from_id, type, media) VALUES (?, ?, ?, ?, ?, ?)", _conversationMediaTableName];
        
        NSString *outboxInsertQueryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (mid, cid, dstate, local_media_id) VALUES (?, ?, ?, ?)", _outgoingMessagesTableName];
        
        NSString *randomIdInsertFormat = [[NSString alloc] initWithFormat:@"INSERT OR IGNORE INTO %@ (random_id, mid) VALUES (?, ?)", _randomIdsTableName];
        
        TGMessage *lastMesage = nil;
        
        int unreadCount = 0;
        int localUnreadCount = 0;
        
        int messagesCount = messages.count;
        NSMutableString *rangeString = [[NSMutableString alloc] init];
        [_database setSoftShouldCacheStatements:false];
        for (int i = 0; i < messagesCount; )
        {
            if (rangeString.length != 0)
                [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
            
            int maybeUnreadCount = 0;
            int maybeLocalUnreadCount = 0;
            
            std::vector<int> checkingMids;
            
            bool first = true;
            for (int lastI = i + 64; i < messagesCount && i < lastI; i++)
            {
                TGMessage *message = [messages objectAtIndex:i];
                int mid = message.mid;
                if (message.outgoing || !message.unread)
                    continue;
                
                if (first)
                    first = false;
                else
                    [rangeString appendString:@","];
                
                [rangeString appendFormat:@"%d", mid];
                checkingMids.push_back(mid);
                
                if (mid >= TGMessageLocalMidBaseline)
                    maybeLocalUnreadCount++;
                else
                    maybeUnreadCount++;
            }
            
            if (maybeUnreadCount != 0 || maybeLocalUnreadCount != 0)
            {
                if (maybeLocalUnreadCount != 0)
                {
                    FMResultSet *alreadyThereResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT mid FROM %@ WHERE mid IN (%@)", _messagesTableName, rangeString]];
                    int midIndex = [alreadyThereResult columnIndexForName:@"mid"];
                    
                    std::set<int> alreadyThereSet;
                    
                    while ([alreadyThereResult next])
                    {
                        int mid = [alreadyThereResult intForColumnIndex:midIndex];
                        alreadyThereSet.insert(mid);
                    }
                    
                    if (alreadyThereSet.empty())
                    {
                        unreadCount += maybeUnreadCount;
                        localUnreadCount += maybeLocalUnreadCount;
                    }
                    else
                    {
                        for (auto it = checkingMids.begin(); it != checkingMids.end(); it++)
                        {
                            if (*it < TGMessageLocalMidBaseline)
                            {
                                if (alreadyThereSet.find(*it) == alreadyThereSet.end())
                                    unreadCount++;
                            }
                            else
                            {
                                if (alreadyThereSet.find(*it) == alreadyThereSet.end())
                                    localUnreadCount++;
                            }
                        }
                    }
                }
                else
                {
                    FMResultSet *countResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE mid IN (%@)", _messagesTableName, rangeString]];
                    if ([countResult next])
                    {
                        int alreadyThere = [countResult intForColumn:@"COUNT(*)"];
                        maybeUnreadCount -= alreadyThere;
                    }
                    
                    unreadCount += maybeUnreadCount;
                }
            }
        }
        [_database setSoftShouldCacheStatements:true];
        
        [_database beginTransaction];
        for (TGMessage *message in messages)
        {   
            if (message.mid == 0)
            {
                TGLog(@"***** Error: message mid = 0");
                continue;
            }
            
            if (lastMesage == nil || message.date > lastMesage.date || (message.date == lastMesage.date && message.mid > lastMesage.mid))
            {
                lastMesage = message;
            }
            
            NSData *mediaData = nil;
            int mediaType = 0;
            if (message.mediaAttachments != nil && message.mediaAttachments.count != 0)
            {
                for (TGMediaAttachment *attachment in message.mediaAttachments)
                {
                    if (attachment.type == TGImageMediaAttachmentType)
                    {
                        mediaData = [TGMessage serializeAttachment:attachment];
                        mediaType = 0;
                    }
                    else if (attachment.type == TGVideoMediaAttachmentType)
                    {
                        mediaData = [TGMessage serializeAttachment:attachment];
                        mediaType = 1;
                        
                        TGVideoMediaAttachment *videoAttachment = (TGVideoMediaAttachment *)attachment;
                        if (videoAttachment.videoId != 0)
                            addVideoMid(self, message.mid, videoAttachment.videoId, false);
                        else if (videoAttachment.localVideoId != 0)
                            addVideoMid(self, message.mid, videoAttachment.localVideoId, true);
                    }
                }
            }
            
            [_database executeUpdate:queryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:messageLifetime], message.text, [message serializeMediaAttachments:false], [[NSNumber alloc] initWithLongLong:message.fromUid], [[NSNumber alloc] initWithLongLong:message.toUid], [[NSNumber alloc] initWithInt:message.outgoing ? 1 : 0], [[NSNumber alloc] initWithInt:message.unread ? 1 : 0], [[NSNumber alloc] initWithInt:message.deliveryState], [[NSNumber alloc] initWithInt:(int)(message.date)]];
            
            if (mediaData != nil && mediaData.length != 0)
                [_database executeUpdate:mediaInsertQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:(int)message.date], [[NSNumber alloc] initWithInt:(int)message.fromUid], [[NSNumber alloc] initWithInt:mediaType], mediaData];
            
            if (message.local && message.deliveryState == TGMessageDeliveryStatePending)
            {
                int localMediaId = 0;
                
                for (TGMediaAttachment *attachment in message.mediaAttachments)
                {
                    if (attachment.type == TGLocalMessageMetaMediaAttachmentType)
                    {
                        localMediaId = ((TGLocalMessageMetaMediaAttachment *)attachment).localMediaId;
                        break;
                    }
                }
                
                [_database executeUpdate:outboxInsertQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:message.deliveryState], [[NSNumber alloc] initWithInt:localMediaId]];
            }
            
            if (message.randomId != 0)
            {
                [_database executeUpdate:randomIdInsertFormat, [[NSNumber alloc] initWithLongLong:message.randomId], [[NSNumber alloc] initWithInt:message.mid]];
            }
        }
        
        [_database commit];
        
        if (!countUnread)
        {
            unreadCount = 0;
            localUnreadCount = 0;
        }
        else if (conversationId < 0 && conversation == nil)
        {
            FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT cid FROM %@ WHERE cid=?", _conversationListTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
            if (![result next])
            {
                unreadCount = 0;
                localUnreadCount = 0;
            }
        }
        
        if (dispatch)
        {
            if (lastMesage != nil)
            {
                [self actualizeConversation:conversationId dispatch:true conversation:conversation forceUpdate:(unreadCount != 0 || localUnreadCount != 0) addUnreadCount:unreadCount addServiceUnreadCount:localUnreadCount keepDate:false];
            }
            else if (conversation != nil)
            {
                [self actualizeConversation:conversationId dispatch:true conversation:conversation forceUpdate:true addUnreadCount:unreadCount addServiceUnreadCount:localUnreadCount keepDate:false];
            }
            
            if (unreadCount != 0)
            {
                int newUnreadCount = [self databaseState].unreadCount + unreadCount;
                if (newUnreadCount < 0)
                    TGLog(@"***** Warning: wrong unread_count");
                [self setUnreadCount:MAX(newUnreadCount, 0)];
            }
        }
        
        [self dispatchOnIndexThread:^
        {
            NSString *indexInsertQueryFormat = [NSString stringWithFormat:@"INSERT OR IGNORE INTO %@ (docid, text) VALUES (?, ?)", _messageIndexTableName];
            [_indexDatabase beginTransaction];
            for (TGMessage *message in messages)
            {
                if (message.text.length != 0)
                    [_indexDatabase executeUpdate:indexInsertQueryFormat, [[NSNumber alloc] initWithInt:message.mid], [message.text lowercaseString]];
            }
            [_indexDatabase commit];
        } synchronous:false];
    } synchronous:false];
}

- (void)setTempIdForMessageId:(int)messageId tempId:(int64_t)tempId
{
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ (tmp_id, mid) VALUES (?, ?)", _temporaryMessageIdsTableName], [[NSNumber alloc] initWithLongLong:tempId], [[NSNumber alloc] initWithInt:messageId]];
    } synchronous:false];
}

- (int)messageIdForTempId:(int64_t)tempId
{
    __block int messageId = 0;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *resultSet = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ where tmp_id=?", _temporaryMessageIdsTableName], [[NSNumber alloc] initWithLongLong:tempId]];
        if ([resultSet next])
        {
            messageId = [resultSet intForColumn:@"mid"];
        }
    } synchronous:true];
    
    return messageId;
}

- (void)tempIdsForLocalMessages:(void (^)(std::vector<std::pair<int64_t, int> >))completion
{
    [self dispatchOnDatabaseThread:^
    {
        std::vector<std::pair<int64_t, int> > result;
        
        FMResultSet *resultSet = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT tmp_id, mid FROM %@ where mid >= %d", _temporaryMessageIdsTableName, TGMessageLocalMidBaseline]];
        int tmpIdIndex = [resultSet columnIndexForName:@"tmp_id"];
        int midIndex = [resultSet columnIndexForName:@"mid"];
        
        while ([resultSet next])
        {
            int64_t tempId = [resultSet longLongIntForColumnIndex:tmpIdIndex];
            int mid = [resultSet intForColumnIndex:midIndex];
            
            result.push_back(std::make_pair(tempId, mid));
        }
        
        if (completion)
            completion(result);
    } synchronous:false];
}

- (void)removeTempIds:(NSArray *)tempIds
{
    [self dispatchOnDatabaseThread:^
    {
        [_database setSoftShouldCacheStatements:false];
        
        NSMutableString *tempIdsString = [[NSMutableString alloc] init];
        
        int count = tempIds.count;
        for (int i = 0; i < count; i += 128)
        {
            [tempIdsString deleteCharactersInRange:NSMakeRange(0, tempIdsString.length)];
            
            for (int j = i; j < count && j < 128; j++)
            {
                int64_t tempId = [[tempIds objectAtIndex:j] longLongValue];
                
                if (j != i)
                    [tempIdsString appendFormat:@",%lld", tempId];
                else
                    [tempIdsString appendFormat:@"%lld", tempId];
            }
            
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE tmp_id IN (%@)", _temporaryMessageIdsTableName, tempIdsString]];
        }
        
        [_database setSoftShouldCacheStatements:true];
    } synchronous:false];
}

- (void)messageIdsForTempIds:(NSArray *)tempIds mapping:(std::map<int64_t, int> *)mapping
{
    [self dispatchOnDatabaseThread:^
    {
        [_database setSoftShouldCacheStatements:false];
        
        NSMutableString *tempIdsString = [[NSMutableString alloc] init];
        
        int count = tempIds.count;
        for (int i = 0; i < count; i += 128)
        {
            [tempIdsString deleteCharactersInRange:NSMakeRange(0, tempIdsString.length)];
            
            for (int j = i; j < count && j < 128; j++)
            {
                int64_t tempId = [[tempIds objectAtIndex:j] longLongValue];
                
                if (j != i)
                    [tempIdsString appendFormat:@",%lld", tempId];
                else
                    [tempIdsString appendFormat:@"%lld", tempId];
            }
            
            FMResultSet *resultSet = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT tmp_id, mid FROM %@ where tmp_id IN (%@)", _temporaryMessageIdsTableName, tempIdsString]];
            
            int tmpIdIndex = [resultSet columnIndexForName:@"tmp_id"];
            int midIndex = [resultSet columnIndexForName:@"mid"];
            
            while ([resultSet next])
            {
                mapping->insert(std::pair<int64_t, int>([resultSet longLongIntForColumnIndex:tmpIdIndex], [resultSet intForColumnIndex:midIndex]));
            }
        }
        
        [_database setSoftShouldCacheStatements:true];
    } synchronous:true];
}

- (void)updateMessage:(int)mid flags:(std::vector<TGDatabaseMessageFlagValue> const &)flags1 dispatch:(bool)dispatch
{
    std::vector<TGDatabaseMessageFlagValue> flags = flags1;
    [self dispatchOnDatabaseThread:^
    {
        NSMutableArray *changedMessageIds = [[NSMutableArray alloc] init];
        
         FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE mid=? LIMIT 1", _messagesTableName], [[NSNumber alloc] initWithInt:mid]];
         if ([result next])
         {
             bool unread = [result intForColumn:@"unread"] != 0;
             int deliveryState = [result intForColumn:@"dstate"];
             int date = [result intForColumn:@"date"];
             bool wasPending = deliveryState == TGMessageDeliveryStatePending || deliveryState == TGMessageDeliveryStateFailed;
             bool wasDelivered = deliveryState == TGMessageDeliveryStateDelivered;
             int newMid = mid;
             int newDate = date;
             int64_t conversationId = [result longLongIntForColumn:@"cid"];
             
             bool changed = false;
             
             for (std::vector<TGDatabaseMessageFlagValue>::const_iterator it = flags.begin(); it != flags.end(); it++)
             {
                 switch (it->flag)
                 {
                     case TGDatabaseMessageFlagDeliveryState:
                         deliveryState = it->value;
                         changed = true;
                         break;
                     case TGDatabaseMessageFlagUnread:
                         unread = it->value != 0;
                         changed = true;
                         break;
                     case TGDatabaseMessageFlagMid:
                         newMid = it->value;
                         changed = true;
                         break;
                     case TGDatabaseMessageFlagDate:
                         newDate = it->value;
                         changed = true;
                         break;
                     default:
                         break;
                 }
             }
             
            //TGLog(@"update %d -> %d (from %d)", mid, newDate, date);
             
             if (changed)
             {
                 if (wasPending && deliveryState == TGMessageDeliveryStateDelivered)
                     [_database executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@ WHERE mid=?", _outgoingMessagesTableName], [[NSNumber alloc] initWithInt:mid]];
                 else if (wasDelivered && deliveryState == TGMessageDeliveryStateFailed)
                 {
                     NSString *outboxInsertQueryFormat = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (mid, cid, dstate, local_media_id) VALUES (?, ?, ?, ?)", _outgoingMessagesTableName];
                     [_database executeUpdate:outboxInsertQueryFormat, [[NSNumber alloc] initWithInt:mid], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:deliveryState], [[NSNumber alloc] initWithInt:0]];
                 }
                 else
                     [_database executeUpdate:[NSString stringWithFormat:@"UPDATE %@ SET dstate=? WHERE mid=?", _outgoingMessagesTableName], [[NSNumber alloc] initWithInt:deliveryState], [[NSNumber alloc] initWithInt:mid]];
                 
                 if (newMid != mid)
                 {
                     [changedMessageIds addObject:[[NSArray alloc] initWithObjects:[[NSNumber alloc] initWithInt:mid], [[NSNumber alloc] initWithInt:newMid], nil]];
                     
                     [_database executeUpdate:[NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET mid=?, unread=?, dstate=?, date=? WHERE mid=?", _messagesTableName], [[NSNumber alloc] initWithInt:newMid], [[NSNumber alloc] initWithInt:unread], [[NSNumber alloc] initWithInt:deliveryState], [[NSNumber alloc] initWithInt:newDate], [[NSNumber alloc] initWithInt:mid]];
                     
                     [_database executeUpdate:[NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET mid=?, date=? WHERE mid=?", _conversationMediaTableName], [[NSNumber alloc] initWithInt:newMid], [[NSNumber alloc] initWithInt:newDate], [[NSNumber alloc] initWithInt:mid]];
                     
                     [self actualizeConversation:conversationId dispatch:dispatch];
                 }
                 else
                 {
                     [_database executeUpdate:[NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET unread=?, dstate=?, date=? WHERE mid=?", _messagesTableName], [[NSNumber alloc] initWithInt:unread], [[NSNumber alloc] initWithInt:deliveryState], [[NSNumber alloc] initWithInt:newDate], [[NSNumber alloc] initWithInt:mid]];

                     [self actualizeConversation:conversationId dispatch:dispatch];
                 }
             }
         }
         else
         {
             TGLog(@"***** Warning: message %d not found", mid);
         }
        
        [self dispatchOnIndexThread:^
        {
            NSString *indexInsertFormat = [NSString stringWithFormat:@"UPDATE %@ SET docid=? WHERE docid=?", _messageIndexTableName];
            
            [_indexDatabase beginTransaction];
            for (NSArray *mids in changedMessageIds)
            {
                [_indexDatabase executeUpdate:indexInsertFormat, [mids objectAtIndex:1], [mids objectAtIndex:0]];
            }
            [_indexDatabase commit];
        } synchronous:false];
    } synchronous:false];
}

- (void)updateMessageIds:(std::vector<std::pair<int, int> > const &)mapping
{
    std::tr1::shared_ptr<std::vector<std::pair<int, int> > > pMapping(new std::vector<std::pair<int, int> >(mapping));
    
    [self dispatchOnDatabaseThread:^
    {
        assert(false);
        
        [_database setSoftShouldCacheStatements:false];
        
        NSMutableString *midsString = [[NSMutableString alloc] init];
        bool first = true;
        for (auto it : *pMapping)
        {
            if (first)
                first = false;
            else
                [midsString appendString:@","];
            
            [midsString appendFormat:@"%d", it.first];
        }
        
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid, cid FROM %@ WHERE mid IN (%@)", _messagesTableName, midsString]];
        int midIndex = [result columnIndexForName:@"mid"];
        int cidIndex = [result columnIndexForName:@"cid"];
        
        while ([result next])
        {
            int mid = [result intForColumnIndex:midIndex];
            int64_t cid = [result longLongIntForColumnIndex:cidIndex];
            
            
        }
        
        result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE ", _outgoingMessagesTableName]];
        
        [_database setSoftShouldCacheStatements:true];
    } synchronous:false];
}

- (void)deleteMessages:(NSArray *)mids populateActionQueue:(bool)populateActionQueue fillMessagesByConversationId:(NSMutableDictionary *)messagesByConversationId
{
    [self deleteMessages:mids populateActionQueue:populateActionQueue fillMessagesByConversationId:messagesByConversationId keepDate:false];
}

- (void)deleteMessages:(NSArray *)mids populateActionQueue:(bool)populateActionQueue fillMessagesByConversationId:(NSMutableDictionary *)messagesByConversationId keepDate:(bool)keepDate
{
    [self dispatchOnDatabaseThread:^
    {
        std::map<int64_t, int> conversationSet;
        
        NSMutableArray *actions = [[NSMutableArray alloc] init];
        
        NSString *messagesDeleteFormat = [NSString stringWithFormat:@"DELETE FROM %@ WHERE mid=?", _messagesTableName];
        NSString *mediaDeleteFormat = [NSString stringWithFormat:@"DELETE FROM %@ WHERE mid=?", _conversationMediaTableName];
        NSString *outboxDeleteFormat = [NSString stringWithFormat:@"DELETE FROM %@ WHERE mid=?", _outgoingMessagesTableName];
        
        int deletedUnreadCount = 0;
        
        for (NSNumber *nMid in mids)
        {
            FMResultSet *messageResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ WHERE mid=? LIMIT 1", _messagesTableName], nMid];
            
            bool found = false;
            NSData *localMedia = nil;
            
            if ([messageResult next])
            {
                found = true;
                
                int indexMedia = [messageResult columnIndexForName:@"media"];
                int indexCid = [messageResult columnIndexForName:@"cid"];
                
                int64_t cid = [messageResult longLongIntForColumnIndex:indexCid];
                
                if (messagesByConversationId != nil)
                {
                    NSNumber *conversationKey = [[NSNumber alloc] initWithLongLong:cid];
                    NSMutableArray *messagesInConversation = [messagesByConversationId objectForKey:conversationKey];
                    if (messagesInConversation == nil)
                    {
                        messagesInConversation = [[NSMutableArray alloc] init];
                        [messagesByConversationId setObject:messagesInConversation forKey:conversationKey];
                    }
                    [messagesInConversation addObject:nMid];
                }
                
                localMedia = [messageResult dataForColumnIndex:indexMedia];
                
                if ([nMid intValue] < TGMessageLocalMidBaseline && [messageResult intForColumn:@"outgoing"] == 0 && [messageResult intForColumn:@"unread"] != 0)
                {
                    conversationSet[cid]--;
                    deletedUnreadCount++;
                }
                else
                {
                    if (conversationSet.find(cid) == conversationSet.end())
                        conversationSet[cid] = 0;
                }
            }
            else
            {
                FMResultSet *mediaResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT cid, media FROM %@ WHERE mid=? LIMIT 1", _conversationMediaTableName], nMid];
                
                if ([mediaResult next])
                {
                    found = true;
                    
                    localMedia = [mediaResult dataForColumn:@"media"];
                    
                    int64_t cid = [mediaResult longLongIntForColumn:@"cid"];
                    if (conversationSet.find(cid) == conversationSet.end())
                        conversationSet[cid] = 0;
                    
                    if (messagesByConversationId != nil)
                    {
                        NSNumber *conversationKey = [[NSNumber alloc] initWithLongLong:cid];
                        NSMutableArray *messagesInConversation = [messagesByConversationId objectForKey:conversationKey];
                        if (messagesInConversation == nil)
                        {
                            messagesInConversation = [[NSMutableArray alloc] init];
                            [messagesByConversationId setObject:messagesInConversation forKey:conversationKey];
                        }
                        [messagesInConversation addObject:nMid];
                    }
                }
            }
            
            if (found)
            {
                if (localMedia != nil && localMedia.length != 0)
                {
                    cleanupMessage(self, [nMid intValue], [TGMessage parseMediaAttachments:localMedia], _messageCleanupBlock);
                }

                if (populateActionQueue && [nMid intValue] < TGMessageLocalMidBaseline)
                {
                    TGDatabaseAction action = { .type = TGDatabaseActionDeleteMessage, .subject = [nMid intValue], .arg0 = 0, .arg1 = 0 };
                    [actions addObject:[[NSValue alloc] initWithBytes:&action objCType:@encode(TGDatabaseAction)]];
                }
                
                [_database executeUpdate:messagesDeleteFormat, nMid];
                [_database executeUpdate:mediaDeleteFormat, nMid];
            }
            
            if ([nMid intValue] >= 800000000)
                [_database executeUpdate:outboxDeleteFormat, nMid];
        }
        
        for (auto it = conversationSet.begin(); it != conversationSet.end(); it++)
        {
            [self actualizeConversation:it->first dispatch:true conversation:nil forceUpdate:false addUnreadCount:it->second addServiceUnreadCount:0 keepDate:keepDate];
        }
        
        if (deletedUnreadCount != 0)
        {
            int unreadCount = [self databaseState].unreadCount - deletedUnreadCount;
            if (unreadCount < 0)
                TGLog(@"***** Warning: wrong unread_count");
            [self setUnreadCount:MAX(unreadCount, 0)];
        }
        
        if (populateActionQueue && actions.count != 0)
            [self storeQueuedActions:actions];
        
        [_database setSoftShouldCacheStatements:false];
        NSMutableString *midsString = [[NSMutableString alloc] init];
        int count = mids.count;
        for (int j = 0; j < count; )
        {
            [midsString deleteCharactersInRange:NSMakeRange(0, midsString.length)];
            
            for (int i = 0; i < 256 && j < count; i++, j++)
            {
                if (midsString.length != 0)
                    [midsString appendString:@","];
                [midsString appendFormat:@"%d", [mids[j] intValue]];
            }
            
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE mid IN (%@)", _selfDestructTableName, midsString]];
        }
        [_database setSoftShouldCacheStatements:true];
        
        [self dispatchOnIndexThread:^
        {
            NSString *deleteQueryFormat = [NSString stringWithFormat:@"DELETE FROM %@ WHERE docid=?", _messageIndexTableName];
            [_indexDatabase beginTransaction];
            for (NSNumber *nMid in mids)
            {
                [_indexDatabase executeUpdate:deleteQueryFormat, nMid];
            }
            [_indexDatabase commit];
        } synchronous:false];
    } synchronous:(populateActionQueue || messagesByConversationId != nil)];
}

- (void)deleteConversation:(int64_t)conversationId populateActionQueue:(bool)populateActionQueue
{
    [self clearConversation:conversationId populateActionQueue:populateActionQueue clearOnly:false];
}

- (void)clearConversation:(int64_t)conversationId populateActionQueue:(bool)populateActionQueue
{
    [self clearConversation:conversationId populateActionQueue:populateActionQueue clearOnly:true];
}

- (void)clearConversation:(int64_t)conversationId populateActionQueue:(bool)populateActionQueue clearOnly:(bool)clearOnly
{
    [self dispatchOnDatabaseThread:^
    {   
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT mid, media FROM %@ WHERE cid=? AND media NOT NULL", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        int midIndex = [result columnIndexForName:@"mid"];
        int mediaIndex = [result columnIndexForName:@"media"];
        while ([result next])
        {
            int mid = [result intForColumnIndex:midIndex];
            NSData *media = [result dataForColumnIndex:mediaIndex];
            if (media != nil && media.length != 0)
            {
                cleanupMessage(self, mid, [TGMessage parseMediaAttachments:media], _messageCleanupBlock);
            }
        }
        
        result = [_database executeQuery:[NSString stringWithFormat:@"SELECT mid, media FROM %@ WHERE cid=?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        midIndex = [result columnIndexForName:@"mid"];
        mediaIndex = [result columnIndexForName:@"media"];
        while ([result next])
        {
            int mid = [result intForColumnIndex:midIndex];
            NSData *media = [result dataForColumnIndex:mediaIndex];
            if (media != nil && media.length != 0)
            {
                cleanupMessage(self, mid, [TGMessage parseMediaAttachments:media], _messageCleanupBlock);
            }
        }
        
        NSMutableArray *midsInConversation = [[NSMutableArray alloc] init];
        FMResultSet *midsResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT mid FROM %@ WHERE cid=?", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        int midsResultMidIndex = [midsResult columnIndexForName:@"mid"];
        while ([midsResult next])
        {
            [midsInConversation addObject:[[NSNumber alloc] initWithInt:[midsResult intForColumnIndex:midsResultMidIndex]]];
        }
        
        [_database executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@ WHERE cid=?", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        [_database executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@ WHERE cid=?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        [_database executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@ WHERE cid=?", _outgoingMessagesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        
        TGConversation *conversation = [self loadConversationWithId:conversationId];
        if (conversation != nil)
        {
            int previousConversationUnreadCount = 0;
            
            if (conversation.unreadCount != 0)
            {
                previousConversationUnreadCount = conversation.unreadCount;
                int unreadCount = [self databaseState].unreadCount - conversation.unreadCount;
                if (unreadCount < 0)
                    TGLog(@"***** Warning: wrong unread_count");
                [self setUnreadCount:MAX(unreadCount, 0)];
            }
            
            if (clearOnly)
            {
                [self loadConversationWithId:conversationId];
                [self actualizeConversation:conversationId dispatch:true];
                
                if (populateActionQueue)
                {
                    TGDatabaseAction action = { .type = TGDatabaseActionClearConversation, .subject = conversationId, .arg0 = 0, .arg1 = previousConversationUnreadCount };
                    [self storeQueuedActions:[NSArray arrayWithObject:[[NSValue alloc] initWithBytes:&action objCType:@encode(TGDatabaseAction)]]];
                }
            }
            else
            {
                [_database executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@ WHERE cid=?", _conversationListTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
            
                if (populateActionQueue)
                {
                    TGDatabaseAction action = { .type = TGDatabaseActionDeleteConversation, .subject = conversationId, .arg0 = 0, .arg1 = previousConversationUnreadCount };
                    [self storeQueuedActions:[NSArray arrayWithObject:[[NSValue alloc] initWithBytes:&action objCType:@encode(TGDatabaseAction)]]];
                }
            }
        }
        
        if (!clearOnly)
        {
            if (conversationId <= INT_MIN)
            {
                [self setConversationCustomProperty:conversationId name:murMurHash32(@"key") value:nil];
            }
        }
        
        [self dispatchOnIndexThread:^
        {
            int midsCount = midsInConversation.count;
            
            [_indexDatabase setSoftShouldCacheStatements:false];
            [_indexDatabase beginTransaction];
            NSMutableString *rangeString = [[NSMutableString alloc] init];
            for (int i = 0; i < midsCount; i++)
            {
                if (rangeString.length != 0)
                    [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
                
                bool first = true;
                int count = 0;
                for (; count < 20 && i < midsCount; i++, count++)
                {
                    if (first)
                        first = false;
                    else
                        [rangeString appendString:@","];
                    
                    [rangeString appendFormat:@"%d", [[midsInConversation objectAtIndex:i] intValue]];
                }
                
                NSString *deleteQueryFormat = [[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE docid IN (%@)", _messageIndexTableName, rangeString];
                [_indexDatabase executeUpdate:deleteQueryFormat];
            }
            [_indexDatabase commit];
            [_indexDatabase setSoftShouldCacheStatements:true];
        } synchronous:false];
    } synchronous:false];
}

- (void)markMessagesAsRead:(NSArray *)mids
{
    if (mids.count == 0)
        return;
    
    [self dispatchOnDatabaseThread:^
    {
        const int batchCount = 256;
        
        std::map<int64_t, int> unreadByConversation;
        std::set<int64_t> outgoingUnreadConversations;
        
        NSMutableString *rangeString = [[NSMutableString alloc] init];
        int midsCount = mids.count;
        for (int i = 0; i < midsCount; i++)
        {
            if (rangeString.length != 0)
                [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
            
            bool first = true;
            int count = 0;
            for (; count < batchCount && i < midsCount; i++, count++)
            {
                if (first)
                    first = false;
                else
                    [rangeString appendString:@","];
                
                [rangeString appendFormat:@"%d", [[mids objectAtIndex:i] intValue]];
            }
            
            FMResultSet *unreadResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT cid, outgoing FROM %@ WHERE mid IN (%@) AND unread!=0", _messagesTableName, rangeString]];
            
            int cidIndex = [unreadResult columnIndexForName:@"cid"];
            int outgoingIndex = [unreadResult columnIndexForName:@"outgoing"];
            while ([unreadResult next])
            {
                int64_t cid = [unreadResult longLongIntForColumnIndex:cidIndex];
                if ([unreadResult intForColumnIndex:outgoingIndex] == 0)
                {
                    std::map<int64_t, int>::iterator it = unreadByConversation.find(cid);
                    if (it == unreadByConversation.end())
                        unreadByConversation.insert(std::pair<int64_t, int>(cid, 1));
                    else
                        it->second++;
                }
                else
                {
                    outgoingUnreadConversations.insert(cid);
                }
            }
            
            if (rangeString.length != 0)
            {
                NSString *readQueryFormat = [[NSString alloc] initWithFormat:@"UPDATE %@ SET unread=0 WHERE mid IN (%@)", _messagesTableName, rangeString];
                [_database executeUpdate:readQueryFormat];
            }
            
            if (i >= midsCount)
                break;
        }
        
        int completeReadCount = 0;
        for (std::map<int64_t, int>::iterator it = unreadByConversation.begin(); it != unreadByConversation.end(); it++)
        {
            completeReadCount += it->second;
            outgoingUnreadConversations.erase(it->first);
            [self actualizeConversation:it->first dispatch:true conversation:nil forceUpdate:false addUnreadCount:(-it->second) addServiceUnreadCount:0 keepDate:false];
        }
        
        for (std::set<int64_t>::iterator it = outgoingUnreadConversations.begin(); it != outgoingUnreadConversations.end(); it++)
        {
            [self actualizeConversation:*it dispatch:true conversation:nil forceUpdate:false addUnreadCount:0 addServiceUnreadCount:0 keepDate:false];
        }
        
        [self setUnreadCount:MAX(0, [self databaseState].unreadCount - completeReadCount)];
        
        /*int midsCount = mids.count;
        
        NSMutableString *rangeString = [[NSMutableString alloc] init];
        for (int i = 0; i < midsCount; i++)
        {
            if (rangeString.length != 0)
                [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
            
            bool first = true;
            int count = 0;
            for (; count < 20 && i < midsCount; i++, count++)
            {
                if (first)
                    first = false;
                else
                    [rangeString appendString:@","];
                
                [rangeString appendFormat:@"%d", [[mids objectAtIndex:i] intValue]];
            }
            
            NSString *readQueryFormat = [[NSString alloc] initWithFormat:@"UPDATE %@ SET unread=0 WHERE mid IN (%@)", _messagesTableName, rangeString];
            [_database executeUpdate:readQueryFormat];
        }*/
    } synchronous:false];
}

- (void)markMessagesAsReadInConversation:(int64_t)conversationId maxDate:(int32_t)maxDate referenceDate:(int32_t)referenceDate
{
    referenceDate += (int)[[NSTimeZone localTimeZone] secondsFromGMT];
    
    [self dispatchOnDatabaseThread:^
    {
        //[self explainQuery:[[NSString alloc] initWithFormat:@"SELECT date FROM %@ WHERE cid=%lld AND date<=%@ ORDER BY date DESC LIMIT 1", _messagesTableName, conversationId, [[NSNumber alloc] initWithInt:maxDate]]];
        
        //TGLog(@"reading from %d", maxDate);
        
        /*FMResultSet *testResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ WHERE cid=? ORDER BY date DESC LIMIT 8", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        while ([testResult next])
        {
            TGLog(@"  %d: %d", [testResult intForColumn:@"mid"], [testResult intForColumn:@"date"]);
        }*/
        
        NSMutableString *midsString = [[NSMutableString alloc] init];
        bool firstLoop = true;
        int startingDate = maxDate;
        
        int startingDateLimit = 0;
        
        NSMutableArray *markedMids = [[NSMutableArray alloc] init];
        
        std::vector<std::pair<int, int> > midsWithLifetime;
        
        while (true)
        {
            [midsString deleteCharactersInRange:NSMakeRange(0, midsString.length)];
            
            FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid, date, unread, outgoing, localMid FROM %@ WHERE cid=? AND date<=? ORDER BY date DESC LIMIT ?, ?", _messagesTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:startingDate], [[NSNumber alloc] initWithInt:startingDateLimit], [[NSNumber alloc] initWithInt:firstLoop ? 8 : 64]];
            
            int midIndex = [result columnIndexForName:@"mid"];
            int dateIndex = [result columnIndexForName:@"date"];
            int unreadIndex = [result columnIndexForName:@"unread"];
            int outgoingIndex = [result columnIndexForName:@"outgoing"];
            int messageLifetimeIndex = [result columnIndexForName:@"localMid"];
            
            firstLoop = false;
            
            bool anyMarked = false;
            bool anyFound = false;
            bool outgoingFound = false;
            
            while ([result next])
            {
                anyFound = true;
                
                if ([result intForColumnIndex:outgoingIndex])
                {
                    outgoingFound = true;
                    
                    if ([result intForColumnIndex:unreadIndex])
                    {
                        int mid = [result intForColumnIndex:midIndex];
                        
                        if (midsString.length != 0)
                            [midsString appendString:@","];
                        [midsString appendFormat:@"%d", mid];
                        
                        anyMarked = true;
                        
                        [markedMids addObject:[[NSNumber alloc] initWithInt:mid]];
                        
                        int messageLifetime = [result intForColumnIndex:messageLifetimeIndex];
                        if (messageLifetime != 0)
                            midsWithLifetime.push_back(std::pair<int, int>(mid, messageLifetime));
                    }
                }
                
                int date = [result intForColumnIndex:dateIndex];
                
                if (date < startingDate)
                {
                    startingDate = date;
                    startingDateLimit = 0;
                }
                
                startingDateLimit++;
            }
            
            if (midsString.length != 0)
            {
                //TGLog(@"%@", midsString);
                [_database setSoftShouldCacheStatements:false];
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET unread=0 WHERE mid IN (%@)", _messagesTableName, midsString]];
                [_database setSoftShouldCacheStatements:true];
            }
            
            if (!anyFound || (outgoingFound && !anyMarked))
                break;
        }
        
        if (markedMids.count != 0)
            [self _scheduleSelfDestruct:&midsWithLifetime referenceDate:referenceDate];
        
        [self actualizeConversation:conversationId dispatch:true];
    } synchronous:false];
}

- (void)loadConversationState:(int64_t)conversationId completion:(void (^)(TGMessage *state))completion
{
    [self dispatchOnDatabaseThread:^
    {
        TGMessage *message = nil;
        
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE cid=?", _conversationsStatesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        if ([result next])
        {
            message = [[TGMessage alloc] init];
            NSString *messageText = [result stringForColumn:@"message_text"];
            message.text = messageText == nil ? @"" : messageText;
        }
        
        if (completion)
            completion(message);
    } synchronous:false];
}

- (void)storeConversationState:(int64_t)conversationId message:(TGMessage *)message
{
    [self dispatchOnDatabaseThread:^
    {
        if (message == nil)
        {
            [_database executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@ WHERE cid=?", _conversationsStatesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        }
        else
        {
            [_database executeUpdate:[NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (cid, message_text) VALUES(?, ?)", _conversationsStatesTableName], [[NSNumber alloc] initWithLongLong:conversationId], message.text];
        }
    } synchronous:false];
}

- (void)readHistory:(int64_t)conversationId includeOutgoing:(bool)includeOutgoing populateActionQueue:(bool)populateActionQueue minRemoteMid:(int)minRemoteMid completion:(void (^)(bool hasItemsOnActionQueue))completion
{
/*#ifdef DEBUG
    return;
#endif*/
    
    [self dispatchOnDatabaseThread:^
    {
        const int firstBatchCount = 32;
        const int batchCount = 256;
        
        NSNumber *nConversationId = [[NSNumber alloc] initWithLongLong:conversationId];
        
        NSString *firstQueryFormat = [[NSString alloc] initWithFormat:@"SELECT mid, unread, date, localMid FROM %@ WHERE cid=? %@ ORDER BY mid DESC LIMIT %d", _messagesTableName, !includeOutgoing ? @"AND outgoing=0" : [[NSString alloc] initWithFormat:@"AND mid < %d", TGMessageLocalMidBaseline], firstBatchCount];
        
        NSString *queryFormat = [[NSString alloc] initWithFormat:@"SELECT mid, unread, date, localMid FROM %@ WHERE cid=? AND mid < ? %@ ORDER BY mid DESC LIMIT %d", _messagesTableName, !includeOutgoing ? @"AND outgoing=0" : [[NSString alloc] initWithFormat:@"AND mid < %d", TGMessageLocalMidBaseline], batchCount];
        
        CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
        
        std::set<int> unreadMids;
        int actionQueueMid = 0;
        int actionQueueDate = 0;
        
        int lastMid = 0;
        int lastProcessedMid = INT_MAX;
        
        int passCount = 0;
        
        std::vector<std::pair<int, int> > midWithLifetime;
        
        while (true)
        {
            passCount++;
            
            int recordCount = 0;
            
            FMResultSet *result = nil;
            if (lastProcessedMid == INT_MAX)
                result = [_database executeQuery:firstQueryFormat, nConversationId];
            else
                result = [_database executeQuery:queryFormat, nConversationId, [[NSNumber alloc] initWithInt:lastProcessedMid]];
            
            int midIndex = [result columnIndexForName:@"mid"];
            int unreadIndex = [result columnIndexForName:@"unread"];
            int dateIndex = [result columnIndexForName:@"date"];
            int messageLifetimeIndex = [result columnIndexForName:@"localMid"];
            
            bool loadedSomething = false;
            
            while ([result next])
            {
                loadedSomething = true;
                
                int mid = [result intForColumnIndex:midIndex];
                int messageLifetime = [result intForColumnIndex:messageLifetimeIndex];
                
                if (mid < lastProcessedMid)
                    lastProcessedMid = mid;
                
                if ([result intForColumnIndex:unreadIndex] != 0)
                {
                    recordCount++;

                    if (lastMid == 0)
                    {
                        actionQueueMid = mid;
                        actionQueueDate = [result intForColumnIndex:dateIndex];
                    }
                    
                    if (mid < lastMid || lastMid == 0)
                        lastMid = mid;
                    
                    unreadMids.insert(mid);
                    if (messageLifetime != 0)
                        midWithLifetime.push_back(std::pair<int, int>(mid, messageLifetime));
                }
            }
            
            if (!loadedSomething)
                break;
            
            if (recordCount > 0 || minRemoteMid == 0 || lastProcessedMid <= minRemoteMid)
            {
                if (recordCount < batchCount && (minRemoteMid == 0 || lastProcessedMid <= minRemoteMid))
                    break;
            }
        }
        
        TGLog(@"Read time: %f ms (%d loops)", (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0, passCount);
        
        if (lastMid != 0)
            [self storeMinAutosaveMessageIdForConversation:conversationId mid:lastMid];
        
        bool hasUnread = !unreadMids.empty();
        
        int localUnreadCount = 0;
        
        NSMutableString *rangeString = [[NSMutableString alloc] init];
        for (std::set<int>::iterator it = unreadMids.begin(); it != unreadMids.end(); it++)
        {
            if (rangeString.length != 0)
                [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
            
            bool first = true;
            int count = 0;
            for (; count < batchCount && it != unreadMids.end(); it++, count++)
            {
                if (first)
                    first = false;
                else
                    [rangeString appendString:@","];
                
                [rangeString appendFormat:@"%d", *it];
                
                if (*it >= TGMessageLocalMidBaseline)
                    localUnreadCount++;
            }
            
            [_database setSoftShouldCacheStatements:false];
            NSString *readQueryFormat = [[NSString alloc] initWithFormat:@"UPDATE %@ SET unread=0 WHERE mid IN (%@)", _messagesTableName, rangeString];
            [_database executeUpdate:readQueryFormat];
            [_database setSoftShouldCacheStatements:true];
            
            if (it == unreadMids.end())
                break;
        }
        
        if (actionQueueMid == 0)
        {
            FMResultSet *lastMidResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT mid FROM %@ WHERE cid=? AND mid<%d ORDER BY mid DESC LIMIT 1", _messagesTableName, TGMessageLocalMidBaseline], nConversationId];
            if ([lastMidResult next])
            {
                actionQueueMid = [lastMidResult intForColumn:@"mid"];
            }
        }
        
        if (actionQueueMid == 0)
        {
            TGLog(@"No messages to read");
            return;
        }
        
        int previousConversationUnreadCount = 0;
        
        TGConversation *conversationData = [self loadConversationWithId:conversationId];
        if (conversationData != nil && ((!conversationData.outgoing && conversationData.unread) || conversationData.unreadCount != 0 || conversationData.serviceUnreadCount != 0))
        {
            int flags = 0;
            if (conversationData.outgoing)
                flags |= 1;
            if (conversationData.isChat)
                flags |= 2;
            if (conversationData.leftChat)
                flags |= 4;
            if (conversationData.kickedFromChat)
                flags |= 8;
            if (conversationData.unread && conversationData.outgoing)
                flags |= 16;
            if (conversationData.deliveryError)
                flags |= 32;
            
            previousConversationUnreadCount = conversationData.unreadCount;
            
            int unreadCount = [self databaseState].unreadCount - (conversationData.unreadCount);
            if (unreadCount < 0)
                TGLog(@"***** Warning: wrong unread_count");
            [self setUnreadCount:MAX(unreadCount, 0)];
            
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET unread_count=0, service_unread=0, flags=? WHERE cid=?", _conversationListTableName], [[NSNumber alloc] initWithInt:flags], nConversationId];
            
            conversationData.unreadCount = 0;
            conversationData.serviceUnreadCount = 0;
            conversationData.unread = false;
            [ActionStageInstance() dispatchResource:_liveMessagesDispatchPath resource:[[SGraphObjectNode alloc] initWithObject:[NSArray arrayWithObject:conversationData]]];
        }
        
        bool storedActions = false;
        
        if (populateActionQueue && (previousConversationUnreadCount != 0 || hasUnread))
        {
            if (actionQueueMid != 0)
            {
#if TARGET_IPHONE_SIMULATOR
                TGLog(@"read date %d", actionQueueDate);
#endif
                TGDatabaseAction action = { .type = TGDatabaseActionReadConversation, .subject = conversationId, .arg0 = (conversationId <= INT_MIN ? actionQueueDate : actionQueueMid), .arg1 = previousConversationUnreadCount};
                [self storeQueuedActions:[NSArray arrayWithObject:[[NSValue alloc] initWithBytes:&action objCType:@encode(TGDatabaseAction)]]];
                
                storedActions = true;
            }
        }
        
        if (minRemoteMid != 0)
        {
            [ActionStageInstance() dispatchResource:[[NSString alloc] initWithFormat:@"/tg/conversationReadApplied/(%lld)", conversationId] resource:[[NSNumber alloc] initWithLongLong:minRemoteMid]];
        }
        
        if (completion)
            completion(storedActions);
        
        if (conversationId <= INT_MIN && !midWithLifetime.empty())
        {
            int currentDate = (int)(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970 + _timeDifferenceFromUTC);
            NSString *selfDestructInsertQuery = [[NSString alloc] initWithFormat:@"INSERT OR IGNORE INTO %@ (mid, date) VALUES (?, ?)", _selfDestructTableName];
            
            [_database beginTransaction];
            for (auto it = midWithLifetime.begin(); it != midWithLifetime.end(); it++)
            {
                NSNumber *nDate = [[NSNumber alloc] initWithInt:currentDate + it->second];
                [_database executeUpdate:selfDestructInsertQuery, [[NSNumber alloc] initWithInt:it->first], nDate];
            }
            [_database commit];
            
            [self processAndScheduleSelfDestruct];
        }
    } synchronous:false];
}

inline TGMessage *loadMessageMediaFromQueryResult(FMResultSet *result, int const &dateIndex, int const &fromIdIndex, int const &midIndex, int const &mediaIndex)
{
    int mid = [result intForColumnIndex:midIndex];
    int date = [result intForColumnIndex:dateIndex];
    int fromId = [result intForColumnIndex:fromIdIndex];
    
    TGMessage *message = [[TGMessage alloc] init];
    
    NSData *mediaData = [result dataForColumnIndex:mediaIndex];
    NSArray *mediaAttachments = [TGMessage parseMediaAttachments:mediaData];
    message.mid = mid;
    if (mid >= TGMessageLocalMidBaseline)
    {
        message.localMid = mid;
        message.local = true;
    }
    message.fromUid = fromId;
    message.date = date;
    message.mediaAttachments = mediaAttachments;
    
    return message;
}

- (void)loadMediaPositionInConversation:(int64_t)conversationId messageId:(int)messageId completion:(void (^)(int position, int count))completion
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *dateResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT date FROM %@ WHERE cid=? AND mid=?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:messageId]];
        if ([dateResult next])
        {
            int maxDate = [dateResult intForColumn:@"date"];
            
            int positionInConversation = 0;
            int totalCount = 0;
            
            FMResultSet *uniqueDateResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE cid=? AND date<?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:maxDate]];
            
            if ([uniqueDateResult next])
            {
                positionInConversation = [uniqueDateResult intForColumn:@"COUNT(*)"];
                
                FMResultSet *equalDateResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE cid=? AND date=?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:maxDate]];
                
                while ([equalDateResult next])
                {
                    int mid = [equalDateResult intForColumn:@"mid"];
                    if (mid != messageId)
                    {
                        if ((mid >= 800000000) != (messageId >= 800000000))
                        {
                            if (mid < 800000000)
                                positionInConversation++;
                        }
                        else
                        {
                            if (mid < messageId)
                                positionInConversation++;
                        }
                    }
                }
                
                FMResultSet *countResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE cid=?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
                if ([countResult next])
                    totalCount = [countResult intForColumn:@"COUNT(*)"];
                
            }
            
            if (completion)
                completion(positionInConversation, totalCount);
        }
        else
        {
            if (completion)
                completion(0, 0);
        }
    } synchronous:false];
}

- (NSArray *)loadMediaInConversation:(int64_t)conversationId atMessageId:(int)atMessageId limitAfter:(int)limitAfter count:(int *)count
{
    NSMutableArray *mediaArray = [[NSMutableArray alloc] init];
    
    [self dispatchOnDatabaseThread:^
    {
        if (conversationId == 0)
        {
            if (count != NULL)
                *count = 0;
            return;
        }
        
        FMResultSet *dateResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT date FROM %@ WHERE cid=? AND mid=? LIMIT 1", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:atMessageId]];
        if ([dateResult next])
        {
            int maxDate = [dateResult intForColumn:@"date"];
            FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT date, from_id, mid, media FROM %@ WHERE cid=? AND date>=?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:maxDate]];
            
            int dateIndex = [result columnIndexForName:@"date"];
            int midIndex = [result columnIndexForName:@"mid"];
            int mediaIndex = [result columnIndexForName:@"media"];
            int fromIdIndex = [result columnIndexForName:@"from_id"];
            
            while ([result next])
            {
                TGMessage *message = loadMessageMediaFromQueryResult(result, dateIndex, fromIdIndex, midIndex, mediaIndex);
                //TGLog(@"mid %d", message.mid);
                [mediaArray addObject:message];
            }
            
            result = [_database executeQuery:[NSString stringWithFormat:@"SELECT date, mid, from_id, media FROM %@ WHERE cid=? AND date<? ORDER BY date DESC LIMIT ?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:maxDate], [[NSNumber alloc] initWithInt:limitAfter]];
            
            dateIndex = [result columnIndexForName:@"date"];
            midIndex = [result columnIndexForName:@"mid"];
            mediaIndex = [result columnIndexForName:@"media"];
            fromIdIndex = [result columnIndexForName:@"from_id"];
            
            while ([result next])
            {
                TGMessage *message = loadMessageMediaFromQueryResult(result, dateIndex, fromIdIndex, midIndex, mediaIndex);
                //TGLog(@"add mid %d", message.mid);
                [mediaArray addObject:message];
            }
            
            if (count != NULL)
            {
                FMResultSet *countResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE cid=?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
                if ([countResult next])
                    *count = [countResult intForColumn:@"COUNT(*)"];
            }
        }
        
    } synchronous:true];
    
    return mediaArray;
}

- (NSArray *)loadMediaInConversation:(int64_t)conversationId maxMid:(int)maxMid maxLocalMid:(int)maxLocalMid maxDate:(int)maxDate limit:(int)limit count:(int *)count
{
    NSMutableArray *mediaArray = [[NSMutableArray alloc] init];
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT date, mid, from_id, media FROM %@ WHERE cid=? AND date<=? ORDER BY date DESC LIMIT ?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:maxDate], [[NSNumber alloc] initWithInt:limit]];
        
        int dateIndex = [result columnIndexForName:@"date"];
        int midIndex = [result columnIndexForName:@"mid"];
        int mediaIndex = [result columnIndexForName:@"media"];
        int fromIdIndex = [result columnIndexForName:@"from_id"];
        
        int extraLimit = 0;
        int extraOffset = 0;
        
        while ([result next])
        {
            extraOffset++;
            
            int mid = [result intForColumnIndex:midIndex];
            if (mid >= 800000000)
            {
                if (mid >= maxLocalMid)
                {
                    extraLimit++;
                    continue;
                }
            }
            else if (mid >= maxMid)
            {
                extraLimit++;
                continue;
            }
            
            TGMessage *message = loadMessageMediaFromQueryResult(result, dateIndex, fromIdIndex, midIndex, mediaIndex);
            
            [mediaArray addObject:message];
        }
        [result close];
        
        if (extraLimit != 0)
        {
            result = [_database executeQuery:[NSString stringWithFormat:@"SELECT date, mid, from_id, media FROM %@ WHERE cid=? AND date<=? ORDER BY date DESC LIMIT ?, ?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId], [[NSNumber alloc] initWithInt:maxDate], [[NSNumber alloc] initWithInt:extraOffset], [[NSNumber alloc] initWithInt:extraLimit]];
            
            while ([result next])
            {
                int mid = [result intForColumnIndex:midIndex];
                if (mid >= 800000000)
                {
                    if (mid >= maxLocalMid)
                    {
                        continue;
                    }
                }
                else if (mid >= maxMid)
                {
                    continue;
                }
                
                TGMessage *message = loadMessageMediaFromQueryResult(result, dateIndex, fromIdIndex, midIndex, mediaIndex);
                
                [mediaArray addObject:message];
            }
        }
        
        if (count != NULL)
        {
            FMResultSet *countResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE cid=?", _conversationMediaTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
            if ([countResult next])
                *count = [countResult intForColumn:@"COUNT(*)"];
        }
    } synchronous:true];
    
    return mediaArray;
}

- (void)addMediaToConversation:(int64_t)conversationId messages:(NSArray *)messages completion:(void (^)(int count))completion
{
    [self dispatchOnDatabaseThread:^
    {
        NSString *queryFormat = [[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ (mid, cid, date, from_id, type, media) VALUES (?, ?, ?, ?, ?, ?)", _conversationMediaTableName];
        
        NSNumber *nConversationId = [[NSNumber alloc] initWithLongLong:conversationId];
        
        [_database beginTransaction];
        
        for (TGMessage *message in messages)
        {
            NSData *mediaData = nil;
            int mediaType = 0;
            
            int64_t videoId = 0;
            
            if (message.mediaAttachments != nil && message.mediaAttachments.count != 0)
            {
                for (TGMediaAttachment *attachment in message.mediaAttachments)
                {
                    if (attachment.type == TGImageMediaAttachmentType)
                    {
                        mediaData = [TGMessage serializeAttachment:attachment];
                        mediaType = 0;
                    }
                    else if (attachment.type == TGVideoMediaAttachmentType)
                    {
                        mediaData = [TGMessage serializeAttachment:attachment];
                        mediaType = 1;
                        videoId = ((TGVideoMediaAttachment *)attachment).videoId;
                    }
                }
            }
            
            if (mediaData != nil && mediaData.length != 0)
            {
                [_database executeUpdate:queryFormat, [[NSNumber alloc] initWithInt:message.mid], nConversationId, [[NSNumber alloc] initWithInt:(int)message.date], [[NSNumber alloc] initWithInt:(int)message.fromUid], [[NSNumber alloc] initWithInt:mediaType], mediaData];
                
                if (mediaType == 1)
                    addVideoMid(self, message.mid, videoId, false);
            }
        }
        
        [_database commit];
        
        if (completion)
        {
            int count = 0;
            FMResultSet *countResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE cid=?", _conversationMediaTableName], nConversationId];
            if ([countResult next])
                count = [countResult intForColumn:@"COUNT(*)"];
            
            completion(count);
        }
    } synchronous:false];
}

- (void)storeQueuedActions:(NSArray *)actions
{
    [self dispatchOnDatabaseThread:^
    {
        [_database beginTransaction];
        for (NSValue *value in actions)
        {
            TGDatabaseAction action;
            [value getValue:&action];
            //TGLog(@"Enqueue action: %d, %lld, %d, %d", action.type, action.subject, action.arg0, action.arg1);
            [_database executeUpdate:[NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (action_type, action_subject, arg0, arg1) VALUES (?, ?, ?, ?)", _actionQueueTableName], [[NSNumber alloc] initWithInt:action.type], [[NSNumber alloc] initWithLongLong:action.subject], [[NSNumber alloc] initWithInt:action.arg0], [[NSNumber alloc] initWithInt:action.arg1]];
        }
        [_database commit];
    } synchronous:false];
}

- (void)confirmQueuedActions:(NSArray *)actions requireFullMatch:(bool)requireFullMatch
{
    [self dispatchOnDatabaseThread:^
    {
        NSString *queryFormat = nil;
        if (requireFullMatch)
            queryFormat = [NSString stringWithFormat:@"DELETE FROM %@ WHERE action_type=? AND action_subject=? AND arg0=?", _actionQueueTableName];
        else
            queryFormat = [NSString stringWithFormat:@"DELETE FROM %@ WHERE action_type=? AND action_subject=?", _actionQueueTableName];
        
        for (NSValue *value in actions)
        {
            TGDatabaseAction action;
            [value getValue:&action];
            
            if (requireFullMatch)
                [_database executeUpdate:queryFormat, [[NSNumber alloc] initWithInt:action.type], [[NSNumber alloc] initWithLongLong:action.subject], [[NSNumber alloc] initWithInt:action.arg0]];
            else
                [_database executeUpdate:queryFormat, [[NSNumber alloc] initWithInt:action.type], [[NSNumber alloc] initWithLongLong:action.subject]];
        }
    } synchronous:false];
}

- (void)loadQueuedActions:(NSArray *)actionTypes completion:(void (^)(NSMutableDictionary *actionSetsByType))completion
{
    [self dispatchOnDatabaseThread:^
    {
        NSMutableDictionary *actionSetsByType = [[NSMutableDictionary alloc] init];
        
        for (NSNumber *nActionType in actionTypes)
        {
            NSMutableArray *array = [[NSMutableArray alloc] init];
            
            FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE action_type=%d", _actionQueueTableName, [nActionType intValue]]];
            int actionSubjectIndex = [result columnIndexForName:@"action_subject"];
            int arg0Index = [result columnIndexForName:@"arg0"];
            int arg1Index = [result columnIndexForName:@"arg1"];
            
            while ([result next])
            {
                TGDatabaseAction action;
                action.type = (TGDatabaseActionType)[nActionType intValue];
                action.subject = [result longLongIntForColumnIndex:actionSubjectIndex];
                action.arg0 = [result intForColumnIndex:arg0Index];
                action.arg1 = [result intForColumnIndex:arg1Index];
                NSValue *value = [[NSValue alloc] initWithBytes:&action objCType:@encode(TGDatabaseAction)];
                if (value != nil)
                    [array addObject:value];
            }
            
            if (array.count != 0)
                [actionSetsByType setObject:array forKey:nActionType];
        }
        
        if (completion)
            completion(actionSetsByType);
    } synchronous:false];
}

- (void)storeFutureActions:(NSArray *)actions
{
    [self dispatchOnDatabaseThread:^
    {
        NSString *queryFormat = [[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ (id, type, data, random_id, insert_date) VALUES (?, ?, ?, ?, ?)", _futureActionsTableName];
        
        int date = (int)(CFAbsoluteTimeGetCurrent() * 100.0);
        
        [_database beginTransaction];
        for (TGFutureAction *action in actions)
        {
            [_database executeUpdate:queryFormat, [[NSNumber alloc] initWithLongLong:action.uniqueId], [[NSNumber alloc] initWithInt:action.type], [action serialize], [[NSNumber alloc] initWithInt:action.randomId], [[NSNumber alloc] initWithInt:date]];
        }
        [_database commit];
    } synchronous:false];
}

static inline TGFutureAction *loadFutureActionFromQueryResult(FMResultSet *result)
{
    int idIndex = [result columnIndexForName:@"id"];
    int typeIndex = [result columnIndexForName:@"type"];
    int dataIndex = [result columnIndexForName:@"data"];
    int randomIdIndex = [result columnIndexForName:@"random_id"];
    
    NSData *data = [result dataForColumnIndex:dataIndex];
    if (data == nil)
        return nil;
    
    int type = [result intForColumnIndex:typeIndex];
    
    TGFutureAction *deserializer = futureActionDeserializer(type);
    
    if (deserializer == nil)
    {
        TGLog(@"Warning: unknown future action type %d", type);
        return nil;
    }
    
    TGFutureAction *action = [deserializer deserialize:data];
    action.uniqueId = [result longLongIntForColumnIndex:idIndex];
    action.randomId = [result intForColumnIndex:randomIdIndex];
    
    return action;
}

- (void)removeFutureAction:(int64_t)uniqueId type:(int)type randomId:(int)randomId
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ WHERE id=? AND type=? AND random_id=?", _futureActionsTableName], [[NSNumber alloc] initWithLongLong:uniqueId], [[NSNumber alloc] initWithInt:type], [[NSNumber alloc] initWithInt:randomId]];
        if ([result next])
        {
            TGFutureAction *action = loadFutureActionFromQueryResult(result);
            [action prepareForDeletion];
            action = nil;
            
            NSString *queryFormat = [[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE id=? AND type=? AND random_id=?", _futureActionsTableName];
            [_database executeUpdate:queryFormat, [[NSNumber alloc] initWithLongLong:uniqueId], [[NSNumber alloc] initWithInt:type], [[NSNumber alloc] initWithInt:randomId]];
        }
    } synchronous:false];
}

- (void)removeFutureActionsWithType:(int)type uniqueIds:(NSArray *)uniqueIds
{
    [self dispatchOnDatabaseThread:^
    {
        NSString *queryFormat = [[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE id=? AND type=?", _futureActionsTableName];
        NSNumber *nType = [[NSNumber alloc] initWithInt:type];
        [_database beginTransaction];
        for (NSNumber *nUniqueId in uniqueIds)
        {
            [_database executeUpdate:queryFormat, nUniqueId, nType];
        }
        [_database commit];
    } synchronous:false];
}

- (NSArray *)loadOneFutureAction
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    
    [self dispatchOnDatabaseThread:^
    {   
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT id, type, data, random_id FROM %@ WHERE type NOT IN (%d, %d, %d, %d) ORDER BY insert_date ASC LIMIT 1", _futureActionsTableName, TGUploadAvatarFutureActionType, TGDeleteProfilePhotoFutureActionType, TGRemoveContactFutureActionType, TGExportContactFutureActionType]];
        
        if ([result next])
        {
            TGFutureAction *action = loadFutureActionFromQueryResult(result);
            
            if (action != nil)
                [actions addObject:action];
        }
    } synchronous:true];
    
    return actions;
}

- (NSArray *)loadFutureActionsWithType:(int)type
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT id, type, data, random_id FROM %@ WHERE type=? ORDER BY insert_date ASC", _futureActionsTableName], [[NSNumber alloc] initWithInt:type]];
        
        while ([result next])
        {
            TGFutureAction *action = loadFutureActionFromQueryResult(result);
            
            if (action != nil)
                [actions addObject:action];
        }
    } synchronous:true];
    
    return actions;
}

- (TGFutureAction *)loadFutureAction:(int64_t)uniqueId type:(int)type
{
    __block TGFutureAction *action = nil;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT id, type, data, random_id FROM %@ WHERE id=? AND type=?", _futureActionsTableName], [[NSNumber alloc] initWithLongLong:uniqueId], [[NSNumber alloc] initWithInt:type]];
        if ([result next])
        {
            action = loadFutureActionFromQueryResult(result);
        }
        
    } synchronous:true];
    
    return action;
}

- (int)loadPeerMinMid:(int64_t)peerId
{
    __block int minMid = 0;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT last_mid FROM %@ WHERE pid=%lld", _peerPropertiesTableName, peerId]];
        if ([result next])
        {
            minMid = [result intForColumn:@"last_mid"];
        }
    } synchronous:true];
    
    return minMid;
}

- (int)loadPeerMinMediaMid:(int64_t)peerId
{
    __block int minMediaMid = 0;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT last_media FROM %@ WHERE pid=%lld", _peerPropertiesTableName, peerId]];
        if ([result next])
        {
            minMediaMid = [result intForColumn:@"last_media"];
        }
    } synchronous:true];
    
    return minMediaMid;
}

- (void)loadPeerNotificationSettings:(int64_t)peerId soundId:(int *)soundId muteUntil:(int *)muteUntil previewText:(bool *)previewText photoNotificationsEnabled:(bool *)photoNotificationsEnabled notFound:(bool *)notFound
{
    __block bool found = false;
    __block int foundSoundId = 1;
    __block int foundMuteUntil = 0;
    __block int foundPreviewText = 1;
    __block bool foundPhotoNotificationsEnabled = true;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT notification_type, mute, preview_text FROM %@ WHERE pid=%lld", _peerPropertiesTableName, peerId]];
        if ([result next])
        {
            foundSoundId = [result intForColumn:@"notification_type"];
            foundMuteUntil = [result intForColumn:@"mute"];
            foundPreviewText = [result intForColumn:@"preview_text"] != 0;
            found = true;
            
            if (foundMuteUntil - (CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970) <= 0)
            {
                foundMuteUntil = 0;
                [_database executeQuery:[NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET mute=0 WHERE pid=%lld", _peerPropertiesTableName, peerId]];
            }
            
            TG_SYNCHRONIZED_BEGIN(_mutedPeers);
            _mutedPeers[peerId] = foundMuteUntil;
            TG_SYNCHRONIZED_END(_mutedPeers);
        }
        
        foundPhotoNotificationsEnabled = [self loadPeerPhotoNotificationsEnabled:peerId];
    } synchronous:true];
    
    if (found && notFound != NULL)
        *notFound = !found;
    
    if (soundId != NULL)
        *soundId = foundSoundId;
    if (muteUntil != NULL)
        *muteUntil = foundMuteUntil;
    if (previewText != NULL)
        *previewText = foundPreviewText;
    if (photoNotificationsEnabled != NULL)
        *photoNotificationsEnabled = foundPhotoNotificationsEnabled;
}

- (BOOL)isPeerMuted:(int64_t)peerId
{
    bool found = false;
    int muteDate = 0;
    
    TG_SYNCHRONIZED_BEGIN(_mutedPeers);
    std::map<int64_t, int>::iterator it = _mutedPeers.find(peerId);
    if (it != _mutedPeers.end())
    {
        found = true;
        muteDate = it->second;
        
        if (muteDate != 0 && muteDate - (CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970) <= 0)
        {
            muteDate = 0;
            _mutedPeers[peerId] = muteDate;
            
            [self dispatchOnDatabaseThread:^
            {
                [_database executeQuery:[NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET mute=0 WHERE pid=%lld", _peerPropertiesTableName, peerId]];
            } synchronous:false];
        }
    }
    TG_SYNCHRONIZED_END(_mutedPeers);
    
    if (found)
        return muteDate > 0;
    
    __block bool blockIsMuted = false;
    
    [self dispatchOnDatabaseThread:^
    {
        int muteUntil = 0;
        [self loadPeerNotificationSettings:peerId soundId:NULL muteUntil:&muteUntil previewText:NULL photoNotificationsEnabled:NULL notFound:NULL];
        
        if (muteUntil != 0 && muteUntil - (CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970 + _timeDifferenceFromUTC) <= 0)
        {
            [_database executeQuery:[NSString stringWithFormat:@"UPDATE OR IGNORE %@ SET mute=0 WHERE pid=%lld", _peerPropertiesTableName, peerId]];
            muteUntil = 0;
        }
        
        TG_SYNCHRONIZED_BEGIN(_mutedPeers);
        _mutedPeers[peerId] = muteUntil;
        TG_SYNCHRONIZED_END(_mutedPeers);
        
        blockIsMuted = muteUntil != 0;
    } synchronous:true];
    
    return blockIsMuted;
}

- (TGPeerCustomSettings)loadPeerCustomSettings:(int64_t)peerId
{
    bool cacheFound = false;
    TGPeerCustomSettings value;
    
    TG_SYNCHRONIZED_BEGIN(_peerCustomSettings);
    auto it = _peerCustomSettings.find(peerId);
    if (it != _peerCustomSettings.end())
    {
        cacheFound = true;
        value = it->second;
    }
    TG_SYNCHRONIZED_END(_peerCustomSettings);
    
    if (cacheFound)
        return value;
    
    NSData *data = [self conversationCustomPropertySync:peerId name:TGCustomPeerSettingsKey];
    
    if (data.length != 0)
    {
        int ptr = 0;
        
        uint8_t version = 0;
        [data getBytes:&version range:NSMakeRange(ptr, 1)];
        ptr++;
        
        uint8_t photoNotificationsEnabled = 0;
        [data getBytes:&photoNotificationsEnabled length:1];
        ptr++;
        
        value.photoNotificationsEnabled = photoNotificationsEnabled;
    }
    else
    {
        value.photoNotificationsEnabled = true;
    }
    
    TG_SYNCHRONIZED_BEGIN(_peerCustomSettings);
    _peerCustomSettings[peerId] = value;
    TG_SYNCHRONIZED_END(_peerCustomSettings);
    
    return value;
}

- (void)storePeerCustomSettings:(int64_t)peerId customSettings:(TGPeerCustomSettings)customSettings
{
    bool commitToDatabase = true;
    
    TG_SYNCHRONIZED_BEGIN(_peerCustomSettings);
    auto it = _peerCustomSettings.find(peerId);
    if (it != _peerCustomSettings.end())
    {
        commitToDatabase = memcmp(&customSettings, &it->second, sizeof(TGPeerCustomSettings));
    }
    _peerCustomSettings[peerId] = customSettings;
    TG_SYNCHRONIZED_END(_peerCustomSettings);
    
    if (commitToDatabase)
    {
        NSMutableData *data = [[NSMutableData alloc] init];
        
        uint8_t version = 0;
        [data appendBytes:&version length:1];
        
        uint8_t photoNotificationsEnabled = customSettings.photoNotificationsEnabled;
        [data appendBytes:&photoNotificationsEnabled length:1];
        
        [self setConversationCustomProperty:peerId name:TGCustomPeerSettingsKey value:data];
    }
}

- (bool)loadPeerPhotoNotificationsEnabled:(int64_t)peerId
{
    return [self loadPeerCustomSettings:peerId].photoNotificationsEnabled;
}

- (void)setPeerPhotoNotificationsEnabled:(int64_t)peerId photoNotificationsEnabled:(bool)photoNotificationsEnabled
{
    TGPeerCustomSettings customSettings = [self loadPeerCustomSettings:peerId];
    if (customSettings.photoNotificationsEnabled != photoNotificationsEnabled)
    {
        customSettings.photoNotificationsEnabled = photoNotificationsEnabled;
        [self storePeerCustomSettings:peerId customSettings:customSettings];
    }
}

- (std::set<int>)filterPeerPhotoNotificationsEnabled:(std::vector<int> const &)uidList
{
#warning optimize
    
    std::set<int> result;
    
    for (auto it : uidList)
    {
        if ([self loadPeerPhotoNotificationsEnabled:it] && [self uidIsRemoteContact:it])
            result.insert(it);
    }
    
    [self _filterPeersAreBlockedSync:&result];
    
    return result;
}

- (int)minAutosaveMessageIdForConversation:(int64_t)conversationId
{
    int result = 0;
    bool found = false;
    
    TG_SYNCHRONIZED_BEGIN(_minAutosaveMessageIdForConversations);
    auto it = _minAutosaveMessageIdForConversations.find(conversationId);
    if (it != _minAutosaveMessageIdForConversations.end())
    {
        result = it->second;
        found = true;
    }
    TG_SYNCHRONIZED_END(_minAutosaveMessageIdForConversations);
    
    if (!found)
    {
        NSData *value = [self conversationCustomPropertySync:conversationId name:@"minReadIncomingMid".hash];
        
        if (value == nil)
            result = INT_MAX;
        else
            [value getBytes:&result range:NSMakeRange(0, 4)];
        
        TG_SYNCHRONIZED_BEGIN(_minAutosaveMessageIdForConversations);
        _minAutosaveMessageIdForConversations[conversationId] = result;
        TG_SYNCHRONIZED_END(_minAutosaveMessageIdForConversations);
    }
    
    return result;
}

- (void)storeMinAutosaveMessageIdForConversation:(int64_t)conversationId mid:(int)mid
{
    bool loadFromDatabase = true;
    bool storeToDatabase = false;
    
    TG_SYNCHRONIZED_BEGIN(_minAutosaveMessageIdForConversations);
    auto it = _minAutosaveMessageIdForConversations.find(conversationId);
    if (it != _minAutosaveMessageIdForConversations.end())
    {
        if (it->second > mid)
        {
            it->second = mid;
            storeToDatabase = true;
        }
        
        loadFromDatabase = false;
    }
    TG_SYNCHRONIZED_END(_minAutosaveMessageIdForConversations);
    
    if (loadFromDatabase)
    {
        NSData *value = [self conversationCustomPropertySync:conversationId name:@"minReadIncomingMid".hash];
        
        int result = INT_MAX;
        if (value != nil)
            [value getBytes:&result range:NSMakeRange(0, 4)];
        
        TG_SYNCHRONIZED_BEGIN(_minAutosaveMessageIdForConversations);
        _minAutosaveMessageIdForConversations[conversationId] = result;
        
        if (result > mid)
            storeToDatabase = true;
        TG_SYNCHRONIZED_END(_minAutosaveMessageIdForConversations);
    }
    
    if (storeToDatabase)
    {
        [self setConversationCustomProperty:conversationId name:@"minReadIncomingMid".hash value:[[NSData alloc] initWithBytes:&mid length:4]];
    }
}

- (void)storePeerMinMid:(int64_t)peerId minMid:(int)minMid
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT pid FROM %@ WHERE pid=%lld", _peerPropertiesTableName, peerId]];
        if ([result next])
        {
            [_database executeUpdate:[NSString stringWithFormat:@"UPDATE %@ SET last_mid=%d WHERE pid=%lld", _peerPropertiesTableName, minMid, peerId]];
        }
        else
        {
            [_database executeUpdate:[NSString stringWithFormat:@"INSERT INTO %@ (pid, last_mid, last_media, notification_type, mute, preview_text, custom_properties) VALUES(%lld, %d, 0, 1, 0, 1, NULL)", _peerPropertiesTableName, peerId, minMid]];
        }
    } synchronous:false];
}

- (void)storePeerMinMediaMid:(int64_t)peerId minMediaMid:(int)minMediaMid
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT pid FROM %@ WHERE pid=%lld", _peerPropertiesTableName, peerId]];
        if ([result next])
        {
            [_database executeUpdate:[NSString stringWithFormat:@"UPDATE %@ SET last_media=%d WHERE pid=%lld", _peerPropertiesTableName, minMediaMid, peerId]];
        }
        else
        {
            [_database executeUpdate:[NSString stringWithFormat:@"INSERT INTO %@ (pid, last_mid, last_media, notification_type, mute, preview_text, custom_properties) VALUES(%lld, 0, %d, 1, 0, 1, NULL)", _peerPropertiesTableName, peerId, minMediaMid]];
        }
    } synchronous:false];
}

- (void)storePeerNotificationSettings:(int64_t)peerId soundId:(int)soundId muteUntil:(int)muteUntil previewText:(bool)previewText photoNotificationsEnabled:(bool)photoNotificationsEnabled writeToActionQueue:(bool)writeToActionQueue completion:(void (^)(bool))completion
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT pid, notification_type, mute, preview_text FROM %@ WHERE pid=%lld", _peerPropertiesTableName, peerId]];
        if ([result next])
        {
            int currentSoundId = [result intForColumn:@"notification_type"];
            int currentMuteUntil = [result intForColumn:@"mute"];
            bool currentPreviewText = [result intForColumn:@"preview_text"] != 0;
            
            [_database executeUpdate:[NSString stringWithFormat:@"UPDATE %@ SET notification_type=%d, mute=%d, preview_text=%d WHERE pid=%lld", _peerPropertiesTableName, soundId, muteUntil, previewText != 0, peerId]];
            
            if (completion)
                completion(soundId != currentSoundId || muteUntil != currentMuteUntil || previewText != currentPreviewText);
        }
        else
        {
            [_database executeUpdate:[NSString stringWithFormat:@"INSERT INTO %@ (pid, last_mid, last_media, notification_type, mute, preview_text, custom_properties) VALUES(%lld, 0, 0, %d, %d, %d, NULL)", _peerPropertiesTableName, peerId, soundId, muteUntil, previewText]];
            
            if (completion)
                completion(soundId != 0 || muteUntil != 0 || previewText != true);
        }
        
        TG_SYNCHRONIZED_BEGIN(_mutedPeers);
        _mutedPeers[peerId] = muteUntil;
        TG_SYNCHRONIZED_END(_mutedPeers);
        
        [self setPeerPhotoNotificationsEnabled:peerId photoNotificationsEnabled:photoNotificationsEnabled];
        
        if (writeToActionQueue)
        {
            [self storeFutureActions:[NSArray arrayWithObject:[[TGChangeNotificationSettingsFutureAction alloc] initWithPeerId:peerId muteUntil:muteUntil soundId:soundId previewText:previewText photoNotificationsEnabled:photoNotificationsEnabled]]];
        }
    } synchronous:false];
}

- (void)setConversationCustomProperty:(int64_t)conversationId name:(int)name value:(NSData *)value
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT custom_properties FROM %@ WHERE pid=?", _peerPropertiesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        
        std::map<int, NSData *> tmpDict;
        bool update = false;
        
        if ([result next])
        {
            update = true;
            NSData *serializedProperties = [result dataForColumn:@"custom_properties"];
            
            int ptr = 0;
            
            int version = 0;
            [serializedProperties getBytes:&version range:NSMakeRange(ptr, 4)];
            ptr += 4;
            
            int count = 0;
            [serializedProperties getBytes:&count range:NSMakeRange(ptr, 4)];
            ptr += 4;
            
            for (int i = 0; i < count; i++)
            {
                int key = 0;
                [serializedProperties getBytes:&key range:NSMakeRange(ptr, 4)];
                ptr += 4;
                
                int valueLength = 0;
                [serializedProperties getBytes:&valueLength range:NSMakeRange(ptr, 4)];
                ptr += 4;
                
                uint8_t *valueBytes = (uint8_t *)malloc(valueLength);
                [serializedProperties getBytes:valueBytes range:NSMakeRange(ptr, valueLength)];
                ptr += valueLength;
                
                NSData *value = [[NSData alloc] initWithBytesNoCopy:valueBytes length:valueLength freeWhenDone:true];
                tmpDict.insert(std::pair<int, NSData *>(key, value));
            }
        }

        if (value != nil)
            tmpDict[name] = value;
        else
            tmpDict.erase(name);
        
        NSMutableData *outData = [[NSMutableData alloc] init];
        
        int outVersion = 0;
        [outData appendBytes:&outVersion length:4];
        
        int outCount = tmpDict.size();
        [outData appendBytes:&outCount length:4];
        
        for (auto it = tmpDict.begin(); it != tmpDict.end(); it++)
        {
            int key = it->first;
            [outData appendBytes:&key length:4];
            
            int valueLength = it->second.length;
            [outData appendBytes:&valueLength length:4];
            [outData appendData:it->second];
        }
        
        if (update)
        {
            [_database executeUpdate:[NSString stringWithFormat:@"UPDATE %@ SET custom_properties=? WHERE pid=?", _peerPropertiesTableName], outData, [[NSNumber alloc] initWithLongLong:conversationId]];
        }
        else
        {
            [_database executeUpdate:[NSString stringWithFormat:@"INSERT INTO %@ (pid, last_mid, last_media, notification_type, mute, preview_text, custom_properties) VALUES(?, 0, 0, 1, 0, 1, ?)", _peerPropertiesTableName], [[NSNumber alloc] initWithLongLong:conversationId], outData];
        }
    } synchronous:false];
}

- (void)conversationCustomProperty:(int64_t)conversationId name:(int)name completion:(void (^)(NSData *value))completion
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT custom_properties FROM %@ WHERE pid=%lld", _peerPropertiesTableName, conversationId]];
        
        id value = nil;
        
        if ([result next])
        {
            NSData *serializedProperties = [result dataForColumn:@"custom_properties"];
            if (serializedProperties != nil)
            {
                NSData *serializedProperties = [result dataForColumn:@"custom_properties"];
                
                int ptr = 0;
                
                int version = 0;
                [serializedProperties getBytes:&version range:NSMakeRange(ptr, 4)];
                ptr += 4;
                
                int count = 0;
                [serializedProperties getBytes:&count range:NSMakeRange(ptr, 4)];
                ptr += 4;
                
                for (int i = 0; i < count; i++)
                {
                    int key = 0;
                    [serializedProperties getBytes:&key range:NSMakeRange(ptr, 4)];
                    ptr += 4;
                    
                    int valueLength = 0;
                    [serializedProperties getBytes:&valueLength range:NSMakeRange(ptr, 4)];
                    ptr += 4;
                    
                    if (key == name)
                    {
                        uint8_t *valueBytes = (uint8_t *)malloc(valueLength);
                        [serializedProperties getBytes:valueBytes range:NSMakeRange(ptr, valueLength)];
                        
                        value = [[NSData alloc] initWithBytesNoCopy:valueBytes length:valueLength freeWhenDone:true];
                        
                        break;
                    }

                    ptr += valueLength;
                }
            }
        }
        
        if (completion)
            completion(value);
    } synchronous:false];
}

- (NSData *)conversationCustomPropertySync:(int64_t)conversationId name:(int)name
{
    __block id value = nil;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[NSString stringWithFormat:@"SELECT custom_properties FROM %@ WHERE pid=?", _peerPropertiesTableName], [[NSNumber alloc] initWithLongLong:conversationId]];
        
        if ([result next])
        {
            NSData *serializedProperties = [result dataForColumn:@"custom_properties"];
            if (serializedProperties != nil)
            {
                NSData *serializedProperties = [result dataForColumn:@"custom_properties"];
                
                int ptr = 0;
                
                int version = 0;
                [serializedProperties getBytes:&version range:NSMakeRange(ptr, 4)];
                ptr += 4;
                
                int count = 0;
                [serializedProperties getBytes:&count range:NSMakeRange(ptr, 4)];
                ptr += 4;
                
                for (int i = 0; i < count; i++)
                {
                    int key = 0;
                    [serializedProperties getBytes:&key range:NSMakeRange(ptr, 4)];
                    ptr += 4;
                    
                    int valueLength = 0;
                    [serializedProperties getBytes:&valueLength range:NSMakeRange(ptr, 4)];
                    ptr += 4;
                    
                    if (key == name)
                    {
                        uint8_t *valueBytes = (uint8_t *)malloc(valueLength);
                        [serializedProperties getBytes:valueBytes range:NSMakeRange(ptr, valueLength)];
                        
                        value = [[NSData alloc] initWithBytesNoCopy:valueBytes length:valueLength freeWhenDone:true];
                        
                        break;
                    }
                    
                    ptr += valueLength;
                }
            }
        }
    } synchronous:true];
    
    return value;
}

- (void)clearPeerNotificationSettings:(bool)writeToActionQueue
{
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET notification_type=1, mute=0, preview_text=1", _peerPropertiesTableName]];
        
        TG_SYNCHRONIZED_BEGIN(_mutedPeers);
        _mutedPeers.clear();
        TG_SYNCHRONIZED_END(_mutedPeers);
        
        if (writeToActionQueue)
        {
            TGClearNotificationsFutureAction *action = [[TGClearNotificationsFutureAction alloc] init];
            [self storeFutureActions:[NSArray arrayWithObject:action]];
        }
    } synchronous:false];
}

- (void)setAssetIsStored:(NSString *)url
{
    [self dispatchOnDatabaseThread:^
    {
        NSData *data = [url dataUsingEncoding:NSUTF8StringEncoding];
        const char *ptr = (const char *)[data bytes];
        unsigned char md5Buffer[16];
        CC_MD5(ptr, data.length, md5Buffer);
        
        int64_t hash_high = 0;
        memcpy(&hash_high, md5Buffer, 8);
        int64_t hash_low = 0;
        memcpy(&hash_low, md5Buffer + 8, 8);
        
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ VALUES (?, ?)", _assetsTableName], [[NSNumber alloc] initWithLongLong:hash_high], [[NSNumber alloc] initWithLongLong:hash_low]];
    } synchronous:false];
}

- (void)checkIfAssetIsStored:(NSString *)url completion:(void (^)(bool stored))completion
{
    [self dispatchOnDatabaseThread:^
    {
        bool result = false;
        
        NSData *data = [url dataUsingEncoding:NSUTF8StringEncoding];
        const char *ptr = (const char *)[data bytes];
        unsigned char md5Buffer[16];
        CC_MD5(ptr, data.length, md5Buffer);
        
        int64_t hash_high = 0;
        memcpy(&hash_high, md5Buffer, 8);
        int64_t hash_low = 0;
        memcpy(&hash_low, md5Buffer + 8, 8);
        
        FMResultSet *resultSet = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ WHERE hash_high=? AND hash_low=?", _assetsTableName], [[NSNumber alloc] initWithLongLong:hash_high], [[NSNumber alloc] initWithLongLong:hash_low]];
        result = [resultSet next];
        resultSet = nil;
        
        if (completion)
            completion(result);
    } synchronous:false];
}

- (void)setPeerIsBlocked:(int64_t)peerId blocked:(bool)blocked writeToActionQueue:(bool)writeToActionQueue
{
    [self dispatchOnDatabaseThread:^
    {
        NSNumber *nPeerId = [[NSNumber alloc] initWithLongLong:peerId];
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT pid FROM %@ WHERE pid=?", _blockedUsersTableName], nPeerId];
        bool currentBlocked = [result next];
        result = nil;
        
        if (blocked != currentBlocked)
        {
            if (blocked)
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT INTO %@ (pid, date) VALUES (?, ?)", _blockedUsersTableName], nPeerId, [[NSNumber alloc] initWithInt:(int)((CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970))]];
            else
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE pid=?", _blockedUsersTableName], nPeerId];
            
            if (writeToActionQueue)
            {
                [self storeFutureActions:[NSArray arrayWithObject:[[TGChangePeerBlockStatusFutureAction alloc] initWithPeerId:[nPeerId longLongValue] block:blocked]]];
            }
        }
    } synchronous:false];
}

- (void)_filterPeersAreBlockedSync:(std::set<int> *)pSet
{
    [self dispatchOnDatabaseThread:^
    {
        auto it = pSet->begin();
        while (it != pSet->end())
        {
            FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT pid FROM %@ WHERE pid=?", _blockedUsersTableName], [[NSNumber alloc] initWithLongLong:*it]];
            bool blocked = [result next];
            
            if (blocked)
                pSet->erase(it++);
            else
                ++it;
        }
    } synchronous:true];
}

- (void)loadPeerIsBlocked:(int64_t)peerId completion:(void (^)(bool blocked))completion
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT pid FROM %@ WHERE pid=?", _blockedUsersTableName], [[NSNumber alloc] initWithLongLong:peerId]];
        bool blocked = [result next];
        if (completion)
            completion(blocked);
    } synchronous:false];
}

- (void)replaceBlockedList:(NSArray *)blockedPeers
{
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@", _blockedUsersTableName]];
        [_database beginTransaction];
        for (NSArray *record in blockedPeers)
        {
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT INTO %@ (pid, date) VALUES (?, ?)", _blockedUsersTableName], [record objectAtIndex:0], [record objectAtIndex:1]];
        }
        [_database commit];
    } synchronous:false];
}

- (void)loadBlockedList:(void (^)(NSArray *blockedList))completion
{
    [self dispatchOnDatabaseThread:^
    {
        NSMutableArray *array = [[NSMutableArray alloc] init];
        
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ ORDER BY date DESC", _blockedUsersTableName]];
        int pidIndex = [result columnIndexForName:@"pid"];
        
        while ([result next])
        {
            int64_t pid = [result longLongIntForColumnIndex:pidIndex];
            [array addObject:[[NSNumber alloc] initWithLongLong:pid]];
        }
        
        if (completion)
            completion(array);
    } synchronous:false];
}

- (int)loadBlockedDate:(int64_t)peerId
{
    __block int date = 0;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT date FROM %@ WHERE pid=?", _blockedUsersTableName], [[NSNumber alloc] initWithLongLong:peerId]];
        if ([result next])
        {
            date = [result intForColumn:@"date"];
        }
    } synchronous:true];
    
    return date;
}

- (void)storePeerProfilePhotos:(int64_t)peerId photosArray:(NSArray *)photosArray append:(bool)append
{
    [self dispatchOnDatabaseThread:^
    {
        [_database beginTransaction];
        
        NSNumber *nPeerId = [[NSNumber alloc] initWithLongLong:peerId];
        
        if (!append)
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE peer_id=?", _peerProfilePhotosTableName], nPeerId];
        
        NSString *insertFormat = [[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ (photo_id, peer_id, data) VALUES (?, ?, ?)", _peerProfilePhotosTableName];
        
        for (TGImageMediaAttachment *imageAttachment in photosArray)
        {
            NSMutableData *data = [[NSMutableData alloc] init];
            [imageAttachment serialize:data];
            [_database executeUpdate:insertFormat, [[NSNumber alloc] initWithLongLong:imageAttachment.imageId], nPeerId, data];
        }
        
        [_database commit];
    } synchronous:false];
}

- (NSArray *)addPeerProfilePhotos:(int64_t)peerId photosArray:(NSArray *)photosArray
{
    NSMutableArray *nonExistingIds = [[NSMutableArray alloc] init];
    
    [self dispatchOnDatabaseThread:^
    {
        [_database beginTransaction];
        
        NSNumber *nPeerId = [[NSNumber alloc] initWithLongLong:peerId];
        
        NSString *insertFormat = [[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ (photo_id, peer_id, data) VALUES (?, ?, ?)", _peerProfilePhotosTableName];
        NSString *selectFormat = [[NSString alloc] initWithFormat:@"SELECT photo_id FROM %@ WHERE peer_id=? AND photo_id=?", _peerProfilePhotosTableName];
        
        for (TGImageMediaAttachment *imageAttachment in photosArray)
        {
            NSNumber *nPhotoId = [[NSNumber alloc] initWithLongLong:imageAttachment.imageId];
            
            FMResultSet *result = [_database executeQuery:selectFormat, nPeerId, nPhotoId];
            if (![result next])
            {
                NSMutableData *data = [[NSMutableData alloc] init];
                [imageAttachment serialize:data];
                [_database executeUpdate:insertFormat, [[NSNumber alloc] initWithLongLong:imageAttachment.imageId], nPeerId, data];
                
                [nonExistingIds addObject:nPhotoId];
            }
        }
        
        [_database commit];
    } synchronous:true];
    
    return nonExistingIds;
}

- (void)loadPeerProfilePhotos:(int64_t)peerId completion:(void (^)(NSArray *photosArray))completion
{
    [self dispatchOnDatabaseThread:^
    {
        NSMutableArray *array = [[NSMutableArray alloc] init];
        
        FMResultSet *resultSet = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT data FROM %@ WHERE peer_id=?", _peerProfilePhotosTableName], [[NSNumber alloc] initWithLongLong:peerId]];
        
        int indexData = [resultSet columnIndexForName:@"data"];
        
        TGImageMediaAttachment *parser = [[TGImageMediaAttachment alloc] init];
        
        while ([resultSet next])
        {
            NSData *data = [resultSet dataForColumnIndex:indexData];
            
            NSInputStream *is = [[NSInputStream alloc] initWithData:data];
            [is open];
            TGImageMediaAttachment *imageAttachment = (TGImageMediaAttachment *)[parser parseMediaAttachment:is];
            [is close];
            
            if (imageAttachment != nil)
                [array addObject:imageAttachment];
        }
        
        if (completion)
            completion(array);
    } synchronous:false];
}

- (void)deletePeerProfilePhotos:(int64_t)peerId imageIds:(NSArray *)imageIds
{
    [self dispatchOnDatabaseThread:^
    {
        NSNumber *nPeerId = [[NSNumber alloc] initWithLongLong:peerId];
        
        NSMutableString *idsString = [[NSMutableString alloc] init];
        for (NSNumber *nImageId in imageIds)
        {
            if (idsString.length != 0)
                [idsString appendString:@","];
            [idsString appendFormat:@"%lld", [nImageId longLongValue]];
        }
        
        [_database setSoftShouldCacheStatements:false];
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE peer_id=? AND photo_id IN (%@)", _peerProfilePhotosTableName, idsString], nPeerId];
        [_database setSoftShouldCacheStatements:true];
    } synchronous:false];
}

- (void)clearPeerProfilePhotos
{
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@", _peerProfilePhotosTableName]];
    } synchronous:false];
}

- (void)updateLatestMessageId:(int)mid applied:(bool)applied completion:(void (^)(int greaterMidForSynchronization))completion
{
    [self dispatchOnDatabaseThread:^
    {
        int databaseMid = 0;
        
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT value FROM %@ WHERE key=?", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceLatestSynchronizedMidKey]];
        if ([result next])
        {
            NSData *data = [result dataForColumn:@"value"];
            [data getBytes:&databaseMid length:4];
        }
        
        if (databaseMid <= mid)
        {
            uint8_t dataBytes[5];
            *((int *)(dataBytes + 0)) = mid;
            dataBytes[4] = applied ? 1 : 0;
            
            NSData *data = [[NSData alloc] initWithBytes:dataBytes length:5];
            if (databaseMid == 0)
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT INTO %@ (key, value) VALUES (?, ?)", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceLatestSynchronizedMidKey], data];
            else
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET value=? WHERE key=?", _serviceTableName], data, [[NSNumber alloc] initWithInt:_serviceLatestSynchronizedMidKey]];
            
            if (completion)
                completion(mid);
        }
        else
        {
            if (completion)
                completion(0);
        }
    } synchronous:false];
}

- (void)updateLatestQts:(int32_t)qts applied:(bool)applied completion:(void (^)(int greaterQtsForSynchronization))completion
{
    [self dispatchOnDatabaseThread:^
    {
        int databaseQts = 0;
        
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT value FROM %@ WHERE key=?", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceLatestSynchronizedQtsKey]];
        if ([result next])
        {
            NSData *data = [result dataForColumn:@"value"];
            [data getBytes:&databaseQts length:4];
        }
        
        if (databaseQts <= qts)
        {
            uint8_t dataBytes[5];
            *((int *)(dataBytes + 0)) = qts;
            dataBytes[4] = applied ? 1 : 0;
            
            NSData *data = [[NSData alloc] initWithBytes:dataBytes length:5];
            if (databaseQts == 0)
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT INTO %@ (key, value) VALUES (?, ?)", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceLatestSynchronizedQtsKey], data];
            else
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"UPDATE %@ SET value=? WHERE key=?", _serviceTableName], data, [[NSNumber alloc] initWithInt:_serviceLatestSynchronizedQtsKey]];
            
            if (completion)
                completion(databaseQts < qts ? qts : 0);
        }
        else
        {
            if (completion)
                completion(0);
        }
    } synchronous:false];
}

- (void)checkIfLatestMessageIdIsNotApplied:(void (^)(int midForSinchronization))completion
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT value FROM %@ WHERE key=?", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceLatestSynchronizedMidKey]];
        if ([result next])
        {
            NSData *data = [result dataForColumn:@"value"];
            int databaseMid = 0;
            uint8_t databaseApplied = 0;
            [data getBytes:&databaseMid length:4];
            [data getBytes:&databaseApplied range:NSMakeRange(4, 1)];
            
            if (completion)
                completion(databaseApplied != 0 ? 0 : databaseMid);
        }
        else
        {
            if (completion)
                completion(0);
        }
    } synchronous:false];
}

- (void)checkIfLatestQtsIsNotApplied:(void (^)(int qtsForSinchronization))completion
{
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT value FROM %@ WHERE key=?", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceLatestSynchronizedQtsKey]];
        if ([result next])
        {
            NSData *data = [result dataForColumn:@"value"];
            int databaseQts = 0;
            uint8_t databaseApplied = 0;
            [data getBytes:&databaseQts length:4];
            [data getBytes:&databaseApplied range:NSMakeRange(4, 1)];
            
            if (completion)
                completion(databaseApplied != 0 ? 0 : databaseQts);
        }
        else
        {
            if (completion)
                completion(0);
        }
    } synchronous:false];
}

- (TGMediaAttachment *)loadServerAssetData:(NSString *)key
{
    __block TGMediaAttachment *attachment = nil;
    
    [self dispatchOnDatabaseThread:^
    {
        int64_t hash_high = 0;
        int64_t hash_low = 0;
        
        NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
        
        if (keyData.length == 16)
        {
            memcpy(&hash_high, [keyData bytes], 8);
            memcpy(&hash_low, ((uint8_t *)[keyData bytes]) + 8, 8);
        }
        else
        {
            const char *ptr = (const char *)[keyData bytes];
            unsigned char md5Buffer[16];
            CC_MD5(ptr, keyData.length, md5Buffer);
            
            memcpy(&hash_high, md5Buffer, 8);
            memcpy(&hash_low, md5Buffer + 8, 8);
        }
        
        FMResultSet *resultSet = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT data FROM %@ WHERE hash_high=? AND hash_low=?", _serverAssetsTableName], [[NSNumber alloc] initWithLongLong:hash_high], [[NSNumber alloc] initWithLongLong:hash_low]];
        
        if ([resultSet next])
        {
            NSData *data = [resultSet dataForColumn:@"data"];
            if (data.length >= 4)
            {
                NSInputStream *is = [[NSInputStream alloc] initWithData:data];
                [is open];
                
                int type = 0;
                [is read:(uint8_t *)&type maxLength:4];
                
                if (type == 0)
                {
                    TGImageMediaAttachment *imageAttachment = (TGImageMediaAttachment *)[[[TGImageMediaAttachment alloc] init] parseMediaAttachment:is];
                    if (imageAttachment != nil)
                        attachment = imageAttachment;
                }
                else if (type == 1)
                {
                    TGVideoMediaAttachment *videoAttachment = (TGVideoMediaAttachment *)[[[TGVideoMediaAttachment alloc] init] parseMediaAttachment:is];
                    if (videoAttachment != nil)
                        attachment = videoAttachment;
                }
                
                [is close];
            }
        }
        
    } synchronous:true];
    
    return attachment;
}

- (void)storeServerAssetData:(NSString *)key attachment:(TGMediaAttachment *)attachment;
{
    [self dispatchOnDatabaseThread:^
    {
        NSMutableData *data = [[NSMutableData alloc] init];
        if (attachment.type == TGImageMediaAttachmentType)
        {
            int type = 0;
            [data appendBytes:&type length:4];
            
            [(TGImageMediaAttachment *)attachment serialize:data];
        }
        else if (attachment.type == TGVideoMediaAttachmentType)
        {
            int type = 1;
            [data appendBytes:&type length:4];
            
            [(TGVideoMediaAttachment *)attachment serialize:data];
        }
        
        if (data.length != 0)
        {
            NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
            const char *ptr = (const char *)[keyData bytes];
            unsigned char md5Buffer[16];
            CC_MD5(ptr, keyData.length, md5Buffer);
            
            int64_t hash_high = 0;
            memcpy(&hash_high, md5Buffer, 8);
            int64_t hash_low = 0;
            memcpy(&hash_low, md5Buffer + 8, 8);
            
            [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@ (hash_high, hash_low, data) VALUES(?, ?, ?)", _serverAssetsTableName], [[NSNumber alloc] initWithLongLong:hash_high], [[NSNumber alloc] initWithLongLong:hash_low], data];
        }
    } synchronous:false];
}

- (void)clearServerAssetData
{
    [self dispatchOnDatabaseThread:^
    {
        [_database executeUpdate:[[NSString alloc] initWithFormat:@"DELETE FROM %@", _serverAssetsTableName]];
    } synchronous:false];
}

- (int64_t)peerIdForEncryptedConversationId:(int64_t)encryptedConversationId
{
    return [self peerIdForEncryptedConversationId:encryptedConversationId createIfNecessary:true];
}

- (int64_t)peerIdForEncryptedConversationId:(int64_t)encryptedConversationId createIfNecessary:(bool)createIfNecessary
{
    int64_t result = 0;
    
    TG_SYNCHRONIZED_BEGIN(_encryptedConversationIds);
    
    auto it = _encryptedConversationIds.find(encryptedConversationId);
    if (it != _encryptedConversationIds.end())
        result = it->second;
    else
    {
        __block int64_t blockResult = 0;
        
        [self dispatchOnDatabaseThread:^
        {
            FMResultSet *encryptedConversationIdResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ WHERE encrypted_id=?", _encryptedConversationIdsTableName], [[NSNumber alloc] initWithLongLong:encryptedConversationId]];
            if ([encryptedConversationIdResult next])
            {
                blockResult = [encryptedConversationIdResult longLongIntForColumn:@"cid"];
            }
            else if (createIfNecessary)
            {
                int localCount = 0;
                
                FMResultSet *encryptedConversationCountResult = [_database executeQuery:[NSString stringWithFormat:@"SELECT * from %@ WHERE key=?", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceEncryptedConversationCount]];
                if ([encryptedConversationCountResult next])
                {
                    NSData *value = [encryptedConversationCountResult dataForColumn:@"value"];
                    int intValue = 0;
                    [value getBytes:&intValue range:NSMakeRange(0, 4)];
                    localCount = intValue;
                }
                
                blockResult = (int64_t)INT_MIN - (int64_t)localCount;
                int newCount = localCount + 1;
            
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT INTO %@(encrypted_id, cid) VALUES(?, ?)", _encryptedConversationIdsTableName], [[NSNumber alloc] initWithLongLong:encryptedConversationId], [[NSNumber alloc] initWithLongLong:blockResult]];
                [_database executeUpdate:[[NSString alloc] initWithFormat:@"INSERT OR REPLACE INTO %@(key, value) VALUES(?, ?)", _serviceTableName], [[NSNumber alloc] initWithInt:_serviceEncryptedConversationCount], [[NSData alloc] initWithBytes:&newCount length:4]];
                
                TGLog(@"===== allocated new encrypted conversation id %lld -> %lld", encryptedConversationId, blockResult);
            }
        } synchronous:true];
        
        result = blockResult;
        if (result != 0)
        {
            _encryptedConversationIds[encryptedConversationId] = result;
            _peerIdsForEncryptedConversationIds[result] = encryptedConversationId;
        }
    }
    TG_SYNCHRONIZED_END(_encryptedConversationIds);
    
    return result;
}

- (int64_t)encryptedConversationIdForPeerId:(int64_t)peerId
{
    __block int64_t encryptedConversationId = 0;
    
    TG_SYNCHRONIZED_BEGIN(_encryptedConversationIds);
    
    auto it = _peerIdsForEncryptedConversationIds.find(peerId);
    if (it != _peerIdsForEncryptedConversationIds.end())
        encryptedConversationId = it->second;
    
    TG_SYNCHRONIZED_END(_encryptedConversationIds);
    
    if (encryptedConversationId == 0)
    {
        [self dispatchOnDatabaseThread:^
        {
            FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT encrypted_id FROM %@ WHERE cid=? LIMIT 1", _encryptedConversationIdsTableName], [[NSNumber alloc] initWithLongLong:peerId]];
            if ([result next])
                encryptedConversationId = [result longLongIntForColumn:@"encrypted_id"];
        } synchronous:true];
    }
    
    return encryptedConversationId;
}

- (int64_t)encryptedConversationAccessHash:(int64_t)conversationId
{
    int64_t accessHash = 0;
    
    TG_SYNCHRONIZED_BEGIN(_encryptedConversationAccessHash);
    auto it = _encryptedConversationAccessHash.find(conversationId);
    if (it != _encryptedConversationAccessHash.end())
        accessHash = it->second;
    TG_SYNCHRONIZED_END(_encryptedConversationAccessHash);
    
    if (accessHash == 0)
    {
        accessHash = [[self loadConversationWithId:conversationId] encryptedData].accessHash;
        if (accessHash != 0)
        {
            TG_SYNCHRONIZED_BEGIN(_encryptedConversationAccessHash);
            _encryptedConversationAccessHash[conversationId] = accessHash;
            TG_SYNCHRONIZED_END(_encryptedConversationAccessHash);
        }
    }
    
    return accessHash;
}

- (NSData *)encryptionKeyForConversationId:(int64_t)conversationId keyFingerprint:(int64_t *)keyFingerprint
{
    bool found = false;
    NSData *key = nil;
    int64_t fingerprint = 0;
    
    TG_SYNCHRONIZED_BEGIN(_conversationEncryptionKeys);
    auto it = _conversationEncryptionKeys.find(conversationId);
    if (it != _conversationEncryptionKeys.end())
    {
        found = true;
        key = it->second.second;
        fingerprint = it->second.first;
    }
    TG_SYNCHRONIZED_END(_conversationEncryptionKeys);
    
    if (!found)
    {
        NSData *data = [self conversationCustomPropertySync:conversationId name:murMurHash32(@"encryptionKey")];
        if (data.length > 8)
        {
            [data getBytes:&fingerprint range:NSMakeRange(0, 8)];
            key = [data subdataWithRange:NSMakeRange(8, data.length - 8)];
        }
        
        TG_SYNCHRONIZED_BEGIN(_conversationEncryptionKeys);
        _conversationEncryptionKeys[conversationId] = std::pair<int64_t, NSData *>(fingerprint, key);
        TG_SYNCHRONIZED_END(_conversationEncryptionKeys);
    }
    
    if (keyFingerprint != NULL)
        *keyFingerprint = fingerprint;
    
    return key;
}

- (void)storeEncryptionKeyForConversationId:(int64_t)conversationId key:(NSData *)key keyFingerprint:(int64_t)keyFingerprint
{
    NSMutableData *data = [[NSMutableData alloc] initWithCapacity:8 + key.length];
    [data appendBytes:&keyFingerprint length:8];
    [data appendData:key];
    
    [self setConversationCustomProperty:conversationId name:murMurHash32(@"encryptionKey") value:data];
    
    TG_SYNCHRONIZED_BEGIN(_conversationEncryptionKeys);
    _conversationEncryptionKeys[conversationId] = std::pair<int64_t, NSData *>(keyFingerprint, key);
    TG_SYNCHRONIZED_END(_conversationEncryptionKeys);
}

- (int)encryptedParticipantIdForConversationId:(int64_t)conversationId
{
    int32_t uid = 0;
    
    TG_SYNCHRONIZED_BEGIN(_encryptedParticipantIds);
    auto it = _encryptedParticipantIds.find(conversationId);
    if (it != _encryptedParticipantIds.end())
        uid = it->second;
    TG_SYNCHRONIZED_END(_encryptedParticipantIds);
    
    if (uid == 0)
    {
        TGConversation *conversation = [self loadConversationWithId:conversationId];
        
        if (conversation != nil && conversation.chatParticipants.chatParticipantUids.count != 0)
        {
            uid = [conversation.chatParticipants.chatParticipantUids[0] intValue];
            
            if (uid != 0)
            {
                TG_SYNCHRONIZED_BEGIN(_encryptedParticipantIds);
                _encryptedParticipantIds[conversationId] = uid;
                TG_SYNCHRONIZED_END(_encryptedParticipantIds);
            }
        }
    }
    
    return uid;
}

- (void)filterExistingRandomIds:(std::set<int64_t> *)randomIds
{
    [self dispatchOnDatabaseThread:^
    {
        [_database setSoftShouldCacheStatements:false];
        NSMutableString *rangeString = [[NSMutableString alloc] init];
        
        const int batchSize = 256;
        for (auto it = randomIds->begin(); it != randomIds->end(); )
        {
            [rangeString deleteCharactersInRange:NSMakeRange(0, rangeString.length)];
            bool first = true;
            
            for (int i = 0; i < batchSize && it != randomIds->end(); i++, it++)
            {
                if (first)
                {
                    first = false;
                    [rangeString appendFormat:@"%lld", *it];
                }
                else
                    [rangeString appendFormat:@",%lld", *it];
            }
            
            FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT random_id FROM %@ WHERE random_id IN (%@)", _randomIdsTableName, rangeString]];
            int randomIdIndex = [result columnIndexForName:@"random_id"];
            while ([result next])
            {
                int64_t randomId = [result longLongIntForColumnIndex:randomIdIndex];
                randomIds->erase(randomId);
            }
        }
        [_database setSoftShouldCacheStatements:true];
    } synchronous:true];
}

- (int64_t)activeEncryptedPeerIdForUserId:(int)userId
{
    __block int64_t activePeerId = 0;
    
    [self dispatchOnDatabaseThread:^
    {
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT * FROM %@ WHERE cid<=%d", _conversationListTableName, INT_MIN]];
        int maxDate = 0;
        int64_t peerIdWithMaxDate = 0;
        
        while ([result next])
        {
            TGConversation *conversation = loadConversationFromDatabase(result);
            if (conversation.chatParticipants.chatParticipantUids.count != 0)
            {
                if ([conversation.chatParticipants.chatParticipantUids[0] intValue] == userId)
                {
                    if (conversation.encryptedData.handshakeState != 3)
                    {
                        if (maxDate == 0 || conversation.date > maxDate)
                            peerIdWithMaxDate = conversation.conversationId;
                    }
                }
            }
        }
        
        activePeerId = peerIdWithMaxDate;
    } synchronous:true];
    
    return activePeerId;
}

- (int)messageLifetimeForPeerId:(int64_t)peerId
{
    int32_t result = 0;
    bool found = false;
    
    TG_SYNCHRONIZED_BEGIN(_messageLifetimeByPeerId);
    auto it = _messageLifetimeByPeerId.find(peerId);
    if (it != _messageLifetimeByPeerId.end())
    {
        result = it->second;
        found = true;
    }
    TG_SYNCHRONIZED_END(_messageLifetimeByPeerId);
    
    if (!found)
    {
        NSData *data = [self conversationCustomPropertySync:peerId name:murMurHash32(@"messageLifetime")];
        if (data != nil && data.length >= 4)
        {
            [data getBytes:&result length:4];
        }
        
        TG_SYNCHRONIZED_BEGIN(_messageLifetimeByPeerId);
        _messageLifetimeByPeerId[peerId] = result;
        TG_SYNCHRONIZED_END(_messageLifetimeByPeerId);
    }
    
    return result;
}

- (void)setMessageLifetimeForPeerId:(int64_t)peerId encryptedConversationId:(int64_t)encryptedConversationId messageLifetime:(int)messageLifetime writeToActionQueue:(bool)writeToActionQueue
{
    bool updated = true;
    
    TG_SYNCHRONIZED_BEGIN(_messageLifetimeByPeerId);
    auto it = _messageLifetimeByPeerId.find(peerId);
    if (it != _messageLifetimeByPeerId.end())
    {
        if (it->second == messageLifetime)
            updated = false;
    }
    _messageLifetimeByPeerId[peerId] = messageLifetime;
    TG_SYNCHRONIZED_END(_messageLifetimeByPeerId);
    
    if (updated)
    {
        int32_t value = messageLifetime;
        [self setConversationCustomProperty:peerId name:murMurHash32(@"messageLifetime") value:[[NSData alloc] initWithBytes:&value length:4]];
        
        [self processAndScheduleSelfDestruct];
        
        [ActionStageInstance() dispatchResource:[[NSString alloc] initWithFormat:@"/tg/conversationMessageLifetime/(%lld)", peerId] resource:@(messageLifetime)];
    }
    
    if (writeToActionQueue)
    {
        [self dispatchOnDatabaseThread:^
        {
            [self removeFutureActionsWithType:TGSynchronizeEncryptedChatSettingsFutureActionType uniqueIds:@[@(encryptedConversationId)]];
            //[ActionStageInstance() dispatchResource:@"/tg/service/cancelSynchronizeEncryptedChatSettings" resource:@(encryptedConversationId)];
            
            int64_t randomId = 0;
            arc4random_buf(&randomId, 8);
            [self storeFutureActions:@[[[TGSynchronizeEncryptedChatSettingsFutureAction alloc] initWithEncryptedConversationId:encryptedConversationId messageLifetime:messageLifetime messageRandomId:randomId]]];
        } synchronous:false];
    }
}

- (void)_filterConversationIdsByMessageLifetime:(std::map<int64_t, int> *)pMap
{
    std::vector<int64_t> unknownCids;
    
    TG_SYNCHRONIZED_BEGIN(_messageLifetimeByPeerId);
    
    for (auto it = pMap->begin(); it != pMap->end(); it++)
    {
        auto foundIt = _messageLifetimeByPeerId.find(it->first);
        if (foundIt != _messageLifetimeByPeerId.end())
        {
            if (foundIt->second == 0)
                pMap->erase(foundIt->second);
            else
                it->second = foundIt->second;
        }
        else
            unknownCids.push_back(it->first);
    }
    
    TG_SYNCHRONIZED_END(_messageLifetimeByPeerId);
    
    if (!unknownCids.empty())
    {
        for (auto it = unknownCids.begin(); it != unknownCids.end(); it++)
        {
            int messageLifetime = [self messageLifetimeForPeerId:*it];
            
            if (messageLifetime == 0)
                pMap->erase(*it);
            else
            {
                auto mapIt = pMap->find(*it);
                if (mapIt != pMap->end())
                    mapIt->second = messageLifetime;
            }
        }
    }
}

- (void)_scheduleSelfDestruct:(std::vector<std::pair<int, int> > *)pMidsWithLifetime referenceDate:(int)referenceDate
{
    NSString *selfDestructInsertQuery = [[NSString alloc] initWithFormat:@"INSERT OR IGNORE INTO %@ (mid, date) VALUES (?, ?)", _selfDestructTableName];
    
    [_database beginTransaction];
    for (auto it : *pMidsWithLifetime)
    {
        NSNumber *nDate = [[NSNumber alloc] initWithInt:referenceDate + it.second];
        [_database executeUpdate:selfDestructInsertQuery, [[NSNumber alloc] initWithInt:it.first], nDate];
    }
    [_database commit];
    
    [self processAndScheduleSelfDestruct];
}

- (void)processAndScheduleSelfDestruct
{
    [self dispatchOnDatabaseThread:^
    {
        if (_selfDestructTimer != nil)
        {
            [_selfDestructTimer invalidate];
            _selfDestructTimer = nil;
        }
        
        int currentDate = (int)(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970 + _timeDifferenceFromUTC);
        
        FMResultSet *result = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT mid FROM %@ WHERE date<=?", _selfDestructTableName], [[NSNumber alloc] initWithInt:currentDate]];
        
        NSMutableArray *deleteMids = [[NSMutableArray alloc] init];
        
        int midIndex = [result columnIndexForName:@"mid"];
        
        while ([result next])
        {
            int mid = [result intForColumnIndex:midIndex];
            
            [deleteMids addObject:[[NSNumber alloc] initWithInt:mid]];
        }
        
        if (deleteMids.count != 0)
        {
            NSMutableDictionary *messagesByConversation = [[NSMutableDictionary alloc] init];
            [self deleteMessages:deleteMids populateActionQueue:false fillMessagesByConversationId:messagesByConversation keepDate:true];
            
            [messagesByConversation enumerateKeysAndObjectsUsingBlock:^(NSNumber *nConversationId, NSArray *messagesInConversation, __unused BOOL *stop)
             {
                 [ActionStageInstance() dispatchResource:[[NSString alloc] initWithFormat:@"/tg/conversation/(%lld)/messagesDeleted", [nConversationId longLongValue]] resource:[[SGraphObjectNode alloc] initWithObject:messagesInConversation]];
             }];
        }
        
        FMResultSet *nextDateResult = [_database executeQuery:[[NSString alloc] initWithFormat:@"SELECT MIN(date) FROM %@", _selfDestructTableName]];
        if ([nextDateResult next])
        {
            int nextDate = [nextDateResult intForColumn:@"MIN(date)"];
            if (nextDate != 0)
            {
                NSTimeInterval delay = MAX(0, nextDate - currentDate + 0.25);
#if TARGET_IPHONE_SIMULATOR
                //TGLog(@"(autodeletion timeout: %f s)", delay);
#endif
                _selfDestructTimer = [[TGTimer alloc] initWithTimeout:delay repeat:false completion:^
                {
                    [self processAndScheduleSelfDestruct];
                } queue:[self databaseQueue]];
                [_selfDestructTimer start];
            }
        }
    } synchronous:false];
}

@end
