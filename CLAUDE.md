# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

`car_play` is a Flutter app that shows **time-synced Spotify lyrics on a car-friendly full-screen display**. It does not play audio itself: it is a remote control + lyrics view over the Spotify Web API, driving whatever device is currently active on the user's Spotify Connect session. Nothing works unless something is already playing on another Spotify device.

UI strings and user-facing error messages are in English; code comments are in Italian.

## Setup

`.env` is gitignored but declared as a Flutter **asset** in `pubspec.yaml` and loaded in `main()`. If it is missing or incomplete the app shows `ConfigErrorScreen` instead of crashing. A fresh clone needs it created at the repo root with:

```
SPOTIFY_CLIENT_ID=...
LYRICS_BASE_URL=...      # optional: Spotify-lyrics proxy, queried as $LYRICS_BASE_URL/?trackid=<spotifyTrackId>
```

`LYRICS_BASE_URL` is optional: leaving it empty (or unset) simply drops the Spotify proxy out of the lyrics provider chain described below, and LRCLIB serves lyrics on its own.

No client secret: auth uses PKCE. The Spotify app registration must whitelist the redirect URI `car-play://callback`.

## Commands

```bash
flutter pub get                    # after any pubspec.yaml change
flutter run -d <device>            # android is the primary target; chrome also works
flutter analyze                    # lint (flutter_lints + prefer_const_constructors)
dart format lib                    # 80-column formatting
flutter test                       # unit + widget tests
flutter build apk --release        # see signing below
dart run flutter_launcher_icons    # regenerate launcher icons from assets/icon/icon.png
```

Release signing reads `android/key.properties` (gitignored: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`). Without that file the release build falls back to debug keys so `flutter run --release` still works locally.

## Architecture

One screen, no router, and two `ChangeNotifier`s.

```
main.dart ──> MultiProvider ──> PlayerScreen
                ├── PlayerProvider     (everything that comes from Spotify)
                └── SettingsProvider   (how the user wants the screen to look)
                                                          ├── LyricsListView         (auto-scrolling lyrics)
                                                          ├── LyricsTextSizeButton   (AppBar, text size menu)
                                                          └── PlayerControls         (prev / play-pause / next)
                            SpotifyAuthWebView is pushed as a route during login
```

**`PlayerProvider` holds all the state that comes from Spotify**, and that is the line between the two. `SettingsProvider` exists because a display preference has nothing to do with playback, tokens or timers, and has a persistence of its own; folding it into a class that is already several hundred lines of polling and auth would have been the only field in there that Spotify never sends. It is deliberately tiny: one preference, read once at startup, written when it changes.

Services are **instances wired through `PlayerProvider`'s factory constructor** (`TokenStorage` → `SpotifyAuth` → `SpotifyService`, plus the `LyricsRepository` chain), all injectable via named parameters. Nothing is static, so a fake `http.Client` is enough to exercise any of them.

### Two timers, two different jobs

This is the core of the design and the thing to understand before touching playback:

- **`_pollTimer` (5s)** hits the Spotify API and stores an *anchor*: the `progress_ms` just read plus the wall-clock instant it was read at.
- **`_tickTimer` (100ms)** never touches the network. It computes `estimatedProgressMs` from the anchor (anchor + elapsed, only while playing) and recomputes the highlighted lyric line.

That split is why highlighting looks smooth on a 5s poll. Both timers are created behind `??=` guards and cancelled in `dispose()`; `notifyListeners()` is overridden to no-op after disposal.

`didChangeAppLifecycleState` stops both timers when the app is backgrounded and freezes the anchor at the current estimate, so nothing polls in the background and the tick cannot extrapolate across minutes of absence. On resume it restarts them and forces an immediate resync. `inactive` is deliberately ignored — it fires for transient things like the notification shade.

`_syncPlayback({force})` is guarded by `_inFlightSync` so periodic polls never overlap. User commands (skip, play/pause) pass `force: true`: they wait for the in-flight poll and then run their own, because silently dropping the post-command refresh would leave the UI stale for up to 5s.

`notifyListeners()` fires only on *visible* change: `PlaybackState.sameDisplayAs` deliberately ignores `progress_ms`, and `_updateCurrentLine` notifies only when the line index actually moves.

Optimistic UI: `togglePlayPause` re-anchors from the current estimate and notifies before awaiting the API, so the button responds instantly. Every command then goes through `_runCommand`, which waits `_commandSettleDelay` before resyncing — `/me/player/currently-playing` stays eventually consistent for a few hundred ms after a command, so an immediate reread would return the *pre-command* state and undo the optimistic update on screen. It resyncs after a failed command too, to correct an optimistic update that never took.

**Invariant worth knowing:** `_anchorIsPlaying` is not always equal to `_playback?.isPlaying`. Backgrounding deliberately sets it `false` while playback keeps running, and it is restored only by a *successful* poll. That asymmetry is intentional: a resume with no connectivity leaves the lyrics frozen rather than advancing them from an anchor that is minutes stale. Frozen is a visible "I don't know"; extrapolating would be a confident lie. It self-corrects on the next successful poll.

### Auth (PKCE)

`SpotifyAuth` implements the authorization-code flow with PKCE — no client secret anywhere, since anything in the bundle is extractable from the APK. Each login generates a random verifier, sends its SHA-256 challenge, and validates the returned `state`.

The flow never leaves the app: `SpotifyAuthWebView` loads the authorize URL and intercepts `car-play://callback` in its `NavigationDelegate`, so the custom scheme is **not** registered in the manifest. The route pops with a `SpotifyAuthResult`, so backing out simply yields `null` — there is no completer that can hang, and a main-frame load error pops with an error instead of leaving a blank page.

**Known trade-off:** RFC 8252 says native apps should use the system browser, not an embedded WebView. This app has always used a WebView, and two consequences are worth knowing before shipping widely: the user types their password into a view the app controls, and federated "Continue with Google/Apple" buttons are often blocked inside embedded WebViews — so accounts created that way may be unable to log in at all. Moving to `flutter_web_auth_2` (Custom Tabs / `ASWebAuthenticationSession`) would keep the same never-hangs property. Untested on device.

Token lifecycle in `SpotifyService._send()`:
1. **proactive** — refresh if the stored expiry is within 60s;
2. **reactive** — on a `401`, refresh once and retry;
3. refreshes are deduplicated through `_pendingRefresh`, because Spotify rotates the refresh token on every exchange and parallel refreshes would invalidate each other;
4. a definitive refresh failure clears storage and fires `onAuthLost`, which drops the provider back to `disconnected`.

**Known trade-off:** `TokenStorage` keeps the Spotify refresh token in plain `SharedPreferences`, not `flutter_secure_storage`. On a non-rooted device that is covered by normal app sandboxing, so this is a deliberate, currently-undecided trade-off rather than an oversight — not a gap nobody noticed. If it needs to change, the move is `flutter_secure_storage` plus a migration step for installs that already have a token in `SharedPreferences`.

### Errors: "nothing playing" vs "don't know"

`SpotifyService` keeps these strictly apart, and it matters more than it looks:

- **204 / `item: null`** → `currentPlayback()` returns `null`, which legitimately means nothing is playing and the provider clears playback and lyrics.
- **anything else** (non-2xx, no session, timeout, socket error) → throws `SpotifyApiException`, caught by `_fetchPlayback`, which logs and **leaves the displayed state untouched**.

Collapsing the two — as an earlier version did by returning `null` for both — makes a transient 500 or a rate limit wipe the lyrics mid-song. Every HTTP call in the app has a 10s timeout; without one a hung request would hold `_inFlightSync` forever and silently kill polling.

A `429` throws with `retryAfter` populated from the header, and `_noteFailure` parks `_pollBlockedUntil` so **no** request — periodic or user-initiated — goes out until that deadline. Detecting a rate limit and then continuing to poll extends Spotify's penalty window instead of shortening it.

### Lyrics

`LyricsRepository` replaced the old single-endpoint `LyricsService`: it holds an ordered list of `LyricsProvider`s and asks them in turn. The chain is `SpotifyProxyProvider` (only added when `LYRICS_BASE_URL` is set) followed by `LrclibProvider`, which always runs. The rule is "first synced source wins": the first provider to return a synced result short-circuits the search; an unsynced result is kept as a fallback and only returned once the whole chain has run without finding anything better; an instrumental result is a fallback of last resort, weaker than an unsynced one.

Each provider follows the same outcome contract as `SpotifyService`: returning `null` means "I don't have it" (legitimately no lyrics), while throwing means "I don't know" (network error, timeout, malformed response). `LyricsRepository.lyricsFor` mirrors that at the chain level, but only for the *return value*: it returns `null` when the chain finishes without a usable result, and throws `LyricsProviderException` only when every source failed outright. A provider that throws does not stop the chain; only if *all* of them throw does the repository give up. That distinction reaches `PlayerProvider._loadLyrics` unchanged: `null` becomes `LyricsStatus.unavailable`, a thrown exception becomes `LyricsStatus.failed` (the only state with a Retry button), and an instrumental result becomes `LyricsStatus.instrumental`.

What is *cached* is stricter than what is *returned*. A synced result is written and returned the moment it is found, before the rest of the chain can matter. Every other write — the post-loop fallback (`bestUnsynced ?? instrumental`) and `writeMissing` — happens only if the chain ran to completion with zero failures. With two providers, one answering "not mine" and the other throwing is the ordinary case once the Spotify proxy is end-of-life and LRCLIB has a bad day on mobile data: the repository still returns `null` (or the unsynced fallback) so the screen shows something reasonable, but it will not freeze that answer into the cache, positive or negative, because it never actually found out whether lyrics exist. Persisting a non-answer would either bury usable lyrics behind a 7-day negative entry or make a degraded fallback permanent, since positive entries never expire.

`LyricsCache` persists resolved outcomes (found or missing) as one JSON file per track ID under the app's documents directory, capped at 200 entries with least-recently-modified eviction, and negative ("missing") entries expire after 7 days so a track that gets lyrics added later on LRCLIB can be found again. The cache is attached to the repository asynchronously after `PlayerProvider` is constructed (`LyricsCache.open()` needs `await`, and the provider itself must stay synchronous for `ChangeNotifierProvider`); until it attaches, the chain still works, just without caching. `LyricsRepository.cache` is deliberately non-`final` to allow this.

`Lyrics.isUsable` requires a non-empty `lines` list and no `error`, where `error` counts **only if the payload says `error: true`** — a missing field is not an error. Defaulting that field to `true` would silently report "no lyrics" for every track whose response omits it.

`Lyrics.isSynced` gates the highlighting. An `UNSYNCED` payload has every line at `startTimeMs: "0"`, and the "last line already started" scan would then pin the highlight to the final line for the whole song; such lyrics are rendered but not followed. As with `error`, the polarity is deliberate: only a declared `UNSYNCED` (or lines that are all at zero) turns following off, so an absent or unrecognised `syncType` keeps working.

`_loadLyrics` stamps each request with `_lyricsRequestId` and drops responses that arrive after a track change — without that guard a slow response paints the previous song's lyrics over the new track. `_resetPlaybackState()` bumps the same counter, since a disconnect or a stop invalidates an in-flight fetch just as much as a track change does.

State reaches the UI as `LyricsStatus` (`loading` / `ready` / `unavailable` / `instrumental` / `failed`), and `PlayerScreen` renders a distinct view per case, with a Retry button on `failed`.

`LyricsListView` renders with `ScrollablePositionedList` and inserts a half-screen spacer at each end, so **list index = lyric index + 1**. `currentLineIndex` is `-1` before the first line starts, meaning nothing is highlighted. Scrolling is driven by a provider listener (a side effect), while highlighting comes from `context.watch` in `build`. A user drag disables auto-scroll until the recenter FAB is tapped or the track changes.

`_scrollToLine` returns whether it actually scrolled, and `_lastScrolledIndex` is only recorded on success — the controller is not attached on the first frame after lyrics load, and marking that as done would strand the view at the top. A post-frame callback in `build` performs the initial centering once the list is attached.

**`ItemScrollController.isAttached` is not a sufficient guard**, and finding that out the hard way is worth recording. It flips to `true` as soon as the list registers itself, which can happen before the viewport has been measured. Calling `scrollTo` in that window does not fail where you called it: the controller defers to a post-frame callback and the assertion — `ScrollController not attached to any scroll views` — fires a frame later, outside any `try` you could wrap around it. The real readiness signal is an `ItemPositionsListener` with a non-empty `itemPositions`, so `_scrollToLine` checks that too and simply returns `false` when the list is not ready yet. Nothing is lost: `_lastScrolledIndex` stays `null` and the next provider update retries.

### Text size

`LyricsTextSize` is an enum of four levels, each a multiplier over the two historical sizes — 20 for the current line, 16 for the rest. The multiplier form is deliberate: the ratio between the highlighted line and the ones around it is what tells a driver at a glance where the song is, and four hand-picked pairs would drift away from it.

**The scale starts at the historical size and only goes up**: `small` is 1.0, and the steps are 1.3, 1.6, 1.9. An earlier version centred the scale on the old size with a 0.8 level below it; trying it in a car showed nobody wants the lyrics *smaller* than they were, while the top of the range ran out of room. Two consequences worth knowing: the historical size is now `small`, not `medium`, and since `medium` remains the default a fresh install renders one step larger than the app used to.

Changing the size resets `_lastScrolledIndex`, because taller or shorter lines move the current one somewhere else in the list and the text would otherwise slide out from under the reader. It reuses the same post-frame recentering path as the first load.

An unrecognised stored value — an older build, or tampered preferences — reads as `medium` rather than as an error, the same polarity choice as `error` and `syncType` in the lyrics payload.

`LyricsTextSizeButton` is its own widget rather than an inline `PopupMenuButton` in the `AppBar`: inside `PlayerScreen` it could only be exercised by mounting the whole screen, which drags in the title `Marquee` and the wakelock and leaves a pending timer in the test.

### Landscape

`PlaybackView` lays the same two pieces out along whichever axis has room to spare. In portrait the controls are a bar at the bottom; in landscape they become a column on the right edge, at the same icon sizes.

The reason is that the two orientations run out of different things. The bar costs about 90pt of **height**, which in landscape is exactly the dimension the lyrics need and the one there is least of — four or five lines instead of six or seven. Width, in landscape, is what is left over, and a column of transport buttons costs around 10% of it.

Two consequences are deliberate. The buttons are grouped at the vertical centre rather than spread over the full height, so a driver reaches all three without moving their hand. And `LyricsListView` moves its recenter FAB to the bottom *left* in landscape: left where it was, it would sit flush against the transport column, and two adjacent targets that do unrelated things is a mis-tap waiting to happen in a car.

`PlaybackView` is public for the same reason `LyricsTextSizeButton` is: the orientation switch can only be exercised by mounting it directly, since mounting `PlayerScreen` drags in the title `Marquee` and the wakelock.

## Conventions

- Never `print`: use `logInfo` / `logError` from `lib/utils/app_log.dart`.
- Failures that a user can act on become a state (`authError`, `LyricsStatus.failed`), not just a log line.
- A failure whose outcome is *unknown* must never overwrite known-good state with an empty one.
- Anything that opens a route from the provider takes a `NavigatorState` resolved before the state change, not a `BuildContext` — notifying listeners unmounts the widget the context came from.
- `disconnect()` also clears the WebView cookies, otherwise the next login silently re-enters the same account.
- One `http.Client` is created in the factory, shared by all three services and closed in `dispose()` — not one pool per service.
- A parsed-but-unused field is a trap, not documentation: `error` and `syncType` both sat unread until they were wired up, and both needed their default polarity chosen carefully at that point.
- `applicationId` is still `com.example.car_play`.
