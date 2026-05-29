#import <AVFoundation/AVFoundation.h>

// PleaseDontStopTheMusic  ***TEST BUILD***
//
// Goal: let a second app (TikTok, Twitter, YouTube, a game, ...) play audio
// WITHOUT pausing the music that is already playing, while leaving that music
// app in full control of the lock screen / Control Center "Now Playing"
// transport controls.
//
// An audio session that opts into MixWithOthers is treated by iOS as a
// *secondary* source: it won't interrupt others, and it gives up the Now
// Playing controls. So we must only force mixing on the "intruder" app, never
// on the primary music app (or its lock-screen controls vanish).
//
// -------- What changed in this test build (vs the shipped 2.1.x) --------
//
// 1. LATCHED secondary detection.  We used to re-check -isOtherAudioPlaying on
//    every single setCategory:/setActive: call. The problem: entering or
//    leaving Picture-in-Picture briefly tears the session down, during which
//    -isOtherAudioPlaying flickers to NO. The intruder then reconfigured
//    itself as an exclusive/interrupting session and killed the background
//    music. This is the most likely cause of:
//        * "Spotify stops on Twitter / YouTube videos"
//        * "enabling PiP stops the background music"
//    Fix: once a process has been seen acting as a secondary source (other
//    audio was playing when it configured its session) we LATCH that decision
//    and keep forcing MixWithOthers, so a transient flicker can't undo it.
//
// 2. NO re-entrant reconfigure inside setActive:.  The old code called
//    -setCategory:mode:options: synchronously from within -setActive:. During
//    PiP this reconfigures the session in the middle of AVPictureInPicture's
//    own activation handshake and is the prime suspect for the "TikTok PiP
//    window freezes" report. We now apply mixing only from the setCategory:*
//    family (which the latch makes reliable) and leave setActive: to log only.
//
// 3. Diagnostic logging (this is a TEST build). Every relevant call prints the
//    bundle id, category, mode and options so we can confirm on-device exactly
//    what each app does. Grep device console for "[PDSTM]".

// Process-global: AVAudioSession is effectively a per-process singleton, so a
// static flag is the right scope. Once YES it stays YES for this app's life.
static BOOL gLatchedSecondary = NO;

static NSString *PDSTMBundle(void) {
    return [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
}

// Returns whether this process should mix. Latches the decision the first time
// other audio is observed playing while this app configures its session.
static BOOL PDSTMShouldMix(AVAudioSession *session) {
    if (session.isOtherAudioPlaying) {
        if (!gLatchedSecondary) {
            gLatchedSecondary = YES;
            NSLog(@"[PDSTM][%@] latched as SECONDARY source -> will mix from now on", PDSTMBundle());
        }
    }
    return gLatchedSecondary;
}

%hook AVAudioSession

// Older convenience setter (category only). No options arg, so to add mixing we
// have to route through the mode/options setter (also hooked).
- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    NSLog(@"[PDSTM][%@] setCategory:%@ (other=%d latched=%d)", PDSTMBundle(), category, self.isOtherAudioPlaying, gLatchedSecondary);
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            // SoloAmbient cannot mix; Ambient is the mixable equivalent.
            return %orig(AVAudioSessionCategoryAmbient, outError);
        }
        if ([category isEqualToString:AVAudioSessionCategoryPlayback] ||
            [category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
            return [self setCategory:category
                                mode:AVAudioSessionModeDefault
                             options:AVAudioSessionCategoryOptionMixWithOthers
                               error:outError];
        }
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    NSLog(@"[PDSTM][%@] setCategory:%@ mode:%@ options:%lu (other=%d latched=%d)", PDSTMBundle(), category, mode, (unsigned long)options, self.isOtherAudioPlaying, gLatchedSecondary);
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, options, outError);
}

// Modern setter (iOS 11+). TikTok and most current apps use this one.
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    NSLog(@"[PDSTM][%@] setCategory:%@ mode:%@ policy:%ld options:%lu (other=%d latched=%d)", PDSTMBundle(), category, mode, (long)policy, (unsigned long)options, self.isOtherAudioPlaying, gLatchedSecondary);
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, policy, options, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    NSLog(@"[PDSTM][%@] setCategory:%@ withOptions:%lu (other=%d latched=%d)", PDSTMBundle(), category, (unsigned long)options, self.isOtherAudioPlaying, gLatchedSecondary);
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, options, outError);
}

// Log-only. We deliberately do NOT reconfigure the category here anymore: doing
// so synchronously during a PiP activation froze the PiP window. The latched
// setCategory:* hooks above already keep the session mixable.
- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    NSLog(@"[PDSTM][%@] setActive:%d (cat=%@ opts=%lu other=%d latched=%d)", PDSTMBundle(), active, self.category, (unsigned long)self.categoryOptions, self.isOtherAudioPlaying, gLatchedSecondary);
    PDSTMShouldMix(self); // keep the latch fresh if other audio is heard here
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    NSLog(@"[PDSTM][%@] setActive:%d withOptions:%lu (cat=%@ opts=%lu other=%d latched=%d)", PDSTMBundle(), active, (unsigned long)options, self.category, (unsigned long)self.categoryOptions, self.isOtherAudioPlaying, gLatchedSecondary);
    PDSTMShouldMix(self);
    return %orig;
}

%end

%ctor {
    NSLog(@"[PleaseDontStopTheMusic] TEST BUILD loaded in %@", PDSTMBundle());
}
