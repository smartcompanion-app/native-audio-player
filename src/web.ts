import { WebPlugin } from '@capacitor/core';

import type { NativeAudioPlayerPlugin, StartOptions, Item } from './definitions';

export class NativeAudioPlayerWeb
  extends WebPlugin
  implements NativeAudioPlayerPlugin
{  
  protected items: Item[] = [];
  protected currentIndex = 0;
  
  async setEarpiece(): Promise<void> {    
    console.log("setEarpiece not implemented on the web");
  }

  async setSpeaker(): Promise<void> {
    console.log("setSpeaker not implemented on the web");
  }

  async start(options: StartOptions): Promise<{id: string}> {
    this.currentIndex = 0;
    this.items = JSON.parse(JSON.stringify(options.items));
    return this.loadAudio(this.items[this.currentIndex]);
  }

  async stop(): Promise<void> {
    const audioElement:HTMLAudioElement = document.querySelector('#web-audio')! as HTMLAudioElement;
    if (audioElement) {
      audioElement.pause();
      audioElement.remove();
    }    
    this.items = [];
  }

  async play(): Promise<void> {
    const audioElement:HTMLAudioElement = document.querySelector('#web-audio')! as HTMLAudioElement;
    await audioElement.play();
    this.notifyListeners('update', {'id': this.items![this.currentIndex].id, 'state': 'playing'});      
  }

  async pause(): Promise<void> {
    const audioElement:HTMLAudioElement = document.querySelector('#web-audio')! as HTMLAudioElement;
    await audioElement.pause();
    this.notifyListeners('update', {'id': this.items![this.currentIndex].id, 'state': 'paused'});    
  }

  async select(options: {id: string}): Promise<{ id: string; }> {
    const index = this.findItemIndexById(options.id);

    if (index >= 0) {
      this.currentIndex = index;
      const result = await this.loadAudio(this.items![this.currentIndex]);
      this.notifyListeners('update', {'state': 'skip', 'id': result.id});
      return result;
    }

    throw new Error(`Item with id ${options.id} doesn't exist`);
  }

  async next(): Promise<{id: string}> {   
    if (this.currentIndex >= (this.items!.length - 1)) {
      this.currentIndex = 0;
    } else {
      this.currentIndex += 1;
    }

    const result = await this.loadAudio(this.items![this.currentIndex]);
    this.notifyListeners('update', {'state': 'skip', 'id': result.id});
    return result;
  }

  async previous(): Promise<{id: string}> {    
    if (this.currentIndex <= 0) {
      this.currentIndex = this.items!.length - 1;
    } else {
      this.currentIndex -= 1;
    }
    
    const result = await this.loadAudio(this.items![this.currentIndex]);
    this.notifyListeners('update', {'state': 'skip', 'id': result.id});
    return result;
  }

  async seekTo(options: {position: number}): Promise<void> {
    const audioElement:HTMLAudioElement = document.querySelector('#web-audio')! as HTMLAudioElement;
    audioElement.currentTime = options.position;
  }

  async getDuration(): Promise<{value: number}> {
    const audioElement:HTMLAudioElement = document.querySelector('#web-audio')! as HTMLAudioElement;
    return {value:  (audioElement && audioElement.duration > 0) ? audioElement.duration : 0};
  }

  async getPosition(): Promise<{value: number}> {
    const audioElement:HTMLAudioElement = document.querySelector('#web-audio')! as HTMLAudioElement;
    return {value: audioElement ? audioElement.currentTime : 0};
  } 

  loadAudio(item: Item): Promise<{id: string}> {
    return new Promise(resolve => { 
      if (document.querySelector('#web-audio')) {
        document.querySelector('#web-audio')?.remove();
      }

      const audio = document.createElement('audio');
      audio.addEventListener('loadedmetadata', () => {
        resolve({ id: item.id });
      });
      audio.addEventListener('ended', () => {
        this.notifyListeners('update', {'state': 'completed', 'id': item.id});
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
