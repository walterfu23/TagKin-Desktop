# Branding (name + icons)

This folder is the only place to change what people **see**: the app name and the Dock / taskbar icons.

Internal names stay as they are (`tagkin_desktop`, bundle id `com.tagkin.tagkinDesktop`, `tagkindesktop://`, keychain). Do not rename those to rebrand.

## 1. Change the name people read

Edit [`branding.yaml`](./branding.yaml):

```yaml
appName: TagKin          # Dock, menu bar, window title, in-app chrome
fileName: TagKin         # TagKin.app / TagKin.exe (no spaces)
adminAppName: TagKin Admin
```

`fileName` and `adminAppName` can be omitted; they default to `appName` without spaces and `"<appName> Admin"`.

Example — TagKin → TagFam: set `appName: TagFam` and `fileName: TagFam`, then do step 3.

## 2. Change the icons

Replace the **contents** of these files. Keep the names.

| File | What it is |
|------|------------|
| `icon_macos.png` | macOS Dock / app icon |
| `icon_windows.png` | Windows taskbar / `.exe` icon |
| `icon_macos_admin.png` | Optional admin-tool Dock icon. If this file is missing, `icon_macos.png` is used. |

Rules:

- Format: PNG only (not `.icns`, `.ico`, `.psd`, or `.jpeg`).
- Shape: **square**. Non-square art will be squashed.
- Size: at least **1024×1024**. Larger is fine; the generator scales down.
- Two files on purpose: macOS art is often inset for the rounded rect; Windows is often full-bleed. Same picture on both is OK — copy the file onto both names.
- Do **not** edit `macos/.../AppIcon.appiconset/`, `windows/runner/resources/app_icon.ico`, or `Icons/TagFam_2/`. Those are generated or old working art.

There is no `.icns` to hand in. The generator writes PNG sizes into the Flutter asset catalog; the Xcode build creates the `.icns` inside the `.app`. The signed-out login poster uses `icon_macos.png` as a Flutter asset — replace that file, then **quit and relaunch** the desktop app (hot restart does not reliably refresh it).

## 3. Regenerate, then relaunch

From `TagKin-Desktop/mac/`:

```bash
./120_branding.sh
```

Windows (`TagKin-Desktop/win/`):

```powershell
./120_branding.ps1
```

If the operator GUI should match (name or Dock icon), from `TagKin/mac/`:

```bash
./131_branding-admin.sh
```

Then **quit the app fully** and start it again:

- Desktop: `./11_dev.sh` or `./11_dev.ps1`
- Admin tool: `./130_admin-tool.sh`

Hot restart (`R`) does not pick up a new icon or a new `.app` / `.exe` name. If the macOS Dock still shows the old mark, quit the app and run `killall Dock`.
