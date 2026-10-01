# Binary Replay container version 1

The `.replay` container is an additional storage representation of the existing Replay V1/V2 facts. JSON input remains supported. App/Parser 0.9.0 introduces it; map assets and converter versions are independent.

## Layout

All fixed-width numbers are little-endian. The file begins with eight magic bytes `43 53 32 52 50 4c 59 00` (`CS2RPLY` and NUL), a uint32 container version (`1`), a uint32 UTF-8 JSON index byte count, that index, and consecutive independently zlib-compressed chunks.

The index contains `replay_version`, `metadata`, `players`, `bounds` (raw CS2 minimum/maximum XYZ for available living frames), `chunk_seconds` (`10`), and `chunks`. Metadata/player validation reuses the JSON contract. Each chunk entry contains `kind`, `start`, `end`, `offset`, `size`, `raw_size`, and compressed-byte `sha256`. Offsets are relative to the first payload byte; ranges must be contiguous, non-overlapping and account for the entire file. Track intervals must cover the whole duration.

The index is limited to 4 MiB; a stored or decompressed chunk is limited to 32 MiB. The reader rejects unknown versions, kinds, non-integral extents, missing families, invalid timeline coverage, checksum failures and malformed records. SHA-256 detects corruption; it is not an authenticity signature. Cache manifests additionally hash the complete file.

## Fact chunks

- `events`: utility, shots and kills.
- `damage`: player_hurt.
- `bomb`: bomb state facts, including moving dropped-bomb position frames.
- `projectiles`: original projectile facts and trajectories.
- `rounds`: currently an empty array. V2 has no reliable round records; this implementation does not invent rounds from bomb events.

These chunks use UTF-8 JSON arrays inside the compressed binary container to preserve existing event facts and validation. Every event carries `_order`, its original zero-based position in the unsplit event stream. The viewer merges by this field before validation, preserving simultaneous-event ordering exactly. Projectiles remain unquantized.

The current viewer loads these smaller fact chunks eagerly, retaining whole-match timeline, kill feed, statuses and Bomb seek semantics. This is track streaming, not full event/projectile streaming. The directory provides family-level offsets, not a per-event byte offset index.

## Player track chunks

Each ten-second interval has one `tracks` chunk containing all players in roster order. It contains:

1. uint32 player count.
2. For each player: uint32 roster index and uint32 frame count.
3. For each frame, seven 32-bit fields (28 bytes): signed tick delta; signed quantized X, Y, Z deltas; float32 yaw in degrees; signed health; uint32 flags.

Flags: bit 0 alive, bit 1 available, bit 2 CT (otherwise T); all other bits must be zero. An alive player must be available. Delta accumulators reset to zero for every player in every chunk. Coordinate bases are `round(source_coordinate * 32)`, reconstructed by dividing by 32. Absolute bases and deltas must fit int32. Each axis has at most 1/64 Source unit position error; yaw is rounded to float32. Discrete facts, source ticks and health are not quantized.

Time is `(tick - source_start_tick) / source_tick_rate`. Boundary frames immediately before/after the interval are duplicated so interpolation and left-hold semantics work without fetching a neighbor. Sparse tracks preserve their actual gaps; no synthetic movement is inserted. The final chunk ends at the exact replay duration.

## Runtime

The viewer opens the index and fact chunks, then decodes the initial track window. Seek selects its indexed interval directly. A three-entry LRU retains at most three decoded track windows, with whole-match raw bounds provided separately for camera framing. The ReplayClock remains the only time source. One background worker reads, checks and decodes the next window using its own file handle. Only the playback thread merges completed results into the LRU. Memory is bounded to three cached windows plus at most one worker window. Unrelated results after a seek are discarded. Cold seeks or unfinished prefetches still read synchronously; measurements and limits are recorded in the M9 report. Releasing the reader joins the worker. A speculative failure is surfaced only when that window is requested. Initial load remains on the existing background loader.

Late corruption pauses playback, hides stale player/combat state and reports an error. Reopening a cached demo checks the whole-file hash and rebuilds from the source when available. Existing Parser 0.6.0 JSON cache manifests remain accepted, including when the source demo is no longer present. New Parser 0.9.0 caches use `file_name: replay.replay`, `storage_version: 1`; their fact schema remains Replay V2.

The writer validates domain data and writes to a temporary file before committing the final output. The parser still collects domain facts for a complete demo before serializing; producer-side streaming is not implemented.
