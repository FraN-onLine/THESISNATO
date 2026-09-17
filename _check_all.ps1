$exe = 'C:\Autolab\_godot\Godot_v4.7-stable_win64.exe'
$proj = 'c:\Autolab\auto-lab'
$files = Get-ChildItem -Path $proj -Recurse -Include *.gd | Sort-Object FullName
Write-Output ("SCRIPTS: " + $files.Count)
$failed = 0
foreach ($f in $files) {
  $rel = 'res://' + $f.FullName.Substring($proj.Length + 1).Replace('\', '/')
  $o = & $exe --path $proj --headless --check-only --script $rel 2>&1 | Out-String
  if ($o -match 'Parse Error|SCRIPT ERROR|ERROR:') {
    $failed++
    Write-Output ("FAIL " + $rel)
    Write-Output $o
  } else {
    Write-Output ("ok   " + $rel)
  }
}
Write-Output ("FAILED: " + $failed)