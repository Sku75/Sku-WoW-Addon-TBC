WoW Login Tool

VERSION 2 (OCR rework):
This release contains two generations of the tool:
- v2 (recommended, folder "v2"): senses the game by capturing the game
  window and reading the text on it with the Windows OCR (both are built
  into Windows 10/11). It announces your REAL character names ("Xynayya,
  Stufe 36 Priesterin, Sturmwind"), reads the live realm list for all
  regions and languages, and reads error/confirmation popups out loud
  verbatim. Selection happens by clicking the recognized text directly -
  the old slow arrow-down scanning is gone.
- v1 (legacy, START.ahk in this folder): the previous pixel-only tool,
  kept as a fallback.
The tool never reads or writes the game's memory and never injects into
the game process. It looks at the screen and presses keys/clicks - the
same things a sighted player does.

Primary tested game version: WoW Classic Anniversary (Burning Crusade).
Cataclysm/Era/Retail remain selectable as an untested baseline - testers
and contributors welcome.

IMPORTANT:
Carefully follow the instructions below to set up the tool, otherwise it won't work.
If the tool isn't working, please consult the "Common problems when the tool doesn't work" section below.
If you need help, feel free to ask in our Discord: https://discord.gg/FsfKeqxZV4

# Setting up the tool (automatic)
The Sku installer (https://sku75.github.io/Sku-WoW-Addon-TBC/) sets up
everything: the tool, the login-screen textures, the readable font, the
AutoHotkey runtimes, and a "WoW Login Tool" shortcut on the desktop and in
the Start menu. If you used it, you are done - skip to "Using the tool".

# Setting up the tool (manual)
1. AutoHotkey: v2 of the tool needs AutoHotkey v2, the legacy v1 tool needs
   AutoHotkey v1.1. Download from https://www.autohotkey.com/ (skip this
   step if the Sku installer put AutoHotkeyV2.exe/AutoHotkey.exe into the
   tool folder already).
2. Open the "CopyTheContentOfThisFolderToInterface" folder in the WoW Login Tool folder you've downloaded. There should be 5 folders in this folder ("BUTTONS", "DialogFrame", etc.).
3. Copy all 5 folders.
4. Browse to the WoW game files. Depending on your setup, this could be "C:\Program Files (x86)\World of Warcraft".
5. In the WoW game files, open the folder for the version of the game you want to play:
	- for Classic Anniversary (Burning Crusade), open "_anniversary_"
	- for Classic Cataclysm, open "_classic_"
	- for Retail open "_retail_"
	- for Classic Era open "_classic_era_"
6. Inside this folder, open the Interface folder.
7. Paste the 5 folders you copied in step 2 into the Interface folder. Important: overwrite any existing files and folders!
8. Recommended: install the readable font override. Run (as administrator)
   the script fonts\install_wow_fonts.ps1 from the tool folder, passing your
   client folder if it is not the Anniversary default. This makes the game's
   text much easier for the OCR (and for low-vision players) to read.
9. Run the tool: for v2 run "v2\START.ahk" (with AutoHotkey v2); for the
   legacy tool run "START.ahk" (with AutoHotkey v1).
10. There will be a setup on the first start. Choose the correct settings and follow the instructions.
11. You're done.

# What does the tool do?
The tool adds audio accessibility to the World of Warcraft login experience. It provides an audio interface for creating characters, choosing servers, etc. 
The tool has three modes: Pause, Login and Play. 
When you start the tool, it will be in Pause mode, waiting in the background and doing nothing.
When it detects the World of Warcraft game window, i.e. when you start the game or tab into the game that's already running, it becomes active and initialises.
The tool will automatically switch modes depending on whether you are in the login screen or the game world. 
In Login mode, you can use an audio menu to select characters and enter the game world, create new characters, change servers, or delete characters.
In Play mode, you can use NUMPAD 7 to left-click at your feet in the game world, or NUMPAD 8 to right-click. (This feature isn't enabled for Retail.)

# Common problems when the tool doesn't work
Most issues are caused by screen overlays that prevent the WoW Login Tool from recognising the WoW game screen.
- If you are in a Discord voice channel, Discord will display an overlay of all channel members at the top left of your screen. This overlay blocks the login tool. You should disable this feature in Discord. In Discord, go to User Settings > Game Overlay, and toggle Enable in-game overlay to Off.
- If you have an Nvidia graphics adapter, there may be an overlay at the top right of your screen showing the status of your graphics adapter. This is caused by an Nvidia tool that could be installed by default with your graphics adapter setup. This overlay blocks the WoW login tool. You can try hiding the overlay using the default Nvidia Alt+R shortcut.
- If you have increased or decreased the brigthness for Windows and/or the game, using HDR, or some high contrast setting (or any other setting that could affect colors), try to reset to the default or disable it. The tool depends on specific textures to have specific colors to recognize the game window. HDR/high contrast/etc. is changing them, leading to the tool don't working anymore.
- If neither of these fixes the problem, please check that you've copied the folders from CopyTheContentOfThisFolderToInterface to the correct game folder.
If all this isn't helping, please feel free to join our Discord server and ask for help: https://discord.gg/FsfKeqxZV4

# Using the tool
Important: Do not press any keys while the tool is working (it will play the blip, blip sound). Do not move the mouse or click while the tool is running.
Start the tool via the "WoW Login Tool" shortcut (or v2\START.ahk). The first time you start it, it will ask you to do a quick setup.
Use the left and right arrow keys to navigate to the submenu of an item.
Use the up and down arrow keys to navigate to the previous or next item in the audio menu.
Use the Enter key to choose a menu item.
To exit the tool, press alt + escape.
Each time you tab out of the game (Pause mode) and back in (Login mode), the tool needs to initialise. This is by design. Just wait for the audio menu to come up.
v2 announces your characters by their real name, level, class and zone, read
live from the screen. (The legacy v1 tool refers to characters by numbers
only: Character 1, 2, etc.)

# Keys
Arrow keys: navigate in the audio menu
Page up and down: navigate ten entries up or down in the audio menu
Enter: execute current audio menu item
Alt + escape: terminate the tool
Alt + f1: switch mode

# Updating the tool
Go to https://duugu.github.io/Sku and check the Updates section of this page to see if there is an update available. Download the update and follow the steps in "Setting up the tool" above.

# Resetting the tool
1. Exit the tool if it is running (alt + escape).
2. Open the "data" folder in your WoW Login Tool folder.
3. Delete the file named settings.ini.
4. Launch the tool. The setup will start.

# What's new for experienced wow menu users
- The tool works for all versions of the game: Cataclysm, Retail and Classic Era
- There is only one tool for all game versions, regions and languages. The tool will guide you through a quick setup to select the correct game, region, etc. on first start.
- The tool is (or can be) localised for all languages supported by the game.
- Page up and down navigates 10 items up or down in menus.
- Audio output is via SAPI.

# Providing translations
Open the Excel spreadsheet data\localization\translations.xlsx in your WoW Login Tool folder and follow the instructions on the Instructions tab.

# Release Notes
	r2.0 (OCR rework)
		- New v2 driver (AutoHotkey v2 + SkuLoginSense helper): the tool now SEES the
		  screen. Window capture (Windows.Graphics.Capture) + Windows OCR, fully
		  offline, out-of-process (never touches the game's memory).
		- Real character names, levels, classes and zones in the character menu;
		  selection clicks the recognized entry directly (no more arrow-down scanning).
		- Realm switching reads the live realm list - all regions and languages work,
		  the hardcoded realm tables are gone.
		- Popups are read out loud verbatim; the delete confirmation types the
		  localized keyword for you (now also French, Russian, Spanish).
		- Redesigned login-screen textures: dark red buttons and a dark blue selection
		  bar instead of pure red/white - readable for the OCR and for low-vision
		  players. Copy CopyTheContentOfThisFolderToInterface again when updating!
		- Readable font override (Atkinson Hyperlegible) ships in fonts\ and is
		  installed automatically by the Sku installer.
		- SAPI fixes: no more voice-swap race, deliberate interrupt-vs-queue behavior,
		  output device configurable in settings.ini (gAudioOutputMatch=, empty =
		  system default), errors are logged to log.txt.
		- The addons menu was removed (the Sku installer enables addons); "select
		  region" is back as main menu item 9.
		- The legacy v1 tool is still included as a fallback (START.ahk).

	r1.16
		- Fixed a bug with character creation on Classic Era.

	r1.15
		- Second try to fix the Retail Outdated Addons bug.

	r1.14
		- Fixed a bug with the Outdated Addons warning in Retail that should be auto clicked away by the tool.

	r1.13
		- Tried to fix an issue with some screen resolutions and retail.

	r1.12
		- Added a log (log.txt in scripts root folder) to make troubleshoting easier. The existing log content is deleted on each script start.

	r1.11
		- Added a key bind to take a full screen screenshot and add it to the Windows clipboard: control + alt + f2

	r1.10
		- Added low res textures, hopefully making the tool work with retail and low screen resolutions.

	r1.9
		- Updated the tool for Classic Era, Classic Cataclysm, and Retail. Don't forget to copy the contents of CopyTheContentOfThisFolderToInterface and overwrite the existing files!
		- Retail specific: if any of your favorite character slots is empty (ignore this, if you don't know what favorite slots are), then the tool will move characters up until all fav slots are used.
		- Issues and bugs are possible. Please report them.
		- Known issues:
			- In era/cata processing the character selection screen can take quite a while (one minute or more) for if there is no existing character on the selected server
			- In retail some servers are locked for players without existing characters on them. The tool can't detect them. They can be selected. But creating a character will fail and the tool will report an incorrect character name.

	r1.8
		- Tried to fix the only first character in the list is recognized issue that some users have. As the root cause of that issue still is unclear, it's just a try. Any feedback if it is working now is highly appreciated.
		- Added an 9th main menu entry Version without a submenu to output the current WoW Login Tool version.

	r1.7
		- Fixed an issue with switching to realms > 17 in Classic ERA.
		- Fixed an issue where the first realm name in some switch server lists was empty.
	r1.6
		- Tried to fix the contract accept feature for low resolutions
		- Some translation fixes
		- Added Autohotkey download instruction to readme
	r1.5
		- Initial public release
	r1.4
		- Russian translation added
		- Spanish translation added
	r1.3
		- Changed the sapi voice selection to leave the selected system voice unmodified
	r1.2
		- Removed the numpad 7 and 8 key binds for retail
		- Added the "Common problems when the tool doesn't work" section to the readme
		- French translation added
	r1.1
		- Bug fixes
		- German translation added
	r1.0
		- Initial release