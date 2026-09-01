# Performance profiling guide

This guide verifies the Phase 7 runtime targets on the reference M2 / 8 GB Mac.
Measurements are manual because GitHub Actions has neither a real Discord window
nor Screen Recording permission or Ollama model weights.

## Built-in content-free metrics

Starting a scan resets one bounded measurement session. Kotoverlay retains only
the newest 256 duration samples for each stage:

- `capture`: selecting and capturing the visible Discord window;
- `ocr`: Vision recognition for a changed frame;
- `translation`: the complete local pipeline for one changed snapshot.

The **Copy Diagnostics** action includes sample counts, average and maximum
milliseconds, changed/unchanged frame counts, and failure count. It never
includes source text, translations, author names, channel names, screenshots,
or raw OCR observations. Static Instruments signposts use the subsystem
`dev.niyy.Kotoverlay`, the system `PointsOfInterest` category, and these
interval names:

- `Discord capture`
- `Vision OCR`
- `Local translation`

These app metrics explain which stage is slow. Instruments remains the source of
truth for process CPU and memory.

## Recording with Instruments

1. Start Discord and Ollama, and select the validated `qwen3:1.7b` model.
2. Open `Kotoverlay.xcodeproj`, select **Kotoverlay > My Mac**, then choose
   **Product > Profile**.
3. Start with **Time Profiler**. Add **Points of Interest** to correlate CPU work
   with the three Kotoverlay signpost intervals.
4. Repeat the memory run with **Allocations**. Use the same Discord channel and
   window size so runs remain comparable.
5. Allow 60 seconds of warm-up before recording values.
6. At the end of each scenario, use **Copy Diagnostics** and save only its
   content-free output with the result table. Do not publish an Instruments trace.

Run these scenarios separately:

| Scenario | Duration | User action | Primary check |
| --- | ---: | --- | --- |
| Idle | 5 min | Leave the Discord window completely unchanged | Average Kotoverlay CPU below 2% over the final 3 min |
| Scroll | 2 min | Browse one active English channel normally | No stale work; capture/OCR intervals remain bounded |
| Translation | Until settled | Open a viewport with uncached English messages | Translation work stays sequential and UI remains responsive |
| Long run | 15 min | Alternate 1 min browsing and 2 min idle | No sustained memory growth after warm-up |

For the long run, record resident memory after warm-up, at 5 minutes, and at
15 minutes. A temporary rise during OCR or inference is acceptable. A repeated
rise that never returns to a stable band is a failure and should be investigated
with Allocations before Phase 7 closes.

## Reference result table

Record only values available from the trace or content-free diagnostics. Do not
estimate missing values. The project owner accepted the 2026-09-01 reference
runs as the Phase 7 baseline on 2026-09-02; a separate lightweight RSS run was
not required for this baseline.

| Date | Build commit | Scenario | Avg CPU | Peak CPU | Start memory | End memory | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 2026-09-01 | `ead471b` | Idle (5 min 28 sec) | — | — | — | — | Accepted; no OCR or translation work in the final 3 min |
| 2026-09-01 | `ead471b` | Scroll (59.8 sec) | — | — | — | — | Pass; no hangs and changed-frame work remained bounded |
| 2026-09-01 | `ead471b` | Translation (59.8 sec) | — | — | — | — | Pass; translation work was effectively sequential |
| 2026-09-01 | `ead471b` | Long run (16 min 1 sec) | — | — | — | 115.0 MB persistent heap | Accepted with limitation; start RSS was not recorded |

### 2026-09-01 observations

- Idle final three minutes: 173 captures averaged 84.67 ms. OCR and
  translation counts were both zero. Instruments reported no hangs and a
  nominal thermal state. CPU percentage was not recorded; the final-three-minute
  sample rate was 25.30 million CPU cycles per second.
- Scroll run: 73 captures averaged 64.40 ms; 23 OCR intervals averaged
  431.68 ms; and 23 translation intervals averaged 2,149.90 ms. There were no
  hangs and the thermal state remained nominal.
- Translation intervals had a maximum concurrency of two, but overlapped for
  only 1.44 ms in total. This is treated as effectively sequential execution.
- Long run: the final Allocations snapshot reported 114,989,360 bytes of
  persistent heap and 5,029,888 bytes of persistent anonymous VM. The bounded
  diagnostics retained 256 capture samples, 94 OCR samples, and 94 translation
  samples. Two capture failures were recorded; the app continued running.
- The long-run trace was used only for local analysis and deleted without being
  published because Instruments traces can include launch-environment metadata.
- Because start and periodic resident-memory samples were not recorded, this
  baseline does not claim that the stable-band memory criterion was measured.
  Re-run the lightweight RSS procedure if a future change shows suspected
  memory growth.

## Pass criteria

- Idle average CPU is below 2% over the final three minutes.
- Memory reaches a stable band; it does not increase monotonically through the
  final ten minutes.
- Diagnostic sample counts never exceed 256 per stage.
- OCR and translation do not run for unchanged frames.
- Scrolling supersedes stale translation work without blocking Discord.
- Diagnostics and signpost names contain no Discord message content.

If idle CPU misses the target, inspect the `Discord capture` intervals first.
If memory grows, compare allocations between the end of warm-up and the end of
the long run, focusing on captured images, OCR observations, translation tasks,
cache entries, and overlay windows.
