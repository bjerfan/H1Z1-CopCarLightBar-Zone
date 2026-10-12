ROTK - COP CAR AND LIGHT GAS PATCHES

QUICK GUIDE
1. Extract the entire ZIP folder.
2. Close ROTK/H1Z1.
3. Double-click "Apply Patches.cmd".
4. Select your ROTK installation folder (e.g. C:\Games\ROTK) and click OK.
5. Wait for SUCCESS (or "Already in the requested state"), then start the game.

Removes the cop car roof light bar and reduces toxic-gas haze.
The script finds Resources\Assets inside your selected game folder.
Apply, Restore, and Check ask each time. Cancel makes no changes.

To undo: close the game and run "Restore Original.cmd".
To check: run "Check patch status.cmd".
Keep the entire folder together, including files and any backups.
No Python or extra downloads required. Uses Windows PowerShell.

If a game update resets the changes, run Apply again. If the script reports
an unfamiliar asset version, it needs an updated patch package.

BEFORE AND AFTER
See images/cop-car-before-after.png for the original and patched car
geometry. This is a wireframe preview, not an in-game screenshot.

ASSET CHANGES AND RULES
Only selected .pack2 game asset archives and their internal indexes are
altered: cop-car geometry and toxic-fog rendering assets. The script does
not edit the game executable, inject into the running game, or alter
server-side damage or zone logic. It also creates local backups.
Asset-only changes do not by themselves establish that a mod is allowed
or not considered cheating. ROTK-specific approval has not been verified;
confirm permission with ROTK staff. See README.md for the policy reference.

By ZzeK
