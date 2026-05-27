#import <AVFoundation/AVFoundation.h>

%hook AVAudioSession

- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    if ([category isEqualToString:@"AVAudioSessionCategoryPlayback"]
     || [category isEqualToString:@"AVAudioSessionCategorySoloAmbient"]) {
        return [self setCategory:category
                            mode:AVAudioSessionModeDefault
                         options:AVAudioSessionCategoryOptionMixWithOthers
                           error:outError];
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, mode, options | AVAudioSessionCategoryOptionMixWithOthers, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, options | AVAudioSessionCategoryOptionMixWithOthers, outError);
}

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    if (active) {
        NSString *cur = [self category];
        if ([cur isEqualToString:@"AVAudioSessionCategorySoloAmbient"]) {
            [self setCategory:cur
                         mode:AVAudioSessionModeDefault
                      options:AVAudioSessionCategoryOptionMixWithOthers
                        error:nil];
        }
    }
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    if (active) {
        NSString *cur = [self category];
        if ([cur isEqualToString:@"AVAudioSessionCategorySoloAmbient"]) {
            [self setCategory:cur
                         mode:AVAudioSessionModeDefault
                      options:AVAudioSessionCategoryOptionMixWithOthers
                        error:nil];
        }
    }
    return %orig;
}

%end

%ctor {
    NSLog(@"[PleaseDontStopTheMusic] loaded");
}
