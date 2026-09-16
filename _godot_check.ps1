param(
  [string]$Mode = "editor",
  [string]$Scene = "",
  [int]$Seconds = 8
)
$exe = 'C:\Users\acer\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
$proj = 'c:\Autolab\auto-lab'
$out = 'c:\Autolab\_godot_out.txt'
$err = 'c:\Autolab\_godot_err.txt'
$a = @('--path', $proj, '--headless')
if ($Mode -eq "editor") {
  $a += @('--editor', '--quit')
} elseif ($Mode -eq "check") {
  $a += @('--check-only', '--script', $Scene)
} else {
  if ($Scene -ne "") { $a += $Scene }
}
$p = Start-Process -FilePath $exe -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
if (-not $p.WaitForExit($Seconds * 1000)) { $p.Kill() }
Write-Output "EXIT=$($p.ExitCode)"