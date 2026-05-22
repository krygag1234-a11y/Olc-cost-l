# Windows PowerShell: run discover + merge + restart on VPS via SSH alias "vpsy"
# Usage:
#   .\win-apply-discover.ps1 -Url "https://www.bbc-doctorwho.ru/season-7/episode-7/"
#   .\win-apply-discover.ps1 -HtmlFile "C:\Users\you\page.html"
param(
  [string]$Url = "",
  [string]$HtmlFile = "",
  [string]$SshHost = "vpsy"
)

$ErrorActionPreference = "Stop"
$remote = "/opt/Olc-cost-l/scripts"

if ($HtmlFile -ne "") {
  if (-not (Test-Path $HtmlFile)) { throw "File not found: $HtmlFile" }
  $name = Split-Path $HtmlFile -Leaf
  scp $HtmlFile "${SshHost}:/tmp/$name"
  ssh $SshHost "sudo bash $remote/discover-page-hosts-from-html.sh /tmp/$name && sudo bash $remote/fetch-ru-direct-domains.sh && sudo systemctl restart olcrtc-manager && echo OK"
} elseif ($Url -ne "") {
  ssh $SshHost "sudo bash $remote/discover-page-hosts.sh '$Url' && sudo bash $remote/fetch-ru-direct-domains.sh && sudo systemctl restart olcrtc-manager && echo OK"
} else {
  Write-Host "Provide -Url or -HtmlFile"
  exit 1
}
