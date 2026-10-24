# MO PHONG tan cong do mat khau tu WINDOWS (de co IP tan cong that, vd 192.168.105.1)
# Chi dung tren he thong cua minh!
# Cach chay trong PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\simulate-bruteforce.ps1 -Url https://192.168.105.130 -User admin -N 30
param(
  [string]$Url = "https://192.168.105.130",
  [string]$User = "admin",
  [int]$N = 30
)
$jar = Join-Path $env:TEMP "bf_cookies.txt"
Remove-Item $jar -ErrorAction SilentlyContinue

$html = curl.exe -sk -c $jar -b $jar "$Url/admin/login" | Out-String
if ($html -match 'name="_csrf" value="([^"]+)"') { $tok = $Matches[1] }
else { Write-Host "Khong lay duoc trang dang nhap tai $Url/admin/login"; exit 1 }

Write-Host "Tan cong do mat khau: $N lan vao $Url/admin/login (user=$User)"
$stats = @{}
for ($i = 1; $i -le $N; $i++) {
  $code = curl.exe -sk -o NUL -w "%{http_code}" -c $jar -b $jar -A "BruteForceSim/1.0" `
    --data-urlencode "username=$User" --data-urlencode "password=matkhau_sai_$i" `
    --data-urlencode "_csrf=$tok" "$Url/admin/login"
  if ($stats.ContainsKey($code)) { $stats[$code]++ } else { $stats[$code] = 1 }
  Write-Host ("Lan {0,2} -> HTTP {1}" -f $i, $code)
  Start-Sleep -Milliseconds 200
}
Write-Host "---- Tong ket ----"
foreach ($k in $stats.Keys) { Write-Host "HTTP $k : $($stats[$k]) lan" }
Write-Host "Mo ngay (trong 1-2 phut): $Url/alertmanager/  va  Grafana > Explore > Loki"
