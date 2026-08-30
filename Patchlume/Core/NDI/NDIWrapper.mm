#import "NDIWrapper.h"
#import <string.h>
#import <TargetConditionals.h>

// The vendored `libndi_ios.a` only ships a device-tagged arm64 slice (no
// arm64-simulator slice) — see ThirdParty/README.md. Rather than exclude
// arm64 from Simulator builds project-wide (which broke ALL Simulator runs
// on any arm64-only runtime, e.g. iOS 26.5, not just NDI), NDI is compiled
// out entirely for Simulator: everything below becomes harmless stubs, and
// the real implementation (needing `Processing.NDI.Lib.h` and the actual
// library) only compiles for device. NDI needs a real network and a real
// camera/receiver on the other end anyway, so it was never meaningfully
// testable in Simulator to begin with.
#if !TARGET_OS_SIMULATOR

#import <Processing.NDI.Lib.h>

@implementation NDISender {
    NDIlib_send_instance_t _sender;
}

- (BOOL)startWithName:(NSString *)name {
    if (_sender) { return YES; }
    if (!NDIlib_initialize()) { return NO; }

    NDIlib_send_create_t desc;
    desc.p_ndi_name = name.UTF8String;
    desc.p_groups = NULL;
    // We already pace frames ourselves (a fixed-rate timer upstream), so
    // NDI shouldn't also rate-limit/block send calls against a declared
    // frame rate — false lets every appendFrame go out immediately.
    desc.clock_video = false;
    desc.clock_audio = false;

    _sender = NDIlib_send_create(&desc);
    return _sender != NULL;
}

- (void)sendFrameWithPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!_sender) { return; }

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    void *base = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t stride = CVPixelBufferGetBytesPerRow(pixelBuffer);

    NDIlib_video_frame_v2_t frame;
    frame.xres = (int)width;
    frame.yres = (int)height;
    frame.FourCC = NDIlib_FourCC_video_type_BGRA;
    frame.frame_rate_N = 30000;
    frame.frame_rate_D = 1000;
    frame.picture_aspect_ratio = (float)width / (float)height;
    frame.frame_format_type = NDIlib_frame_format_type_progressive;
    frame.timecode = NDIlib_send_timecode_synthesize;
    frame.p_data = (uint8_t *)base;
    frame.line_stride_in_bytes = (int)stride;
    frame.p_metadata = NULL;
    frame.timestamp = 0;

    // Synchronous: copies the frame into NDI's own send queue before
    // returning, so it's safe to unlock the pixel buffer right after.
    NDIlib_send_send_video_v2(_sender, &frame);

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
}

- (void)stop {
    if (_sender) {
        NDIlib_send_destroy(_sender);
        _sender = NULL;
    }
}

- (void)dealloc {
    [self stop];
}

@end

@implementation NDIReceiver {
    NDIlib_find_instance_t _finder;
    NDIlib_recv_instance_t _receiver;
    NDIlib_video_frame_v2_t _pendingFrame;
    BOOL _hasPending;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NDIlib_initialize();
    }
    return self;
}

- (NSArray<NSString *> *)discoverSourceNames {
    if (!_finder) {
        NDIlib_find_create_t desc;
        desc.show_local_sources = true;
        desc.p_groups = NULL;
        desc.p_extra_ips = NULL;
        _finder = NDIlib_find_create_v2(&desc);
        if (!_finder) { return @[]; }
    }
    NDIlib_find_wait_for_sources(_finder, 200);
    uint32_t count = 0;
    const NDIlib_source_t *sources = NDIlib_find_get_current_sources(_finder, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        if (sources[i].p_ndi_name) {
            [names addObject:[NSString stringWithUTF8String:sources[i].p_ndi_name]];
        }
    }
    return names;
}

- (BOOL)connectToSourceNamed:(NSString *)name {
    if (!_finder) { [self discoverSourceNames]; }
    uint32_t count = 0;
    const NDIlib_source_t *sources = NDIlib_find_get_current_sources(_finder, &count);
    const NDIlib_source_t *match = NULL;
    const char *utf8Name = name.UTF8String;
    for (uint32_t i = 0; i < count; i++) {
        if (sources[i].p_ndi_name && utf8Name && strcmp(sources[i].p_ndi_name, utf8Name) == 0) {
            match = &sources[i];
            break;
        }
    }
    if (!match) { return NO; }

    if (_receiver) {
        NDIlib_recv_destroy(_receiver);
        _receiver = NULL;
    }

    NDIlib_recv_create_v3_t desc;
    desc.source_to_connect_to = *match;
    desc.color_format = NDIlib_recv_color_format_BGRX_BGRA;
    desc.bandwidth = NDIlib_recv_bandwidth_highest;
    desc.allow_video_fields = false;
    desc.p_ndi_recv_name = "Patchlume";

    _receiver = NDIlib_recv_create_v3(&desc);
    return _receiver != NULL;
}

- (BOOL)captureNextFrameTimeoutMs:(int)timeoutMs {
    if (!_receiver) { return NO; }
    if (_hasPending) {
        NDIlib_recv_free_video_v2(_receiver, &_pendingFrame);
        _hasPending = NO;
    }

    NDIlib_video_frame_v2_t frame;
    NDIlib_frame_type_e type = NDIlib_recv_capture_v3(_receiver, &frame, NULL, NULL, (uint32_t)timeoutMs);
    if (type != NDIlib_frame_type_video) { return NO; }

    _pendingFrame = frame;
    _hasPending = YES;
    return YES;
}

- (CGSize)pendingFrameSize {
    if (!_hasPending) { return CGSizeZero; }
    return CGSizeMake(_pendingFrame.xres, _pendingFrame.yres);
}

- (void)copyPendingFrameInto:(CVPixelBufferRef)pixelBuffer {
    if (!_hasPending) { return; }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t dstStride = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t dstHeight = CVPixelBufferGetHeight(pixelBuffer);
    uint8_t *dst = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
    if (dst) {
        size_t rows = MIN((size_t)_pendingFrame.yres, dstHeight);
        size_t rowBytes = MIN((size_t)_pendingFrame.line_stride_in_bytes, dstStride);
        for (size_t y = 0; y < rows; y++) {
            memcpy(dst + y * dstStride, _pendingFrame.p_data + y * _pendingFrame.line_stride_in_bytes, rowBytes);
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    NDIlib_recv_free_video_v2(_receiver, &_pendingFrame);
    _hasPending = NO;
}

- (void)disconnect {
    if (_hasPending && _receiver) {
        NDIlib_recv_free_video_v2(_receiver, &_pendingFrame);
        _hasPending = NO;
    }
    if (_receiver) {
        NDIlib_recv_destroy(_receiver);
        _receiver = NULL;
    }
    if (_finder) {
        NDIlib_find_destroy(_finder);
        _finder = NULL;
    }
}

- (void)dealloc {
    [self disconnect];
}

@end

#else // TARGET_OS_SIMULATOR — stubs, NDI is device-only (see comment above)

@implementation NDISender
- (BOOL)startWithName:(NSString *)name { return NO; }
- (void)sendFrameWithPixelBuffer:(CVPixelBufferRef)pixelBuffer {}
- (void)stop {}
@end

@implementation NDIReceiver
- (NSArray<NSString *> *)discoverSourceNames { return @[]; }
- (BOOL)connectToSourceNamed:(NSString *)name { return NO; }
- (BOOL)captureNextFrameTimeoutMs:(int)timeoutMs { return NO; }
- (CGSize)pendingFrameSize { return CGSizeZero; }
- (void)copyPendingFrameInto:(CVPixelBufferRef)pixelBuffer {}
- (void)disconnect {}
@end

#endif
