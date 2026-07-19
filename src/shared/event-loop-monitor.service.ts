import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { monitorEventLoopDelay } from 'perf_hooks';
import type { IntervalHistogram } from 'perf_hooks';

export interface EventLoopLagSample {
  meanMs: number;
  p99Ms: number;
  maxMs: number;
}

const SAMPLE_INTERVAL_MS = 5000;

/**
 * Tracks event-loop responsiveness — the earliest, cheapest signal that the
 * process is CPU-bound and falling behind (a synchronous hot path blocking
 * the loop shows up here before it shows up as slow HTTP/WS responses).
 * Directly motivated by a real finding: at 30 concurrent games, a full-pool
 * scan on every gameplay action degraded game duration and unrelated
 * /metrics requests ~3x (see LOAD_TEST_RESULTS.md) — event-loop lag is
 * exactly the metric that would have surfaced that CPU contention on its own,
 * without having to infer it from higher-level symptoms after the fact.
 *
 * Uses Node's built-in `perf_hooks.monitorEventLoopDelay()` (a native
 * histogram, not a hand-rolled setImmediate-timing loop) sampled and reset on
 * a fixed interval, so each sample reflects "since the last sample" — the
 * same windowing a Prometheus scrape interval would give you — rather than a
 * cumulative-since-boot average that dilutes recent spikes into invisibility
 * over a long-running process.
 */
@Injectable()
export class EventLoopMonitorService implements OnModuleInit, OnModuleDestroy {
  private histogram: IntervalHistogram | null = null;
  private timer: ReturnType<typeof setInterval> | null = null;
  private lastSample: EventLoopLagSample = { meanMs: 0, p99Ms: 0, maxMs: 0 };

  onModuleInit(): void {
    this.histogram = monitorEventLoopDelay({ resolution: 20 });
    this.histogram.enable();
    this.timer = setInterval(() => this._sample(), SAMPLE_INTERVAL_MS);
    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
    this.histogram?.disable();
  }

  private _sample(): void {
    if (!this.histogram) return;
    const toMs = (ns: number) => Math.round((ns / 1e6) * 100) / 100;
    this.lastSample = {
      meanMs: Number.isFinite(this.histogram.mean) ? toMs(this.histogram.mean) : 0,
      p99Ms: toMs(this.histogram.percentile(99)),
      maxMs: toMs(this.histogram.max),
    };
    this.histogram.reset();
  }

  /** Last completed 5s window — never triggers a read-side reset, so /health and /metrics can both read it independently without interfering with each other. */
  getLastSample(): EventLoopLagSample {
    return this.lastSample;
  }
}
