#import "Settings.h"
#import "AirTrafficControl/Atc.h"

// The Air Traffic Control page: rules that route links from other apps to a
// Dia profile by domain. The engine itself is AirTrafficControl/Atc.m.
@implementation DPAtcView {
    NSMutableArray<NSDictionary *> *_rules;      // {pattern, profile}, the model
    NSMutableArray<NSDictionary *> *_ruleRows;   // {field, popup}, the live rows
    NSArray<NSString *> *_profileNames;
    NSPopUpButton *_unmatched;
    NSTextField *_status;
    NSSwitch *_enabled;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _rules = [NSMutableArray new];
    _profileNames = DPAtcProfileNames();
    [self syncRulesFromDefaults];
    [self rebuild];
    return self;
}

- (void)rebuild {
    for (NSView *view in self.arrangedSubviews.copy) {
        [self removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    _ruleRows = [NSMutableArray new];

    _enabled = _enabled ?: [[NSSwitch alloc] initWithFrame:NSZeroRect];
    _enabled.target = self;
    _enabled.action = @selector(toggleEnabled:);
    [_enabled setState:DPAtcEnabled() ? NSControlStateValueOn : NSControlStateValueOff];

    NSStackView *heading = [NSStackView stackViewWithViews:@[
        DPIconTile(@"airplane", [NSColor valueForKey:@"systemTealColor"]),
        DPColumn(@[ DPLabel(@"Air Traffic Control", 13, NSFontWeightSemibold, NSColor.labelColor),
                    DPLabel(@"Route links from other apps to the right profile, by domain.",
                            11, NSFontWeightRegular, NSColor.secondaryLabelColor) ], 2),
        _enabled,
    ]];
    heading.spacing = 10;
    heading.alignment = NSLayoutAttributeTop;

    _unmatched = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_unmatched addItemsWithTitles:[@[@"Current profile"] arrayByAddingObjectsFromArray:_profileNames]];
    NSString *fallback = [DPAtcSettings() stringForKey:@"atcDefault"];
    [_unmatched selectItemWithTitle:fallback.length ? fallback : @"Current profile"];
    _unmatched.controlSize = NSControlSizeSmall;
    [_unmatched.widthAnchor constraintEqualToConstant:170].active = YES;

    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObjects:heading, nil];
    [views addObject:DPGroup(@[ DPRow(
        DPColumn(@[ DPLabel(@"Unmatched links", 13, NSFontWeightRegular, NSColor.labelColor),
                    DPLabel(@"Where links without a matching rule open.", 11, NSFontWeightRegular,
                            NSColor.secondaryLabelColor) ], 2), _unmatched) ])];

    [views addObject:DPHeader(@"Rules")];
    NSMutableArray<NSView *> *rows = [NSMutableArray new];
    if (!_rules.count) {
        [rows addObject:DPRow(DPLabel(@"No rules yet — add one below.", 13, NSFontWeightRegular,
                                      NSColor.secondaryLabelColor), [NSStackView new])];
    }
    for (NSUInteger i = 0; i < _rules.count; i++) [rows addObject:[self ruleRowAtIndex:i]];
    [views addObject:DPGroup(rows)];

    NSButton *add = [NSButton buttonWithTitle:@"Add Rule" target:self action:@selector(addRule:)];
    add.controlSize = NSControlSizeSmall;
    [views addObject:DPRow(DPLabel(@"A domain matches it and its subdomains; add a path to be exact.", 11,
                                   NSFontWeightRegular, NSColor.secondaryLabelColor), add)];

    _status = _status ?: DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    NSButton *save = [NSButton buttonWithTitle:@"Save" target:self action:@selector(save:)];
    save.controlSize = NSControlSizeSmall;
    [views addObject:DPRow(_status, save)];

    [views addObject:DPGroup(@[ DPRow(
        DPLabel(@"Applies to links opened from other apps the moment you save. Links you click inside Dia stay "
                @"where they are. Saved in com.diapatches (atcRules).",
                11, NSFontWeightRegular, NSColor.secondaryLabelColor), [NSStackView new]) ])];

    DPFillStack(self, views);
    [self layoutSubtreeIfNeeded];
}

- (NSView *)ruleRowAtIndex:(NSUInteger)index {
    NSDictionary *rule = _rules[index];
    NSTextField *pattern = [NSTextField new];
    pattern.stringValue = rule[@"pattern"] ?: @"";
    pattern.placeholderString = @"github.com or github.com/org";
    pattern.controlSize = NSControlSizeSmall;
    pattern.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];

    NSPopUpButton *profile = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [profile addItemsWithTitles:_profileNames.count ? _profileNames : @[ @"(no profiles found)" ]];
    [profile selectItemWithTitle:rule[@"profile"]];
    profile.controlSize = NSControlSizeSmall;
    [profile.widthAnchor constraintEqualToConstant:150].active = YES;

    NSButton *remove = [NSButton buttonWithTitle:@"−" target:self action:@selector(removeRule:)];
    remove.controlSize = NSControlSizeSmall;
    remove.bezelStyle = NSBezelStyleInline;
    remove.tag = index;

    NSStackView *trailing = [NSStackView stackViewWithViews:@[ profile, remove ]];
    trailing.spacing = 8;
    [_ruleRows addObject:@{ @"field": pattern, @"popup": profile }];
    return DPRow(pattern, trailing);
}

// The rows are the source of truth while the page is open.
- (void)syncRules {
    NSMutableArray *rules = [NSMutableArray new];
    for (NSDictionary *row in _ruleRows) {
        NSString *pattern = [row[@"field"] stringValue];
        NSPopUpButton *popup = row[@"popup"];
        NSString *profile = popup.titleOfSelectedItem;
        if (![profile isKindOfClass:NSString.class]) profile = @"";
        if (!pattern.length && !profile.length) continue;
        [rules addObject:@{ @"pattern": pattern ?: @"", @"profile": profile }];
    }
    _rules = rules;
}

- (void)syncRulesFromDefaults {
    [_rules removeAllObjects];
    for (NSDictionary *rule in DPAtcRules())
        if ([rule isKindOfClass:NSDictionary.class])
            [_rules addObject:@{ @"pattern": rule[@"pattern"] ?: @"", @"profile": rule[@"profile"] ?: @"" }];
}

- (IBAction)addRule:(id)sender {
    [self syncRules];
    NSString *first = _profileNames.firstObject ?: @"";
    [_rules addObject:@{ @"pattern": @"", @"profile": first }];
    [self rebuild];
}

- (IBAction)removeRule:(id)sender {
    [self syncRules];
    if (_rules.count > (NSUInteger)[sender tag]) [_rules removeObjectAtIndex:[sender tag]];
    [self rebuild];
}

- (IBAction)toggleEnabled:(id)sender {
    [DPAtcSettings() setBool:[sender state] == NSControlStateValueOn forKey:@"atcEnabled"];
    _status.stringValue = [sender state] == NSControlStateValueOn ? @"Routing on" : @"Routing off";
}

- (IBAction)save:(id)sender {
    [self syncRules];
    NSMutableArray *rules = [NSMutableArray new];
    for (NSDictionary *rule in _rules) {
        NSString *pattern = [rule[@"pattern"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!pattern.length) continue;
        [rules addObject:@{ @"pattern": pattern, @"profile": rule[@"profile"] ?: @"" }];
    }
    DPAtcSetRules(rules);
    NSString *fallback = _unmatched.titleOfSelectedItem;
    if (![fallback isEqualToString:@"Current profile"] && fallback.length) [DPAtcSettings() setObject:fallback forKey:@"atcDefault"];
    else [DPAtcSettings() removeObjectForKey:@"atcDefault"];
    _status.stringValue = [NSString stringWithFormat:@"Saved %lu rule%@ — links route immediately",
                            (unsigned long)rules.count, rules.count == 1 ? @"" : @"s"];
    _status.textColor = NSColor.secondaryLabelColor;
}
@end
