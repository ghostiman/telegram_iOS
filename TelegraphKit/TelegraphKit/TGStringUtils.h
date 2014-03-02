/*
 * This is the source code of Telegram for iOS v. 1.1
 * It is licensed under GNU GPL v. 2 or later.
 * You should have received a copy of the license in this archive (see LICENSE).
 *
 * Copyright Peter Iakovlev, 2013.
 */

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
    
int32_t murMurHash32(NSString *string);
    
int32_t phoneMatchHash(NSString *phone);
    
#ifdef __cplusplus
}
#endif

@interface TGStringUtils : NSObject

+ (NSString *)stringByEscapingForURL:(NSString *)string;
+ (NSString *)stringByEncodingInBase64:(NSData *)data;
+ (NSString *)stringByUnescapingFromHTML:(NSString *)srcString;

+ (NSString *)md5:(NSString *)string;

+ (NSString *)formatPhone:(NSString *)phone forceInternational:(bool)forceInternational;
+ (NSString *)formatPhoneUrl:(NSString *)phone;

+ (NSString *)cleanPhone:(NSString *)phone;

+ (NSDictionary *)argumentDictionaryInUrlString:(NSString *)string;

+ (bool)stringContainsEmoji:(NSString *)string;

@end

@interface NSString (Telegraph)

- (int)lengthByComposedCharacterSequences;
- (int)lengthByComposedCharacterSequencesInRange:(NSRange)range;

- (NSData *)dataByDecodingHexString;

@end

@interface NSData (Telegraph)

- (NSString *)stringByEncodingInHex;

@end