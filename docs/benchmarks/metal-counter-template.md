# Metal performance-counter template

`xctrace` can consume a configured Instruments template but cannot select a
Metal counter set from its command line. Create the local template once for
each Xcode installation:

1. Open Instruments and choose **Metal System Trace**.
2. Select the **Metal Application** instrument.
3. Set **Counter Set** to **Performance Limiters**.
4. Choose **File > Save As Template** and name it
   `VF64 Performance Limiters`.

Confirm that it is visible:

```bash
xcrun xctrace list templates
```

The template is an Xcode-owned keyed archive and is not redistributed by this
repository. `capture-metal-performance-counters.sh` fails closed if the named
template is absent or if the resulting trace does not contain `Kernel
Occupancy`, `L1 Register Residency`, and `Compute SIMD Groups Inflight`.

Counters are device-level samples. The summarizer selects samples whose
timestamps overlap labeled VF64 compute intervals, but concurrent GPU work from
other processes can still contribute. Record on an otherwise idle system and
retain that limitation in published evidence.

On the measured M4 Pro with Xcode 26.6, the profile advertises the requested
counter definitions but the exported sample table contains only counter IDs
71–84 (texture, bandwidth, MMU, and last-level-cache metrics). The capture
therefore fails rather than publishing empty occupancy/register evidence. This
is a documented toolchain result, not evidence that another Xcode or Apple GPU
combination will behave identically.
