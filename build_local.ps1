$cfg = ConvertFrom-Json $(Get-Content -Path .\localbuild.cfg -Encoding utf8 -Delimiter "this is a jank hack recommended by microsoft themselves.")
if ( -not (Test-Path -Path "$($cfg.disk_path)/OVERWRITABLE_SENTINAL"))
{
	echo "Missing a file named OVERWRITABLE_SENTINAL in the destination ($($cfg.disk_path)), refusing to do anything!"
	return
}

# Spooky!
Remove-Item "$($cfg.disk_path)/*" -Recurse -Exclude "OVERWRITABLE_SENTINAL"
Copy-Item -Path ".\disk_template\*" -Destination $cfg.disk_path -Recurse -Exclude "*.bak"