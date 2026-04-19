# CHANGELOG

## v1.1.0 (The UI Overhaul Update)
* **Complete UI Modernization**: Massive visual refactor of the tracking panel.
* **Settings Preview**: Now you can see how the panel will look in real-time inside the Blizzard Options menu!
* **LibSharedMedia Integration**: You can now choose your preferred Bar Texture (Plater, ElvUI natively supported).
* **Class Bars Mode**: Added a classic mode to fill the entire bar width with the target's class color.
* **Modern UI & Emphasize**: Added smooth opacity pulsing for ready interrupts and a translucent crystal look.
* **Minimalist & Smart Visibility**: Added options to completely remove the background frame ("Hide Frame") and to hide the panel outside of instances ("Only in Dungeons").
* **Spell Icons**: Added the ability to toggle the display of class-specific interrupt icons on the tracker.
* **Performance**: Codebase cleaned up for better stability and taint-free combat operation.

## v1.0.5
* Added **Auto Focus Target** option: Automatically sets your assigned target as your focus to monitor spellcasts efficiently.
* Fixed several background taint issues related to party marking in Mythic+ Dungeons.
* Removed deprecated addon network channels to drastically improve performance and zero-out UI taint warnings.

## v1.0.4
* Addressed `UNIT_SPELLCAST_SUCCEEDED` taint error when interrupting spells locally.

## v1.0.3
* Reverted to macro-only synchronization for standard Mythic+ environments.
* Added native localization framework for enUS & esES.

## v1.0.0
* Initial Release. Modern Interrupt Tracker with Floating Drop-down UI!
