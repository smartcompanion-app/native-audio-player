import { afterEach, describe, expect, it, vi } from 'vitest';

import type { AudioPlayerChange, AudioPlayerProgress, Item } from '../definitions';
import { NativeAudioPlayerWeb } from '../web';

import { createAudioUri, createUnloadableUri, revokeAudioUris } from './audio-fixture';

/**
 * The contract these tests assert lives in definitions.ts, and iOS and Android are held to
 * it by their own unit tests and by the Appium suite in example/. This is the web side of
 * the same contract, run against a real <audio> element in a real browser -- a stubbed
 * element would only prove that web.ts calls it, not that the playback it promises happens.
 */

const LONG_ITEM_SECONDS = 5;
const SHORT_ITEM_SECONDS = 1;

/**
 * Records the audioPlayerChange events in the order the plugin reported them, the same way
 * the example app's #events element does for the Appium suite. Asserting the whole sequence
 * rather than the last event is what catches an extra or missing transition -- the contract
 * promises exactly one event per change.
 */
class PlayerHarness {
  readonly player = new NativeAudioPlayerWeb();
  readonly events: AudioPlayerChange[] = [];
  readonly items: Item[];

  private constructor(items: Item[]) {
    this.items = items;
  }

  static async create(itemSeconds = LONG_ITEM_SECONDS): Promise<PlayerHarness> {
    const items = ['1', '2', '3'].map((id) => ({
      id,
      title: `Item ${id}`,
      subtitle: 'Animals',
      audioUri: createAudioUri(itemSeconds),
      imageUri: `data:image/gif;base64,R0lGODlhAQABAAAAACw=`,
    }));

    const harness = new PlayerHarness(items);
    await harness.player.addListener('audioPlayerChange', (event: AudioPlayerChange) => {
      harness.events.push(event);
    });
    return harness;
  }

  /** The state names alone, which is what most of the assertions below are about. */
  get states(): string[] {
    return this.events.map((event) => event.state);
  }

  /** Everything reported since the last call, so a test can assert one step at a time. */
  drain(): AudioPlayerChange[] {
    return this.events.splice(0);
  }

  async start(): Promise<{ id: string }> {
    return this.player.start({ items: this.items });
  }

  get audioElement(): HTMLAudioElement | null {
    return this.player.getAudioElement();
  }

  get isPlaying(): boolean {
    const element = this.audioElement;
    return !!element && !element.paused && !element.ended;
  }
}

/**
 * web.ts finds its element by id on the document, so anything a test leaves behind is
 * picked up by the next one.
 */
afterEach(() => {
  document.querySelector('#web-audio')?.remove();
  revokeAudioUris();
  vi.restoreAllMocks();
});

type ActionHandler = (details: any) => void;

/**
 * The handlers web.ts registers on the media session. setActionHandler is write-only, so a
 * test that wants to press the browser's own play button has to catch them on the way in.
 * Call this before the player is constructed, which is where they are registered.
 */
const captureActionHandlers = (): Map<string, ActionHandler> => {
  const handlers = new Map<string, ActionHandler>();

  vi.spyOn(navigator.mediaSession, 'setActionHandler').mockImplementation((action, handler) => {
    if (handler) {
      handlers.set(action, handler);
    } else {
      handlers.delete(action);
    }
  });

  return handlers;
};

/**
 * Asserts that a call refuses, and distinguishes refusing from never answering at all. A
 * promise that stays pending is its own failure and has to read as one: `rejects.toThrow()`
 * around a timeout would be satisfied by the timeout itself and report a hang as a pass.
 */
const expectRejection = async (promise: Promise<unknown>, what: string, ms = 4000): Promise<void> => {
  const pending = 'never settled';
  let timer: ReturnType<typeof setTimeout> | undefined;
  const expired = new Promise<string>((resolve) => {
    timer = setTimeout(() => resolve(pending), ms);
  });

  try {
    const outcome = await Promise.race([
      promise.then(
        () => 'resolved',
        () => 'rejected',
      ),
      expired,
    ]);
    expect(outcome, `${what} should have rejected`).toBe('rejected');
  } finally {
    clearTimeout(timer);
  }
};

describe('start', () => {
  it('resolves with the id of the first item', async () => {
    const harness = await PlayerHarness.create();

    expect(await harness.start()).toEqual({ id: '1' });
  });

  it('loads the item without reporting a state change or playing it', async () => {
    const harness = await PlayerHarness.create();

    await harness.start();

    expect(harness.audioElement).not.toBeNull();
    expect(harness.isPlaying).toBe(false);
    expect(harness.states).toEqual([]);
  });

  it('replaces the previous playlist when called again', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();
    await harness.player.next();
    harness.drain();

    expect(await harness.start()).toEqual({ id: '1' });
    expect(document.querySelectorAll('#web-audio')).toHaveLength(1);
  });

  it('rejects when the audio cannot be loaded', async () => {
    const harness = await PlayerHarness.create();
    harness.items[0].audioUri = createUnloadableUri();

    await expectRejection(harness.start(), 'start() with an audio file that cannot be loaded');
  });
});

describe('play and pause', () => {
  it('reports playing and then paused for the current item', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.play();
    expect(harness.isPlaying).toBe(true);
    expect(harness.drain()).toEqual([{ state: 'playing', id: '1' }]);

    await harness.player.pause();
    expect(harness.isPlaying).toBe(false);
    expect(harness.drain()).toEqual([{ state: 'paused', id: '1' }]);
  });

  it('keeps the position when paused', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.play();
    await vi.waitFor(async () => expect((await harness.player.getPosition()).value).toBeGreaterThan(0));
    await harness.player.pause();

    const position = (await harness.player.getPosition()).value;
    expect(position).toBeGreaterThan(0);
    expect((await harness.player.getPosition()).value).toBe(position);
  });

  it('reports nothing for a pause that stopped nothing', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    // an app that pauses while a scrubber is dragged calls this on every input event, and a
    // state is reported per change rather than per call
    await harness.player.pause();
    await harness.player.pause();
    expect(harness.drain()).toEqual([]);

    // and the pause that does stop something is still reported, once
    await harness.player.play();
    harness.drain();
    await harness.player.pause();
    await harness.player.pause();
    expect(harness.drain()).toEqual([{ state: 'paused', id: '1' }]);
  });

  it('rejects before start, because there is nothing to play', async () => {
    const harness = await PlayerHarness.create();

    await expect(harness.player.play()).rejects.toThrow();
    await expect(harness.player.pause()).rejects.toThrow();
  });

  it('rejects after stop, because the playlist is gone', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();
    await harness.player.stop();

    await expect(harness.player.play()).rejects.toThrow();
    await expect(harness.player.pause()).rejects.toThrow();
  });
});

describe('stop', () => {
  it('reports stopped, and no paused alongside it, and drops the audio element', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();
    await harness.player.play();
    harness.drain();

    await harness.player.stop();

    expect(harness.drain()).toEqual([{ state: 'stopped', id: '1' }]);
    expect(harness.audioElement).toBeNull();
  });

  it('reports stopped when nothing was playing', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    // clearing the playlist is a change whatever the player was doing
    await harness.player.stop();

    expect(harness.drain()).toEqual([{ state: 'stopped', id: '1' }]);
  });

  it('can be called twice without failing', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.stop();
    await expect(harness.player.stop()).resolves.toBeUndefined();
  });

  // The element is found on the document, the playlist belongs to the instance, so an
  // instance can find an element while it has no item of its own -- a second copy of the
  // plugin, say, or a test runner that shares the page between modules.
  it('drops an element it has no item for, and reports nothing for it', async () => {
    const owner = await PlayerHarness.create();
    const other = await PlayerHarness.create();
    await owner.start();

    await expect(other.player.stop()).resolves.toBeUndefined();

    expect(other.drain()).toEqual([]);
    expect(other.audioElement).toBeNull();
  });
});

describe('next, previous and select', () => {
  it('moves to the next item and reports skipped', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    expect(await harness.player.next()).toEqual({ id: '2' });
    expect(harness.drain()).toEqual([{ state: 'skipped', id: '2' }]);
  });

  it('wraps from the last item to the first and back', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.next();
    await harness.player.next();
    expect(await harness.player.next()).toEqual({ id: '1' });

    expect(await harness.player.previous()).toEqual({ id: '3' });
  });

  it('selects an item by its id and reports skipped', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    expect(await harness.player.select({ id: '3' })).toEqual({ id: '3' });
    expect(harness.drain()).toEqual([{ state: 'skipped', id: '3' }]);
  });

  it('rejects an id that is not in the playlist', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await expect(harness.player.select({ id: 'nope' })).rejects.toThrow();
  });

  it('selects the new item without playing it', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();
    await harness.player.play();
    harness.drain();

    await harness.player.next();

    expect(harness.isPlaying).toBe(false);
    expect((await harness.player.getPosition()).value).toBe(0);
  });

  it('rejects before start', async () => {
    const harness = await PlayerHarness.create();

    await expectRejection(harness.player.next(), 'next()');
    await expectRejection(harness.player.previous(), 'previous()');
    await expectRejection(harness.player.select({ id: '1' }), 'select()');
  });

  it('rejects after stop', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();
    await harness.player.stop();

    await expectRejection(harness.player.next(), 'next()');
    await expectRejection(harness.player.previous(), 'previous()');
    await expectRejection(harness.player.select({ id: '1' }), 'select()');
  });
});

describe('seekTo', () => {
  it('moves to the requested position', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.seekTo({ position: 3 });

    expect((await harness.player.getPosition()).value).toBeGreaterThanOrEqual(3);
  });

  it('resumes a paused player and reports playing', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.seekTo({ position: 1 });

    expect(harness.isPlaying).toBe(true);
    expect(harness.drain()).toEqual([{ state: 'playing', id: '1' }]);
  });

  it('reports nothing while already playing, which is not a change', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();
    await harness.player.play();
    harness.drain();

    await harness.player.seekTo({ position: 2 });

    expect(harness.isPlaying).toBe(true);
    expect(harness.drain()).toEqual([]);
  });

  it('pulls a position past the end back to the end rather than failing', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.seekTo({ position: LONG_ITEM_SECONDS + 60 });

    const duration = (await harness.player.getDuration()).value;
    expect((await harness.player.getPosition()).value).toBeLessThanOrEqual(duration);
  });

  it('rejects before start', async () => {
    const harness = await PlayerHarness.create();

    await expect(harness.player.seekTo({ position: 1 })).rejects.toThrow();
  });
});

describe('getDuration and getPosition', () => {
  it('report zero before start, where iOS and Android also report zero', async () => {
    const harness = await PlayerHarness.create();

    expect(await harness.player.getDuration()).toEqual({ value: 0 });
    expect(await harness.player.getPosition()).toEqual({ value: 0 });
  });

  it('report the loaded item once started', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    expect((await harness.player.getDuration()).value).toBeCloseTo(LONG_ITEM_SECONDS, 1);
    expect((await harness.player.getPosition()).value).toBe(0);
  });

  it('report zero again after stop', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();
    await harness.player.stop();

    expect(await harness.player.getDuration()).toEqual({ value: 0 });
    expect(await harness.player.getPosition()).toEqual({ value: 0 });
  });
});

describe('an item that plays to its end', () => {
  const playOut = async (harness: PlayerHarness) => {
    await harness.player.play();
    await vi.waitFor(() => expect(harness.states).toContain('completed'), { timeout: 10000, interval: 50 });
  };

  it('reports completed and nothing else', async () => {
    const harness = await PlayerHarness.create(SHORT_ITEM_SECONDS);
    await harness.start();

    await playOut(harness);

    expect(harness.states).toEqual(['playing', 'completed']);
    expect(harness.events[harness.events.length - 1]).toEqual({ state: 'completed', id: '1' });
  });

  it('rewinds the item and stays on it rather than advancing', async () => {
    const harness = await PlayerHarness.create(SHORT_ITEM_SECONDS);
    await harness.start();

    await playOut(harness);

    expect((await harness.player.getPosition()).value).toBe(0);
    expect(harness.isPlaying).toBe(false);
  });

  it('stays stopped rather than starting itself over', async () => {
    const harness = await PlayerHarness.create(SHORT_ITEM_SECONDS);
    await harness.start();

    await playOut(harness);
    await new Promise((resolve) => setTimeout(resolve, 1500));

    expect(harness.states).toEqual(['playing', 'completed']);
    expect(harness.isPlaying).toBe(false);
  });

  it('is ready to play again, which is what the rewind is for', async () => {
    const harness = await PlayerHarness.create(SHORT_ITEM_SECONDS);
    await harness.start();
    await playOut(harness);
    harness.drain();

    await harness.player.play();

    expect(harness.isPlaying).toBe(true);
    expect(harness.drain()).toEqual([{ state: 'playing', id: '1' }]);
  });
});

// The state is otherwise only observable through audioPlayerChange, so an app that mounts late
// or missed an event has nothing to recover it from. See getState in definitions.ts.
describe('getState', () => {
  it('reports stopped before start, with nothing loaded', async () => {
    const harness = await PlayerHarness.create();

    expect(await harness.player.getState()).toEqual({ id: '', state: 'stopped', position: 0, duration: 0 });
  });

  it('reports the first item as paused once started', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    const state = await harness.player.getState();

    expect(state).toMatchObject({ id: '1', state: 'paused', position: 0 });
    expect(state.duration).toBeCloseTo(LONG_ITEM_SECONDS, 1);
  });

  it('follows playback as it starts and stops', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.play();
    expect((await harness.player.getState()).state).toBe('playing');

    await vi.waitFor(async () => expect((await harness.player.getState()).position).toBeGreaterThan(0));
    await harness.player.pause();

    const paused = await harness.player.getState();
    expect(paused.state).toBe('paused');
    expect(paused.position).toBe((await harness.player.getPosition()).value);
  });

  it('follows the selected item', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.next();
    expect(await harness.player.getState()).toMatchObject({ id: '2', state: 'paused', position: 0 });

    await harness.player.select({ id: '3' });
    expect((await harness.player.getState()).id).toBe('3');
  });

  it('reports an item that played out as paused on it, rewound to its start', async () => {
    const harness = await PlayerHarness.create(SHORT_ITEM_SECONDS);
    await harness.start();

    await harness.player.play();
    await vi.waitFor(() => expect(harness.states).toContain('completed'), { timeout: 10000, interval: 50 });

    expect(await harness.player.getState()).toMatchObject({ id: '1', state: 'paused', position: 0 });
  });

  it('reports stopped again after stop', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();
    await harness.player.play();

    await harness.player.stop();

    expect(await harness.player.getState()).toEqual({ id: '', state: 'stopped', position: 0, duration: 0 });
  });

  it('reports nothing of its own, since asking is not a change', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.getState();

    expect(harness.states).toEqual([]);
  });
});

// The playhead was only reachable by polling getPosition(), which every app ended up doing for
// itself. See the progress event in definitions.ts.
describe('the progress event', () => {
  const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  /** Every progress event, in order. Registered on the harness's own player. */
  const recordProgress = async (harness: PlayerHarness): Promise<AudioPlayerProgress[]> => {
    const progress: AudioPlayerProgress[] = [];
    await harness.player.addListener('progress', (event: AudioPlayerProgress) => {
      progress.push(event);
    });
    return progress;
  };

  it('reports the playhead of the playing item about twice a second', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.start();

    await harness.player.play();
    await wait(1700);

    // half a second apart by default, so three in 1.7 seconds -- give or take one either side
    // for timers that do not land exactly
    expect(progress.length).toBeGreaterThanOrEqual(2);
    expect(progress.length).toBeLessThanOrEqual(4);

    progress.forEach((event) => {
      expect(event.id).toBe('1');
      expect(event.duration).toBeCloseTo(LONG_ITEM_SECONDS, 1);
    });

    const positions = progress.map((event) => event.position);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
    expect(positions[positions.length - 1]).toBeGreaterThan(positions[0]);
  });

  it('reports at the interval start() was given', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.player.start({ items: harness.items, progressInterval: 0.2 });

    await harness.player.play();
    await wait(1100);

    // five at 0.2 seconds, where the default would have managed two
    expect(progress.length).toBeGreaterThanOrEqual(4);
    expect(progress.length).toBeLessThanOrEqual(6);
  });

  it('falls back to the default for an interval that is not a positive number', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.player.start({ items: harness.items, progressInterval: 0 });

    await harness.player.play();
    await wait(1200);

    expect(progress.length).toBeGreaterThanOrEqual(1);
    expect(progress.length).toBeLessThanOrEqual(3);
  });

  it('reports nothing before playback starts', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.start();

    await wait(1200);

    expect(progress).toEqual([]);
  });

  it('stops reporting once paused', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.start();
    await harness.player.play();
    await vi.waitFor(() => expect(progress.length).toBeGreaterThan(0), { timeout: 2000 });

    await harness.player.pause();
    progress.length = 0;
    await wait(1200);

    expect(progress).toEqual([]);
  });

  it('starts again with the playback, at the same interval', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.start();
    await harness.player.play();
    await harness.player.pause();
    await harness.player.play();

    // a pause and a play inside one interval must not leave two timers running
    await wait(1700);

    expect(progress.length).toBeLessThanOrEqual(4);
  });

  it('stops reporting when the item is skipped away from', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.start();
    await harness.player.play();

    await harness.player.next();
    progress.length = 0;
    await wait(1200);

    expect(progress).toEqual([]);
  });

  it('reports the item it is on after a skip', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.start();

    await harness.player.next();
    await harness.player.play();
    await vi.waitFor(() => expect(progress.length).toBeGreaterThan(0), { timeout: 2000 });

    expect(progress.every((event) => event.id === '2')).toBe(true);
  });

  it('stops reporting once the item played out', async () => {
    const harness = await PlayerHarness.create(SHORT_ITEM_SECONDS);
    const progress = await recordProgress(harness);
    await harness.start();

    await harness.player.play();
    await vi.waitFor(() => expect(harness.states).toContain('completed'), { timeout: 10000, interval: 50 });
    progress.length = 0;
    await wait(1200);

    expect(progress).toEqual([]);
  });

  it('stops reporting after stop', async () => {
    const harness = await PlayerHarness.create();
    const progress = await recordProgress(harness);
    await harness.start();
    await harness.player.play();

    await harness.player.stop();
    progress.length = 0;
    await wait(1200);

    expect(progress).toEqual([]);
  });

  it('is an event of its own, and adds nothing to audioPlayerChange', async () => {
    const harness = await PlayerHarness.create();
    await recordProgress(harness);
    await harness.start();

    await harness.player.play();
    await wait(1200);

    expect(harness.states).toEqual(['playing']);
  });
});

describe('audio output', () => {
  it('always reports external, since the browser picks the output itself', async () => {
    const harness = await PlayerHarness.create();

    expect(await harness.player.getAudioOutput()).toEqual({ output: 'external' });

    await harness.start();
    expect(await harness.player.getAudioOutput()).toEqual({ output: 'external' });
  });

  it('accepts the earpiece and speaker calls without changing anything', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await expect(harness.player.setEarpiece()).resolves.toBeUndefined();
    await expect(harness.player.setSpeaker()).resolves.toBeUndefined();

    expect(await harness.player.getAudioOutput()).toEqual({ output: 'external' });
    expect(harness.states).toEqual([]);
  });
});

describe('the media session', () => {
  it('describes the loaded item to the browser', async () => {
    const harness = await PlayerHarness.create();

    await harness.start();

    expect(navigator.mediaSession.metadata?.title).toBe('Item 1');
    expect(navigator.mediaSession.metadata?.artist).toBe('Animals');
  });

  it('follows the item as it changes', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.next();

    expect(navigator.mediaSession.metadata?.title).toBe('Item 2');
  });

  it('tells the browser whether the audio is playing', async () => {
    const harness = await PlayerHarness.create();
    await harness.start();

    await harness.player.play();
    expect(navigator.mediaSession.playbackState).toBe('playing');

    await harness.player.pause();
    expect(navigator.mediaSession.playbackState).toBe('paused');
  });

  it('keeps the scrubber in step with the audio', async () => {
    const positionStates: any[] = [];
    const setPositionState = vi
      .spyOn(navigator.mediaSession, 'setPositionState')
      .mockImplementation((state?: MediaPositionState) => {
        positionStates.push(state);
      });

    try {
      const harness = await PlayerHarness.create();
      await harness.start();
      positionStates.length = 0;

      await harness.player.seekTo({ position: 3 });

      // Without this the browser's own scrubber sits wherever the item was loaded, which is
      // the web side of what the lock screen transport does on iOS.
      expect(positionStates.length).toBeGreaterThan(0);
      expect(positionStates[positionStates.length - 1].position).toBeGreaterThanOrEqual(3);
    } finally {
      setPositionState.mockRestore();
    }
  });

  it('drives the player from the browser controls', async () => {
    const handlers = captureActionHandlers();
    const harness = await PlayerHarness.create();
    await harness.start();

    // The handlers are not awaited -- the browser calls them and moves on -- so each step
    // waits for the event rather than for the element, whose paused flag flips before the
    // plugin has reported anything.
    handlers.get('play')?.({ action: 'play' });
    await vi.waitFor(() => expect(harness.states).toEqual(['playing']));
    expect(harness.drain()).toEqual([{ state: 'playing', id: '1' }]);
    expect(harness.isPlaying).toBe(true);

    handlers.get('pause')?.({ action: 'pause' });
    await vi.waitFor(() => expect(harness.states).toEqual(['paused']));
    expect(harness.drain()).toEqual([{ state: 'paused', id: '1' }]);
    expect(harness.isPlaying).toBe(false);

    handlers.get('nexttrack')?.({ action: 'nexttrack' });
    await vi.waitFor(() => expect(harness.states).toEqual(['skipped']));
    expect(harness.drain()).toEqual([{ state: 'skipped', id: '2' }]);
  });

  it('refuses a browser control used before anything is loaded, but refuses quietly', async () => {
    // The handlers are registered in the constructor, so the operating system can offer the
    // controls before start(). Refusing is right -- there is nothing to play -- but an
    // unhandled rejection reaches the app's error reporting as a crash it cannot act on.
    const handlers = captureActionHandlers();
    const rejections: PromiseRejectionEvent[] = [];
    const record = (event: PromiseRejectionEvent) => {
      rejections.push(event);
      event.preventDefault();
    };
    window.addEventListener('unhandledrejection', record);

    try {
      await PlayerHarness.create();

      handlers.get('play')?.({ action: 'play' });
      handlers.get('pause')?.({ action: 'pause' });
      handlers.get('seekto')?.({ action: 'seekto', seekTime: 2 });

      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(rejections).toEqual([]);
    } finally {
      window.removeEventListener('unhandledrejection', record);
    }
  });
});
