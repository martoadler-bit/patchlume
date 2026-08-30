#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C++ wrapper around the NDI SDK's C API (declared in
/// ThirdParty/NDI/include/Processing.NDI.Lib.h) — Swift can't import that
/// header directly (C++ default-argument constructors, unions, etc.), so
/// this is the one bridge point. Deliberately minimal: video-only, one
/// sender at a time, synchronous send (NDIlib_send_send_video_v2 copies
/// the frame internally, so it's safe to unlock/reuse the pixel buffer
/// the moment the call returns).
@interface NDISender : NSObject

/// Creates the NDI source and starts advertising it on the local network.
/// `name` becomes the source name other NDI apps (OBS, Resolume, NDI
/// Monitor...) see on the network, formatted as "<device name> (name)".
- (BOOL)startWithName:(NSString *)name;

/// Sends one BGRA frame. Safe to call from any thread; safe to call after
/// `stop` (silently does nothing).
- (void)sendFrameWithPixelBuffer:(CVPixelBufferRef)pixelBuffer;

/// Stops advertising and tears down the NDI source.
- (void)stop;

@end

/// The receive-side counterpart to `NDISender` — picks up another
/// device's NDI broadcast (a second phone running the free "NDI Camera"
/// app, another Patchlume, OBS, Resolume...) as raw BGRA frames. NDI's
/// receive API is a blocking poll, not a delegate callback, so this is
/// driven by the caller repeatedly calling `captureNextFrame` on its own
/// background loop rather than pushing frames on its own thread.
@interface NDIReceiver : NSObject

/// Scans the local network (blocks briefly) and returns the NDI source
/// names currently visible — call again to refresh, e.g. right before
/// showing a picker.
- (NSArray<NSString *> *)discoverSourceNames;

/// Connects to a source by the exact name `discoverSourceNames` returned.
- (BOOL)connectToSourceNamed:(NSString *)name;

/// Blocks up to `timeoutMs` waiting for the next video frame. Returns YES
/// if one is now pending (read its size via `pendingFrameSize` and copy it
/// out via `copyPendingFrameInto:` before calling this again — a second
/// call without copying discards the previous pending frame).
- (BOOL)captureNextFrameTimeoutMs:(int)timeoutMs;

/// The pending frame's pixel dimensions, or `CGSizeZero` if none is
/// pending. Frame size can change between calls if the sender changes its
/// own resolution.
- (CGSize)pendingFrameSize;

/// Copies the pending frame (as BGRA) into `pixelBuffer`, which must
/// already be sized to `pendingFrameSize`, then frees NDI's own copy.
/// Does nothing if there's no pending frame.
- (void)copyPendingFrameInto:(CVPixelBufferRef)pixelBuffer;

/// Tears down the receiver and source finder.
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
