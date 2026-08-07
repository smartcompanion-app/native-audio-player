import type { PluginListenerHandle } from '@capacitor/core';

export interface NativeAudioPlayerPlugin {
  /**
   * Set the audio output to the earpiece. Has no audible effect while an external device
   * such as headphones or a bluetooth speaker is connected.
   *
   * Playback pauses, as it does on every audio output change — see
   * {@link NativeAudioPlayerPlugin.addListener} for `audioOutputChange`.
   * @returns {Promise<void>} A promise that resolves when the audio output is set to the earpiece.
   */
  setEarpiece(): Promise<void>;

  /**
   * Set the audio output to the speaker. Has no audible effect while an external device
   * such as headphones or a bluetooth speaker is connected.
   *
   * Playback pauses, as it does on every audio output change — see
   * {@link NativeAudioPlayerPlugin.addListener} for `audioOutputChange`.
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
   *
   * Rejects when there is nothing to play, which is the case before {@link NativeAudioPlayerPlugin.start}
   * and after {@link NativeAudioPlayerPlugin.stop} -- start the playlist again rather than
   * calling this.
   * @returns {Promise<void>} A promise that resolves when the audio starts playing.
   */
  play(): Promise<void>;

  /**
   * Pause the currently playing audio item.
   *
   * Reports `paused` only when something was playing. Pausing a player that is already
   * stopped is accepted and changes nothing, so it reports nothing -- an app that pauses
   * while a scrubber is dragged calls this many times over one gesture and hears about the
   * first of them.
   * @returns {Promise<void>} A promise that resolves when the audio is paused.
   */
  pause(): Promise<void>;

  /**
   * Select an audio item from the playlist by its id.
   *
   * Rejects when no item carries that id, rather than resolving with whatever was already
   * selected -- a caller that asked for one item and silently got another has no way to tell.
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
   *
   * Seeking resumes, so a listener who dragged a scrubber hears the audio carry on from where
   * they dropped it. `playing` is reported only when that actually started something: a player
   * that was already running carries on and reports nothing.
   *
   * A position outside the item is pulled to the nearest end of it, so seeking past the end
   * leaves the player on the last moment rather than somewhere it cannot play from. That is
   * not the same as the item finishing: `completed` follows only once the audio actually runs
   * out, which for a player that is already playing happens immediately, and for a paused one
   * waits for the next {@link NativeAudioPlayerPlugin.play}.
   * @param {number} options.position - The position in seconds to seek to. Fractional seconds
   * are kept, so a scrubber can hand back what {@link NativeAudioPlayerPlugin.getPosition}
   * reported without rounding it first.
   * @returns {Promise<void>} A promise that resolves when the seek operation is complete.
   */
  seekTo(options: { position: number }): Promise<void>;

  /**
   * Get the duration of the current audio item in seconds.
   *
   * Seconds are fractional on every platform. How finely they are resolved is the player's
   * own business, so the same audio can report durations that differ by a few milliseconds
   * across platforms -- compare with a tolerance rather than for equality.
   * @returns {Promise<{value: number}>} The duration in fractional seconds.
   */
  getDuration(): Promise<{ value: number }>;

  /**
   * Get the current position of the audio item in seconds.
   *
   * Seconds are fractional, which is what a progress bar needs to move smoothly. Callers that
   * want whole seconds can round the value themselves.
   * @returns {Promise<{value: number}>} The current position in fractional seconds.
   */
  getPosition(): Promise<{ value: number }>;

  /**
   * Get the audio output the player is currently routed to.
   * @returns {Promise<{output: AudioOutput}>} The current audio output.
   */
  getAudioOutput(): Promise<{ output: AudioOutput }>;

  /**
   * Add an event listener for player changes. The listener should accept an event object
   * containing the current state and id of the audio item.
   *
   * The event reports every change, whichever caused it: a call on this plugin, a lock screen
   * or notification control, a headset button, or the audio itself running out. An app that
   * mirrors playback in its own UI should follow this event rather than assume its own calls
   * are the only thing moving the player.
   *
   * See {@link AudioPlayerState} for what each state promises.
   * @returns {Promise<PluginListenerHandle>} The listener can be removed using the returned handle.
   */
  addListener(
    eventName: 'audioPlayerChange',
    listener: (result: AudioPlayerChange) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Add an event listener for audio output changes. Fires both when the output is changed
   * through {@link NativeAudioPlayerPlugin.setEarpiece} or {@link NativeAudioPlayerPlugin.setSpeaker}
   * and when the route changes on its own, e.g. when headphones are unplugged or a bluetooth
   * device connects.
   *
   * Playback pauses on every one of these changes, so that audio meant for the earpiece cannot
   * carry on out loud through a different output. A `audioPlayerChange` event with the `paused`
   * state is emitted alongside this one whenever something was playing. Resuming is left to the
   * app: call {@link NativeAudioPlayerPlugin.play} from this listener to play on regardless.
   * @returns {Promise<PluginListenerHandle>} The listener can be removed using the returned handle.
   */
  addListener(
    eventName: 'audioOutputChange',
    listener: (result: AudioOutputChange) => void,
  ): Promise<PluginListenerHandle>;
}

/**
 * The playback state of the player.
 *
 * Exactly one event is emitted per transition, so a state never arrives paired with another
 * describing the same change -- and a call that changes nothing reports nothing at all. Every
 * state below behaves the same way on iOS, Android and the web.
 *
 * - `playing` -- playback started or resumed.
 * - `paused` -- playback stopped and the position was kept. Emitted for a
 *   {@link NativeAudioPlayerPlugin.pause} call that stopped something, for a
 *   {@link NativeAudioPlayerPlugin.stop} call whatever was happening, for an output change, and
 *   for an interruption -- an incoming call, or another app taking the audio -- that stopped
 *   something, but never for an item that reached its end: that is `completed`. The player is
 *   not started again when an interruption ends, and nothing is reported then, so an app that
 *   wants to carry on has to call {@link NativeAudioPlayerPlugin.play} itself. Interruptions
 *   are not reported on the web, where the browser exposes nothing to observe them with.
 * - `skip` -- the selected item changed through {@link NativeAudioPlayerPlugin.next},
 *   {@link NativeAudioPlayerPlugin.previous} or {@link NativeAudioPlayerPlugin.select}. The new
 *   item is selected but not playing, so it takes a {@link NativeAudioPlayerPlugin.play} to
 *   start it. The `id` is the item moved to.
 * - `completed` -- the item played through to its end. The player stops there rather than
 *   advancing, so nothing else starts on its own, and the item is rewound so a following
 *   {@link NativeAudioPlayerPlugin.play} starts it again from the beginning. The `id` is the
 *   item that finished, and it stays the selected one. Advancing is left to the app: call
 *   {@link NativeAudioPlayerPlugin.next} from this listener to play through a playlist.
 */
export type AudioPlayerState = 'playing' | 'paused' | 'skip' | 'completed';

/**
 * The audio output the player is routed to.
 *
 * `external` means the audio is not routed to the built-in earpiece or speaker, which is the
 * case whenever an external device such as headphones or a bluetooth speaker is connected.
 * The earpiece and speaker settings do not apply while an external device is in use, so
 * neither value would describe what is actually heard.
 *
 * The built-in output starts on the `speaker` on both platforms, so audio a listener has not
 * asked to keep private is audible without holding the phone to an ear.
 * {@link NativeAudioPlayerPlugin.setEarpiece} is what opts into the earpiece.
 */
export type AudioOutput = 'earpiece' | 'speaker' | 'external';

/**
 * The payload of the `audioPlayerChange` event.
 */
export interface AudioPlayerChange {
  /**
   * The playback state the player changed to.
   */
  state: AudioPlayerState;

  /**
   * The id of the audio item the state refers to.
   */
  id: string;
}

/**
 * The payload of the `audioOutputChange` event.
 */
export interface AudioOutputChange {
  /**
   * The audio output the player changed to.
   */
  output: AudioOutput;
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
