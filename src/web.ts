import { WebPlugin } from '@capacitor/core';

import type { NativeAudioPlayerPlugin, StartOptions, Item, AudioOutput } from './definitions';

const getMediaSession = () => {
  return 'mediaSession' in navigator ? (navigator as any).mediaSession : null;
};

const createMediaMetadata = (init: any) => {
  return 'MediaMetadata' in window ? new (window as any).MediaMetadata(init) : null;
};

const updateMediaSessionMetadata = (item: Item, duration: number) => {
  const mediaSession = getMediaSession();
  if (mediaSession) {
    mediaSession.metadata = createMediaMetadata({
      title: item.title,
      artist: item.subtitle,
      album: item.subtitle,
      artwork: [{ src: item.imageUri }],
    });
    mediaSession.setPositionState({
      position: 0,
      duration: duration,
      playbackRate: 1.0,
    });
  }
};

/**
 * Tells the browser whether the audio is running, which is what its own media control shows.
 * Left alone it stays at 'none' and the control offers play while the audio is playing.
 */
const updateMediaSessionPlaybackState = (state: 'none' | 'playing' | 'paused') => {
  const mediaSession = getMediaSession();
  if (mediaSession) {
    mediaSession.playbackState = state;
  }
};

/**
 * Moves the scrubber on the browser's media control to where the audio actually is. Set once
 * at load time it would sit at the start for the whole item, the same way the iOS lock screen
 * did before it was given the position on every change.
 */
const updateMediaSessionPosition = (audioElement: HTMLAudioElement) => {
  const mediaSession = getMediaSession();

  // setPositionState rejects a duration it cannot make sense of, and an element whose
  // metadata has not arrived reports NaN
  if (!mediaSession || !(audioElement.duration > 0)) {
    return;
  }

  mediaSession.setPositionState({
    position: Math.min(Math.max(audioElement.currentTime, 0), audioElement.duration),
    duration: audioElement.duration,
    playbackRate: audioElement.playbackRate || 1.0,
  });
};

/**
 * A browser media control is not a caller that can handle a rejection -- there is nowhere to
 * return the failure to. Refusing before anything is loaded is right, but it has to stay
 * quiet: an unhandled rejection reaches an app's error reporting as a crash it cannot act on.
 */
const ignoreUnreachablePlayer = (error: unknown) => {
  console.warn('native audio player: ignoring a browser media control', error);
};

export class NativeAudioPlayerWeb extends WebPlugin implements NativeAudioPlayerPlugin {
  protected items: Item[] = [];
  protected currentIndex = 0;

  constructor() {
    super();

    const mediaSession = getMediaSession();
    if (mediaSession) {
      mediaSession.setActionHandler('play', () => {
        this.play().catch(ignoreUnreachablePlayer);
      });
      mediaSession.setActionHandler('pause', () => {
        this.pause().catch(ignoreUnreachablePlayer);
      });
      mediaSession.setActionHandler('nexttrack', () => {
        this.next().catch(ignoreUnreachablePlayer);
      });
      mediaSession.setActionHandler('previoustrack', () => {
        this.previous().catch(ignoreUnreachablePlayer);
      });
      mediaSession.setActionHandler('seekto', (details: any) => {
        if (details?.seekTime !== undefined) {
          this.seekTo({ position: details.seekTime }).catch(ignoreUnreachablePlayer);
        }
      });
    }
  }

  getAudioElement(): HTMLAudioElement | null {
    return document.querySelector('#web-audio') as HTMLAudioElement | null;
  }

  /**
   * Everything that moves the player needs one. Before start() and after stop() there is no
   * element, and acting would only promise playback that cannot happen -- see the behaviour
   * overview in the README.
   */
  protected requireAudioElement(): HTMLAudioElement {
    const audioElement = this.getAudioElement();

    if (!audioElement) {
      throw new Error('could not play without a loaded audio item');
    }

    return audioElement;
  }

  async setEarpiece(): Promise<void> {
    console.log('setEarpiece not implemented on the web');
  }

  async setSpeaker(): Promise<void> {
    console.log('setSpeaker not implemented on the web');
  }

  // The browser picks the output device itself and gives no way to route to an earpiece,
  // so the plugin never controls the route on the web and always reports it as 'external'.
  async getAudioOutput(): Promise<{ output: AudioOutput }> {
    return { output: 'external' };
  }

  async start(options: StartOptions): Promise<{ id: string }> {
    this.currentIndex = 0;
    this.items = JSON.parse(JSON.stringify(options.items));
    return this.loadAudio(this.items[this.currentIndex]);
  }

  async stop(): Promise<void> {
    const audioElement = this.getAudioElement();
    if (audioElement) {
      this.notifyListeners('audioPlayerChange', { id: this.items[this.currentIndex].id, state: 'paused' });
      audioElement.pause();
      audioElement.remove();
    }
    updateMediaSessionPlaybackState('none');
    this.items = [];
  }

  async play(): Promise<void> {
    const audioElement = this.requireAudioElement();

    await audioElement.play();
    updateMediaSessionPlaybackState('playing');
    updateMediaSessionPosition(audioElement);
    this.notifyListeners('audioPlayerChange', { id: this.items[this.currentIndex].id, state: 'playing' });
  }

  async pause(): Promise<void> {
    const audioElement = this.requireAudioElement();

    // Pausing a player that is not running changes nothing, and a state is reported per
    // change rather than per call -- see AudioPlayerState in definitions.ts. An app that
    // pauses while a slider is dragged calls this on every input event, which is many times
    // over one gesture, and only the first of them stops anything.
    //
    // stop() reports its pause whatever was happening, since clearing the playlist is a
    // change either way, and so it does not come through here.
    if (audioElement.paused) {
      return;
    }

    audioElement.pause();
    updateMediaSessionPlaybackState('paused');
    updateMediaSessionPosition(audioElement);
    this.notifyListeners('audioPlayerChange', { id: this.items[this.currentIndex].id, state: 'paused' });
  }

  async select(options: { id: string }): Promise<{ id: string }> {
    const index = this.findItemIndexById(options.id);

    if (index >= 0) {
      this.currentIndex = index;
      const result = await this.loadAudio(this.items[this.currentIndex]);
      this.notifyListeners('audioPlayerChange', { state: 'skip', id: result.id });
      return result;
    }

    throw new Error(`Item with id ${options.id} doesn't exist`);
  }

  /**
   * There is no item to move to before start() and after stop(). Without this the index
   * arithmetic below runs on an empty playlist, loads `undefined` and fails with whatever
   * that happens to throw -- and previous() leaves the index at -1, where it stays.
   */
  protected requireItems(failure: string): void {
    if (this.items.length === 0) {
      throw new Error(failure);
    }
  }

  async next(): Promise<{ id: string }> {
    this.requireItems('could not switch to next item');

    if (this.currentIndex >= this.items.length - 1) {
      this.currentIndex = 0;
    } else {
      this.currentIndex += 1;
    }

    const result = await this.loadAudio(this.items[this.currentIndex]);
    this.notifyListeners('audioPlayerChange', { state: 'skip', id: result.id });
    return result;
  }

  async previous(): Promise<{ id: string }> {
    this.requireItems('could not switch to previous item');

    if (this.currentIndex <= 0) {
      this.currentIndex = this.items.length - 1;
    } else {
      this.currentIndex -= 1;
    }

    const result = await this.loadAudio(this.items[this.currentIndex]);
    this.notifyListeners('audioPlayerChange', { state: 'skip', id: result.id });
    return result;
  }

  async seekTo(options: { position: number }): Promise<void> {
    const audioElement = this.requireAudioElement();

    // the element clamps a position outside the media to its nearest end on its own
    audioElement.currentTime = options.position;
    updateMediaSessionPosition(audioElement);

    // seeking resumes, so a listener who dragged the scrubber hears the audio carry on from
    // where they dropped it. Already playing is not a change, and reports nothing.
    if (audioElement.paused) {
      await this.play();
    }
  }

  async getDuration(): Promise<{ value: number }> {
    const audioElement = this.getAudioElement();
    return { value: audioElement && audioElement.duration > 0 ? audioElement.duration : 0 };
  }

  async getPosition(): Promise<{ value: number }> {
    const audioElement = this.getAudioElement();
    return { value: audioElement ? audioElement.currentTime : 0 };
  }

  loadAudio(item: Item): Promise<{ id: string }> {
    return new Promise((resolve, reject) => {
      const existingAudio = this.getAudioElement();
      if (existingAudio) {
        existingAudio.remove();
      }

      const audio = document.createElement('audio');
      audio.addEventListener('loadedmetadata', () => {
        updateMediaSessionMetadata(item, audio.duration);
        resolve({ id: item.id });
      });
      // Without this an item that cannot be loaded leaves the caller waiting for metadata
      // that will never arrive, and start() never settles. iOS and Android both reject.
      // The element goes with it, so nothing is left behind for play() to accept.
      audio.addEventListener('error', () => {
        audio.remove();
        reject(new Error(`could not load audio item ${item.id}`));
      });
      audio.addEventListener('ended', () => {
        // an item that played out has to be ready to play again rather than sit on its end --
        // see AudioPlayerState in definitions.ts
        audio.currentTime = 0;
        updateMediaSessionPlaybackState('paused');
        updateMediaSessionPosition(audio);
        this.notifyListeners('audioPlayerChange', { state: 'completed', id: item.id });
      });
      audio.setAttribute('id', 'web-audio');
      audio.src = item.audioUri;
      document.body.appendChild(audio);
    });
  }

  findItemIndexById(id: string): number {
    if (this.items) {
      for (let index = 0; index < this.items.length; index++) {
        if (this.items[index].id == id) {
          return index;
        }
      }
    }
    return -1;
  }
}
