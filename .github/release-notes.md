## Install

1. Download **Headroom-*.dmg** below and open it.
2. Drag **Headroom** onto **Applications**.
3. Open Headroom from Applications. It lives in the menu bar, not the Dock.

Headroom is not notarized by Apple yet, so the first launch is blocked once. Open **System Settings > Privacy & Security**, scroll down and click **Open Anyway** next to the Headroom message. Alternatively run:

```bash
xattr -dr com.apple.quarantine /Applications/Headroom.app
```

Requires macOS 14 or newer. Universal build for Apple Silicon and Intel.

Claude Code limits and token usage appear when Claude Code is signed in; Grok appears when the Grok CLI is signed in (`grok login`).
