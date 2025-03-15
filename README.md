# native-audio-player

Play Native Audio from a Capacitor App

## Install

```bash
npm install native-audio-player
npx cap sync
```

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

--------------------


### setSpeaker()

```typescript
setSpeaker() => Promise<void>
```

--------------------


### start(...)

```typescript
start(options: StartOptions) => Promise<{ id: string; }>
```

| Param         | Type                                                  |
| ------------- | ----------------------------------------------------- |
| **`options`** | <code><a href="#startoptions">StartOptions</a></code> |

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### stop()

```typescript
stop() => Promise<void>
```

--------------------


### play()

```typescript
play() => Promise<void>
```

--------------------


### pause()

```typescript
pause() => Promise<void>
```

--------------------


### select(...)

```typescript
select(options: { id: string; }) => Promise<{ id: string; }>
```

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### next()

```typescript
next() => Promise<{ id: string; }>
```

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### previous()

```typescript
previous() => Promise<{ id: string; }>
```

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### seekTo(...)

```typescript
seekTo(options: { position: number; }) => Promise<void>
```

| Param         | Type                               |
| ------------- | ---------------------------------- |
| **`options`** | <code>{ position: number; }</code> |

--------------------


### getDuration()

```typescript
getDuration() => Promise<{ value: number; }>
```

**Returns:** <code>Promise&lt;{ value: number; }&gt;</code>

--------------------


### getPosition()

```typescript
getPosition() => Promise<{ value: number; }>
```

**Returns:** <code>Promise&lt;{ value: number; }&gt;</code>

--------------------


### addListener('update', ...)

```typescript
addListener(eventName: 'update', listener: (result: { state: 'playing' | 'paused' | 'skip' | 'completed'; id: string; }) => void) => Promise<PluginListenerHandle>
```

| Param           | Type                                                                                                     |
| --------------- | -------------------------------------------------------------------------------------------------------- |
| **`eventName`** | <code>'update'</code>                                                                                    |
| **`listener`**  | <code>(result: { state: 'playing' \| 'paused' \| 'skip' \| 'completed'; id: string; }) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### Interfaces


#### StartOptions

| Prop        | Type                |
| ----------- | ------------------- |
| **`items`** | <code>Item[]</code> |


#### Item

| Prop           | Type                |
| -------------- | ------------------- |
| **`id`**       | <code>string</code> |
| **`title`**    | <code>string</code> |
| **`subtitle`** | <code>string</code> |
| **`audioUri`** | <code>string</code> |
| **`imageUri`** | <code>string</code> |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |

</docgen-api>
