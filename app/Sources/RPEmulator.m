//
//  RetroPhone — RPEmulator.m
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
#import "RPEmulator.h"

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "soc.h"
#include "bringup.h"
#include "ios3_bringup_gate.h"
#include "ios4_bringup_gate.h"
#include "ios3_kernel_patch.h"
#include "ios4_kernel_patch.h"
#include "rootfs_work.h"
#include "file_block.h"
#include "VMFirmwarePolicy.h"
#include "ios4_sb_ca_plist.h"
#include "ios4_datamigrator_plist.h"

#define RP_DISK_BYTES (UINT64_C(8) * 1024u * 1024u * 1024u)
#define RP_GROWTH_BYTES (32u * 1024u * 1024u)
#define RP_IOS4_ROOTFS_SIZE UINT64_C(681500672)
#define RP_CHUNK_INSTRUCTIONS 100000u

static uint64_t rp_file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) return 0;
    return (uint64_t)st.st_size;
}

static uint8_t *rp_slurp(const char *path, size_t *out_size) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long n = ftell(f);
    if (n <= 0 || fseek(f, 0, SEEK_SET) != 0) { fclose(f); return NULL; }
    uint8_t *buf = (uint8_t *)malloc((size_t)n);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *out_size = (size_t)n;
    return buf;
}

static void *rp_run_thread(void *ctx);

static uint64_t rp_fnv1a(const uint8_t *data, size_t n) {
    uint64_t h = UINT64_C(1469598103934665603);
    for (size_t i = 0; i < n; i++) {
        h ^= data[i];
        h *= UINT64_C(1099511628211);
    }
    return h;
}

@interface RPEmulator () {
    s5l8900_t *_machine;
    s5l_bringup_md_t *_bridges;
    file_block_t *_media;
    pthread_t _thread;
    BOOL _threadRunning;
    volatile BOOL _stopRequested;
    volatile BOOL _machineChanging;
    uint64_t _retired;
    arm_status_t _lastStatus;
    uint32_t _lastPC;

    uint8_t *_rgb;
    size_t _rgbCapacity;
    uint64_t _lastFrameHash;
    uint64_t _frameChanges;
    uint64_t _changeWindowStart;
    unsigned _changesInWindow;
    double _fps;
    uint32_t _activeWindow;
    uint32_t _fbAddress;
    uint32_t _fbWidth;
    uint32_t _fbHeight;
    BOOL _clcdRunning;

    double _provisionProgress;
    NSString *_statusText;
    NSString *_detailText;
}
@end

@implementation RPEmulator

- (instancetype)initWithFirmwareDirectory:(NSString *)firmwareDirectory
                         machineDirectory:(NSString *)machineDirectory
                           softwareRender:(BOOL)softwareRender {
    self = [super init];
    if (!self) return nil;
    _firmwareDirectory = [firmwareDirectory copy];
    _machineDirectory = [machineDirectory copy];
    _softwareRender = softwareRender;
    _statusText = @"Stopped";
    _detailText = @"";
    _provisionProgress = -1;
    _activeWindow = UINT32_MAX;
    return self;
}

- (void)dealloc {
    [self stop];
    free(_rgb);
}

- (BOOL)running { return _threadRunning; }
- (NSString *)statusText { return _statusText; }
- (NSString *)detailText { return _detailText; }
- (uint64_t)retiredInstructions { return _retired; }
- (double)provisionProgress { return _provisionProgress; }
- (BOOL)clcdRunning { return _clcdRunning; }
- (uint32_t)activeWindow { return _activeWindow; }
- (uint32_t)framebufferAddress { return _fbAddress; }
- (uint32_t)frameWidth { return _fbWidth; }
- (uint32_t)frameHeight { return _fbHeight; }
- (uint64_t)frameChanges { return _frameChanges; }
- (double)framesPerSecond { return _fps; }

- (void)setStatus:(NSString *)status detail:(NSString *)detail {
    _statusText = status ?: @"";
    _detailText = detail ?: @"";
}

/* ------------------------------------------------------------ provision */

static void rp_progress(void *ctx, uint64_t done, uint64_t total) {
    RPEmulator *self = (__bridge RPEmulator *)ctx;
    if (total > 0) self->_provisionProgress = (double)done / (double)total;
}

- (BOOL)provisionWithError:(NSString **)error {
    char source_path[1200], work_path[1200];
    snprintf(source_path, sizeof source_path, "%s/rootfs.img",
             _firmwareDirectory.fileSystemRepresentation);
    snprintf(work_path, sizeof work_path, "%s/rootfs-work.img",
             _machineDirectory.fileSystemRepresentation);

    uint64_t source_size = rp_file_size(source_path);
    if (source_size == 0) {
        if (error) *error = @"The imported root filesystem is missing.";
        return NO;
    }
    uint64_t existing = rp_file_size(work_path);
    if (existing >= source_size && existing > 0) return YES; /* already made */
    if (existing > 0) (void)remove(work_path);              /* incomplete   */

    rootfs_work_options_t options;
    rootfs_work_result_t result;
    memset(&options, 0, sizeof options);
    memset(&result, 0, sizeof result);
    options.fstab_line = ROOTFS_WORK_DEFAULT_FSTAB;
    options.growth_bytes = RP_GROWTH_BYTES;
    options.minimum_volume_bytes = RP_DISK_BYTES;
    options.progress = rp_progress;
    options.progress_ctx = (__bridge void *)self;
    _provisionProgress = 0;

    static const rootfs_work_file_rewrite_t sb_ca_rewrite = {
        IOS4_SB_PLIST_PATH,
        IOS4_SB_PLIST_STOCK, sizeof IOS4_SB_PLIST_STOCK,
        IOS4_SB_PLIST_SOFTWARE_RENDER, sizeof IOS4_SB_PLIST_SOFTWARE_RENDER,
        0u, 0u, 0644,
    };
    static const rootfs_work_file_rewrite_t dm_rewrite = {
        IOS4_DATAMIGRATOR_PLIST_PATH,
        IOS4_DATAMIGRATOR_PLIST_STOCK, sizeof IOS4_DATAMIGRATOR_PLIST_STOCK,
        IOS4_DATAMIGRATOR_PLIST_DISABLED, sizeof IOS4_DATAMIGRATOR_PLIST_DISABLED,
        0u, 0u, 0644,
    };
    static rootfs_work_file_rewrite_t ios4_rewrites[2];

    if (source_size == RP_IOS4_ROOTFS_SIZE) {
        /* iOS 4.2.1: no system keybag exists in a stock IPSW image and the
         * data migrator can never finish on a from-IPSW image, so both jobs
         * are disabled in the image; the QuartzCore renderer choice rides
         * the SpringBoard binary-plist rewrite instead of the 3.1.3 stage. */
        size_t n = 0;
        options.keybag_job_disable = true;
        options.ca_software_render = false;
        if (_softwareRender) ios4_rewrites[n++] = sb_ca_rewrite;
        ios4_rewrites[n++] = dm_rewrite;
        options.file_rewrites = ios4_rewrites;
        options.file_rewrite_count = n;
    } else {
        options.ca_software_render = _softwareRender;
    }

    /* Offline activation (data_ark.plist, FactoryActivated). No PPP in v1,
     * so the standard entry table is the activation entries only. */
    rootfs_work_entry_t entries[16];
    size_t count = rootfs_work_standard_entries(true, false, entries, 16);
    if (count > 16) {
        if (error) *error = @"The standard provisioning table no longer fits.";
        _provisionProgress = -1;
        return NO;
    }
    options.entries = count ? entries : NULL;
    options.entry_count = count;

    rootfs_work_status_t status =
        rootfs_work_create(source_path, work_path, &options, &result);
    _provisionProgress = -1;
    if (status != ROOTFS_WORK_OK) {
        if (error)
            *error = [NSString stringWithFormat:
                @"Could not prepare the root filesystem (%s at %s): %s",
                rootfs_work_status_name(status),
                rootfs_work_stage_name(result.stage), result.detail];
        return NO;
    }
    return YES;
}

/* ----------------------------------------------------------------- boot */

- (BOOL)startWithError:(NSString **)error {
    if (_threadRunning) return YES;
    if (![self bootMachineWithError:error]) return NO;
    _stopRequested = NO;
    _threadRunning = YES;
    pthread_create(&_thread, NULL, rp_run_thread, (__bridge void *)self);
    return YES;
}

- (void)teardownMachine {
    if (_media) {
        (void)file_block_close(_media);
        (void)file_block_destroy(&_media);
        _media = NULL;
    }
    if (_machine) {
        s5l8900_free(_machine);
        free(_machine);
        _machine = NULL;
    }
    free(_bridges);
    _bridges = NULL;
}

/* One full boot of the configured firmware into a fresh machine object.
 * Used by the first start and by the run thread's restart path: a guest
 * that asks the board for a cold restart (PMU/watchdog) gets exactly
 * that — a new machine on the same work image. */
- (BOOL)bootMachineWithError:(NSString **)error {
    char kernel_path[1200], tree_path[1200], work_path[1200];
    const char *fw = _firmwareDirectory.fileSystemRepresentation;
    const char *md = _machineDirectory.fileSystemRepresentation;
    snprintf(kernel_path, sizeof kernel_path, "%s/kernel.macho", fw);
    snprintf(tree_path, sizeof tree_path, "%s/devicetree.bin", fw);
    snprintf(work_path, sizeof work_path, "%s/rootfs-work.img", md);

    uint64_t work_size = rp_file_size(work_path);
    if (work_size == 0) {
        if (error) *error = @"The machine's disk has not been prepared yet.";
        return NO;
    }
    size_t kernel_size = 0, tree_size = 0;
    uint8_t *kernel = rp_slurp(kernel_path, &kernel_size);
    uint8_t *tree = kernel ? rp_slurp(tree_path, &tree_size) : NULL;
    if (!kernel || !tree) {
        free(kernel);
        free(tree);
        if (error)
            *error = kernel ? @"Cannot read devicetree.bin."
                            : @"Cannot read kernel.macho.";
        return NO;
    }
    const BOOL is421 = (uint64_t)kernel_size == IOS4_KERNEL_PATCH_FILE_SIZE;
    const BOOL is313 = (uint64_t)kernel_size == IOS3_KERNEL_PATCH_FILE_SIZE;
    if (!is421 && !is313) {
        free(kernel);
        free(tree);
        if (error)
            *error = [NSString stringWithFormat:
                @"This kernel (%zu bytes) is not a build RetroPhone supports.",
                kernel_size];
        return NO;
    }

    _machine = (s5l8900_t *)calloc(1, sizeof(s5l8900_t));
    _bridges = (s5l_bringup_md_t *)calloc(1, sizeof(s5l_bringup_md_t));
    _media = file_block_create();
    if (!_machine || !_bridges || !_media ||
        !s5l8900_init(_machine, S5L_BRINGUP_PHYS_BASE, S5L_BRINGUP_RAM_SIZE)) {
        if (error) *error = @"Not enough memory to build the machine.";
        [self teardownMachine];
        free(kernel);
        free(tree);
        return NO;
    }
    if (file_block_open(_media, work_path, work_size) != FILE_BLOCK_STATUS_OK) {
        if (error) *error = @"Cannot open the root filesystem work image.";
        [self teardownMachine];
        free(kernel);
        free(tree);
        return NO;
    }

    vm_fw_policy_t policy;
    BOOL skip_checksums =
        vm_fw_policy_read(fw, &policy) == 1 && policy.skip_stock_checksums;

    s5l_bringup_request_t request;
    memset(&request, 0, sizeof request);
    request.kernel = kernel;
    request.kernel_size = kernel_size;
    request.devicetree = tree;
    request.devicetree_size = tree_size;
    request.root_media = file_block_get(_media);
    if (is421) {
        request.virt_base = IOS4_KERNEL_PATCH_VIRT_BASE;
        ios4_bringup_gate_configure_with_policy(&request, NULL, skip_checksums);
    } else {
        ios3_bringup_gate_configure_with_policy(&request, NULL, skip_checksums);
    }
    static const char *const hide_software[] = {
        "arm-io/mbx", "arm-io/sha1", "baseband", "arm-io/spi2",
    };
    static const char *const hide_mbx[] = {
        "arm-io/sha1", "baseband", "arm-io/spi2",
    };
    if (_softwareRender) {
        request.unmatch = hide_software;
        request.unmatch_count = 4;
    } else {
        request.unmatch = hide_mbx;
        request.unmatch_count = 3;
    }

    s5l_bringup_result_t result;
    s5l_bringup_status_t status =
        s5l_bringup(_machine, &request, _bridges, &result);
    free(kernel);
    free(tree);
    if (status != S5L_BRINGUP_OK) {
        if (error)
            *error = [NSString stringWithFormat:
                @"Could not start Apple's kernel (%s at %s): %s",
                s5l_bringup_status_name(status),
                s5l_bringup_stage_name(result.stage), result.detail];
        [self teardownMachine];
        return NO;
    }
    [self setStatus:@"Running"
             detail:is421 ? @"iOS 4.2.1 kernel, root on /dev/md0"
                          : @"iPhone OS 3.1.3 kernel, root on /dev/md0"];
    return YES;
}

static void *rp_run_thread(void *ctx) {
    RPEmulator *self = (__bridge RPEmulator *)ctx;
    arm_status_t status = ARM_OK;
    unsigned restarts = 0;
    while (!self->_stopRequested) {
        unsigned retired =
            s5l8900_run(self->_machine, RP_CHUNK_INSTRUCTIONS, &status);
        self->_retired += retired;
        self->_lastStatus = status;
        self->_lastPC = self->_machine->cpu.r[15];
        if (status == ARM_OK || self->_stopRequested) continue;
        if (status == ARM_RESTART && restarts < 8) {
            /* The board asked for a cold restart: rebuild the machine on
             * the same work image and keep going. */
            restarts++;
            self->_machineChanging = YES;
            [self teardownMachine];
            NSString *error = nil;
            BOOL rebooted = [self bootMachineWithError:&error];
            self->_machineChanging = NO;
            if (rebooted) {
                status = ARM_OK;
                continue;
            }
            [self setStatus:@"Stopped"
                     detail:error ?: @"The guest restart failed."];
            break;
        }
        break;
    }
    self->_threadRunning = NO;
    if (!self->_stopRequested && status != ARM_OK) {
        NSString *detail = [NSString stringWithFormat:
            @"Guest stopped (status %d) at pc 0x%08x after %llu instructions.",
            (int)self->_lastStatus, self->_lastPC,
            (unsigned long long)self->_retired];
        [self setStatus:@"Stopped" detail:detail];
    }
    return NULL;
}

- (void)stop {
    if (_threadRunning) {
        _stopRequested = YES;
        pthread_join(_thread, NULL);
    }
    [self teardownMachine];
    [self setStatus:@"Stopped" detail:@""];
}

/* --------------------------------------------------------------- display */

- (CGImageRef)copyFrameImage {
    if (!_machine || _machineChanging) return NULL;
    const s5l_clcd_t *clcd = &_machine->clcd;
    _clcdRunning = s5l_clcd_running(clcd);
    uint32_t active = s5l_clcd_active_window(clcd);
    _activeWindow = active;
    if (active == CLCD_WIN_NONE) return NULL;

    uint32_t fb = 0, w = 0, h = 0, stride = 0, format = 0, order = 0;
    if (!s5l_clcd_window(clcd, active, &fb, &w, &h, &stride, &format, &order))
        return NULL;
    _fbAddress = fb;
    _fbWidth = w;
    _fbHeight = h;
    if (w == 0 || h == 0 || w > 2048 || h > 2048) return NULL;

    size_t need = (size_t)w * h * 3;
    if (need > _rgbCapacity) {
        free(_rgb);
        _rgb = (uint8_t *)malloc(need);
        _rgbCapacity = _rgb ? need : 0;
        if (!_rgb) return NULL;
    }
    uint32_t out_w = 0, out_h = 0;
    if (!s5l_clcd_scanout(clcd, active, _machine->ram, _machine->ram_base,
                          _machine->ram_size, _rgb, _rgbCapacity,
                          &out_w, &out_h))
        return NULL;

    /* Frame-change accounting: this is the number that separates "guest
     * never draws" from "guest draws, we drop it". */
    uint64_t hash = rp_fnv1a(_rgb, (size_t)out_w * out_h * 3);
    uint64_t now = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
    if (_changeWindowStart == 0) _changeWindowStart = now;
    if (hash != _lastFrameHash) {
        _lastFrameHash = hash;
        _frameChanges++;
        _changesInWindow++;
    }
    if (now - _changeWindowStart >= 1000) {
        _fps = (double)_changesInWindow * 1000.0 /
               (double)(now - _changeWindowStart);
        _changesInWindow = 0;
        _changeWindowStart = now;
    }

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        _rgb, out_w, out_h, 8, (size_t)out_w * 3, space,
        kCGBitmapByteOrderDefault | kCGImageAlphaNone);
    CGColorSpaceRelease(space);
    if (!ctx) return NULL;
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return image;
}

/* --------------------------------------------------------------- console */

- (NSString *)drainConsole {
    if (!_machine || _machineChanging || _machine->uart0.tx_len == 0)
        return @"";
    NSString *text = [[NSString alloc] initWithBytes:_machine->uart0.tx
                                              length:_machine->uart0.tx_len
                                            encoding:NSUTF8StringEncoding];
    _machine->uart0.tx_len = 0;
    return text ?: @"";
}

/* ----------------------------------------------------------------- input */

- (void)sendTouchPhase:(NSString *)phase x:(uint16_t)x y:(uint16_t)y {
    if (!_machine || _machineChanging) return;
    s5l_mt_contact_t contact;
    memset(&contact, 0, sizeof contact);
    contact.id = 1;
    contact.x = x;
    contact.y = y;
    contact.major = 8;
    contact.minor = 8;
    if ([phase isEqualToString:@"down"]) {
        contact.phase = MTZ2_PHASE_MAKE_TOUCH;
        contact.pressure = 200;
    } else if ([phase isEqualToString:@"move"]) {
        contact.phase = MTZ2_PHASE_TOUCHING;
        contact.pressure = 200;
    } else {
        contact.phase = MTZ2_PHASE_BREAK_TOUCH;
        contact.pressure = 0;
    }
    (void)s5l8900_set_contacts(_machine, &contact, 1);
}

- (void)setHomeButtonPressed:(BOOL)pressed {
    if (_machine) (void)s5l8900_set_button(_machine, S5L_BUTTON_MENU, pressed);
}

- (void)setPowerButtonPressed:(BOOL)pressed {
    if (_machine) (void)s5l8900_set_button(_machine, S5L_BUTTON_HOLD, pressed);
}

@end
