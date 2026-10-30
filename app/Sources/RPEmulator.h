//
//  RetroPhone — RPEmulator.h
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
//  The emulator controller: owns one emulated S5L8900 machine, prepares its
//  writable root filesystem, boots Apple's kernel through the core bring-up,
//  runs it on a worker thread, and serves the guest's display, console and
//  input to the Swift UI. Written for RetroPhone; the emulation core it
//  drives is the vendored Engine (see Engine/UPSTREAM-LICENSE).
//
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface RPEmulator : NSObject

/* Configuration, fixed at creation. */
@property (nonatomic, copy, readonly) NSString *firmwareDirectory;
@property (nonatomic, copy, readonly) NSString *machineDirectory;
@property (nonatomic, readonly) BOOL softwareRender;

/* Live state, safe to read from the UI thread. */
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, copy, readonly) NSString *statusText;
@property (nonatomic, copy, readonly) NSString *detailText;
@property (nonatomic, readonly) uint64_t retiredInstructions;
@property (nonatomic, readonly) double provisionProgress; /* 0..1, -1 when idle */

/* Display diagnostics, refreshed by every frame poll. These exist so a
 * black screen is a measurement, not a mystery: they say whether the guest
 * ever enabled a scanout window, where it points, and whether its contents
 * ever change. */
@property (nonatomic, readonly) BOOL clcdRunning;
@property (nonatomic, readonly) uint32_t activeWindow;   /* CLCD_WIN_NONE = none */
@property (nonatomic, readonly) uint32_t framebufferAddress;
@property (nonatomic, readonly) uint32_t frameWidth;
@property (nonatomic, readonly) uint32_t frameHeight;
@property (nonatomic, readonly) uint64_t frameChanges;   /* polls whose pixels differed */
@property (nonatomic, readonly) double framesPerSecond;  /* changes in the last second */

- (instancetype)initWithFirmwareDirectory:(NSString *)firmwareDirectory
                         machineDirectory:(NSString *)machineDirectory
                           softwareRender:(BOOL)softwareRender
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/* Create the writable root filesystem in the machine directory if it is
 * missing or incomplete. Runs the caller onto a background queue itself is
 * NOT done here: call from a worker thread; progress lands in
 * provisionProgress. Returns NO with a detail message on failure. */
- (BOOL)provisionWithError:(NSString **)error;

/* Boot the machine and start the run thread. Call provision first. */
- (BOOL)startWithError:(NSString **)error;
- (void)stop;

/* The guest's current frame, decoded from its own scanout window, or nil
 * when the guest has not enabled one. Caller owns the returned image. */
- (nullable CGImageRef)copyFrameImage CF_RETURNS_RETAINED;

/* Guest serial console text produced since the last call. */
- (NSString *)drainConsole;

/* Single-touch input in guest panel points (320x480). phase is one of
 * "down", "move", "up". */
- (void)sendTouchPhase:(NSString *)phase x:(uint16_t)x y:(uint16_t)y;
- (void)setHomeButtonPressed:(BOOL)pressed;
- (void)setPowerButtonPressed:(BOOL)pressed;

@end

NS_ASSUME_NONNULL_END
