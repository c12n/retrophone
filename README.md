# RetroPhone

Copyright (c) 2026 c12n Apps

RetroPhone is an iPhone app that runs **iPhone OS 3.1.3** and **iOS 4.2.1**
on modern iPhones, by emulating the original S5L8900 (iPhone 3G)
hardware: ARM CPU, memory-disk root filesystem, CLCD display, multitouch,
buttons and the rest of the board, at native speed via a static
translation engine.

It is c12n's own application — its interface, boot controller, importer
front-end and display path were written for this project. The emulation
core under `Engine/` is vendored from the S5LBox project (MIT, see
`Engine/UPSTREAM-LICENSE`), including the iOS 4.2.1 kernel patch and
provisioning work developed alongside it.

## What works

- Import an iPhone1,2 Restore IPSW (3.1.3 `7E18` or 4.2.1 `8C148`); the
  kernel, device tree and root filesystem are extracted and verified
  against known-good digests. No firmware is bundled or downloaded by
  the app — you supply your own IPSW.
- Create machines with a writable 8 GB disk, provisioned on first open
  (offline activation included).
- Boot to the guest's own lock screen, rendered from the emulated
  display controller's scanout, with touch and Home/Power buttons.
- Guest serial console and live display diagnostics in-app.

## Not yet

- Guest networking (PPP/NAT) — planned.
- Audio — planned.
- Jailbreak payloads — out of scope for now.

## Building

The Xcode project is generated with XcodeGen (`app/project.yml`); the
static engine's handler table is generated first:

```
python3 Engine/host/gen_a64_static.py app/Generated/a64_static_handlers.S
cd app && xcodegen generate
```

CI (`.github/workflows/build.yml`) builds an unsigned device build and
packages an ad-hoc-signed IPA for sideloading.
`.github/workflows/sim-run.yml` boots the app in an iOS 26 Simulator
with a seeded 4.2.1 machine and uploads screenshots.

## License

MIT — see `LICENSE`. The vendored engine keeps its own MIT license in
`Engine/UPSTREAM-LICENSE`.
