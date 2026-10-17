#import <Foundation/Foundation.h>
#import <objc/runtime.h>
int main(void) {
    Class updater = objc_getClass("SPUUpdater");
    Class driver = objc_getClass("SPUStandardUserDriver");
    printf("SPUUpdater=%s SPUStandardUserDriver=%s\n", updater ? "loaded" : "MISSING", driver ? "loaded" : "MISSING");
    return (updater && driver) ? 0 : 1;
}
