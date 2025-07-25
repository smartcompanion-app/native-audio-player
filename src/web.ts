import { WebPlugin } from '@capacitor/core';

import type { NativeAudioPlayerPlugin, StartOptions, Item } from './definitions';

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

export class NativeAudioPlayerWeb extends WebPlugin implements NativeAudioPlayerPlugin {
  protected items: Item[] = [];
  protected currentIndex = 0;

  constructor() {
    super();

    const mediaSession = getMediaSession();
    if (mediaSession) {
      mediaSession.setActionHandler('play', () => {
        this.play();
      });
      mediaSession.setActionHandler('pause', () => {
        this.pause();
      });
      mediaSession.setActionHandler('nexttrack', () => {
        this.next();
      });
      mediaSession.setActionHandler('previoustrack', () => {
        this.previous();
      });
      mediaSession.setActionHandler('seekto', (details: any) => {
        if (details?.seekTime !== undefined) {
          this.seekTo({ position: details.seekTime });
        }
      });
    }
  }

  getAudioElement(): HTMLAudioElement | null {
    return document.querySelector('#web-audio') as HTMLAudioElement | null;
  }

  async setEarpiece(): Promise<void> {
    console.log('setEarpiece not implemented on the web');
  }

  async setSpeaker(): Promise<void> {
    console.log('setSpeaker not implemented on the web');
  }

  async start(options: StartOptions): Promise<{ id: string }> {
    this.currentIndex = 0;
    this.items = JSON.parse(JSON.stringify(options.items));
    return this.loadAudio(this.items[this.currentIndex]);
  }

  async stop(): Promise<void> {
    const audioElement = this.getAudioElement();
    if (audioElement) {
      audioElement.pause();
      audioElement.remove();
    }
    this.items = [];
  }

  async play(): Promise<void> {
    const audioElement = this.getAudioElement();
    if (audioElement) {
      await audioElement.play();
      this.notifyListeners('update', { id: this.items[this.currentIndex].id, state: 'playing' });
    }
  }

  async pause(): Promise<void> {
    const audioElement = this.getAudioElement();
    if (audioElement) {
      await audioElement.pause();
      this.notifyListeners('update', { id: this.items[this.currentIndex].id, state: 'paused' });
    }
  }

  async select(options: { id: string }): Promise<{ id: string }> {
    const index = this.findItemIndexById(options.id);

    if (index >= 0) {
      this.currentIndex = index;
      const result = await this.loadAudio(this.items[this.currentIndex]);
      this.notifyListeners('update', { state: 'skip', id: result.id });
      return result;
    }

    throw new Error(`Item with id ${options.id} doesn't exist`);
  }

  async next(): Promise<{ id: string }> {
    if (this.currentIndex >= this.items.length - 1) {
      this.currentIndex = 0;
    } else {
      this.currentIndex += 1;
    }

    const result = await this.loadAudio(this.items[this.currentIndex]);
    this.notifyListeners('update', { state: 'skip', id: result.id });
    return result;
  }

  async previous(): Promise<{ id: string }> {
    if (this.currentIndex <= 0) {
      this.currentIndex = this.items.length - 1;
    } else {
      this.currentIndex -= 1;
    }

    const result = await this.loadAudio(this.items[this.currentIndex]);
    this.notifyListeners('update', { state: 'skip', id: result.id });
    return result;
  }

  async seekTo(options: { position: number }): Promise<void> {
    const audioElement = this.getAudioElement();
    if (audioElement) {
      audioElement.currentTime = options.position;
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
    return new Promise((resolve) => {
      const existingAudio = this.getAudioElement();
      if (existingAudio) {
        existingAudio.remove();
      }

      const audio = document.createElement('audio');
      audio.addEventListener('loadedmetadata', () => {
        updateMediaSessionMetadata(item, audio.duration);
        resolve({ id: item.id });
      });
      audio.addEventListener('ended', () => {
        this.notifyListeners('update', { state: 'completed', id: item.id });
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
