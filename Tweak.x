#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <notify.h>

// PleaseDontStopTheMusic
//
// Default rule (every app except TikTok): when other audio is already playing,
// the "intruder" app is forced to MixWithOthers so it joins the music as a
// *secondary* source. The music app stays primary and keeps its lock-screen /
// Control Center "Now Playing" controls. An app that has been forced to mix is
// also prevented from publishing Now-Playing info, so it cannot steal the
// lock-screen / Control Center transport controls from the music app.
//
// Special case — TikTok Live PiP: TikTok Live uses a sample-buffer Picture-in-
// Picture renderer that only advances video frames while its audio session is
// the *primary* (hardware-clock) source. Forcing it to mix freezes the PiP
// video. So TikTok is kept primary, and — only while TikTok is in the
// foreground — it sends a one-shot Darwin notification telling the background
// music app to make ITS OWN session secondary (MixWithOthers) so TikTok's
// primary session does not interrupt it. TikTok is intentionally NOT blocked
// from Now-Playing because its PiP renderer depends on it.

static BOOL gIsVideoApp    = NO;   // TikTok: kept primary so its PiP clock runs
static BOOL gForcedToMix   = NO;   // this app was forced secondary; suppress Now-Playing
static BOOL gSessionActive = NO;   // tracks setActive: state

static NSString *const kBegin = @"com.pdstm.pip.begin";

static BOOL PDSTMShouldMix(AVAudioSession *s) {
    if (gIsVideoApp) return NO;
    return s.isOtherAudioPlaying;
}

// Mark this process as a forced secondary mixer and set its audio session.
static void PDSTMApplyMix(AVAudioSession *s) {
    gForcedToMix = YES;
}

static void PDSTMPost(NSString *name) { notify_post(name.UTF8String); }

static void PDSTMGoSecondary(void) {
    if (gIsVideoApp) return;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSString *cat = s.category;
    BOOL playbackish = [cat isEqualToString:AVAudioSessionCategoryPlayback]
                    || [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord];
    if (!gSessionActive || !playbackish) return;
    if (s.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) return;
    gForcedToMix = YES;
    [s setCategory:cat mode:s.mode
           options:(s.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers) error:nil];
    [s setActive:YES error:nil];
}

static void PDSTMDarwinCallback(CFNotificationCenterRef c, void *obs, CFStringRef name,
                                const void *obj, CFDictionaryRef info) {
    if ([(__bridge NSString *)name isEqualToString:kBegin]) PDSTMGoSecondary();
}

#pragma mark - AVAudioSession

%hook AVAudioSession

- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        PDSTMApplyMix(self);
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient])
            return %orig(AVAudioSessionCategoryAmbient, outError);
        if ([category isEqualToString:AVAudioSessionCategoryPlayback])
            return [self setCategory:category mode:AVAudioSessionModeDefault
                             options:AVAudioSessionCategoryOptionMixWithOthers error:outError];
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        PDSTMApplyMix(self);
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, options, outError);
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        PDSTMApplyMix(self);
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, policy, options, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        PDSTMApplyMix(self);
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, options, outError);
}

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    gSessionActive = active;
    if (gIsVideoApp && active && self.isOtherAudioPlaying) PDSTMPost(kBegin);
    if (active && PDSTMShouldMix(self)
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        PDSTMApplyMix(self);
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) cat = AVAudioSessionCategoryAmbient;
        [self setCategory:cat mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    }
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    gSessionActive = active;
    if (gIsVideoApp && active && self.isOtherAudioPlaying) PDSTMPost(kBegin);
    if (active && PDSTMShouldMix(self)
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        PDSTMApplyMix(self);
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) cat = AVAudioSessionCategoryAmbient;
        [self setCategory:cat mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    }
    return %orig;
}

%end

#pragma mark - Now-Playing suppression (forced-secondary apps only)

// When this app has been forced to mix (secondary), block it from publishing
// Now-Playing metadata so the music app keeps the lock-screen controls.
// TikTok is explicitly excluded — its PiP renderer depends on owning Now-Playing.

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    if (gForcedToMix) return;   // don't steal lock-screen controls from the music app
    %orig;
}

%end

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
    NSArray *video = @[ @"com.zhiliaoapp.musically",
                        @"com.zhiliaoapp.musically.go",
                        @"com.ss.iphone.ugc.Ame" ];
    gIsVideoApp = [video containsObject:bid];

    if (gIsVideoApp) {
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMPost(kBegin); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationWillEnterForegroundNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMPost(kBegin); }];
        PDSTMPost(kBegin);
    } else {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            PDSTMDarwinCallback, (__bridge CFStringRef)kBegin, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }

    NSLog(@"[PleaseDontStopTheMusic] loaded (bundle=%@ video=%d)", bid, gIsVideoApp);
}
