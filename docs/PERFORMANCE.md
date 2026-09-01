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

Fill this table from one continuous test session. Do not estimate missing values.

| Date | Build commit | Scenario | Avg CPU | Peak CPU | Start memory | End memory | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| Pending | Pending | Idle | — | — | — | — | Not measured |
| Pending | Pending | Scroll | — | — | — | — | Not measured |
| Pending | Pending | Translation | — | — | — | — | Not measured |
| Pending | Pending | Long run | — | — | — | — | Not measured |

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
