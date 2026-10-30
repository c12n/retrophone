//
//  RetroPhone — RPImport.h
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
//  IPSW import: turns an iPhone1,2 Restore IPSW into the three verified
//  files the emulator boots (kernel.macho, devicetree.bin, rootfs.img) plus
//  the import policy that records their sizes. A thin controller over the
//  vendored importer (Engine/import); the file sink below is RetroPhone's.
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RPImportResult : NSObject
@property (nonatomic, copy) NSString *productVersion; /* "4.2.1"   */
@property (nonatomic, copy) NSString *build;          /* "8C148"   */
@property (nonatomic) BOOL verified;                  /* all three matched */
@end

@interface RPImport : NSObject

/* Import the IPSW at ipswPath into outDirectory (created if needed).
 * Synchronous and slow (the root filesystem is ~700 MB decrypted): call
 * from a worker thread. On success the directory holds the three files
 * and import-policy-v1, and the result names the build. */
+ (nullable RPImportResult *)importIPSWAtPath:(NSString *)ipswPath
                                intoDirectory:(NSString *)outDirectory
                                        error:(NSString **)error
    NS_SWIFT_NAME(importIPSW(atPath:intoDirectory:error:));

@end

NS_ASSUME_NONNULL_END
