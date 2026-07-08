SkuMapper Addon

This addon is used to build and edit map data for the Sku addon.
For more information join the Sku Discord server: https://discord.gg/FsfKeqxZV4

------------------------------------------------
Key bindings (no default bindings, set them up via Game Settings > Interface > Key bindings > Other)
	- Open Sku minimap
	- Add normal waypoint (same as CTRL + LEFT MOUSE)
	- Add large waypoint
	- NEW Select waypoints under mouse (same as CTRL + ALT + MIDDLE MOUSE)
	- Rename an existing waypoint (same as CTRL + MIDDLE MOUSE)
	- Cancel current recording/deleting	
	- Show map data on default game minimap
	- Toggle default game minimap size
	- Undo
	- Unselect waypoints

------------------------------------------------
Mouse buttons
	Creating...
		CTRL + LEFT MOUSE
			Start/end creating a new link
		CTRL + SHIFT +	LEFT MOUSE
			Create a new custom waypoint
		CTRL + SHIFT + ALT + LEFT MOUSE	
			Add a new comment to an existing waypoint

	Deleting...
		CTRL + RIGHT MOUSE
			Start/end deleting an existing link
		CTRL + SHIFT + RIGHT MOUSE
			Delete an existing custom waypoint
		CTRL + ALT + RIGHT MOUSE
			Delete all comments from an existing waypoint

	Modifing...
		CTRL + MIDDLE MOUSE
			Rename an existing custom waypoint
		CTRL + MOUSE 4
			Hold and drag to move an existing waypoint

	Selecting...
		CTRL + ALT + MIDDLE MOUSE
			In selection mode "mouse over": toggle selection for all mouse over waypoints
			In selection mode "start / end": set start point for selected routes
		CTRL + ALT + LEFT MOUSE
			In selection mode "start / end": set additional end point for selected routes

------------------------------------------------
Slash commands
	/sku import		import a text file with map data
	/sku export		output the map data for the text file
	/sku follow		set the sku minimap to follow
	/sku reset		reset all map data to the the default data (caution: all your work will be lost)
	/sku version	output the addon version
	/sku mmreset	reset the size and position of the sku minimap

------------------------------------------------
Release notes

r4.5
	- Uldum area fixed

r4.4
	- A lot of Spirit Healer waypoints added
	- Fixed the Molten Front area
	- Enhanced the overall performance
	- Map is auto set to Follow on moving to a different continent
	- Limited the maximum number of drawn waypoints and links with Current Contintent selected to 15k
	- Resticted the max zoom out factor with Current Contintent to a level that still can be handled by the UI

r4.3
	- Removed a lot of incorrect maps
	- Fixed bugs with the zones list
	- Removed a lot of decoration objects
	- Tried to fix Gilneas
	- Fixed Barrens
	- Fixed Strangle

r4.2
	- Added a "Unique only" button to the options, to show creatures and objects with a single spawn point only
		Linked creatures and objects are always shwon, no matter if it has one or multiple spawns.

r4.1
	- Initial Cata release

r3.4
	- Added a bunch of missing creature, quest, item, and object data for phase 3 & 4 from Questie.

r3.3
	- Fixed an issue with the new Blizzard options panel and key bindings.
	- Changed the map file format.

r3.2
	- Added a new key bind: Unselect waypoints
	- Tried to fix an issue with hyphens not working for filter terms
	- Fixed a bunch of errors with deselecting waypoints that could lead to lua errors

r3.1
	- Added a new key bind: Undo.
		That is to reverse the last action (create/delete waypoint, link, rename, select waypoints, etc.)
		The only exception is moving waypoints. That action can't be undone with the Undo shortcut.
		The Undo history stores up to 100 actions. If you're doing more than 100, the oldest will be removed. 
		The history will be cleared on logout/reload. So, you can undo 100 recent actions from the current session max.
		It is a complex feature. I have tested it, and it seems to work. However, issues are possible. Please carefully check if it is working as intended. 
		Please report any problem with the Undo feature asap. Thanks!

r3
	- Update to new map data structure and interface with named auto waypoints and layers for waypoints

r2.4
	- Updated the toc for Ulduar patch.

r2.3
	- There is a new input box to enter filter terms for waypoints. Found waypoints are shown in white with double size.

r2.2
	- Object waypoints (green): first 3 are now shown in yellow and the "limit" filter is applied to them
	- Added a check for existing names on renaming waypoints

r2.1
	- Added player coords to map

r2
	- Added updated data to item, quest, creature and object databases

r1.9
	- Fixed the missing sounds

r1.8
	- Fixed incorrect path data

r1.7
	- Fixed missing SkuDB link

r1.6
	- Bug fixes
	- Removed controls for recording special areas

r1.5
	- Added sounds
	- Added a key bind to cancel the current action (recording/deleting)