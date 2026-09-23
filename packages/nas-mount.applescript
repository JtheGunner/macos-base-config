-- nas-mount: mount the NAS shares. Built by macos-base-config
-- (./bootstrap.sh extras) from packages/nas-mount.applescript and
-- NAS_MOUNT_SHARES - edit those, not this app. Finder takes the credentials
-- from the Keychain. Each share has its own try: one that is offline doesn't
-- stop the others.
tell application "Finder"
	repeat with share in {@@NAS_MOUNT_SHARES@@}
		try
			mount volume (share as text)
		end try
	end repeat
end tell
