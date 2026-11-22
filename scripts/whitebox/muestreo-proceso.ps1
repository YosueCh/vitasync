# Muestrea CPU y memoria de un proceso cada 500 ms durante N segundos y las guarda en CSV (Práctica 11, fase 5).
#   powershell -File muestreo-proceso.ps1 -Pid 1234 -Segundos 30 -Salida muestreo.csv
param([int]$ProcesoId, [int]$Segundos = 30, [string]$Salida)
$nucleos = [Environment]::ProcessorCount
$p = Get-Process -Id $ProcesoId -ErrorAction Stop
$cpuAnterior = $p.TotalProcessorTime.TotalMilliseconds
$t0 = Get-Date
"segundo,cpu_porcentaje,memoria_mb,hilos" | Out-File -FilePath $Salida -Encoding ascii
$anterior = $t0
while (((Get-Date) - $t0).TotalSeconds -lt $Segundos) {
  Start-Sleep -Milliseconds 500
  $p = Get-Process -Id $ProcesoId -ErrorAction SilentlyContinue
  if (-not $p) { break }
  $ahora = Get-Date
  $cpu = $p.TotalProcessorTime.TotalMilliseconds
  $usoCpu = 100.0 * ($cpu - $cpuAnterior) / (($ahora - $anterior).TotalMilliseconds * $nucleos)
  $cpuAnterior = $cpu
  $anterior = $ahora
  $linea = "{0:N1},{1:N1},{2:N1},{3}" -f (($ahora - $t0).TotalSeconds), $usoCpu, ($p.WorkingSet64 / 1MB), $p.Threads.Count
  $linea.Replace(',', ';').Replace(';', ',') | Out-File -FilePath $Salida -Append -Encoding ascii
}
