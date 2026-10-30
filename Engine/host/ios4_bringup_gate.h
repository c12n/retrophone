/*
 * S5LBox -- the iOS 4.2.1 (8C148) kernel gate, as a bring-up hook.
 *
 * The iOS 4 twin of ios3_bringup_gate.h: same adapter shape over
 * ios4_kernel_patch_apply(), plus the four SVC site addresses the
 * memory-disk bridges must watch. The packet (PPP/NAT) sites stay zero:
 * that offload has no 8C148 manifest, and a zero site never matches a
 * guest PC, so the packet bridge stays inert for this build.
 *
 * Copyright (c) 2026 j0shua-SYSON. MIT licensed.
 */
#ifndef S5LBOX_IOS4_BRINGUP_GATE_H
#define S5LBOX_IOS4_BRINGUP_GATE_H

#include "bringup.h"
#include "ios4_kernel_patch.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    ios4_kernel_patch_status_t status;
    ios4_kernel_patch_report_t report;
    bool ran;
} ios4_bringup_gate_report_t;

bool ios4_bringup_gate(void *context,
                       const uint8_t *kernel_file,
                       size_t kernel_file_size,
                       uint8_t *ram,
                       size_t ram_size,
                       uint64_t ram_base,
                       uint32_t virt_base,
                       char *detail,
                       size_t detail_capacity);

void ios4_bringup_gate_configure(s5l_bringup_request_t *request,
                                 ios4_bringup_gate_report_t *gate_report);

void ios4_bringup_gate_configure_with_policy(s5l_bringup_request_t *request,
    ios4_bringup_gate_report_t *gate_report, bool skip_stock_checksum);

#ifdef __cplusplus
}
#endif

#endif /* S5LBOX_IOS4_BRINGUP_GATE_H */
