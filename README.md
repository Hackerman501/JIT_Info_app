# iOS Info App

Eine schnelle System-/Debug-Info-App für iOS. Zeigt alles Wichtige über dein Gerät
und die beiden wichtigsten Sideloading-Werte:

- **JIT** (On/Off)
- **Extended Memory** (On/Off)

Die App hat **drei Modi** (oben umschaltbar):

- **Normal** – nur die Infos, die ein Sideloader wirklich braucht: JIT-/Extended-Memory-Status
  inkl. Grund, Gerätename/-modell, iOS-Version und freier Speicherplatz.
- **Experte** – deutlich erweitert: zusätzlich alle JIT-/Memory-Checks (Flags),
  CPU/RAM, Akku, Display, Netzwerk, Locale und App-Version.
- **Dev** – alles, für Entwickler: zusätzlich Kernel-Build, SoC/Board, CPU-Frequenz,
  RLIMIT-Werte, VM-Statistiken, PID/PPID, Executable-Pfad und Entitlement-Präsenz.

> **Mindestanforderung:** iOS 16.1 (Live Activities, Lockscreen-Widgets, Charts, App Intents).

## Features

- **Live Activity** – der JIT-/Memory-Status läuft als Live Activity auf dem Sperrbildschirm
  und in der Dynamic Island (in den Einstellungen abschaltbar, per Kurzbefehl steuerbar).
- **Widgets** – Home-Screen-Widgets (Small/Medium) und iOS-16-Lockscreen-Widgets
  (Rectangular, Circular, Inline) mit Live-Status aus der App Group.
- **App Intents / Kurzbefehle** – JIT-Status, Uptime, Geräteinfo, Speicher, Akku abfragen
  sowie Live Activities starten/stoppen.
- **Prozessliste** – sortier- und durchsuchbar, mit Detailansicht (PID, PPID, CPU, RAM, virtueller Speicher).
- **Alternative App-Symbole** – Farbe, Dunkel und Tinted direkt in den Einstellungen wählbar.

## Was die App erkennt

### JIT
- `csops` Flag `CS_DEBUGGED` (Debugger hängt → JIT erlaubt)
- `sysctl KERN_PROC` / `P_TRACED` (Debugger)
- Entitlement `com.apple.security.cs.allow-jit`
- Entitlement `dynamic-codesigning`
- Sysctl `kern.jit_entitled`
- Jailbreak-Hinweise (writable Systempfade)

### Extended Memory
- Entitlement `com.apple.developer.kernel.increased-memory-limit`
- Entitlement `com.apple.developer.kernel.increased-debugging-memory-limit`
- Entitlement `com.apple.developer.kernel.extended-virtual-addressing`
- Geschätztes Speicherlimit = `os_proc_available_memory()` + `phys_footprint`,
  Anteil am physikalischen RAM (Verdict „Extended Memory" ab ≥ 70 %)
- `RLIMIT_AS` / `RLIMIT_DATA`, `phys_footprint`, VM-Statistiken

### Sonstiges
Gerät/Modell, iOS/Kernel-Version, CPU, RAM, Speicherplatz, Akku, Display,
Netzwerkstatus (NWPathMonitor), Locale, App/Bundle-Daten, PID/PPID.

## Zusätzliche Features

- **Empfehlung** – die App wertet iOS-Version, Jailbreak-Hinweise und JIT-Status aus
  und schlägt den passenden Weg vor (TrollStore 3, Xcode, Sideloader-„Enable JIT“ …).
- **JIT-Verlauf** – jeder JIT-Wechsel (z. B. Debugger andockt) wird mit Zeitstempel
  gespeichert (Experte/Dev) und beim Neustart wieder geladen.
- **Flag-Erklärungen** – hinter jedem Check-Row erklärt ein ⓘ-Button, was das Flag bedeutet.
- **Report teilen** – Share-Button oben rechts exportiert den kompletten Report als Text.
- **Einstellungen** – Update-Intervall wählbar (1–30 s) und Benachrichtigung bei
  JIT-Wechsel (Haptik + lokale Notification), alles wird gespeichert.
- **Sprache** – Deutsch oder Englisch direkt in der App wählbar („System“ = Gerätesprache).
- **Darstellung** – Hell/Dunkel direkt in der App umschaltbar („System“ = Geräte-Einstellung).
- **Kernel-Detail (Dev)** – `kern.iossupportversion`, `kern.osvariant_status`,
  `kern.securebootstate`, `kern.tfp.policy`, Cache-Größen und alle `csops`-Flags
  mit offiziellen Namen (inkl. korrektem `CS_DEBUGGED`-Bit).
- **Alle Entitlements (Dev)** – liest den `__TEXT,__entitlements`-Bereich des Binaries
  (Fallback über `csops CS_OPS_ENTITLEMENTS_BLOB`) und listet alle Entitlements auf.

Die Status-Cards aktualisieren sich im einstellbaren Intervall (JIT kann sich ändern,
wenn ein Debugger andockt).

## .ipa bauen

> **Hinweis:** Ein natives iOS-Binary (Mach-O) kann nur mit Xcode/macOS gebaut
> werden – nicht unter Windows/Linux. Deshalb brauchst du einen Mac oder GitHub
> Actions (kostenlos, baut in der Cloud).

### Weg 1: GitHub Actions (empfohlen, kein Mac nötig)
1. Repo auf GitHub pushen (workflow liegt in `.github/workflows/build-ipa.yml`).
2. Auf GitHub unter **Actions → „Build unsigned IPA“ → Run workflow** ausführen.
3. Im Run das Artifact **JITInfo-ipa** herunterladen → `.ipa` ist fertig.

### Weg 2: Lokal auf einem Mac
```bash
git clone <repo> && cd <repo>
./build_ipa.sh
```
Ergebnis: `JITInfo.ipa` (unsigniert). Das Script installiert XcodeGen automatisch
und setzt `CODE_SIGNING_ALLOWED=NO`.

## Sideloaden
Die `.ipa` ist **unsigniert** – der Sideloader signiert sie beim Installieren mit
deiner Apple-ID. Geeignet: AltStore, Sideloadly, SideStore, TrollStore (permanent).

## iOS 18.4+ Einschränkung
Seit iOS 18.4 akzeptiert der Kernel JIT über Debugger nur noch, wenn der Debugger
das Entitlement `com.apple.private.cs.debugger` hat (nur Xcode). Ohne TrollStore 3
oder Jailbreak ist JIT außerhalb von Xcode dort nicht mehr aktivierbar – die App
zeigt das dann als `OFF` ohne positive JIT-Quelle an.
