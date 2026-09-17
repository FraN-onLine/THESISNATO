param([string]$Scene = "", [int]$Seconds = 25)
$exe = 'C:\Autolab\_godot\Godot_v4.7-stable_win64.exe'
$proj = 'c:\Autolab\auto-lab'
$out = 'c:\Autolab\_run_out.txt'
$err = 'c:\Autolab\_run_err.txt'
$a = @('--path', $proj, '--headless')
if ($Scene -ne "") { $a += $Scene }
$p = Start-Process -FilePath $exe -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
if (-not $p.WaitForExit($Seconds * 1000)) { $p.Kill() }
Write-Output "EXIT=$($p.ExitCode)"