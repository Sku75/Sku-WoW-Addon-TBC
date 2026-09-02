on run
	-- A process-level restart is the Hammerspoon equivalent of reloading an
	-- AutoHotkey script and also works when the menu-bar app is unresponsive.
	do shell script "/usr/bin/killall Hammerspoon >/dev/null 2>&1 || true; /bin/sleep 1; /usr/bin/open -gja '/Applications/Hammerspoon.app'"
	delay 1
	display notification "Hammerspoon-Konfiguration wurde geladen." with title "Sku Login Tool"
end run

