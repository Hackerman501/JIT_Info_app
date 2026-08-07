# JIT Info

Eine schnelle System-/Debug-Info-App für iOS. Zeigt alles Wichtige über dein Gerät
und die beiden wichtigsten Sideloading-Werte:

- **JIT** (On/Off)
- **Extended Memory** (On/Off)

## Was die App erkennt

### JIT
- `csops` Flag `CS_DEBUGGED` (Debugger hängt → JIT erlaubt)
- `sysctl KERN_PROC` / `P_TRACED` (Debugger)
- Entitlement `com.apple.security.cs.allow-jit`
- Entitlement `dynamic-codesigning`
- Sysctl `kern.jit_entitled`
- Jailbreak-Hinweise (writable Systempfade)
- **Laufzeit-Probe**: `mmap` RW-Seite → `mprotect(PROT_EXEC)` → Ausführung einer
  `RET`-Instruktion. Wenn das fault/trapped → JIT blockiert, wenn es läuft → JIT aktiv.

### Extended Memory
- Entitlement `com.apple.developer.kernel.increased-memory-limit`
- Entitlement `com.apple.developer.kernel.increased-debugging-memory-limit`
- Entitlement `com.apple.developer.kernel.extended-virtual-addressing`
- `os_proc_available_memory()` + Anteil an physikalischem RAM (Heuristik > 60 %)
- `RLIMIT_AS` / `RLIMIT_DATA`, `phys_footprint`, VM-Statistiken

### Sonstiges
Gerät/Modell, iOS/Kernel-Version, CPU, RAM, Speicherplatz, Akku, Display,
Netzwerkstatus (NWPathMonitor), Locale, App/Bundle-Daten, PID/PPID.

Die Status-Cards aktualisieren sich alle 2 Sekunden (JIT kann sich ändern, wenn
ein Debugger andockt).

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
zeigt das dann als `OFF` mit „mprotect rejected“ an.
