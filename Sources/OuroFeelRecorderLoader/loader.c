// Ouro Feel's recorder, loaded into an app by its UI test (DYLD_INSERT_LIBRARIES, simulator only) rather than linked
// into it, so no build of the app carries it. Loading starts nothing by itself: the recorder installs only when the
// test also set its directory (OuroFeel.injectedRecorderEnvironment sets both).
#include <TargetConditionals.h>

#if TARGET_OS_IPHONE && !TARGET_OS_WATCH
extern void ouro_feel_recorder_install_when_launched(void);

__attribute__((constructor)) static void ouro_feel_recorder_loaded(void) {
    ouro_feel_recorder_install_when_launched();
}
#endif
