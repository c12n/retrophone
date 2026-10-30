//
//  RetroPhone — RPImport.m
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
#import "RPImport.h"

#include <stdio.h>
#include <string.h>

#include "VMFirmwareImport.h"
#include "VMFirmwareKeys.h"
#include "VMFirmwarePolicy.h"

/* ------------------------------------------------------------- IPSW source */

typedef struct {
    FILE *f;
    uint64_t size;
} rp_src_t;

static size_t rp_src_pread(void *ctx, uint64_t off, uint8_t *buf, size_t len) {
    rp_src_t *s = (rp_src_t *)ctx;
    if (off >= s->size) return 0;
    if (len > s->size - off) len = (size_t)(s->size - off);
    if (fseeko(s->f, (off_t)off, SEEK_SET) != 0) return 0;
    return fread(buf, 1, len, s->f);
}

/* -------------------------------------------------------------- file sink */

typedef struct {
    char dir[1024];
} rp_out_t;

static bool rp_safe_name(const char *n) {
    if (!n || !*n || *n == '.') return false;
    for (const char *p = n; *p; p++)
        if (*p == '/' || *p == '\\' || *p == ':') return false;
    return true;
}

static void *rp_out_open(void *ctx, const char *name) {
    rp_out_t *o = (rp_out_t *)ctx;
    char path[1200];
    if (!rp_safe_name(name)) return NULL;
    snprintf(path, sizeof path, "%s/%s", o->dir, name);
    return fopen(path, "w+b"); /* the DMG scratch file is read back */
}

static bool rp_out_write(void *ctx, void *h, const uint8_t *d, size_t n) {
    (void)ctx;
    return h && fwrite(d, 1, n, (FILE *)h) == n;
}

static size_t rp_out_pread(void *ctx, void *h, uint64_t off, uint8_t *b,
                           size_t n) {
    (void)ctx;
    if (!h) return 0;
    if (fflush((FILE *)h) != 0) return 0;
    if (fseeko((FILE *)h, (off_t)off, SEEK_SET) != 0) return 0;
    size_t got = fread(b, 1, n, (FILE *)h);
    (void)fseek((FILE *)h, 0, SEEK_END);
    return got;
}

static void rp_out_close(void *ctx, void *h, bool keep) {
    (void)ctx;
    (void)keep;
    if (h) fclose((FILE *)h);
}

/* ------------------------------------------------------------------ import */

@implementation RPImportResult
@end

@implementation RPImport

+ (RPImportResult *)importIPSWAtPath:(NSString *)ipswPath
                       intoDirectory:(NSString *)outDirectory
                               error:(NSString **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:outDirectory
        withIntermediateDirectories:YES attributes:nil error:nil];

    const char *ipsw = ipswPath.fileSystemRepresentation;
    FILE *f = fopen(ipsw, "rb");
    if (!f) {
        if (error) *error = @"Cannot open the IPSW file.";
        return nil;
    }
    if (fseeko(f, 0, SEEK_END) != 0) {
        fclose(f);
        if (error) *error = @"Cannot read the IPSW file.";
        return nil;
    }
    off_t end = ftello(f);
    (void)fseeko(f, 0, SEEK_SET);
    if (end <= 0) {
        fclose(f);
        if (error) *error = @"The IPSW file is empty.";
        return nil;
    }

    rp_src_t src = { f, (uint64_t)end };
    rp_out_t out;
    memset(&out, 0, sizeof out);
    snprintf(out.dir, sizeof out.dir, "%s",
             outDirectory.fileSystemRepresentation);

    vm_fw_files_t files;
    memset(&files, 0, sizeof files);
    files.open = rp_out_open;
    files.write = rp_out_write;
    files.pread = rp_out_pread;
    files.close = rp_out_close;
    files.ctx = &out;

    vm_fw_import_t in;
    memset(&in, 0, sizeof in);
    in.pread = rp_src_pread;
    in.pread_ctx = &src;
    in.size = src.size;
    in.files = &files;
    in.keys = NULL;
    in.resolve_keys = vm_fw_resolve_public_keys;
    in.require_supported = true;

    vm_fw_report_t rep;
    memset(&rep, 0, sizeof rep);
    vm_fw_status_t st = vm_fw_import_run(&in, &rep);
    fclose(f);

    if (st != VM_FW_OK || !vm_fw_report_is_verified(&rep)) {
        if (error) {
            NSString *detail = rep.detail[0]
                ? [NSString stringWithUTF8String:rep.detail] : @"";
            *error = [NSString stringWithFormat:
                @"This IPSW could not be imported as a supported, verified "
                @"build. %@", detail];
        }
        return nil;
    }

    /* Record the import policy the boot path reads: the produced sizes are
     * authoritative for this firmware set. Checksums were verified against
     * the reference digests during the run, so nothing is skipped. */
    vm_fw_policy_t policy;
    memset(&policy, 0, sizeof policy);
    policy.skip_stock_checksums = false;
    for (unsigned i = 0; i < 3; i++)
        policy.sizes[i] = rep.artefacts[i].produced;
    if (!vm_fw_policy_write(out.dir, &policy)) {
        if (error) *error = @"The import finished but its policy could not be recorded.";
        return nil;
    }

    RPImportResult *result = [[RPImportResult alloc] init];
    result.productVersion = [NSString stringWithUTF8String:rep.product_version];
    result.build = [NSString stringWithUTF8String:rep.build];
    result.verified = YES;
    return result;
}

@end
