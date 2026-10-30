/* See md_geometry_bridge.h. Copyright (c) 2026 j0shua-SYSON. */
#include "md_geometry_bridge.h"

#include <limits.h>

bool md_geometry_bridge_valid(const md_geometry_bridge_t *b) {
    if (!b || !b->strategy || !md_bridge_config_valid(&b->strategy->config))
        return false;
    const md_bridge_config_t *c = &b->strategy->config;
    const md_geometry_sites_t *s = &b->sites;
    const uint32_t pc[] = {s->register_pc,    s->bounds_pc,  s->count64_pc,
                           s->count32_pc,     s->map_pc,     s->trim_pc,
                           s->eof_pc,         s->invalid_pc, s->count64_done_pc,
                           s->count32_done_pc};
    if (c->media_size > MD_GEOMETRY_MAX_SIZE || !s->device_va || (s->device_va & 3u) ||
        s->device_va > UINT32_MAX - 0x24u)
        return false;
    for (size_t i = 0; i < sizeof pc / sizeof pc[0]; ++i) {
        if (!pc[i] || (pc[i] & 1u) || pc[i] > UINT32_MAX - 2u)
            return false;
        for (size_t j = 0; j < i; ++j)
            if (pc[i] == pc[j])
                return false;
    }
    return true;
}

static bool word(const md_bridge_config_t *c, arm_cpu_t *cpu, uint32_t base,
                 uint32_t offset, uint32_t *out) {
    uint32_t pa;
    if (base > UINT32_MAX - offset || ((base + offset) & 3u) ||
        arm_mmu_translate(cpu, base + offset, ARM_ACCESS_READ, true, &pa) ||
        pa < c->ram_base || (uint64_t)pa + 4u > c->ram_base + c->ram_size)
        return false;
    const uint8_t *p = c->ram + (size_t)((uint64_t)pa - c->ram_base);
    *out = (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
    return true;
}

/*
 * The flags word at +12 is the device entry's registration bits as
 * _mdevadd leaves them: it ORs in bit 0 when its flag argument is zero
 * and bit 2 when it is nonzero, one bit per call. A boot that registers
 * through a single call (the xnu-1504 IOFindBSDRoot path) therefore
 * shows exactly one of the two bits, so either bit proves registration;
 * requiring both would reject that kernel's only registration. The
 * token, page count and sector size checks above remain exact.
 */
static bool device(const md_geometry_bridge_t *b, arm_cpu_t *cpu, uint32_t *sector) {
    const md_bridge_config_t *c = &b->strategy->config;
    uint32_t lo, hi, pages, flags;
    return word(c, cpu, b->sites.device_va, 0, &lo) &&
           word(c, cpu, b->sites.device_va, 4, &hi) &&
           word(c, cpu, b->sites.device_va, 8, &pages) &&
           word(c, cpu, b->sites.device_va, 12, &flags) &&
           word(c, cpu, b->sites.device_va, 16, sector) &&
           (((uint64_t)hi << 32) | lo) == (c->token_base >> 12) &&
           pages == (c->media_size >> 12) && (flags & 5u) != 0u && *sector >= 512u;
}

arm_svc_result_t md_geometry_bridge_svc(void *context, arm_cpu_t *cpu, uint32_t pc,
                                        uint32_t encoding) {
    const md_geometry_bridge_t *b = context;
    if (!b)
        return ARM_SVC_UNHANDLED;
    const md_geometry_sites_t *s = &b->sites;
    unsigned operation;
    if (s->register_pc && pc == s->register_pc && encoding == 0xdfe5u)
        operation = 0;
    else if (s->bounds_pc && pc == s->bounds_pc && encoding == 0xdfe6u)
        operation = 1;
    else if (s->count64_pc && pc == s->count64_pc && encoding == 0xdfe7u)
        operation = 2;
    else if (s->count32_pc && pc == s->count32_pc && encoding == 0xdfe8u)
        operation = 3;
    else
        return ARM_SVC_UNHANDLED;
    if (!cpu)
        return ARM_SVC_ERROR;
    if (!(cpu->cpsr & ARM_CPSR_T) || (cpu->cpsr & ARM_CPSR_MODE_MASK) == ARM_MODE_USR)
        return ARM_SVC_UNHANDLED;
    if (!arm_mode_is_valid(cpu->cpsr & ARM_CPSR_MODE_MASK) ||
        !md_geometry_bridge_valid(b) ||
        ((cpu->cp15.sctlr & ARM_SCTLR_M) && (!cpu->bus || !cpu->bus->read32)))
        return ARM_SVC_ERROR;
    const md_bridge_config_t *c = &b->strategy->config;
    if (operation == 0) {
        uint32_t bootstrap = c->media_size > MD_GEOMETRY_BOOTSTRAP_SIZE
                                 ? MD_GEOMETRY_BOOTSTRAP_SIZE
                                 : (uint32_t)c->media_size;
        /*
         * Two kernel generations reach this site with different register
         * arrangements, and both are exact:
         *
         * - xnu-1506 (iPhone OS 3.1.3): r0 = 1, r1 = token_base >> 12,
         *   with the size shift still to run on r2.
         * - xnu-1504 (iOS 4.2.1): IOFindBSDRoot converts the memory-map
         *   address with ml_static_ptovirt on its way to _mdevadd, so r0
         *   carries the token virtual address itself, r1 is a caller-saved
         *   leftover (a property-name pointer) that the next instruction
         *   overwrites from r0, and r2 still holds the byte size. The
         *   caller's following instructions derive the page numbers from
         *   r0 and from the r2 this op returns, exactly as on 3.1.3.
         *
         * The site address and encoding come from the gate and already pin
         * the call site; r2 (bootstrap byte size) and r3 (the caller's
         * registration flag) authenticate the call in both arrangements.
         */
        bool arranged_1506 = cpu->r[0] == 1u &&
                             cpu->r[1] == (c->token_base >> 12);
        bool arranged_1504 = cpu->r[0] == (uint32_t)c->token_base;
        if ((!arranged_1506 && !arranged_1504) ||
            cpu->r[2] != bootstrap || cpu->r[3] != 1u)
            return ARM_SVC_ERROR;
        cpu->r[2] = (uint32_t)(c->media_size >> 12);
        return ARM_SVC_HANDLED;
    }
    uint32_t sector;
    if (!device(b, cpu, &sector))
        return ARM_SVC_ERROR;
    if (operation == 1) {
        uint32_t lo, hi, count;
        if (cpu->r[5] != s->device_va || !word(c, cpu, cpu->r[13], 0x10, &lo) ||
            !word(c, cpu, cpu->r[13], 0x14, &hi) ||
            !word(c, cpu, cpu->r[8], 0x30, &count))
            return ARM_SVC_ERROR;
        uint64_t offset = ((uint64_t)hi << 32) | lo;
        uint32_t target;
        if (offset > c->media_size)
            target = s->invalid_pc;
        else if (offset == c->media_size)
            target = s->eof_pc;
        else if (count > c->media_size - offset) {
            /* Native SUB computes the bounded remainder modulo 2^32. */
            cpu->r[1] = (uint32_t)c->media_size;
            cpu->r[4] = lo;
            target = s->trim_pc;
        } else
            target = s->map_pc;
        cpu->r[15] = target;
        return ARM_SVC_REDIRECTED;
    }
    /* Both ioctl variants have already passed native privilege/init checks.
     * Even at 8 GiB the sector count fits in 32 bits (sector >= 512). */
    if (cpu->r[5] != 0u || cpu->r[6] != 0u || cpu->r[0] != (c->media_size >> 12) ||
        cpu->r[1] != sector)
        return ARM_SVC_ERROR;
    cpu->r[0] = (uint32_t)((c->media_size + sector - 1u) / sector);
    cpu->r[15] = operation == 2 ? s->count64_done_pc : s->count32_done_pc;
    return ARM_SVC_REDIRECTED;
}
