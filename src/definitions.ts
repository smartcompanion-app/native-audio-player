import type { PluginListenerHandle } from '@capacitor/core';

export interface NativeAudioPlayerPlugin {
  
  /**
   * Set the audio output to the earpiece.
   * @returns {Promise<void>} A promise that resolves when the audio output is set to the earpiece.
   */
  setEarpiece(): Promise<void>;

  /**
   * Set the audio output to the speaker.
   * @returns {Promise<void>} A promise that resolves when the audio output is set to the speaker.
   */
  setSpeaker(): Promise<void>;

  /**
   * Initialize the audio player with a list of audio items.
   * @param {StartOptions} options - The options for starting the audio player.
   * @returns {Promise<{id: string}>} The id of the first audio item.
   */
  start(options: StartOptions): Promise<{ id: string }>;

  /**
   * Stop the currently playing audio item and clear the playlist.
   * @returns {Promise<void>} A promise that resolves when the audio is stopped.
   */
  stop(): Promise<void>;

  /**
   * Play the currently selected audio item.
   * @returns {Promise<void>} A promise that resolves when the audio starts playing.
   */
  play(): Promise<void>;

  /**
   * Pause the currently playing audio item.
   * @returns {Promise<void>} A promise that resolves when the audio is paused.
   */
  pause(): Promise<void>;

  /**
   * Select an audio item from the playlist by its id.
   * @param {string} options.id - The id of the audio item to select.
   * @returns {Promise<{id: string}>} The id of the selected audio item.
   */
  select(options: { id: string }): Promise<{ id: string }>;

  /**
   * Skip to the next audio item in the playlist.
   * @returns {Promise<{id: string}>} The ID of the next audio item.
   */
  next(): Promise<{ id: string }>;

  /**
   * Skip to the previous audio item in the playlist.
   * @returns {Promise<{id: string}>} The ID of the previous audio item.
   */
  previous(): Promise<{ id: string }>;

  /**
   * Seek to a specific position in the currently playing audio item.
   * @param {number} options.position - The position in seconds to seek to.
   * @returns {Promise<void>} A promise that resolves when the seek operation is complete.
   */
  seekTo(options: { position: number }): Promise<void>;

  /**
   * Get the duration of the current audio item in seconds.
   * @returns {Promise<{value: number}>} The duration in seconds.
   */
  getDuration(): Promise<{ value: number }>;

  /**
   * Get the current position of the audio item in seconds.
   * @returns {Promise<{value: number}>} The current position in seconds.
   */
  getPosition(): Promise<{ value: number }>;

  /**
   * Add an event listener for the update event. The listener should accept an event object
   * containing the current state and id of the audio item.
   * @returns {Promise<PluginListenerHandle>} The listener can be removed using the returned handle.
   */
  addListener(
    eventName: 'update',
    listener: (result: { state: 'playing' | 'paused' | 'skip' | 'completed'; id: string }) => void,
  ): Promise<PluginListenerHandle>;
}

/**
 * Options for starting the audio player.
 */
export interface StartOptions {
  /**
   * A list of audio items to be initialized in the audio player.
   */
  items: Item[];
}

/**
 * Represents an audio item in the playlist.
 */
export interface Item {
  /**
   * The unique identifier for the audio item.
   */
  id: string;

  /**
   * The title of the audio item, which is e.g. displayed in the notification player.
   */
  title: string;

  /**
   * The subtitle of the audio item, which is e.g. displayed in the notification player.
   */
  subtitle: string;

  /**
   * The local file URI of the audio file.
   */
  audioUri: string;

  /**
   * The local file URI of the image associated with the audio item.
   */
  imageUri: string;
}
