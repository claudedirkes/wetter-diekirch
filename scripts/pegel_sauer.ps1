# Holt Pegelstand (Messung) und Prognose der Sauer bei Diekirch von inondations.lu
# (Administration de la gestion de l'eau, Luxemburg) und speichert beides gemeinsam
# als data/pegel/diekirch.json für die Webseite.
#
# Warum ein Job? Die Quelle schickt keinen CORS-Header, der Browser darf die Dateien
# von der Wetterseite aus nicht direkt laden. Der GitHub-Job holt sie stattdessen.
#
# Quellen (öffentliche JSON-Dateien, Waasserstand in cm):
#   Messung:  /content/dam/inondations/ctie/datas/Diekirch.json   (15-min-Werte, letzte 7 Tage)
#   Prognose: /percentile/diekirch-p10|p30|p50|p70|p90.json         (Stundenwerte, ca. 2 Tage)
#
# Start:  pwsh scripts/pegel_sauer.ps1

$ErrorActionPreference = 'Stop'
$basis = 'https://inondations.public.lu'
$ziel  = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'data') 'pegel'
$kultur = [System.Globalization.CultureInfo]::InvariantCulture

# Zeitstempel als UTC-Text "2026-10-23T05:45Z" (PowerShell wandelt ISO-Zeiten teils selbst in DateTime um)
function ZuUtc($t) {
    if ($t -is [datetime]) { $d = $t.ToUniversalTime() }
    else { $d = [datetimeoffset]::Parse([string]$t, $kultur).UtcDateTime }
    return $d.ToString("yyyy-MM-dd'T'HH:mm'Z'", $kultur)
}

# Lädt eine Datei und gibt die Liste [Zeit, Wert] zurück
function HoleReihe($pfad) {
    $antwort = Invoke-RestMethod -Uri ($basis + $pfad) -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 60
    $eintrag = @($antwort)[0]                      # Datei ist eine Liste mit einem Eintrag (oder ein Objekt)
    $reihe = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $eintrag.data) {
        if ($null -eq $p[1]) { continue }
        $reihe.Add(@((ZuUtc $p[0]), [double]$p[1]))
    }
    if ($reihe.Count -eq 0) { throw "Keine Werte in $pfad" }
    return , $reihe
}

try {
    $ergebnis = [ordered]@{
        quelle    = "Administration de la gestion de l'eau, Luxembourg – inondations.lu"
        station   = 'Diekirch (Sauer)'
        einheit   = 'cm'
        abgerufen = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm'Z'", $kultur)
    }
    $ergebnis['gemessen'] = HoleReihe '/content/dam/inondations/ctie/datas/Diekirch.json'
    $prognose = [ordered]@{}
    foreach ($p in 'p10', 'p30', 'p50', 'p70', 'p90') {
        $prognose[$p] = HoleReihe "/percentile/diekirch-$p.json"
        Start-Sleep -Seconds 1
    }
    $ergebnis['prognose'] = $prognose

    New-Item -ItemType Directory -Force -Path $ziel | Out-Null
    $json = $ergebnis | ConvertTo-Json -Depth 6 -Compress
    [System.IO.File]::WriteAllText((Join-Path $ziel 'diekirch.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    $g = $ergebnis['gemessen']
    Write-Host ("Pegel Diekirch: {0} Messwerte, neuester {1} = {2} cm; Prognose {3} Werte" -f $g.Count, $g[$g.Count - 1][0], $g[$g.Count - 1][1], $prognose['p50'].Count)
}
catch {
    # Quelle nicht erreichbar: alte Daten bleiben stehen (die Webseite zeigt das Alter der Messung an)
    Write-Warning ("Pegel Diekirch konnte nicht geladen werden: " + $_.Exception.Message)
}
