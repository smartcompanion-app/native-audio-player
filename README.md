# native-audio-player

> Play native audio from a Capacitor app.

[![npm version](https://img.shields.io/npm/v/@smartcompanion/native-audio-player.svg)](https://www.npmjs.com/package/@smartcompanion/native-audio-player)
[![CI](https://github.com/smartcompanion-app/native-audio-player/actions/workflows/ci.yml/badge.svg)](https://github.com/smartcompanion-app/native-audio-player/actions/workflows/ci.yml)
[![license](https://img.shields.io/npm/l/@smartcompanion/native-audio-player.svg)](LICENSE)

## ✨ Features

 - 🔈 Toggle between `Speaker` and `Earpiece` as audio output
 - 🎶 Audio keeps playing in the background, when app is minimized
 - 🔓 Native players in notifications and lock screens
 - 📱 Support for Android, iOS, Web (only Speaker)

## Maintainers

| Maintainer  | GitHub                                      | Social                                                          |
| ----------- | ------------------------------------------- | --------------------------------------------------------------- |
| Stefan Huber | [stefanhuber](https://github.com/stefanhuber) | [Linkedin](https://www.linkedin.com/in/stefan-huber/) |

## Requirements

| Requirement | Version |
| --- | --- |
| Capacitor | 8.0.0 or later |
| iOS | 15.0 or later |
| Android | API level 24 (Android 7.0) or later |

## Install

```bash
npm install @smartcompanion/native-audio-player
npx cap sync
```

## Configuration

| Platform | Configuration |
| --- | --- |
| iOS | Audio has to be added as Background Mode within Signing & Capabilities of the app, in order to keep audio playing in the background |
| Android | The plugin has a `AndroidManifest.xml`, which includes all configurations | 

## Usage

```typescript
import { NativeAudioPlayer } from '@smartcompanion/native-audio-player';

// 1. Hand over the playlist. The first item is selected and prepared,
//    but nothing plays yet — call play() when you are ready.
await NativeAudioPlayer.start({
  items: [
    {
      id: 'elephant',
      title: 'Elephant',
      subtitle: 'Animals',
      audioUri: elephantAudioUri, // local file URI, see below
      imageUri: elephantImageUri, // shown in the notification / lock screen
    },
    {
      id: 'leopard',
      title: 'Leopard',
      subtitle: 'Animals',
      audioUri: leopardAudioUri,
      imageUri: leopardImageUri,
    },
  ],
});

// 2. Follow the player state. The event fires for your own calls *and* for
//    the native notification and lock screen controls, so this is the single
//    place where your UI stays in sync.
const listener = await NativeAudioPlayer.addListener('update', async ({ state, id }) => {
  switch (state) {
    case 'playing': // playback started or resumed
    case 'paused': // playback paused
    case 'skip': // another item became the current one
      break;
    case 'completed': // the item reached its end — the player stops there
      await NativeAudioPlayer.next();
      await NativeAudioPlayer.play();
      break;
  }
});

// 3. Control playback
await NativeAudioPlayer.play();
await NativeAudioPlayer.pause();
await NativeAudioPlayer.next();
await NativeAudioPlayer.previous();
await NativeAudioPlayer.select({ id: 'leopard' });
await NativeAudioPlayer.seekTo({ position: 30 }); // seconds

const { value: duration } = await NativeAudioPlayer.getDuration(); // seconds
const { value: position } = await NativeAudioPlayer.getPosition(); // seconds

// 4. Route the audio (no-op on the web)
await NativeAudioPlayer.setEarpiece();
await NativeAudioPlayer.setSpeaker();

// 5. Clean up — releases the player and removes the native player UI
await listener.remove();
await NativeAudioPlayer.stop();
```

### Preparing local file URIs

On Android and iOS the player reads audio and images from the device, so remote
files have to be downloaded once — for example with
[`@capacitor/filesystem`](https://capacitorjs.com/docs/apis/filesystem) into
`Directory.Data`. On the web you can pass the remote URL straight through:

```typescript
import { Capacitor } from '@capacitor/core';
import { Directory, Filesystem } from '@capacitor/filesystem';

const toLocalUri = async (url: string, filename: string): Promise<string> => {
  if (Capacitor.getPlatform() === 'web') {
    return url;
  }

  const blob = await (await fetch(url)).blob();
  const data = await new Promise<string>((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.readAsDataURL(blob);
  });

  await Filesystem.writeFile({ path: filename, directory: Directory.Data, data });
  return (await Filesystem.getUri({ path: filename, directory: Directory.Data })).uri;
};

const elephantAudioUri = await toLocalUri('https://example.com/elephant.mp3', 'elephant.mp3');
```

On iOS the file is looked up by its filename in the app's documents directory,
so keep the files flat in `Directory.Data` rather than in sub-folders.

### Good to know

- `start()` only prepares the playlist — playback begins with `play()`.
- The player does not advance on its own. When an item finishes you get a
  `completed` event and decide what happens next (see the example above).
- Positions and durations are whole seconds.
- `setEarpiece()` / `setSpeaker()` only override the built-in output. When
  headphones or Bluetooth are connected, that route stays untouched.

In folder `./example` a full usage example is available. This example is also used for automated and manual testing.

| Demo App | Native Audio Player |
|---|---|
| ![Demo App Screen](docs/demo-app-screen.png) | ![Native Audio Player (Android)](docs/native-audio-player.png) |

## Other Audio Player Plugins

 - [@capacitor-community/native-audio](https://github.com/capacitor-community/native-audio)
 - [@capawesome-team/capacitor-audio-player](https://capawesome.io/plugins/audio-player/)
 - [@capgo/native-audio](https://github.com/Cap-go/capacitor-native-audio)
 - [@mediagrid/capacitor-native-audio](https://github.com/mediagrid/capacitor-native-audio)

## API

<docgen-index>

* [`setEarpiece()`](#setearpiece)
* [`setSpeaker()`](#setspeaker)
* [`start(...)`](#start)
* [`stop()`](#stop)
* [`play()`](#play)
* [`pause()`](#pause)
* [`select(...)`](#select)
* [`next()`](#next)
* [`previous()`](#previous)
* [`seekTo(...)`](#seekto)
* [`getDuration()`](#getduration)
* [`getPosition()`](#getposition)
* [`addListener('update', ...)`](#addlistenerupdate-)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### setEarpiece()

```typescript
setEarpiece() => Promise<void>
```

Set the audio output to the earpiece.

--------------------


### setSpeaker()

```typescript
setSpeaker() => Promise<void>
```

Set the audio output to the speaker.

--------------------


### start(...)

```typescript
start(options: StartOptions) => Promise<{ id: string; }>
```

Initialize the audio player with a list of audio items.

| Param         | Type                                                  | Description                                  |
| ------------- | ----------------------------------------------------- | -------------------------------------------- |
| **`options`** | <code><a href="#startoptions">StartOptions</a></code> | - The options for starting the audio player. |

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### stop()

```typescript
stop() => Promise<void>
```

Stop the currently playing audio item and clear the playlist.

--------------------


### play()

```typescript
play() => Promise<void>
```

Play the currently selected audio item.

--------------------


### pause()

```typescript
pause() => Promise<void>
```

Pause the currently playing audio item.

--------------------


### select(...)

```typescript
select(options: { id: string; }) => Promise<{ id: string; }>
```

Select an audio item from the playlist by its id.

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### next()

```typescript
next() => Promise<{ id: string; }>
```

Skip to the next audio item in the playlist.

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### previous()

```typescript
previous() => Promise<{ id: string; }>
```

Skip to the previous audio item in the playlist.

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### seekTo(...)

```typescript
seekTo(options: { position: number; }) => Promise<void>
```

Seek to a specific position in the currently playing audio item.

| Param         | Type                               |
| ------------- | ---------------------------------- |
| **`options`** | <code>{ position: number; }</code> |

--------------------


### getDuration()

```typescript
getDuration() => Promise<{ value: number; }>
```

Get the duration of the current audio item in seconds.

**Returns:** <code>Promise&lt;{ value: number; }&gt;</code>

--------------------


### getPosition()

```typescript
getPosition() => Promise<{ value: number; }>
```

Get the current position of the audio item in seconds.

**Returns:** <code>Promise&lt;{ value: number; }&gt;</code>

--------------------


### addListener('update', ...)

```typescript
addListener(eventName: 'update', listener: (result: { state: 'playing' | 'paused' | 'skip' | 'completed'; id: string; }) => void) => Promise<PluginListenerHandle>
```

Add an event listener for the update event. The listener should accept an event object
containing the current state and id of the audio item.

| Param           | Type                                                                                                     |
| --------------- | -------------------------------------------------------------------------------------------------------- |
| **`eventName`** | <code>'update'</code>                                                                                    |
| **`listener`**  | <code>(result: { state: 'playing' \| 'paused' \| 'skip' \| 'completed'; id: string; }) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### Interfaces


#### StartOptions

Options for starting the audio player.

| Prop        | Type                | Description                                                  |
| ----------- | ------------------- | ------------------------------------------------------------ |
| **`items`** | <code>Item[]</code> | A list of audio items to be initialized in the audio player. |


#### Item

Represents an audio item in the playlist.

| Prop           | Type                | Description                                                                         |
| -------------- | ------------------- | ----------------------------------------------------------------------------------- |
| **`id`**       | <code>string</code> | The unique identifier for the audio item.                                           |
| **`title`**    | <code>string</code> | The title of the audio item, which is e.g. displayed in the notification player.    |
| **`subtitle`** | <code>string</code> | The subtitle of the audio item, which is e.g. displayed in the notification player. |
| **`audioUri`** | <code>string</code> | The local file URI of the audio file.                                               |
| **`imageUri`** | <code>string</code> | The local file URI of the image associated with the audio item.                     |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |

</docgen-api>
