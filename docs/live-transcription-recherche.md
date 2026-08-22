# Live Transcription (Real-Time-Transkription) – Recherche & Konzept

**Stand:** 22.08.2026 · **Repo:** `Saik0s/Whisperboard` · **Lokaler Checkout:** `23e6d26` (= exakt GitHub `main`-HEAD)

## 1. Kernaussage (TL;DR)

**Die Live-Transcription ist bereits vollständig implementiert und auf `main` gemerged** (entwickelt Juni–Juli 2024, Released als Version 1.13.1, Juli 2024). Die README-Roadmap („Instant text: Real-time transcription is on our roadmap", ungehakt) ist **veraltet** – das Häkchen wurde nie nachgezogen.

Das Feature ist allerdings als **In-App-Kauf (IAP)** hinterlegt (`me.igortarasenko.Whisperboard.LiveTranscription`) und wird nur angezeigt, wenn das StoreKit-Produkt aufgelöst werden kann (`isProductFound == true`). D.h. der Aufwand ist nicht „von Null bauen", sondern:
- **Sofort nutzbar:** StoreKit-Produkt in App Store Connect einrichten bzw. Debug-Override nutzen → **praktisch kein Aufwand**
- **Wirklich gut machen:** Die Kern-Implementierung hat bekannte Performanz-Schwächen (O(n²)-Re-Transkription, Batch statt inkrementellem Decoding) → **einige Tage bis Wochen**

## 2. Forks (113 gesamt) – Ergebnis

| Fork | Bewertung |
|---|---|
| `deerlamp/Whisperboard` (13 Commits voraus, Apr 2026) | **Einziger Fork mit eigener Arbeit**, aber: TCA-/Swift-6-API-Migration (neue Observation-APIs, Sendable-Fixes). Berührt dieselben Dateien (u.a. `TranscriptionStream`, `LiveTranscriptionModelSelector`), fügt aber **keine neuen Live-Features** hinzu. |
| `bodhibyte/Whisperboard` (Feb 2026) | Nur Bot-artige „Update"-Commits, kein Inhalt. |
| `jgibbarduk`, `lytv`, `vijaim/xcribe`, `knfisd`, restliche ~107 | Reine Sync-Kopien bzw. alte Stände, keine Abweichung von `main`. |

**Fazit:** Kein Fork hat Live-Transcription über den Stand von `main` hinaus verbessert oder alternative Ansätze implementiert.

## 3. Pull Requests (5 gesamt) – Ergebnis

| PR | Status | Inhalt |
|---|---|---|
| #48 | offen | Xcode 16.3 / Swift 6.1 Build-Fix (`EXC_BAD_ACCESS`) – nicht Live-bezogen |
| #37 / #36 | gemergt | WhisperKit-Integration (Juni 2024) |
| #34 | gemergt | TCA-1.10-Upgrade |
| #33 | gemergt | Projekt-Setup-Migration |

**Fazit:** Es gibt **keinen PR** für Live-Transcription – der Autor hat das Feature direkt auf `main` committet (Commit-Reihe Juni–Juli 2024, siehe §5).

## 4. Issues (52 gesamt) – Ergebnis

Relevante Issues für Live-Transcription:

- **#2 „Great project"** (offen, 03/2023): expliziter Wunsch „transcribe the speech on time. Showing the text on the fly" (mit Screenshot). → **Dieser Wunsch ist heute im Code umgesetzt.**
- **#5 „Suggestions"** (offen, 03/2023): „Ability to see the transcribing … while it's still recording". Autor-Antwort damals: *„The realtime feature is still an open question, will do my best."*
- **#16 „transcription while app is running in background"** (offen): verwandt, aber **nicht** umgesetzt (Feature läuft nur bei offener App + aktiver Recording-Session).
- Alle anderen Issues betreffen Build, Modelle, Export etc.

**Fazit:** Die Feature-Anfragen existieren seit Anfang 2023; umgesetzt wurde es 2024 direkt am Hauptzweig.

## 5. Code-Analyse: Die Implementierung im Detail

### 5.1 Architektur (3 Schichten)

```
UI (TCA)                                  AudioProcessing (Actors)
─────────────────────────                 ──────────────────────────────
RecordScreenView                          RecordingTranscriptionStream  (TCA DependencyClient,
 └─ LiveTranscriptionModelSelector  ◄──►   kapselt beide Streams in AsyncThrowingStream)
    (Toggle, Modellwahl, IAP-Gating)        ├── RecordingStream  (actor)
 └─ RecordingView                            │    startRecording / pause / resume / stop
    (Live-Text, Model-Loading-Fortschritt,   │    schreibt AVAudioFile + Waveform
     blendet Waveform aus)                   └── TranscriptionStream (actor)
 └─ RecordingControlsView                        startRealtimeLoop / stopRealtimeLoop
    (aktiviert Live nur bei Kauf)                transcribeCurrentBuffer
                                                 + Modell-Download/Prewarm/Load
```

### 5.2 Kernlogik (`Sources/AudioProcessing/TranscriptionStream.swift`)

`startRealtimeLoop(callback:)`:
1. Baut `DecodingOptions` (Task `.transcribe`, Wort-Timestamps, Temperature-Fallbacks, `compressionRatioThreshold`, `logProbThreshold`, `noSpeechThreshold`, …)
2. Loop solange `state.isWorking`:
   - `transcribeCurrentBuffer`:
     - Liest **komplett akkumulierten** Puffer aus WhisperKit `AudioProcessor.audioSamples` (16 kHz Float)
     - Wartet, bis ≥ **1 s** neue Audiodaten vorhanden sind
     - **VAD** (energiebasiert): `AudioProcessor.isVoiceDetected(relativeEnergy, silenceThreshold: 0.3)`
     - Batch-Transkription des **gesamten** Puffers via `whisperKit.transcribe(audioArray:)` mit
       `clipTimestamps = [lastConfirmedSegmentEndSeconds]` (überspringt bereits bestätigte Anteile)
     - Segment-Bestätigung: `requiredSegmentsForConfirmation = 2` → letzten 2 Segmente bleiben „unconfirmed", Rest wird bestätigt
     - Early-Stopping über Compression-Ratio & Avg-LogProb im Progress-Callback
3. Zustandswechsel pusht per `didSet` auf den Main-Queue (`stateChangeCallback`)

### 5.3 Aufnahme (`RecordingStream.swift`)

- `AudioProcessor.startFileRecording` (WhisperKit): installiert Tap auf `AVAudioEngine.inputNode`, resampled auf 16 kHz mono, liefert Roh-Puffer
- Schreibt parallel `AVAudioFile` (für spätere finale Transkription/Playback), trackt Dauer + Waveform-Energie
- Pause/Resume via `resumeRecordingLive`

### 5.4 UI & Monetarisierung

- `LiveTranscriptionModelSelector`: Toggle `isLiveTranscriptionEnabled` + Modell-Picker; „Locked"-Ansicht mit Kauf-Modal, solange `liveTranscriptionIsPurchased == false`
- `PurchaseLiveTranscriptionModalView` + `PremiumFeaturesSection`: StoreKit `Product.products(for: [PremiumFeaturesProductID.liveTranscription])`, `Transaction.updates`, Restore, Preis-Anzeige
- `RecordingControlsView.createNewRecording()`: Live nur aktiv, wenn **Kauf bestätigt UND** Setting aktiv
- `RecordScreenView`: Selektor erscheint nur, wenn `premiumFeatures.isProductFound == true`
- `DebugSettings.swift`: enthält Override-Flags (`shouldOverridePurchaseStatus`, `liveTranscriptionIsPurchasedOverride`), wird aber **aktuell nirgends referenziert** (tote Debug-Mechanik)

### 5.5 WhisperKit-Fundstück

WhisperKit **0.7.2** (verwendete Version) bringt bereits einen fertigen Actor **`AudioStreamTranscriber`** mit – mit nahezu identischer Logik (realTimeLoop, transcribeCurrentBuffer, `requiredSegmentsForConfirmation: 2`, `silenceThreshold: 0.3`, `compressionCheckWindow: 60`, `useVAD`). Whisperboard hat dieses Muster (aus dem WhisperKit-Demo) **manuell nachgebaut**, um es mit eigener Modellverwaltung, Datei-Aufnahme und TCA-Dependencies zu verzahnen.

## 6. Verbleibende Lücken / bekannte Schwächen

1. **O(n²)-Verhalten:** Jeder Zyklus transkribiert den **gesamten akkumulierten Puffer** erneut (nur Start wird per `clipTimestamps` gekürzt). Latenz & Rechenzeit wachsen mit der Aufnahmedauer.
2. **Batch statt Streaming:** Nutzt kein inkrementelles Decoding / keinen Encoder-Reuse zwischen Iterationen (neuere WhisperKit-Versionen können das deutlich besser).
3. **Mindestlatenz:** Neuer Audio muss ≥ 1 s betragen, danach komplette Batch-Transkription.
4. **VAD nur energiebasiert:** verpasst leise Sprache, triggert bei Geräuschen.
5. **Unbegrenzter Speicher:** `audioSamples` wächst während der Aufnahme endlos.
6. **Keine Hintergrund-Transkription** (Issue #16 offen).
7. **Doku/README veraltet**, `DebugSettings` ungenutzt.

## 7. Konzept: Umsetzungsoptionen

### Option A – Feature freischalten (minimaler Aufwand, „Live-Transcoding sofort haben")

1. In App Store Connect das Produkt `me.igortarasenko.Whisperboard.LiveTranscription` anlegen/aktualisieren → `isProductFound` wird `true`, UI erscheint. *(Aufwand: ~1 Stunde + Review-Zeit)*
2. ODER lokal: `premiumFeatures.json` in den Documents Ordner schreiben (`{"liveTranscriptionIsPurchased": true}`) bzw. `DebugSettings` verdrahten → sofort testbar. *(Aufwand: Minuten)*
3. README-Roadmap-Häkchen nachziehen, ggf. `DebugSettings`-Override an den Kauf-Check anbinden.

### Option B – Echtzeit-Qualität verbessern (empfohlen, Kern-Engineering)

**Ziel:** Latenz & Rechenlast unabhängig von der Aufnahmedauer halten (echtes „Instant text").

1. **Sliding Window statt Voll-Puffer** (kleiner Eingriff)
   - Nach bestätigten Segmenten den verarbeiteten Pufferanteil abschneiden bzw. `audioSamples` trimmen.
   - Nur das Fenster ab `lastConfirmedSegmentEndSeconds` (plus Overlap für Kontext-Prefill) an `transcribe(audioArray:)` übergeben.
   - *Aufwand: ~1 Tag.*

2. **WhisperKit-Upgrade auf ≥ 0.10** für verbessertes Streaming
   - Neuere Versionen bieten besseres Streaming/inkrementelle APIs (`AudioStreamTranscriber`, Encoder-Caching), teils > Real-time-Faktor.
   - Aufbruch auf `whisperkit-coreml`-Modelle prüfen (Modell-URLs/Repo-Name, Projekt-Dependencies).
   - *Aufwand: ~2–4 Tage inkl. Regressionstests* (upstream-Fork `deerlamp` zeigt die nötige Migrationsarbeit bei TCA/Swift-6).

3. **VAD verfeinern**
   - Energie-VAD durch echte Sprachaktivitäts-Erkennung ergänzen bzw. Schwellwerte kalibrieren (`silenceThreshold`, `noSpeechThreshold`).
   - *Aufwand: ~1–2 Tage.*

4. **Memory-Management**
   - `audioSamples` nach Bestätigung trimmen; Obergrenze definieren.
   - *Aufwand: wenige Stunden.*

### Option C – Langfristig / ehrgeizig

- WhisperKit `AudioStreamTranscriber` direkt als Dependency einsetzen statt eigener Loop (Weniger eigener Code, Upstream-Fixes mitnehmen).
- **Hintergrund-Transkription** (Issue #16): Recording-Session im Hintergrund halten, Timer/„Speech in the background"-APIs (iOS) → größeres Projekt.
- Live-Token-/Wort-Highlighting beim Playback (Issue #5-Vorschlag), Sprachen-Schnellwahl, Cache-Prefill für Folge-Segmente.

## 8. Empfehlung

1. **Kein Greenfield-Build nötig** – die Funktion existiert.
2. Erster Schritt: Feature lokal freischalten (Option A) und die bestehende Qualität auf dem Zielgerät messen (tokensPerSecond-Anzeige ist im UI vorgesehen, aktuell auskommentiert).
3. Falls die Latenz bei längeren Aufnahmen stört → Option B Schritt 1 (Sliding Window) zuerst, dann Schritt 2 (WhisperKit-Upgrade) evaluieren.
