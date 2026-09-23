#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GStreamerWhipReceiver : NSObject

@property (nonatomic, strong, readonly) UIView *videoView;
@property (nonatomic, copy, readonly, nullable) NSString *whipURL;
@property (nonatomic, copy, nullable) void (^onStateChanged)(NSString *message);
@property (nonatomic, copy, nullable) void (^onFrameRendered)(void);
/// Called on the main queue with each decoded video frame (BGRA).
@property (nonatomic, copy, nullable) void (^onFrameImage)(CGImageRef image);

- (BOOL)startWithAdvertisedHost:(NSString *)advertisedHost
                           port:(NSInteger)port
                          error:(NSError **)error;
- (void)stop;

/// Main queue. Live preview UIImage (already oriented for UIKit).
- (void)setPreviewImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
