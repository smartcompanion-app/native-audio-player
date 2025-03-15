import type { PluginListenerHandle } from '@capacitor/core';

export interface NativeAudioPlayerPlugin {

  setEarpiece(): Promise<void>;

  setSpeaker(): Promise<void>;

  start(options: StartOptions): Promise<{id: string}>;

  stop(): Promise<void>;
  
  play(): Promise<void>;

  pause(): Promise<void>;

  select(options: {id: string}): Promise<{id: string}>;

  next(): Promise<{id: string}>;

  previous(): Promise<{id: string}>;

  seekTo(options: {position: number}): Promise<void>;

  getDuration(): Promise<{value: number}>;

  getPosition(): Promise<{value: number}>;

  addListener(
    eventName: 'update', 
    listener: (result: {
      state: 'playing' | 'paused' | 'skip' | 'completed', 
      id: string
    }) => void
  ): Promise<PluginListenerHandle>;

}

export interface StartOptions {
  items: Item[]
}

export interface Item {
  id: string;
  title: string;
  subtitle: string;
  audioUri: string;
  imageUri: string;
}
