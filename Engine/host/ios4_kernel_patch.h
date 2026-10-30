/*
 * S5LBox -- fail-closed iOS 4.2.1 (8C148) kernel compatibility gate.
 *
 * The compatibility patches in this interface are valid for one exact
 * decrypted kernel build. They are deliberately host policy rather than a
 * generic ARM-core feature: a different kernel fails before any guest byte is
 * changed.
 *
 * This is the iOS 4 twin of ios3_kernel_patch.h, derived by auditing the
 * xnu-1504.58.28 (iPhone1,2 8C148) kernel against the 7E18 sites: the
 * memory-device compilation unit, IOKitInitializeTime and IOFindBSDRoot are
 * instruction-for-instruction identical to their xnu-1506 counterparts, so
 * every site carries the same expected/replacement bytes at its 8C148
 * address. The packet (PPP/NAT) sites have no 8C148 entry here: that
 * offload is not part of the disk-bridge manifest for this build.
 *
 * Copyright (c) 2026 j0shua-SYSON. MIT licensed.
 */
#ifndef S5LBOX_IOS4_KERNEL_PATCH_H
#define S5LBOX_IOS4_KERNEL_PATCH_H

#include "guest_patch.h"
#include "macho.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define IOS4_KERNEL_PATCH_FILE_SIZE UINT64_C(8343552)
#define IOS4_KERNEL_PATCH_SHA256_LENGTH UINT32_C(32)
#define IOS4_KERNEL_PATCH_UUID_LENGTH UINT32_C(16)

#define IOS4_KERNEL_PATCH_VIRT_BASE UINT32_C(0x80000000)
#define IOS4_KERNEL_PATCH_RAM_BASE UINT64_C(0x08000000)

#define IOS4_KERNEL_PATCH_RAW_WATCHER_VA UINT32_C(0x80072b6c)
#define IOS4_KERNEL_UIOMOVE_VA UINT32_C(0x80156850)
#define IOS4_KERNEL_PATCH_IORTC_VA UINT32_C(0x801a800a)
#define IOS4_KERNEL_PATCH_BSD_ROOT_VA UINT32_C(0x801d51e8)
#define IOS4_KERNEL_PATCH_MD_READ_VA UINT32_C(0x80072d18)
#define IOS4_KERNEL_PATCH_MD_WRITE_VA UINT32_C(0x80072dbe)
#define IOS4_KERNEL_PATCH_MD_REGISTER_VA UINT32_C(0x801d51ec)
#define IOS4_KERNEL_PATCH_MD_BOUNDS_VA UINT32_C(0x80072c60)
#define IOS4_KERNEL_PATCH_MD_HIGH_VA UINT32_C(0x80072cba)
#define IOS4_KERNEL_PATCH_MD_COUNT64_VA UINT32_C(0x80072a8c)
#define IOS4_KERNEL_PATCH_MD_COUNT32_VA UINT32_C(0x80072afa)
#define IOS4_KERNEL_PATCH_MATCHGATE_VA UINT32_C(0x801b044a)
#define IOS4_KERNEL_PATCH_MATCHSYM_VA UINT32_C(0x801b0588)
#define IOS4_KERNEL_PATCH_MATCHBITS_VA UINT32_C(0x801b04aa)

/* Smallest RAM aperture, starting at IOS4_KERNEL_PATCH_RAM_BASE, that contains
 * every byte of every file-backed segment in the supported kernel. Real boots
 * use the full 128 MiB aperture. */
#define IOS4_KERNEL_PATCH_MIN_RAM_SIZE ((size_t)UINT32_C(0x0082c000))

#define IOS4_KERNEL_PATCH_NO_SITE UINT32_MAX
#define IOS4_KERNEL_PATCH_NO_SEGMENT UINT32_MAX
#define IOS4_KERNEL_PATCH_NO_BYTE UINT32_MAX
#define IOS4_KERNEL_PATCH_NO_ADDRESS UINT64_MAX

/* Exact identity of the supported decrypted kernel bytes. */
extern const uint8_t ios4_kernel_patch_expected_sha256[
    IOS4_KERNEL_PATCH_SHA256_LENGTH];
extern const uint8_t ios4_kernel_patch_expected_uuid[
    IOS4_KERNEL_PATCH_UUID_LENGTH];

typedef enum {
    IOS4_KERNEL_PATCH_SITE_IORTC = 0,
    IOS4_KERNEL_PATCH_SITE_BSD_ROOT,
    IOS4_KERNEL_PATCH_SITE_MD_READ,
    IOS4_KERNEL_PATCH_SITE_MD_WRITE,
    IOS4_KERNEL_PATCH_SITE_RAW_WATCHER,
    IOS4_KERNEL_PATCH_SITE_MATCHGATE,
    IOS4_KERNEL_PATCH_SITE_MATCHSYM,
    IOS4_KERNEL_PATCH_SITE_MATCHBITS,
    IOS4_KERNEL_PATCH_SITE_MD_REGISTER,
    IOS4_KERNEL_PATCH_SITE_MD_BOUNDS,
    IOS4_KERNEL_PATCH_SITE_MD_HIGH,
    IOS4_KERNEL_PATCH_SITE_MD_COUNT64,
    IOS4_KERNEL_PATCH_SITE_MD_COUNT32
} ios4_kernel_patch_site_t;

typedef enum {
    IOS4_KERNEL_PATCH_STATUS_OK = 0,
    IOS4_KERNEL_PATCH_STATUS_INVALID_ARGUMENT,
    IOS4_KERNEL_PATCH_STATUS_HOST_RANGE_OVERFLOW,
    IOS4_KERNEL_PATCH_STATUS_REPORT_OVERLAP,
    IOS4_KERNEL_PATCH_STATUS_REQUEST_KERNEL_OVERLAP,
    IOS4_KERNEL_PATCH_STATUS_REQUEST_RAM_OVERLAP,
    IOS4_KERNEL_PATCH_STATUS_KERNEL_RAM_OVERLAP,
    IOS4_KERNEL_PATCH_STATUS_KERNEL_SIZE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_MACHO_PARSE_FAILED,
    IOS4_KERNEL_PATCH_STATUS_CPU_TYPE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_CPU_SUBTYPE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_FILE_TYPE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_UUID_MISSING,
    IOS4_KERNEL_PATCH_STATUS_UUID_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_SEGMENT_COUNT_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_SEGMENT_NAME_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_SEGMENT_VMADDR_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_SEGMENT_VMSIZE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_SEGMENT_FILEOFF_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_SEGMENT_FILESIZE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_VM_RANGE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_ENTRYPOINT_MISSING,
    IOS4_KERNEL_PATCH_STATUS_ENTRYPOINT_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_ENTRY_STACK_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_SYMTAB_MISSING,
    IOS4_KERNEL_PATCH_STATUS_SYMTAB_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_KERNEL_DIGEST_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_VIRT_BASE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_RAM_BASE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_INVALID_RAM_GEOMETRY,
    IOS4_KERNEL_PATCH_STATUS_RAM_TOO_SMALL,
    IOS4_KERNEL_PATCH_STATUS_LOADED_SEGMENT_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_RAW_WATCHER_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_UIOMOVE_MISMATCH,
    IOS4_KERNEL_PATCH_STATUS_PATCH_TRANSACTION_FAILED
} ios4_kernel_patch_status_t;

/*
 * `kernel_file` is the complete decrypted Mach-O whose exact byte length is
 * `kernel_file_size`; the gate parses those bytes and, by default, authenticates
 * their SHA-256. Explicit import policy can skip only the stock digest check.
 * `ram` must already contain the loaded kernel segments, including zero-filled
 * bytes from each segment's file size through its VM size. This manifest
 * accepts only the iPhone1,2 mapping 80000000 -> 08000000.
 *
 * Every nonempty range below must be a valid, non-wrapping host range. The
 * request object, kernel file, and RAM aperture must be pairwise disjoint.
 * Guest execution and all access to those ranges must remain stopped for the
 * whole call.
 */
typedef struct {
    const uint8_t *kernel_file;
    size_t kernel_file_size;
    uint8_t *ram;
    size_t ram_size;
    uint64_t ram_base;
    uint32_t virt_base;
    /* Opt-in only with an installed md_geometry_bridge. Legacy media and
     * desktop callers retain the original five-site patch manifest. */
    bool extended_md_geometry;
    /* Explicit custom-firmware opt-in. All structural and patch-site checks
     * remain mandatory; zero-initialized callers keep stock authentication. */
    bool skip_stock_checksum;
} ios4_kernel_patch_request_t;

/*
 * The first deterministic failure is reported. `site`, `segment_index`, and
 * `byte_index` use the *_NO_* sentinels when they do not apply.
 * expected_value/actual_value hold scalar identity values, or the mismatching
 * digest, UUID, or site byte. `macho_status` and `guest_patch_status` retain
 * detailed subordinate failures.
 *
 * The report must be a valid object disjoint from the request object, kernel
 * file, and RAM aperture. This is checked before the first report write. On
 * REPORT_OVERLAP or HOST_RANGE_OVERFLOW the function returns the status but
 * deliberately leaves `*report` byte-for-byte untouched, because writing it
 * could corrupt an input or guest RAM. On every other call with a non-NULL,
 * disjoint report, the report is fully reset and populated.
 */
typedef struct {
    ios4_kernel_patch_status_t status;
    uint32_t site;
    uint32_t segment_index;
    uint32_t byte_index;
    uint64_t virtual_address;
    uint64_t physical_address;
    uint64_t expected_value;
    uint64_t actual_value;
    macho_status_t macho_status;
    guest_patch_status_t guest_patch_status;
} ios4_kernel_patch_report_t;

/*
 * Validate the complete build identity, exact segment topology, loaded file
 * bytes and zero-fill tails, fixed mapping, and every expected byte at the
 * five base patch sites (plus five optional extended-geometry sites) before
 * applying any replacement. The raw-mdev entry/completion pair is one site.
 * Any rejection leaves the kernel file and guest RAM unchanged. The
 * implementation performs no allocation.
 */
ios4_kernel_patch_status_t ios4_kernel_patch_apply(
    const ios4_kernel_patch_request_t *request,
    ios4_kernel_patch_report_t *report);

/* Portable allocation-free SHA-256 used by the gate. This diagnostic helper
 * exists so its implementation can be checked against public known-answer
 * vectors. `digest` may overlap `data`: it is written only after all input has
 * been consumed. NULL data is accepted only for a zero-length message. Inputs
 * longer than SHA-256's 64-bit bit-length field are rejected before output. */
bool ios4_kernel_patch_sha256(
    const uint8_t *data,
    size_t length,
    uint8_t digest[IOS4_KERNEL_PATCH_SHA256_LENGTH]);

const char *ios4_kernel_patch_status_string(ios4_kernel_patch_status_t status);
const char *ios4_kernel_patch_site_string(uint32_t site);

#endif /* S5LBOX_IOS4_KERNEL_PATCH_H */
