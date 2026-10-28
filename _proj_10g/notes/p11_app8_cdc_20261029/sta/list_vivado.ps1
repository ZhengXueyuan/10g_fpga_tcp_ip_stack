Get-CimInstance Win32_Process -Filter "Name='vivado.exe'" | ForEach-Object {
  $cl = $_.CommandLine
  if ($cl.Length -gt 200) { $cl = $cl.Substring(0,200) }
  Write-Output ("PID=" + $_.ProcessId + " CL=" + $cl)
}
