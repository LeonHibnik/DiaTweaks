#import "StdPatch/StdPatch.h"

// dia-byok: model selection for Settings → Patches.
// Pure switches: the toggle state lives in com.diapatches and the dia-byok
// proxy polls it, switching models within seconds. No hooks are installed,
// so these patches only read and write their own switch.
//
// Order = toggle order in the list; the proxy uses priority
// GLM-5.3 > GLM-5.3 Flash > DeepSeek, so DeepSeek stays the fallback.

DP_PATCH(DPByokModelDeepseek) {
    .key = @"byokModelDeepseek",
    .defaultOn = YES,
    .order = 100,
    .title = @"AI Model: DeepSeek V4.1 Flash",
    .detail = @"BYOK — the default model. Chat runs on DeepSeek V4.1 Flash via your zro key. Leave this on unless you switch to another model.",
    .symbol = @"sparkles",
    .tint = @"systemBlueColor",
    .section = @"AI Model",
};

DP_PATCH(DPByokModelGlm53) {
    .key = @"byokModelGlm53",
    .order = 101,
    .title = @"AI Model: GLM-5.3",
    .detail = @"BYOK — route chat to GLM-5.3 (strongest reasoning) on your key. Applies within seconds; turn off to return to the default model.",
    .symbol = @"brain",
    .tint = @"systemPurpleColor",
    .section = @"AI Model",
};

DP_PATCH(DPByokModelGlm53Flash) {
    .key = @"byokModelGlm53Flash",
    .order = 102,
    .title = @"AI Model: GLM-5.3 Flash",
    .detail = @"BYOK — route chat to GLM-5.3 Flash (fast, cheap) on your key. Applies within seconds; turn off to return to the default model.",
    .symbol = @"bolt.fill",
    .tint = @"systemYellowColor",
    .section = @"AI Model",
};
