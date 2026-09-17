$exe = 'C:\Autolab\_godot\Godot_v4.7-stable_win64.exe'
$proj = 'c:\Autolab\auto-lab'
$scenes = @(
  'res://Testing/AlgorithmSelect.tscn',
  'res://Testing/TestRoom.tscn',
  'res://Testing/TestingGrounds.tscn',
  'res://Testing/AutomataWorkshopRoom.tscn',
  'res://Testing/TestPanelBillboard.tscn'
)
foreach ($s in $scenes) {
  $out = 'c:\Autolab\_s_out.txt'
  $err = 'c:\Autolab\_s_err.txt'
  Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
  $p = Start-Process -FilePath $exe -ArgumentList @('--path', $proj, '--headless', $s) -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
  if (-not $p.WaitForExit(14000)) { $p.Kill() }
  Start-Sleep -Milliseconds 400
  $e = if (Test-Path $err) { (Get-Content $err -Raw) } else { '' }
  if ($e -match 'SCRIPT ERROR|ERROR:|Parse Error') {
    Write-Output "FAIL $s"
    Write-Output $e
  } else {
    Write-Output "ok   $s"
  }
}