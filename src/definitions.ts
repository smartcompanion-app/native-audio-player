export interface NativeAudioPlayerPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
