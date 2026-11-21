
## Anbernic RG351P: how to install

The RG351P has one SD slot, so dArkMoss and spruce share the same card. A card bigger than about 12 GB is needed: dArkMoss keeps 11 GB, spruce gets the rest.

1. **Download** the image below (`dArkMoss_RG351P_trixie_<date>.img.7z.001`). If there is also a `.002` part, download it into the same folder.
2. **Unpack** with [7-Zip](https://www.7-zip.org/download.html): right-click the `.001` file and choose *Extract Here*. You get one `.img` file.
3. **Flash** the `.img` to your SD card with [balenaEtcher](https://etcher.balena.io/) or Raspberry Pi Imager. This erases the card. Re-flashing a card that already has dArkMoss erases its **SPRUCEOS** drive too (the first boot formats it again), so back up `Saves/` and your ROMs first, or update instead (below). If Windows asks to format the disk afterwards, click *Cancel*.
4. **First boot:** put the card in the RG351P and turn it on. It sets up the card and makes a **SPRUCEOS** partition (a few minutes), then shows *spruce card not found* and turns off. That is expected.
5. **Copy spruce:** put the card back in your computer and open the **SPRUCEOS** drive.
   - Extract the newest spruce `.7z` into it (a [release](https://github.com/spruceUI/spruceOS/releases) or a [nightly](https://github.com/spruceUI/spruceOSNightlies/releases) with RG351P support).
6. **Turn the RG351P on.** The first start unpacks spruce's apps and themes, which takes a few minutes once.

## Updating an RG351P that already runs dArkMoss

No need to re-flash: spruce's **Apps → Firmware Update** installs this release in place. Charge to at least 15% (or plug in) first. Either connect a USB Wi-Fi dongle (see *Wi-Fi* below), turn Wi-Fi on and join a network in spruce's settings, and let the app download it, or copy `dArkMoss_RG351P_<version>.dmupd` from this release to the root of the **SPRUCEOS** drive and then open Firmware Update. spruce, your settings, saves and ROMs are kept, and the update also refreshes U-Boot.

## Using the RG351P

**Wi-Fi:** the RG351P has no built-in radio. Plug a USB Wi-Fi dongle into its USB-C OTG port through an OTG adapter. The kernel has drivers for dongles with these chipsets: Realtek RTL8188EU/EUS, RTL8188FU, RTL8192CU, RTL8723BU, RTL8811AU/8812AU/8821AU, RTL8821CU and RTL8822BU; MediaTek MT7601U; Ralink RT2800-family (RT3070, RT5370).

**Controls:** there is no menu button, so a stick click is the menu: the left one (L3) by default, or the right one under *Settings → Button Settings → Menu button*. The other click works as L3/R3. In the menus **SELECT + START** opens the menu too. In games, a tap on the menu click opens the emulator menu and holding it opens the Game Switcher; SELECT is the RetroArch hotkey: SELECT+B exit, SELECT+R1 save, SELECT+L1 load, SELECT+Y RetroArch menu.

**Volume** is the hardware wheel only; spruce keeps its own volume at full.

**Reporting problems:** logs are on the SPRUCEOS drive in `Saves/spruce/` (`spruce.log`, `darkmoss_debug.log`, and `retroarch.log` with *Settings → Emulator Settings → Verbose emulator logging* on). If a game you cannot leave resumes at every boot, delete `spruce/flags/save_active.lock` on SPRUCEOS.
