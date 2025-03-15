import { NativeAudioPlayer } from '@smartcompanion/native-audio-player';
import { downloadAndWrite } from './helpers';

const basePath = 'https://www.smartcompanion.app/test_data/';

const filenames = [
  'elephant',
  'leopard',
  'crocodile'
];

const updatePosition = async () => {
  const duration = (await NativeAudioPlayer.getDuration()).value;
  const position = (await NativeAudioPlayer.getPosition()).value;
  const value = (position / duration) * 100;
  document.querySelector("#position").value = value;

  if (duration >= position) {
    setTimeout(() => {      
      if (document.querySelector('#play-pause').innerText != 'PLAY') {
        updatePosition();
      }
    }, 500);
  }
}

const setActiveItem = async (id) => {
  const select = document.querySelector("#select");
  select.querySelectorAll('button').forEach((button) => {
    if (button.getAttribute('data-id') == id) {
      button.classList.add('active');
    } else {
      button.classList.remove('active');
    }
  });
};

const load = async () => {
  const items = await Promise.all(filenames.map(async (filename, index) => ({
    id: (index + 1).toString(),
    title: filename.charAt(0).toUpperCase() + filename.slice(1),
    subtitle: 'Animals',
    audioUri: await downloadAndWrite(`${basePath}${filename}.mp3`, `${filename}.mp3`),
    imageUri: await downloadAndWrite(`${basePath}${filename}.jpg`, `${filename}.jpg`)
  })));

  await NativeAudioPlayer.start({
    items: items
  });

  document.querySelector("#play-pause").removeAttribute("disabled");
  document.querySelector("#prev").removeAttribute("disabled");
  document.querySelector("#next").removeAttribute("disabled");
  document.querySelector("#start-stop").removeAttribute("disabled");
  document.querySelector("#position").removeAttribute("disabled");

  const select = document.querySelector("#select");
  select.innerHTML = items.map((item, index) => `<button class="${index == 0 ? 'active' : ''}" data-id="${item.id}">${item.title}</button>`).join('');
};

document.querySelector('#set-earpiece').addEventListener('click', () => {
  NativeAudioPlayer.setEarpiece();
});
document.querySelector('#set-speaker').addEventListener('click', () => {
  NativeAudioPlayer.setSpeaker();
});
document.querySelector('#prev').addEventListener('click', () => {
  NativeAudioPlayer.previous();
});
document.querySelector('#next').addEventListener('click', () => {
  NativeAudioPlayer.next();
});
document.querySelector('#play-pause').addEventListener('click', async (e) => {
  if (e.target.innerText == "PLAY") {
    await NativeAudioPlayer.play();    
  } else {
    await NativeAudioPlayer.pause();
  }
});
document.querySelector('#start-stop').addEventListener('click', async (e) => {
  if (e.target.innerText == "START") {
    await load();
    document.querySelector("#start-stop").innerHTML = 'STOP';
  } else {
    await NativeAudioPlayer.stop();
    document.querySelector("#play-pause").setAttribute("disabled", "");
    document.querySelector("#prev").setAttribute("disabled", "");
    document.querySelector("#next").setAttribute("disabled", "");
    document.querySelector("#position").setAttribute("disabled", "");
    document.querySelector("#start-stop").innerHTML = 'START';
    document.querySelector("#select").innerHTML = '';
  }
});
document.querySelector('#position').addEventListener('input', async () => {
  await NativeAudioPlayer.pause();
});
document.querySelector('#position').addEventListener('change', async (e) => {
  const duration = (await NativeAudioPlayer.getDuration()).value;
  const position = parseInt((e.target.value / 100) * duration);
  NativeAudioPlayer.seekTo({ position });
  if (document.querySelector('#play-pause').innerText == 'PLAY') {
    NativeAudioPlayer.play();
  }  
});
document.querySelector("#select").addEventListener('click', async (e) => {
  const id = e.target.getAttribute('data-id');
  if (id) {
    await NativeAudioPlayer.select({ id });
  }
});

(async () => {
  await NativeAudioPlayer.addListener("update", async (data) => {
    if (data.state == 'playing') {
      document.querySelector('#play-pause').innerHTML = "PAUSE";
      await updatePosition();
    } else if (data.state == 'paused') {
      document.querySelector('#play-pause').innerHTML = "PLAY";
    } else if (data.state == 'skip') {
      document.querySelector('#play-pause').innerHTML = "PLAY";
      await updatePosition();
      setActiveItem(data.id);
    } else if (data.state == 'completed') {
      await NativeAudioPlayer.pause();
      await NativeAudioPlayer.seekTo({ position: 0 });
      await updatePosition();
    }
  });

  await load();
})();
