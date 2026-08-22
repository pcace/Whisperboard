# Konzept: Live-Übersetzung (Live-Transkription mit Zielsprache)

**Stand:** 22.08.2026 · **Basis:** Whisperboard (Fork `pcace/Whisperboard`) mit funktionierender Live-Transkription

## 1. Ausgangslage

Die Live-Transkription ist bereits vollständig implementiert und läuft auf dem Gerät:

- **`TranscriptionStream`** (Actor): VAD-basierte Echtzeit-Transkription, Segment-Bestätigung, Modell-Handling
- **`LiveTranscriptionModelSelector`**: Toggle + Modellwahl (multilinguale Modelle markiert)
- **`Settings`**: `voiceLanguage` (Eingabesprache), `parameters: TranscriptionParameters`
- **WhisperKit 0.7.2** mit `DecodingTask.transcribe` / `.translate`

**Was fehlt:** Die Option, eine **Ausgabesprache** (Zielsprache) für die Live-Transkription zu wählen – also echte Übersetzung in Echtzeit.

## 2. Wichtige technische Grundlage: Was Whisper kann

Whisper unterstützt zwei Decoding-Tasks:

| Task | Bedeutung | Einschränkung |
|---|---|---|
| `transcribe` | Text in der Eingabesprache | keine |
| `translate` | **Übersetzung ins Englische** | **nur Englisch** als Zielsprache |

> ⚠️ **Kern-Erkenntnis:** Whisper kann **nur Englisch** als Zielsprache (`translate`). Für beliebige Zielsprachen braucht es einen **zusätzlichen Übersetzungsschritt** nach der Transkription.

Der App-Code hat `task: DecodingTask = .transcribe` als Konstante in `TranscriptionStream.State` – die Variable müsste dynamisch werden.

## 3. Ziel-Szenarien

1. **Live-Gespräch mit englischem Gegenüber** → Whisper `translate` (kein Zusatzaufwand)
2. **Live-Übersetzung in beliebige Sprache** (z. B. Deutsch → Spanisch) → Transkription + Übersetzungs-Engine
3. **Nebenbei-Mitschnitt:** Transkription bleibt gespeichert, Übersetzung nur live angezeigt

## 4. Optionen für die Übersetzungs-Engine

### Option A – Whisper `translate`-Task (nur Englisch)
- **Wie:** `DecodingTask` von `.transcribe` auf `.translate` umschalten; Output-Sprache ist fix Englisch.
- **Vorteile:** Kein neues Package, keine Netzwerk/API-Key, komplett offline, sofort nutzbar.
- **Nachteile:** Nur Englisch; Qualität = Whisper-Übersetzung (gut, aber nicht DeepL-Niveau).
- **Aufwand:** ~0,5–1 Tag
- **Einsatz:** Englisch als Zielsprache; Baseline für alles Weitere.

### Option B – On-Device-Übersetzung via Apple Translation Framework (iOS 17.4+)
- **Wie:** `TranslationSession` / `LanguageAvailability` aus dem `Translation`-Framework. Segment-weise Übersetzung der bestätigten Live-Segmente.
- **Vorteile:** **On-device & kostenlos**, ~20+ Sprachen, privat (kein Netzwerk), gut mit Streams kombinierbar (segment-weises Übersetzen).
- **Nachteile:** Setzt **iOS 17.4+** voraus (App-Deployment ist iOS 16 → `#available`-Check + Fallback nötig); erstmaliger Sprachen-Download (~100–500 MB pro Sprachpaar); Qualität solide, aber unter Cloud-Niveau.
- **Aufwand:** ~2–4 Tage
- **Einsatz:** **Empfohlener Standard-Weg** für beliebige Zielsprachen.

### Option C – Cloud-Übersetzungs-API (OpenAI, DeepL, Google)
- **Wie:** Bestätigte Segmente batch-weise an API senden, Ergebnis im Stream anzeigen.
- **Vorteile:** Beste Qualität, alle Sprachen, kein On-Device-Download.
- **Nachteile:** Netzwerkpflicht, API-Key + Kosten, Latenz pro Batch, Datenschutz (Audio→Text geht raus).
- **Aufwand:** ~2–3 Tage + Backend/Key-Setup (im App-Code gibt es bereits ein `Secrets`-Schema für Keys)
- **Einsatz:** Optional als Qualitäts-Stufe, wenn Netzwerk vorhanden.

### Option D – On-Device-Übersetzungsmodell (NLLB / mBART / Small100 via CoreML)
- **Wie:** Eigenes Übersetzungsmodell als CoreML-Paket herunterladen, analog zum Whisper-Modell-Handling.
- **Vorteile:** Offline + beliebige Sprachen + privat.
- **Nachteile:** Hoher Aufwand (Modell-Konvertierung, Download-Management, RAM), Qualität je nach Modell.
- **Aufwand:** ~1–2 Wochen
- **Einsatz:** Nur wenn Apple-Framework nicht reicht (z. B. ältere iOS-Versionen, exotische Sprachen).

## 5. Empfohlene Architektur (Option A + B kombiniert)

```
Aufnahme (Mikrofon)
   │
   ▼
TranscriptionStream (bestehend)
   ├─ Whisper transcribe (Eingabesprache)   ← bleibt
   ├─ wenn Zielsprache == Englisch:
   │    → DecodingTask.translate            ← Option A (Whisper nativ)
   └─ wenn Zielsprache != Englisch:
        → bestätigte Segmente → Apple Translation (iOS 17.4+)   ← Option B
                                  ↓
                        übersetzter Text → UI
```

### Neue Bausteine

**1. Settings-Erweiterung** (`Settings.swift`)
```swift
public var isLiveTranslationEnabled: Bool = false   // Toggle
public var outputLanguage: String? = nil            // Zielsprache ("de", "es", …)
```
Mit Codable-Support (analog zu bestehenden Feldern).

**2. Übersetzungs-Client** (neuer TCA-Dependency-Client, analog `RecordingTranscriptionStream`)
- `LiveTranslationClient` mit:
  - `translate(segments:targetLanguage:) async throws -> [String]`
  - Live-Implementierung: Apple `TranslationSession` (iOS 17.4+) bzw. Whisper-`translate`-Shortcut (Englisch)
  - Stub/Test-Implementierung

**3. TranscriptionStream-Erweiterung**
- `State.task` von `let` → `var`, dynamisch: `.translate` wenn Zielsprache == Englisch, sonst `.transcribe`
- Nach Segment-Bestätigung: bestätigte Segmente an `LiveTranslationClient` geben, Übersetzung in den `state.unconfirmedText`/`confirmedSegments`-Fluss einhängen
- Nur **bestätigte** Segmente übersetzen → geringe Latenz, keine Neu-Übersetzung

**4. UI-Erweiterungen**
- `LiveTranscriptionModelSelector`: 
  - Toggle „Live Translation"
  - Zielsprachen-Picker (Liste aus `Constants.languages`)
  - Hinweis: multilinguales Modell nötig (`.en`-Modelle ausblenden/blockieren)
- `RecordingView`: Live-Text zeigt Übersetzung; Original-Transkription weiterhin gespeichert
- `SettingsScreen`: Abschnitt „Translation" (wenn gewünscht)

**5. Model-Handling**
- `.en`-Modelle (tiny.en, base.en, …) können **nicht** übersetzen → bei aktivierter Übersetzung automatisch auf multilinguales Modell wechseln oder Warnung zeigen
- `selectedModelName` + Modell-Info (`isMultilingual`) existieren bereits in der UI

## 6. UI-Flow (Vorschlag)

```
[🎙 Record-Screen]
  Live Transcription: [ON]
  └─ Model: [small (multilingual)] ▸
  Live Translation:   [OFF ▸ ON]
  └─ Output language: [English ▸ Español ▸ Deutsch ▸ …]

Während der Aufnahme:
  [ Original:   "Hallo, wie geht es dir?" ]
  [ Übersetzt:  "Hello, how are you?"     ]   ← nur bei ON
```

## 7. Umsetzungsphasen

| Phase | Inhalt | Aufwand |
|---|---|---|
| **1** | Whisper-`translate`-Task anbinden (Toggle + Englisch-Ziel) | ~0,5–1 Tag |
| **2** | Apple Translation Framework (iOS 17.4+): beliebige Zielsprache, segment-weises Übersetzen, Sprach-Download-Management | ~2–4 Tage |
| **3** | Model-Restriktionen (multilingual) + Feinschliff UI/Fehlerzustände | ~1 Tag |
| **4** (optional) | Cloud-API als Qualitäts-Option | ~2–3 Tage |

**Gesamt (Phase 1–3): ca. 4–6 Tage** für eine saubere, offline-fähige Live-Übersetzung.

## 8. Risiken & offene Punkte

1. **iOS 17.4+ Pflicht** für Apple Translation → Fallback auf Whisper-`translate` (Englisch) für ältere Geräte
2. **Erstmaliger Sprach-Download** (~100–500 MB) → Fortschrittsanzeige, Vorab-Download in Settings
3. **Latenz:** Übersetzung nur bestätigter Segmente hält den Live-Strom flüssig; Whisper `translate` verdoppelt die Decode-Zeit (Modellgröße beachten)
4. **Qualität:** Apple Translation < Cloud; für Meetings ggf. Cloud-API bevorzugt
5. **Modellgröße/RAM:** multilinguale Modelle sind größer; `tiny`/`small` für Live-Betrieb empfehlen
6. **`task`-Konstante:** `TranscriptionStream.State.task` muss von `let` auf `var` + dynamisch umgestellt werden (kleiner Refactor)

## 9. Empfehlung

1. **Phase 1 zuerst** (Whisper `translate`): liefert sofort Live-Übersetzung ins Englische – minimale Änderung, kein neues Framework.
2. **Phase 2** (Apple Translation) nur, wenn Englisch nicht reicht: größter Mehrwert für „beliebige Zielsprache" bei Offline-Betrieb.
3. Cloud-API (Phase 4) als späteres Qualitäts-Upgrade, nicht als Basis.
