# 🏍️ MOTO TOURING NAV — SYSTEM ARCHITECTURE & BLUEPRINT

A high-performance, battery-efficient, eyes-free motorcycle touring navigation and intercom platform engineered for Android.

---

## 1. System Architecture Overview

```mermaid
graph TD
    subgraph Mobile Device (Android / Flutter)
        UI[Touring Cockpit UI]
        PocketMode[AMOLED Pocket Mode]
        
        subgraph Native Android Layer (Kotlin)
            FGS[MotoTouringForegroundService]
            WL[Partial WakeLock]
            AFM[AudioFocus & Ducking Manager]
            NL[NotificationListenerService]
            MSM[MediaSessionManager]
        end

        subgraph Core Services
            NavEngine[Offline Corridor & TTS Nav]
            TripTracker[Timestamp Arithmetic & Local SQLite]
            LiveKitClient[LiveKit WebRTC + Opus DTX]
            CanvasRenderer[Telemetry Image Canvas]
        end
    end

    subgraph External System
        Spotify[Spotify / YouTube Music / Local Media]
        Spatialflow[Spatialflow Android App / HUD]
    end

    subgraph Cloud Infrastructure
        SupabaseDB[(Supabase PostgreSQL + PostGIS)]
        SupabaseStorage[(Supabase Storage - Share Images)]
        LiveKitSFU[LiveKit SFU Server - Audio Intercom]
        CronJob[cron-job.org / Keep-Alive Ping]
    end

    UI --> NavEngine
    UI --> TripTracker
    UI --> LiveKitClient
    
    MSM <--> NL
    NL <--> Spotify
    
    FGS --> WL
    FGS --> AFM
    AFM -->|Ducks Volume| Spotify
    
    NavEngine -->|Speech Alerts| AFM
    LiveKitClient -->|Low Bitrate Opus| LiveKitSFU
    
    TripTracker -->|Post-Trip Batch Sync| SupabaseDB
    CanvasRenderer -->|Upload Snapshot| SupabaseStorage
    
    CronJob -->|Scheduled RPC Ping| SupabaseDB
    UI -->|Intent / Deep-link| Spatialflow
```

---

## 2. Audio Focus & Ducking Priority Matrix

| Level | Sound Source | Audio Attributes / Stream | Focus Request | Ducking Behavior |
|---|---|---|---|---|
| **Priority 1 (Highest)** | **Navigation TTS** (Turn-by-turn guidance) | `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE`, `CONTENT_TYPE_SPEECH` | `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` | Music automatically drops to 20-30% volume. Instantly restored when instruction completes. |
| **Priority 2** | **Squad Voice Chat** (LiveKit Intercom) | `STREAM_VOICE_CALL`, `MODE_IN_COMMUNICATION` | Dynamic mixing | Music ducked while peer voice activity is detected. |
| **Priority 3 (Lowest)** | **Universal Music Player** (Spotify, etc.) | `STREAM_MUSIC` | Passive listener | Yields volume immediately to Priority 1 and 2. |

---

## 3. Battery & Thermal Mitigation Strategy

1. **Pure Timestamp Arithmetic (Zero Background Loops):**
   - Standard navigation apps run periodic timer intervals (`setInterval(100ms)`) which force the CPU cores to stay awake in C0 power state.
   - Moto Nav records `startUnixMillis` at start, and `finishUnixMillis` at end:
     $$\Delta t = \frac{T_{\text{finish}} - T_{\text{start}}}{1000}$$
   - Between GPS breadcrumbs, the CPU is allowed to drop into deep C-states.

2. **AMOLED Pocket Mode:**
   - Turning off map rendering (which uses GPU shader passes, texture binding, and high 60-120Hz refresh rates) eliminates up to 70% of device thermal accumulation during hot daylight touring.
   - Screen turns 100% black (AMOLED pixels turned off), and double-tap gesture wakes the UI.

3. **Opus Low-Bitrate + DTX (Discontinuous Transmission):**
   - Voice room is configured to Opus 16 kbps mono.
   - When rider is silent, DTX completely stops sending UDP WebRTC audio packets, saving cellular radio battery and mobile data.
   - Hardware high-pass filter cuts motorcycle engine frequencies below 100 Hz.

---

## 4. Supabase Keep-Alive Configuration (Prevent Free Tier Auto-Pause)

Supabase free-tier databases enter an auto-pause state after 7 days without inbound requests. To prevent this during off-touring seasons:

1. In Supabase SQL Editor, run `supabase/schema.sql` to register:
   ```sql
   CREATE OR REPLACE FUNCTION public.ping_keep_alive() ...
   ```
2. Set up a free monitoring monitor on [cron-job.org](https://cron-job.org) or [UptimeRobot](https://uptimerobot.com):
   - **URL:** `https://<YOUR-PROJECT-REF>.supabase.co/rest/v1/rpc/ping_keep_alive`
   - **Method:** `POST`
   - **Headers:**
     - `apikey: <YOUR_SUPABASE_ANON_KEY>`
     - `Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>`
     - `Content-Type: application/json`
   - **Schedule:** Once every 3 days (e.g., `0 0 */3 * *`).
