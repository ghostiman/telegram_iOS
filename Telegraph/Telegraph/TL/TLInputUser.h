/*
 * This is the source code of Telegram for iOS v. 1.1
 * It is licensed under GNU GPL v. 2 or later.
 * You should have received a copy of the license in this archive (see LICENSE).
 *
 * Copyright Peter Iakovlev, 2013.
 */

#import <Foundation/Foundation.h>

#import "TLObject.h"
#import "TLMetaRpc.h"


@interface TLInputUser : NSObject <TLObject>


@end

@interface TLInputUser$inputUserEmpty : TLInputUser


@end

@interface TLInputUser$inputUserSelf : TLInputUser


@end

@interface TLInputUser$inputUserContact : TLInputUser

@property (nonatomic) int32_t user_id;

@end

@interface TLInputUser$inputUserForeign : TLInputUser

@property (nonatomic) int32_t user_id;
@property (nonatomic) int64_t access_hash;

@end

