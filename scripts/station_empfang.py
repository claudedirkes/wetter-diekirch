"""
Nimmt Messwerte der eigenen ESP32-Wetterstation entgegen und speichert sie.

Der ESP32 schickt alle 10 Minuten per GitHub-API ein „repository_dispatch“-Ereignis.
Darin stecken die letzten Messungen (auch schon gesendete – so geht nichts verloren,
falls ein Durchlauf ausfällt). Doppelte Zeitpunkte werden hier zusammengeführt.

Eingabe (Umgebungsvariable PAYLOAD, JSON):
    {"werte": [["2026-10-10T08:50Z", 24.8, 42.0, 991.1, 0.0], ...]}
    Spalten: Zeit (UTC), Temperatur °C, Luftfeuchte %, Luftdruck hPa (Station), Regen mm seit letzter Messung

Ausgabe:
    data/station/<Jahr>.json   alle Werte des Jahres
    data/station/letzte.json   die letzten 48 Stunden (für die Webseite)
"""

import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

ZIEL = Path(__file__).resolve().parent.parent / "data" / "station"
SPALTEN = ["zeit_utc", "temp", "feuchte", "druck", "regen_mm"]
ZEIT = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\dZ$")
GRENZEN = [(-40, 50), (0, 100), (850, 1100), (0, 100)]   # plausible Bereiche


def pruefen(zeile):
    """Nur saubere Zeilen übernehmen: richtige Zeit, Zahlen im plausiblen Bereich."""
    if not isinstance(zeile, list) or len(zeile) != 5 or not ZEIT.match(str(zeile[0])):
        return None
    werte = []
    for wert, (lo, hi) in zip(zeile[1:], GRENZEN):
        if isinstance(wert, (int, float)) and lo <= wert <= hi:
            werte.append(round(float(wert), 2))
        else:
            werte.append(None)
    return [zeile[0]] + werte


def main():
    daten = json.loads(os.environ.get("PAYLOAD") or "{}")
    neu = [z for z in map(pruefen, daten.get("werte", [])[:500]) if z]
    print(f"{len(neu)} gültige Werte empfangen")
    if not neu:
        return
    ZIEL.mkdir(parents=True, exist_ok=True)

    for jahr in sorted({z[0][:4] for z in neu}):
        datei = ZIEL / f"{jahr}.json"
        alt = json.loads(datei.read_text())["werte"] if datei.exists() else []
        alle = {z[0]: z for z in alt}
        alle.update({z[0]: z for z in neu if z[0][:4] == jahr})
        datei.write_text(json.dumps({"spalten": SPALTEN, "werte": sorted(alle.values())},
                                    separators=(",", ":")))

    # letzte 48 Stunden (aus aktuellem und ggf. vorigem Jahr)
    grenze = (datetime.now(timezone.utc) - timedelta(hours=48)).strftime("%Y-%m-%dT%H:%MZ")
    letzte = []
    for datei in sorted(ZIEL.glob("[0-9][0-9][0-9][0-9].json"))[-2:]:
        letzte += [z for z in json.loads(datei.read_text())["werte"] if z[0] >= grenze]
    (ZIEL / "letzte.json").write_text(json.dumps({
        "quelle": "Eigene Wetterstation (ESP32 + BME280 + Misol-Regenmesser)",
        "spalten": SPALTEN, "werte": letzte}, separators=(",", ":")))


if __name__ == "__main__":
    main()
