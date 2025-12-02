# Synastria Questie Helper

> **Locate all quests required for attuning in the current zone, including quest chains**

---

## Requirements

- **Questie Addon**: Required for quest database and coordinate lookups https://github.com/Netrinil/Questie-335
- **\[Optional\] TomTom Addon**: If TomTom is installed, it will add a waypoint when clicking the coordinates.

---

## Features

- **TomTom**: Left click a coordinate to get a waypoint in TomTom (requires the TomTom addon).
- **Wowhead Link**: Right click a quest to get a popup with a link to the quest on wowhead.

---

## Quick Start

1. **Download & Extract**: Place the `SynastriaQuestieHelper` folder in your `Interface/AddOns/` directory.
2. **Enable**: Activate Synastria Questie Helper in your WoW AddOns menu.
3. **Click the Minimap Button**: Look for the yellow exclamation mark on your minimap.
4. **Scan Zone**: Click the "Scan Zone" button to find quests with attunement rewards.

---

## Commands

- `/synastriaquestiehelper toggle` — Toggle the quest list UI
- `/synastriaquestiehelper reset` — Reset UI position and size

---

## Screenshot

![Addon](image.png)

---

## Changelog

### Version 1.2

- Added right click for wowhead url
- Rewrote quest fetching to allow more than 10 quests
- Fixed item icons not re-loading caching

### Version 1.1

- Fixed error
- Added TomTom support

### Version 1.0

- Initial release

---

## Credits

- **Questie**: For the excellent quest database
- **Copilot**: Basically wrote the entire addon
