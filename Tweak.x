#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <notify.h>

// PleaseDontStopTheMusic
//
// Default rule (every app except TikTok): when other audio is already playing,
// the "intruder" app is forced to MixWithOthers so it joins the music as a
// *secondary* source. The music app stays primary and keeps its lock-screen /
// Control Center "Now Playing" controls. This is the proven v2.2.0 behaviour and
// is left completely untouched.
//
// Lock-screen controls (added v2.3.2): a forced-secondary *intruder* is also
// stopped from publishing Now-Playing info, so it cannot grab the lock-screen /
// Control Center transport controls away from your background music. The lead
// music app is explicitly exempt (see gIsPrimaryMusic) so it NEVER suppresses
// itself — including when it goes secondary for TikTok. TikTok is also never
// suppressed (see below).
//
// Special case — TikTok Live PiP: TikTok Live uses a sample-buffer Picture-in-
// Picture renderer that only advances video frames while its audio session is
// the *primary* (hardware-clock) source. Forcing it to mix freezes the PiP
// video. So TikTok is kept primary, and — only while TikTok is in the
// foreground — it sends a one-shot Darwin notification telling the background
// music app to make ITS OWN session secondary (MixWithOthers) so TikTok's
// primary session does not interrupt it. Net result: PiP video plays and the
// music keeps going.
//
// Important: nothing here ever makes another app *seize* the primary session, so
// it can never re-introduce the "intruder pauses your music" bug. The only app
// that stays primary is TikTok itself. TikTok is ALSO deliberately never marked
// as a forced-secondary intruder, so its Now-Playing is never suppressed — its
// PiP renderer depends on owning Now-Playing, and touching that re-freezes PiP.

static BOOL gIsVideoApp     = NO;   // TikTok: kept primary so its PiP clock runs; never suppressed
static BOOL gSessionActive  = NO;   // tracks setActive: state (are we playing?)
static BOOL gForcedToMix    = NO;   // this app is a forced-secondary intruder; suppress its Now-Playing
static BOOL gIsPrimaryMusic = NO;   // this app played as the lead audio; never treat it as an intruder

static NSString *const kBegin = @"com.pdstm.pip.begin";

static BOOL PDSTMShouldMix(AVAudioSession *s) {
    if (gIsVideoApp) return NO;        // TikTok stays primary
    return s.isOtherAudioPlaying;      // everyone else: exactly the v2.2.0 rule
}

// Latch this process as a forced-secondary intruder (suppress its Now-Playing) —
// but NEVER the lead music app, which must keep its lock-screen controls. TikTok
// never reaches here because PDSTMShouldMix() returns NO for it.
static void PDSTMMarkIntruder(void) {
    if (!gIsPrimaryMusic) gForcedToMix = YES;
}

static void PDSTMPost(NSString *name) { notify_post(name.UTF8String); }

// Music side: TikTok is foreground and wants the primary session. If we are the
// background app currently playing, make our session secondary (one shot) so we
// keep playing instead of being interrupted. We never seize primary back here —
// that is what previously broke Twitter/YouTube/Dr Driving. We also do NOT mark
// ourselves as an intruder here: going secondary for TikTok must not cost the
// music app its own lock-screen controls.
static void PDSTMGoSecondary(void) {
    if (gIsVideoApp) return;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSString *cat = s.category;
    BOOL playbackish = [cat isEqualToString:AVAudioSessionCategoryPlayback]
                    || [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord];
    if (!gSessionActive || !playbackish) return;
    if (s.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) return;
    [s setCategory:cat mode:s.mode
           options:(s.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers) error:nil];
    [s setActive:YES error:nil];
}

static void PDSTMDarwinCallback(CFNotificationCenterRef c, void *obs, CFStringRef name,
                                const void *obj, CFDictionaryRef info) {
    if ([(__bridge NSString *)name isEqualToString:kBegin]) PDSTMGoSecondary();
}

// Mark this process as the lead music app when it activates playback while no
// other audio is playing. Once it is the lead, it is exempt from intruder
// suppression, and we clear any transient latch so it can never lose its own
// lock-screen controls.
static void PDSTMNoteLeadIfPlaying(AVAudioSession *s, BOOL active) {
    if (gIsVideoApp || !active || s.isOtherAudioPlaying) return;
    NSString *cat = s.category;
    if ([cat isEqualToString:AVAudioSessionCategoryPlayback]
     || [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        gIsPrimaryMusic = YES;
        gForcedToMix    = NO;
    }
}

#pragma mark - AVAudioSession

%hook AVAudioSession

- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        PDSTMMarkIntruder();
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
        PDSTMMarkIntruder();
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, options, outError);
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        PDSTMMarkIntruder();
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, policy, options, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        PDSTMMarkIntruder();
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, options, outError);
}

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    gSessionActive = active;
    PDSTMNoteLeadIfPlaying(self, active);
    if (gIsVideoApp && active && self.isOtherAudioPlaying) PDSTMPost(kBegin);
    if (active && PDSTMShouldMix(self)
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        PDSTMMarkIntruder();
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) cat = AVAudioSessionCategoryAmbient;
        [self setCategory:cat mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    }
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    gSessionActive = active;
    PDSTMNoteLeadIfPlaying(self, active);
    if (gIsVideoApp && active && self.isOtherAudioPlaying) PDSTMPost(kBegin);
    if (active && PDSTMShouldMix(self)
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        PDSTMMarkIntruder();
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) cat = AVAudioSessionCategoryAmbient;
        [self setCategory:cat mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    }
    return %orig;
}

%end

#pragma mark - Now-Playing suppression (forced-secondary intruders only)

// When this process has been latched as a forced-secondary intruder, block it
// from publishing Now-Playing metadata so the lead music app keeps the
// lock-screen / Control Center controls. The lead music app never sets
// gForcedToMix, and TikTok never sets it either, so neither is ever suppressed.

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    if (gForcedToMix) return;   // intruder: don't steal lock-screen controls from the music app
    %orig;
}

%end

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
    NSArray *video = @[ @"com.zhiliaoapp.musically",       // TikTok
                        @"com.zhiliaoapp.musically.go",
                        @"com.ss.iphone.ugc.Ame" ];        // TikTok (other region)
    gIsVideoApp = [video containsObject:bid];

    if (gIsVideoApp) {
        // TikTok only posts (never observes). Tell the background music app to go
        // secondary as TikTok comes to the foreground, before TikTok's Live audio
        // seizes the primary session.
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMPost(kBegin); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationWillEnterForegroundNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMPost(kBegin); }];
        PDSTMPost(kBegin);
    } else {
        // Music app only listens; it never seizes primary on its own.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            PDSTMDarwinCallback, (__bridge CFStringRef)kBegin, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }

    NSLog(@"[PleaseDontStopTheMusic] loaded (bundle=%@ video=%d)", bid, gIsVideoApp);
}
