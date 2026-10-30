/* See ios4_bringup_gate.h. Copyright (c) 2026 j0shua-SYSON. MIT licensed. */
#include "ios4_bringup_gate.h"

#include <stdio.h>
#include <string.h>

static bool apply_gate(bool extended, bool skip_stock_checksum, void *context,
                       const uint8_t *kernel_file,
                       size_t kernel_file_size,
                       uint8_t *ram,
                       size_t ram_size,
                       uint64_t ram_base,
                       uint32_t virt_base,
                       char *detail,
                       size_t detail_capacity) {
    ios4_bringup_gate_report_t *out = (ios4_bringup_gate_report_t *)context;
    ios4_kernel_patch_request_t request;
    ios4_kernel_patch_report_t report;
    ios4_kernel_patch_status_t status;

    memset(&request, 0, sizeof request);
    memset(&report, 0, sizeof report);
    request.kernel_file = kernel_file;
    request.kernel_file_size = kernel_file_size;
    request.ram = ram;
    request.ram_size = ram_size;
    request.ram_base = ram_base;
    request.virt_base = virt_base;
    request.extended_md_geometry = extended;
    request.skip_stock_checksum = skip_stock_checksum;

    status = ios4_kernel_patch_apply(&request, &report);
    if (out != NULL) {
        out->status = status;
        out->report = report;
        out->ran = true;
    }
    if (status == IOS4_KERNEL_PATCH_STATUS_OK) return true;

    if (detail != NULL && detail_capacity > 0u) {
        (void)snprintf(detail, detail_capacity,
                       "this is not the supported iOS 4.2.1 kernel: %s "
                       "(site %s, va 0x%08llx)",
                       ios4_kernel_patch_status_string(status),
                       ios4_kernel_patch_site_string(report.site),
                       (unsigned long long)report.virtual_address);
        detail[detail_capacity - 1u] = '\0';
    }
    return false;
}

bool ios4_bringup_gate(void *context, const uint8_t *file, size_t file_size,
                      uint8_t *ram, size_t ram_size, uint64_t ram_base,
                      uint32_t virt_base, char *detail, size_t capacity) {
    return apply_gate(false, false, context, file, file_size, ram, ram_size, ram_base,
                      virt_base, detail, capacity);
}

static bool extended_gate(void *context, const uint8_t *file, size_t file_size,
                          uint8_t *ram, size_t ram_size, uint64_t ram_base,
                          uint32_t virt_base, char *detail, size_t capacity) {
    return apply_gate(true, false, context, file, file_size, ram, ram_size, ram_base,
                      virt_base, detail, capacity);
}

void ios4_bringup_gate_configure(s5l_bringup_request_t *request,
                                 ios4_bringup_gate_report_t *gate_report) {
    ios4_bringup_gate_configure_with_policy(request, gate_report, false);
}

static bool custom_gate(void *context, const uint8_t *file, size_t file_size,
    uint8_t *ram, size_t ram_size, uint64_t ram_base, uint32_t virt_base,
    char *detail, size_t capacity) {
    return apply_gate(false, true, context, file, file_size, ram, ram_size,
        ram_base, virt_base, detail, capacity);
}

static bool custom_extended_gate(void *context, const uint8_t *file, size_t file_size,
    uint8_t *ram, size_t ram_size, uint64_t ram_base, uint32_t virt_base,
    char *detail, size_t capacity) {
    return apply_gate(true, true, context, file, file_size, ram, ram_size,
        ram_base, virt_base, detail, capacity);
}

void ios4_bringup_gate_configure_with_policy(s5l_bringup_request_t *request,
    ios4_bringup_gate_report_t *gate_report, bool skip_stock_checksum) {
    if (request == NULL) return;
    /* xnu-1504's IOFindBSDRoot runs the RAMDisk memory-map word through
     * ml_static_ptovirt before _mdevadd; with this build's fixed bases
     * (phys 0x08000000, virt 0x80000000) the word that arrives as the
     * bridge token 0xe0000000 is 0x68000000. */
    request->root_dt_address_override = UINT32_C(0x68000000);
    request->kernel_gate = skip_stock_checksum ? custom_gate : ios4_bringup_gate;
    request->kernel_gate_context = gate_report;
    request->md_read_site_pc = IOS4_KERNEL_PATCH_MD_READ_VA;
    request->md_write_site_pc = IOS4_KERNEL_PATCH_MD_WRITE_VA;
    request->md_raw_site_pc = IOS4_KERNEL_PATCH_RAW_WATCHER_VA;
    request->uiomove_pc = IOS4_KERNEL_UIOMOVE_VA;
    request->md_major_va = UINT32_C(0x80257318);   /* _mdevCMajor */
    request->md_geometry_sites = (md_geometry_sites_t){0};
    if (request->root_media &&
        request->root_media->size > MD_GEOMETRY_BOOTSTRAP_SIZE) {
        request->kernel_gate = skip_stock_checksum ? custom_extended_gate : extended_gate;
        /* Geometry watchpoints inside the 8C148 memory-device unit,
         * offset-mapped from the audited 7E18 positions and verified
         * against the 8C148 disassembly (the unit is instruction-
         * identical between the two kernels). device_va is the 8C148
         * md device structure in __DATA. */
        request->md_geometry_sites = (md_geometry_sites_t){
            .register_pc = IOS4_KERNEL_PATCH_MD_REGISTER_VA,
            .bounds_pc = IOS4_KERNEL_PATCH_MD_BOUNDS_VA,
            .count64_pc = IOS4_KERNEL_PATCH_MD_COUNT64_VA,
            .count32_pc = IOS4_KERNEL_PATCH_MD_COUNT32_VA,
            .device_va = UINT32_C(0x80270268),
            .map_pc = UINT32_C(0x80072c9a),
            .trim_pc = UINT32_C(0x80072e64),
            .eof_pc = UINT32_C(0x80072c76),
            .invalid_pc = UINT32_C(0x80072c6e),
            .count64_done_pc = UINT32_C(0x80072a96),
            .count32_done_pc = UINT32_C(0x80072b04)
        };
    }
    /* No packet offload manifest for 8C148: zero sites never match. */
    request->packet_sites = (guest_packet_sites_t){0};
}
