#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface RetroMediaClient : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (void)restoreWithBootstrapEmail:(NSString*)email password:(NSString*)password;
- (void)signInWithEmail:(NSString*)email password:(NSString*)password;
- (void)signOut;
- (void)loadArtwork:(NSString*)mediaType;
- (void)syncArtwork:(NSString*)mediaType gameNames:(NSString*)gameNames;

@end

NS_ASSUME_NONNULL_END
