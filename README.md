# cogi
Cogi is a lightweight, open-source application that synchronizes clipboard content between trusted devices on the same local network.

## Installation

1. Download the latest `Cogi.dmg` from [GitHub Releases](../../releases).
2. Open the DMG and drag **Cogi.app** into the **Applications** folder.
3. Open **Applications** and double-click **Cogi**.
4. If macOS blocks the app, go to **System Settings → Privacy & Security → Open Anyway → Open**.

    or you can run:
    ```bash
    xattr -dr com.apple.quarantine /Applications/Cogi.app && open /Applications/Cogi.app
    ```

Note: This release is currently unsigned/not notarized app, so macOS may show a security warning on first launch.