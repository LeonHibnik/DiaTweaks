# Screen-capture permission loop

Pressing Share in a video call keeps asking to record the screen even though
Screen Recording is already on for Dia — sometimes while sharing itself works.

## Cause

Every TCC grant is stored with the app's code-signing requirement. DiaTweaks
signs Dia with its own local identity, so a grant recorded while Dia still had
The Browser Company's official signature can never match again. While such a
stale row exists, screen capture is never re-prompted, so every permission
*check* is denied forever — the toggle in System Settings cannot heal the row
because the recorded requirement is the part that is stale. In `log show
--predicate 'process == "tccd"'` this appears as:

```
Failed to match existing code requirement for subject company.thebrowser.dia and service kTCCServiceScreenCapture
Service kTCCServiceScreenCapture does not allow prompting; returning denied.
```

## Fix

Run `scripts/fix-screen-capture`, or by hand:

1. System Settings → Privacy & Security → Screen Recording.
2. Select Dia and click **−** to remove it (the toggle being on is fine).
3. Share your screen from Dia and grant when asked; let macOS restart Dia.

The new grant is recorded against DiaTweaks' local identity, which is stable
across re-signs, so this only happens once — for rows created before DiaTweaks
was installed.

`tccutil reset ScreenCapture company.thebrowser.dia` should do step 1–2 by
itself, but on some systems its LaunchServices lookup cannot resolve the
bundle and it fails with "No such bundle identifier". The script detects that
and opens System Settings instead.
