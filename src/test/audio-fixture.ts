/**
 * A playable audio file, built in the browser and handed to the plugin as a blob URL.
 *
 * The suite needs items that run out in about a second so that `completed` can be waited
 * for rather than mocked, and it needs them at a URL the page can actually load. Generating
 * the bytes here keeps both out of the repo: no binary fixture to commit, and no static
 * server to configure alongside the test runner.
 *
 * WAV rather than MP3 because it can be written by hand -- an MP3 would need an encoder,
 * and nothing in these tests depends on the container.
 */

const SAMPLE_RATE = 8000;
const BITS_PER_SAMPLE = 16;
const CHANNELS = 1;

const writeAscii = (view: DataView, offset: number, text: string) => {
  for (let index = 0; index < text.length; index++) {
    view.setUint8(offset + index, text.charCodeAt(index));
  }
};

/**
 * Builds a silent mono WAV of the given length. Silence still advances the media clock,
 * so `ended` fires on time even on a CI runner with no audio device.
 */
export const createAudioFile = (seconds: number): Blob => {
  const sampleCount = Math.floor(SAMPLE_RATE * seconds);
  const dataBytes = sampleCount * CHANNELS * (BITS_PER_SAMPLE / 8);
  const buffer = new ArrayBuffer(44 + dataBytes);
  const view = new DataView(buffer);

  writeAscii(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, true);
  writeAscii(view, 8, 'WAVE');

  writeAscii(view, 12, 'fmt ');
  view.setUint32(16, 16, true); // PCM header length
  view.setUint16(20, 1, true); // PCM, uncompressed
  view.setUint16(22, CHANNELS, true);
  view.setUint32(24, SAMPLE_RATE, true);
  view.setUint32(28, (SAMPLE_RATE * CHANNELS * BITS_PER_SAMPLE) / 8, true); // byte rate
  view.setUint16(32, (CHANNELS * BITS_PER_SAMPLE) / 8, true); // block align
  view.setUint16(34, BITS_PER_SAMPLE, true);

  writeAscii(view, 36, 'data');
  view.setUint32(40, dataBytes, true);
  // the samples themselves are left at zero -- silence

  return new Blob([buffer], { type: 'audio/wav' });
};

const objectUrls: string[] = [];

/**
 * A blob URL for an audio file of the given length. Revoked by {@link revokeAudioUris}.
 */
export const createAudioUri = (seconds: number): string => {
  const uri = URL.createObjectURL(createAudioFile(seconds));
  objectUrls.push(uri);
  return uri;
};

/**
 * A URL that is well-formed but cannot be loaded, for the failure paths. A blob URL that
 * was revoked fails the same way a missing file does, without going near the network.
 */
export const createUnloadableUri = (): string => {
  const uri = URL.createObjectURL(new Blob(['not audio'], { type: 'audio/wav' }));
  URL.revokeObjectURL(uri);
  return uri;
};

export const revokeAudioUris = (): void => {
  objectUrls.splice(0).forEach((uri) => URL.revokeObjectURL(uri));
};
