// Air Traffic Control for Dia: links from other apps open in the profile whose
// rule matches their domain. Dia receives such links as kAEGetURL Apple events,
// which this replaces at registration time and either routes or forwards.
#import "AirTrafficControl/Atc.h"
#import "StdPatch/StdPatch.h"
#import <objc/runtime.h>

NSUserDefaults *DPAtcSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

BOOL DPAtcEnabled(void) {
    id value = [DPAtcSettings() objectForKey:@"atcEnabled"];
    return value ? [value boolValue] : YES;
}

NSArray<NSDictionary *> *DPAtcRules(void) {
    return [DPAtcSettings() arrayForKey:@"atcRules"] ?: @[];
}

void DPAtcSetRules(NSArray<NSDictionary *> *rules) {
    [DPAtcSettings() setObject:rules forKey:@"atcRules"];
}

// Dia's profile names, as Chromium keeps them. "Profile N" directories are the
// profile IDs Dia's own window state uses; the names are what AppleScript takes.
NSArray<NSString *> *DPAtcProfileNames(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
                                            @"Library/Application Support/Dia/User Data/Local State"];
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path]
                                                        options:0 error:nil];
    NSDictionary *cache = state[@"profile"][@"info_cache"];
    if (![cache isKindOfClass:NSDictionary.class]) return @[];
    NSMutableArray *keys = [cache.allKeys mutableCopy];
    [keys sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSRegularExpression *number = [NSRegularExpression regularExpressionWithPattern:@"\\d+$" options:0 error:NULL];
        NSTextCheckingResult *na = [number firstMatchInString:a options:0 range:NSMakeRange(0, a.length)];
        NSTextCheckingResult *nb = [number firstMatchInString:b options:0 range:NSMakeRange(0, b.length)];
        if (na && nb) return [@([a substringWithRange:na.range].integerValue)
                                compare:@([b substringWithRange:nb.range].integerValue)];
        return [a compare:b];
    }];
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (NSString *key in keys) {
        NSString *name = cache[key][@"name"];
        if ([name isKindOfClass:NSString.class] && name.length) [names addObject:name];
    }
    return names;
}

#pragma mark Matching

// A pattern is a domain ("github.com" matches it and every subdomain) or a
// domain plus a path ("github.com/org" also requires that path prefix).
static BOOL DPAtcHostMatches(NSString *host, NSString *pattern) {
    host = host.lowercaseString;
    pattern = pattern.lowercaseString;
    if ([pattern hasPrefix:@"*."]) pattern = [pattern substringFromIndex:2];
    return [host isEqualToString:pattern] || [host hasSuffix:[@"." stringByAppendingString:pattern]];
}

static BOOL DPAtcPatternMatches(NSString *pattern, NSURL *url) {
    if (!pattern.length || !url.host.length) return NO;
    NSString *hostPart = pattern, *pathPart = nil;
    NSRange slash = [pattern rangeOfString:@"/"];
    if (slash.location != NSNotFound) {
        hostPart = [pattern substringToIndex:slash.location];
        pathPart = [pattern substringFromIndex:slash.location];
    }
    if (!DPAtcHostMatches(url.host, hostPart)) return NO;
    if (pathPart.length > 1) {
        NSString *path = (url.path ?: @"/").lowercaseString;
        if (![path hasPrefix:pathPart.lowercaseString]) return NO;
    }
    return YES;
}

static NSString *DPAtcProfileForURL(NSURL *url) {
    if (!DPAtcEnabled()) return nil;
    for (NSDictionary *rule in DPAtcRules()) {
        if (![rule isKindOfClass:NSDictionary.class]) continue;
        NSString *pattern = rule[@"pattern"], *profile = rule[@"profile"];
        if (![pattern isKindOfClass:NSString.class] || ![profile isKindOfClass:NSString.class]) continue;
        if (DPAtcPatternMatches(pattern, url) && profile.length) return profile;
    }
    NSString *fallback = [DPAtcSettings() stringForKey:@"atcDefault"];
    return fallback.length ? fallback : nil;
}

#pragma mark Routing

static id DPAtcTarget;      // Dia's original handler for kAEGetURL
static SEL DPAtcSelector;
static IMP DPAtcOriginalIMP;
static id DPAtcRouter;

static NSString *DPAtcEscape(NSString *text) {
    return [[text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
              stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

// Creating a tab in a profile also focuses that profile, which is what makes the
// link land where the rule says. Runs off the main thread: Apple Events are
// answered on the main run loop, which must stay free. At launch no window may
// exist yet, so it retries a few times before giving the link back to Dia.
static void DPAtcOpenInProfile(NSString *url, NSString *profile, void (^fallback)(void)) {
    NSString *source = [NSString stringWithFormat:
        @"tell application \"Dia\" to tell profile \"%@\" of window 1 "
         "to make new tab at end of tabs with properties {URL:\"%@\"}",
        DPAtcEscape(profile), DPAtcEscape(url)];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
        for (int attempt = 0; attempt < 6; attempt++) {
            NSDictionary *error = nil;
            [script executeAndReturnError:&error];
            if (!error) return;
            [NSThread sleepForTimeInterval:0.75];
        }
        // No window, renamed profile… let Dia open the link its own way after all.
        dispatch_async(dispatch_get_main_queue(), fallback);
    });
}

// A link arrives on two paths (the kAEGetURL Apple event and the app delegate's
// application:openURLs:); Dia dedupes them itself, and this does the same for
// links we route, so they don't open twice.
static NSMutableDictionary<NSString *, NSDate *> *DPAtcRouted(void) {
    static NSMutableDictionary *routed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ routed = [NSMutableDictionary new]; });
    return routed;
}

static void DPAtcRememberRouted(NSString *url) {
    NSMutableDictionary *routed = DPAtcRouted();
    for (NSString *key in routed.allKeys.copy)
        if (-[routed[key] timeIntervalSinceNow] > 5) [routed removeObjectForKey:key];
    routed[url] = [NSDate date];
}

static BOOL DPAtcJustRouted(NSString *url) {
    NSDate *when = DPAtcRouted()[url];
    return when && -[when timeIntervalSinceNow] < 5;
}

@interface DPAtcEventRouter : NSObject
@end

@implementation DPAtcEventRouter
- (void)handleEvent:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    @autoreleasepool {
        NSString *string = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
        NSURL *url = [NSURL URLWithString:string];
        NSString *scheme = url.scheme.lowercaseString;
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
            if (DPAtcJustRouted(string)) return;  // the delegate path already took it
            NSString *profile = DPAtcProfileForURL(url);
            if (profile.length) {
                DPAtcRememberRouted(string);
                DPAtcOpenInProfile(string, profile, ^{
                    if (DPAtcOriginalIMP)
                        ((void (*)(id, SEL, id, id))DPAtcOriginalIMP)(DPAtcTarget, DPAtcSelector, event, reply);
                });
                return;
            }
        }
        if (DPAtcOriginalIMP)
            ((void (*)(id, SEL, id, id))DPAtcOriginalIMP)(DPAtcTarget, DPAtcSelector, event, reply);
    }
}
@end

// The second path a link takes: AppKit hands LaunchServices URLs to the app
// delegate. Dia dedupes this against its Apple-event delivery; we dedupe ours
// the same way, and route here too, which is also what catches launch links.
static void DPAtcApplicationOpenURLs(id self, SEL _cmd, NSArray<NSURL *> *urls) {
    NSMutableArray<NSURL *> *pass = [NSMutableArray new];
    for (NSURL *url in urls) {
        if (![url isKindOfClass:NSURL.class]) { [pass addObject:url]; continue; }
        NSString *string = url.absoluteString;
        if (DPAtcJustRouted(string)) continue;
        NSString *profile = DPAtcProfileForURL(url);
        if (profile.length) {
            DPAtcRememberRouted(string);
            DPAtcOpenInProfile(string, profile, ^{
                DPCallOriginal(DPAtcApplicationOpenURLs, self, @[url]);
            });
            continue;
        }
        [pass addObject:url];
    }
    if (pass.count) DPCallOriginal(DPAtcApplicationOpenURLs, self, pass);
}

static IMP (*DPAtcOrigSetHandler)(id, SEL, id, SEL, AEEventClass, AEEventID);

// Dia registers its kAEGetURL handler at launch; swap in ours and keep Dia's for chaining.
static void DPAtcSetEventHandler(id self, SEL _cmd, id handler, SEL sel, AEEventClass ec, AEEventID eid) {
    if (ec == kInternetEventClass && eid == kAEGetURL && handler && handler != DPAtcRouter) {
        DPAtcTarget = handler;
        DPAtcSelector = sel;
        DPAtcOriginalIMP = [handler methodForSelector:sel];
        DPAtcRouter = DPAtcRouter ?: [[DPAtcEventRouter alloc] init];
        DPAtcOrigSetHandler(self, _cmd, DPAtcRouter, @selector(handleEvent:withReply:), ec, eid);
        return;
    }
    DPAtcOrigSetHandler(self, _cmd, handler, sel, ec, eid);
}

void DPInstallAtc(void) {
    DPHook(DPDiaAppDelegate, @selector(application:openURLs:), (IMP)DPAtcApplicationOpenURLs);
    Method method = class_getInstanceMethod([NSAppleEventManager class],
                                            @selector(setEventHandler:andSelector:forEventClass:andEventID:));
    if (!method) return;
    DPAtcOrigSetHandler = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)DPAtcSetEventHandler);
}
