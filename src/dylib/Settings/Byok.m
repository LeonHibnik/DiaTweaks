#import "Settings.h"

// The BYOK settings page: vendor, API key and endpoint for the dia-byok proxy.
// It edits the proxy's config.json in place; the proxy watches that file and
// reloads within a couple of seconds, so no restart is needed.
// The config's location differs per machine — point at it once with:
//   defaults write com.diapatches byokConfigPath "$HOME/.../dia-byok/config.json"
static NSString *DPByokConfigPath(void) {
    NSString *path = [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] stringForKey:@"byokConfigPath"];
    return path.length ? path : nil;
}
static NSString *const DPByokZroEndpoint = @"https://zro.moonmath.ai/v1/messages";
static NSString *const DPByokOpenAIEndpoint = @"https://api.openai.com/v1/chat/completions";

@implementation DPByokView {
    NSPopUpButton *_vendor;
    NSSecureTextField *_key;
    NSTextField *_endpoint;
    NSTextField *_status;
    NSMutableDictionary *_config;
    NSString *_shownVendor;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;

    _vendor = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_vendor addItemsWithTitles:@[ @"zro", @"openai" ]];
    _vendor.controlSize = NSControlSizeSmall;
    _vendor.target = self;
    _vendor.action = @selector(vendorChanged);
    [_vendor.widthAnchor constraintEqualToConstant:180].active = YES;

    _key = [NSSecureTextField new];
    _key.placeholderString = @"API key";
    _key.controlSize = NSControlSizeSmall;
    _key.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    [_key.widthAnchor constraintEqualToConstant:250].active = YES;

    _endpoint = [NSTextField new];
    _endpoint.placeholderString = @"https://…";
    _endpoint.controlSize = NSControlSizeSmall;
    _endpoint.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    [_endpoint.widthAnchor constraintEqualToConstant:250].active = YES;

    _status = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    NSButton *save = [NSButton buttonWithTitle:@"Save" target:self action:@selector(save)];
    save.controlSize = NSControlSizeSmall;

    NSStackView *heading = [NSStackView stackViewWithViews:@[
        DPIconTile(@"key.horizontal", [NSColor valueForKey:@"systemPinkColor"]),
        DPColumn(@[ DPLabel(@"BYOK Providers", 13, NSFontWeightSemibold, NSColor.labelColor),
                    DPLabel(@"Choose the vendor Dia's chat talks to, and set its API key and endpoint.",
                            11, NSFontWeightRegular, NSColor.secondaryLabelColor) ], 2),
    ]];
    heading.spacing = 10;
    heading.alignment = NSLayoutAttributeTop;

    NSView *vendorRow = DPRow(DPColumn(@[ DPLabel(@"Vendor", 13, NSFontWeightRegular, NSColor.labelColor),
                                          DPLabel(@"Which API the proxy uses for chat.", 11, NSFontWeightRegular,
                                                  NSColor.secondaryLabelColor) ], 2), _vendor);
    NSView *keyRow = DPRow(DPColumn(@[ DPLabel(@"API key", 13, NSFontWeightRegular, NSColor.labelColor),
                                       DPLabel(@"Sent only to the vendor above.", 11, NSFontWeightRegular,
                                               NSColor.secondaryLabelColor) ], 2), _key);
    NSView *endpointRow = DPRow(DPColumn(@[ DPLabel(@"Endpoint", 13, NSFontWeightRegular, NSColor.labelColor),
                                            DPLabel(@"The vendor's API base URL.", 11, NSFontWeightRegular,
                                                    NSColor.secondaryLabelColor) ], 2), _endpoint);
    NSView *actions = DPRow(_status, save);
    NSView *note = DPGroup(@[ DPRow(DPLabel(@"Saved to config.json — the proxy picks it up within a few seconds. The AI Model toggles on the previous page choose zro's model; they don't apply to openai.",
                                         11, NSFontWeightRegular, NSColor.secondaryLabelColor),
                                  [NSStackView new]) ]);

    DPFillStack(self, @[ heading, DPGroup(@[ vendorRow, keyRow, endpointRow ]), actions, note ]);
    [self load];
    return self;
}

- (void)load {
    NSString *configPath = DPByokConfigPath();
    NSData *data = configPath ? [NSData dataWithContentsOfFile:configPath] : nil;
    NSError *error;
    id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error] : nil;
    _config = [parsed isKindOfClass:NSMutableDictionary.class] ? parsed : [NSMutableDictionary dictionary];

    NSMutableDictionary *providers = _config[@"providers"];
    if (![providers isKindOfClass:NSMutableDictionary.class]) {
        providers = [NSMutableDictionary new];
        _config[@"providers"] = providers;
    }
    for (NSString *name in @[ @"zro", @"openai" ]) {
        NSMutableDictionary *provider = providers[name];
        if (![provider isKindOfClass:NSMutableDictionary.class]) {
            provider = [NSMutableDictionary new];
            providers[name] = provider;
        }
        if (!provider[@"endpoint"])
            provider[@"endpoint"] = [name isEqualToString:@"zro"] ? DPByokZroEndpoint : DPByokOpenAIEndpoint;
        if (!provider[@"model"])
            provider[@"model"] = [name isEqualToString:@"zro"] ? @"deepseek-v4.1-flash" : @"gpt-4.1";
    }

    NSString *active = _config[@"active"];
    _shownVendor = [@[ @"zro", @"openai" ] containsObject:active] ? active : @"zro";
    [_vendor selectItemWithTitle:_shownVendor];
    [self showVendor:_shownVendor];
    _status.stringValue = data ? @"Loaded config.json"
        : configPath ? @"config.json not found — showing defaults"
        : @"Not configured — run: defaults write com.diapatches byokConfigPath <path to dia-byok's config.json>";
}

- (void)showVendor:(NSString *)vendor {
    NSDictionary *provider = _config[@"providers"][vendor];
    _key.stringValue = provider[@"apiKey"] ?: @"";
    _endpoint.stringValue = provider[@"endpoint"] ?: @"";
}

- (void)stashVendor:(NSString *)vendor {
    NSMutableDictionary *provider = _config[@"providers"][vendor];
    provider[@"apiKey"] = _key.stringValue ?: @"";
    provider[@"endpoint"] = _endpoint.stringValue ?: @"";
}

- (void)vendorChanged {
    if (_shownVendor) [self stashVendor:_shownVendor];
    _shownVendor = _vendor.titleOfSelectedItem;
    [self showVendor:_shownVendor];
    _status.stringValue = [NSString stringWithFormat:@"Editing %@ — not saved yet", _shownVendor];
}

- (void)save {
    NSString *configPath = DPByokConfigPath();
    if (!configPath) {
        _status.stringValue = @"Not configured — run: defaults write com.diapatches byokConfigPath <path>";
        _status.textColor = NSColor.systemRedColor;
        return;
    }
    if (_shownVendor) [self stashVendor:_shownVendor];
    _config[@"active"] = _shownVendor ?: @"zro";
    NSError *error;
    NSData *json = [NSJSONSerialization dataWithJSONObject:_config
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&error];
    BOOL ok = json && [json writeToFile:configPath options:NSDataWritingAtomic error:&error];
    _status.stringValue = ok
        ? [NSString stringWithFormat:@"Saved — the proxy switches to %@ within a few seconds", _config[@"active"]]
        : [NSString stringWithFormat:@"Couldn't save config.json: %@", error.localizedDescription ?: @"unknown error"];
    _status.textColor = ok ? NSColor.secondaryLabelColor : NSColor.systemRedColor;
}
@end
