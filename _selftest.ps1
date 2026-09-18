param([string]$Script = "res://Testing/_selftest_builder.gd", [int]$Seconds = 60)
$exe = 'C:\Autolab\_godot\Godot_v4.7-stable_win64.exe'
$proj = 'c:\Autolab\auto-lab'
$out = 'c:\Autolab\_self_out.txt'
$err = 'c:\Autolab\_self_err.txt'
Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
Get-Process -Name 'Godot_v4.7-stable_win64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$args = @('--path', $proj, '--headless', '--script', $Script)
$p = Start-Process -FilePath $exe -ArgumentList $args -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
if (-not $p.WaitForExit($Seconds * 1000)) { $p.Kill(); Write-Output "TIMEOUT" }
Write-Output "EXIT=$($p.ExitCode)"
Write-Output "=== OUT ==="
Get-Content $out -ErrorAction SilentlyContinue
Write-Output "=== ERR ==="
Get-Content $err -ErrorAction SilentlyContinue