// Air Traffic Control: route links from other apps to the right Dia profile,
// like Arc's Air Traffic Control. Rules live in com.diapatches:
//   atcRules  = [ { pattern: "github.com" | "github.com/org", profile: "Work" }, ... ]
//   atcDefault = profile name for unmatched links (absent = Dia's normal handling)
//   atcEnabled = NO turns routing off (absent = on)
#import <Foundation/Foundation.h>

void DPInstallAtc(void);
NSUserDefaults *DPAtcSettings(void);
NSArray<NSDictionary *> *DPAtcRules(void);
void DPAtcSetRules(NSArray<NSDictionary *> *rules);
NSArray<NSString *> *DPAtcProfileNames(void);
BOOL DPAtcEnabled(void);
