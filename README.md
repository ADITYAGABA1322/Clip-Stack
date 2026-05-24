# ClipStack

A native iOS short-form video feed built for the Chaptr take-home challenge. One polished surface: a full-screen vertical For You feed that streams Pexels clips from a bundled JSON catalog, with a fixed-size player pool, opportunistic disk cache, threaded comments, scrub preview, and Instruments-ready performance diagnostics.

**Walkthrough video:** https://drive.google.com/file/d/1Qwy5ULNwQFb7F3e3bvsz3x6Piy8zmWew/view

---

## Building and Running

### Prerequisites

| Requirement | Version |
|---|---|
| Xcode | 16.4 or newer |
| iOS deployment target | 18.0 or newer |
| Device or simulator | iPhone (portrait) |
| Dependencies | None |

There are no Swift packages, CocoaPods, Carthage dependencies, API keys, or backend services. Everything runs from the bundle.

### Steps

1. Download or clone the repo and open `ClipStack.xcodeproj` in Xcode.
2. In the scheme selector at the top of Xcode, confirm the scheme is **ClipStack** (not a test or UI test scheme).
3. Select any iPhone simulator running iOS 18 or newer. iPhone 16 Pro or iPhone 17 Pro give the most realistic performance headroom.
4. Press **⌘R** to build and run. Build time is under 20 seconds on M-series hardware.
5. The feed appears immediately. Swipe up to advance, swipe down to go back, tap to pause/resume, double-tap to like, drag the thin bar at the bottom to scrub.

### Running the Tests

1. Select the **ClipStack** scheme and choose **Product → Test** (⌘U), or expand the test navigator and run individual suites.
2. All 33 tests should pass. The catalog suite (`CatalogTests`) loads the bundled JSON at runtime and validates that ≥ 50 videos exist, that all IDs are unique, and that every URL is HTTPS. The pool suite (`PlayerPoolManagerTests`) launches real `AVPlayer` instances and advances through all 65 videos.

### Instruments Profiling

Open **Instruments**, choose the **Time Profiler** template, and add the **Points of Interest** instrument. Run on simulator. `FeedPerformanceMonitor` emits named intervals for every first-frame window (`First Frame` begin/end) and discrete events for every page settle (`Page Settled`) that include index, settled count, and resident memory in MB. This lets you see cold-start latency and memory growth per scroll in a single timeline.

---

## What Was Built

### Feed and Scroll

- Full-screen vertical paging feed with one clip per screen, built with `ScrollView`, `LazyVStack`, `.scrollTargetBehavior(.paging)`, `.scrollPosition`, `.onScrollGeometryChange`, and `.onScrollPhaseChange`. These are the current-generation SwiftUI scroll APIs available from iOS 17 onward, as opposed to the older `TabView(.page)` approach.
- `LazyVStack` with `.scrollTargetLayout()` ensures only visible and immediately adjacent pages are instantiated. The list can hold 65 (or 6,500) entries without proportional memory growth.
- Dual page-change detection: `scrollPosition` binding for reliable settled-page notification, backed by `onScrollGeometryChange` for mid-scroll fractional tracking used by the pool advance logic.

### Player Pool

- Five `AVPlayer` instances, created once at startup and reused forever via `replaceCurrentItem(with:)`. The pool keeps index `[current−1, current, current+1, current+2, current+3]` warm. Releasing a slot calls `replaceCurrentItem(with: nil)` — not `AVPlayer` deallocation — so the object itself stays alive and its memory footprint stays constant.
- `automaticallyWaitsToMinimizeStalling = false` on all pool players so the app controls stall behavior explicitly rather than letting AVFoundation delay playback for an arbitrary buffer window.
- `preferredForwardBufferDuration = 6` on each `AVPlayerItem` to prime 6 seconds of forward buffer before handing the item to the active player.
- `preroll(atRate: 1)` called on every warm non-active player so the decoder is running before the user arrives.
- Rapid-swipe safety: `syncPool` cancels the in-flight `Task` before dispatching a new `advance()` call to the pool actor, and guards on `Task.isCancelled` before the actor hop. This prevents a queue of stale `advance()` calls from building up during fast swipes. A `poolRevision` integer also validates that the final `playerGeneration` increment still reflects the correct index.

### Disk Cache

- `VideoFileCache` is a Swift actor that downloads up to five nearby videos into the app's Caches directory via `URLSession.download(from:)`. The pool actor's `diskCacheWindow` schedules the current index plus the next four for download, matching the five-slot player window.
- LRU trimming on every download completion: files are sorted by `contentModificationDate`, and files beyond the newest five are deleted. Touch dates are updated on read so recently accessed files survive a trim cycle.
- Downloads deduplicated by an `inFlightVideoIDs` set so rapid scrolling cannot queue duplicate network requests for the same video.
- When a cached file exists, the pool creates `AVPlayerItem(url: localURL)` instead of the remote URL. This removes network latency for replays and improves behavior under poor connectivity.

### Mid-Playback Buffering Indicator

- `AVPlayerItem.status` transitions from `.unknown` → `.readyToPlay` once at startup, and never goes back. A video that stalls mid-playback after the first frame would show nothing without additional observation. `VideoPageView` observes `AVPlayer.timeControlStatus` via KVO (`NSKeyValueObservation`) and sets `isMidPlaybackBuffering = true` when status is `.waitingToPlayAtSpecifiedRate`. The spinner overlay condition is `(initial buffering) || (mid-playback stall && not paused by user)`.

### Scrub and Preview

- Progress bar is a custom `ZStack` driven by a `addPeriodicTimeObserver` at 0.1-second intervals. A `seekTarget` pin prevents the bar from snapping backward when the player catches up to a seek — the bar stays at the drag position until the player time is within 1 second of the target.
- Live seek during drag uses `±0.3 s` tolerance so AVFoundation snaps to the nearest keyframe rather than doing a full frame decode. Final seek on release uses zero tolerance.
- Scrub preview thumbnail: `AVAssetImageGenerator` with `±1 s` keyframe tolerance and `maximumSize = (80, 142)`. Image generation runs in a `Task.detached(priority: .userInitiated)` to avoid blocking the main actor. New drag positions cancel the previous image task before starting a new one.

### Playback Controls and UI

- Right-side action rail: like (with bounce animation), comments (with fill indicator when the user has commented), bookmark, share, quick controls, mute.
- Single-tap: toggle play/pause with center icon flash.
- Double-tap: animated heart flies from tap location toward the like button, then like is applied at the midpoint of the travel animation.
- Quick controls panel: `−10s` skip, playback speed (`0.75×`, `1×`, `1.25×`, `1.5×`, `2×`), `+10s` skip. Slides in from the bottom.
- Mute state persisted in UserDefaults, applied to all pool players immediately.
- Gesture guide for first-time users: shows "Swipe up for next" then "Double tap to like" on the first video, auto-dismisses, and is never shown again.

### Social State

- Like, bookmark, share count, and comments persist across sessions via UserDefaults (JSON-encoded `[Int: FeedSocialState]` keyed by video ID).
- Threaded comments with Instagram-style UI: author avatar, timestamp, like count per comment, expandable reply threads, reply targeting with animated "Replying to X" pill, reply likes.
- Comment copy versioning: if the app's seed comment content changes (`commentCopyVersion`), user-authored comments are preserved but generated comments are refreshed on next load.

### Performance Diagnostics

- `FeedPerformanceMonitor` emits `os_signpost` intervals around every first-frame acquisition and `os_signpost` events on every page settle including index, settled count, and `mach_task_basic_info` resident memory.
- Scroll phase changes logged via `Logger` at debug level including velocity, so Instruments shows exactly when inertia ends and the pool advance fires.

### Tests (33 passing)

Nine suites covering: video model formatting, backward-compatible comment decoding, social state mutations, gesture guide logic, load state, player pool slot correctness, catalog validation, and social state JSON round-trip.

---

## What Was Skipped and Why

### Server-Backed Social State

Like counts, follower graphs, notifications, and view tracking are skipped. The bundled data has no user model, no write API, and no session. Faking them locally would not demonstrate meaningful engineering: the real challenge in social state is conflict resolution, optimistic updates, and eventual consistency with a backend, none of which can be shown with UserDefaults. Local persistence of the viewer's own likes and bookmarks *is* implemented as that's genuinely useful and testable.

### Profile and Discovery Surfaces

The challenge scope is the For You feed. Building a hollow profile tab or a search surface that has no real data behind it would dilute focus from the parts of the app that can actually be evaluated.

### Landscape and iPad Layouts

The design is deliberately portrait-only. Short-form video content is produced and consumed in portrait. Adapting `AVPlayerLayer` to landscape requires non-trivial layout work (safe area handling changes completely, the action rail moves) that adds no insight into the core performance problem.

### HLS / Adaptive Bitrate

All URLs in the catalog are direct MP4 links at a single fixed resolution (720×1280, 30fps). Building an HLS rendition switcher without a server that serves real `.m3u8` manifests with multiple renditions would be simulated rather than real. The architecture — `AVPlayerItem` over a URL — is already compatible with HLS; switching to it requires only changing the source URL format.

### Offline Mode and Download Management

The disk cache is opportunistic, not a download manager. There is no download progress UI, no storage quota display, no user-triggered download, and no `AVAssetDownloadURLSession`. Building that surface without network conditions to test against (and without entitlements for background download) would be premature.

### Network Reachability

No `NWPathMonitor` integration. The app surfaces per-video retry on failure and catalog retry on load failure, but it does not proactively disable actions or show a banner when the network is unavailable. This was a time trade-off in favor of getting the player pool and scrub interaction correct.

---

## Tradeoffs and How I'd Revisit Them

### `ScrollView` over `TabView`

The feed uses the SwiftUI `ScrollView` + `LazyVStack` + `.paging` stack rather than `TabView(.page)`. `TabView` is simpler to set up but loses `onScrollGeometryChange` and `onScrollPhaseChange`, which are the hooks that make mid-scroll pool advance and Instruments instrumentation possible. The downside is that the paging math (dual detection via `scrollPosition` and `onScrollGeometryChange`) is more fragile than `TabView`'s built-in tab change callback.

Revisit: once the page detection is stable, the implementation is worth keeping. If SwiftUI adds a more reliable paging callback in a future release, it would simplify the dual-detection pattern.

### Fixed Five-Player Pool

The window `[current−1, current, current+1, current+2, current+3]` is asymmetric: one back, three forward. This is a deliberate bet that users scroll forward more than backward. Going back two positions cold-starts a player. The window size (five) is hardcoded rather than derived from device memory class.

Revisit: query `ProcessInfo.processInfo.physicalMemory` at startup and size the pool dynamically — six players on 8 GB devices, four on 4 GB. The `PlayerPoolManager` initializer already accepts `preloadWindowSize` as a parameter; the view model just needs to pass the right value.

### `UserDefaults` for Social Persistence

Encoding `[Int: FeedSocialState]` as JSON and writing to UserDefaults works for a demo. It does not scale past a few hundred keys, does not support conflict resolution, and does not survive a data migration if the schema changes.

Revisit: replace with Core Data or SwiftData — both support incremental schema migrations and predicate-based fetching, which become necessary once the feed can hold thousands of videos.

### `AsyncImage` for Thumbnails

`AsyncImage` uses an undocumented internal URLCache. For 65 videos that get scrolled through in a session, the cache grows unboundedly (observed at 7–15 MB after 50 scrolls). There is no way to set a size cap or an eviction policy from the outside.

Revisit: replace with a lightweight custom thumbnail cache — a `NSCache<NSURL, UIImage>` with an `NSCache.countLimit` of 30, loaded via `URLSession.data(from:)` on a background task. That gives explicit control over memory pressure.

### `UserDefaults` for Mute State

A single boolean stored under a string key. If the key constant changes, the preference silently resets. This is acceptable for a demo.

Revisit: wrap in a typed `AppStorage` property wrapper or a dedicated preferences struct that owns all key constants, making them impossible to mistype and easy to test.

### Comment Seeding in the View Model

`FeedViewModel.initialComments(for:)` is a 60-line function that generates deterministic fake comments from a seed derived from the video ID. SwiftLint would flag this as too long. The logic is correct and the output is stable (same video always produces the same comment set), but it belongs in a separate `CommentSeedService` that can be tested in isolation without instantiating a `FeedViewModel`.

Revisit: extract to a pure static function in its own file. Move the seed pools to a separate data file or embedded JSON.

---

## What I Would Do Differently with Another Week

**Day 1–2: Backend contract and paginated loading**

Replace the bundled `for-you.json` with a `FeedRepository` protocol that has two conformances: `BundledFeedRepository` (current) and `RemoteFeedRepository` (paginates over a real endpoint). This is the single highest-leverage architectural change because it forces every assumption about "all videos available at once" to become explicit.

**Day 3: Real device measurement**

Run a 100-swipe session on a physical iPhone 14 with Network Link Conditioner set to "3G" and attach the Instruments Time Profiler + Points of Interest output to this README. The pool and cache were designed around specific latency budgets that have only been measured on simulator so far.

**Day 4: Network reachability and graceful degradation**

Add `NWPathMonitor` to surface a non-blocking banner when the path is unsatisfied. Buffer the last two played videos in the disk cache so the user has something to return to when connectivity drops. Replace the current "retry" error with distinct messaging for timeout vs. server error vs. no network.

**Day 5: Core Data persistence and sync**

Move social state from UserDefaults to SwiftData. Add optimistic like/unlike with a rollback on server error. This is the last piece needed before the social rail is more than cosmetic.

**Day 6: UI tests for the scroll surface**

Write XCUITest cases for: vertical paging (swipe 5 times, assert the like count label changes per video), mute toggle (assert button label changes), retry (kill network, advance to a new video, assert error UI, restore network, assert video plays). These are the tests most likely to catch regressions during a refactor of the pool or scroll detection logic.

**Day 7: Polish and submission**

Record a 90-second Loom showing: launch → first video plays → rapid swipe through 10 videos with memory visible in the Debug navigator → slow network simulation → retry → scrubbing → double-tap like → comments sheet. Add the Instruments screenshot.

---

## Biggest Risk in Scaling to Thousands of Videos and Users

**Content delivery latency is the bottleneck, and the client cannot solve it alone.**

The player pool and disk cache address memory and replay latency. They do not address the time between when a user lands on a video they have never seen and when the first frame appears. On simulator with a fast connection, that number is around 100 ms (measured by `FeedPerformanceMonitor`). On a real device over a cell connection to an origin server in a different region, it can easily be 1–4 seconds — enough to feel broken.

Three specific risks at scale:

**1. Origin latency without CDN edge caching**

All 65 current videos come from `videos.pexels.com`, which has CDN infrastructure. A real product serving its own video files from a single-region origin will see catastrophic first-frame latency for users outside that region. The fix is HLS delivery through a CDN (CloudFront, Fastly, Akamai) with edge PoPs close to users. The client already calls `AVPlayerItem(url:)` — switching to an HLS `.m3u8` URL is a one-line change per item. Everything else, including adaptive bitrate switching and the prefetch cache, continues to work.

**2. Catalog size and feed personalization**

A bundled 65-video JSON file obviously does not scale. The bigger problem is that once the catalog grows to thousands of videos, the app needs a ranked feed endpoint that returns a window of personalized video IDs for the current session, not a flat dump. The `VideoRepository` protocol boundary was designed to make this swap cheap (swap the implementation, not the call sites), but the `PlayerPoolManager.advance` method assumes all videos are loaded upfront into the `[Video]` array passed at scroll time. That array would need to become lazy — the pool should ask the repository for the next item when it needs to preload, rather than receiving a pre-built slice.

**3. Memory at scale with large thumbnails**

At 65 videos, `AsyncImage` thumbnail growth is a minor annoyance (~15 MB). At thousands of videos in a session (an engaged user spending 30 minutes in the app), an unbounded image cache will eventually trigger memory warnings and potential jetsam. A bounded `NSCache` with a sensible byte limit (e.g. 30 MB) and `UIApplicationDidReceiveMemoryWarningNotification` eviction would cap this. The player pool memory is already O(1) — five players regardless of catalog size. The thumbnail cache is the only remaining component that grows with session depth.
