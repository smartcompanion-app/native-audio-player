import { NativeAudioPlayer } from '@smartcompanion/native-audio-player';
import { downloadAndWrite } from './helpers';

// The media files ship with the app (see src/public/media). Loading them from
// the app's own origin instead of a remote host keeps the e2e tests off the
// network, which is the main source of startup flakiness.
const basePath = '/media/';

const filenames = ['elephant', 'leopard', 'crocodile'];

const updatePosition = async () => {
  const duration = (await NativeAudioPlayer.getDuration()).value;
  const position = (await NativeAudioPlayer.getPosition()).value;
  const value = (position / duration) * 100;
  const slider = document.querySelector('#position');
  slider.value = value;

  // the slider is a percentage and rounds to its step, so the seconds the player reported are
  // kept next to it -- the e2e suite has no other way to see what the plugin actually returns
  slider.dataset.position = position;
  slider.dataset.duration = duration;

  if (duration >= position) {
    setTimeout(() => {
      if (document.querySelector('#play-pause').innerText != 'PLAY') {
        updatePosition();
      }
    }, 500);
  }
};

const setAudioOutput = (output) => {
  document.querySelector('#audio-output').innerHTML = output.toUpperCase();
};

const setActiveItem = async (id) => {
  const select = document.querySelector('#select');
  select.querySelectorAll('button').forEach((button) => {
    if (button.getAttribute('data-id') == id) {
      button.classList.add('active');
    } else {
      button.classList.remove('active');
    }
  });
};

const load = async () => {
  const items = await Promise.all(
    filenames.map(async (filename, index) => ({
      id: (index + 1).toString(),
      title: filename.charAt(0).toUpperCase() + filename.slice(1),
      subtitle: 'Animals',
      audioUri: await downloadAndWrite(`${basePath}${filename}.mp3`, `${filename}.mp3`),
      imageUri: await downloadAndWrite(`${basePath}${filename}.jpg`, `${filename}.jpg`),
    })),
  );

  await NativeAudioPlayer.start({
    items: items,
  });

  // the event only fires on changes, so the initial output has to be queried
  setAudioOutput((await NativeAudioPlayer.getAudioOutput()).output);

  document.querySelector('#play-pause').removeAttribute('disabled');
  document.querySelector('#prev').removeAttribute('disabled');
  document.querySelector('#next').removeAttribute('disabled');
  document.querySelector('#start-stop').removeAttribute('disabled');
  document.querySelector('#position').removeAttribute('disabled');

  const select = document.querySelector('#select');
  select.innerHTML = items
    .map((item, index) => `<button class="${index == 0 ? 'active' : ''}" data-id="${item.id}">${item.title}</button>`)
    .join('');
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
  if (e.target.innerText == 'PLAY') {
    await NativeAudioPlayer.play();
  } else {
    await NativeAudioPlayer.pause();
  }
});
document.querySelector('#start-stop').addEventListener('click', async (e) => {
  if (e.target.innerText == 'START') {
    await load();
    document.querySelector('#start-stop').innerHTML = 'STOP';
  } else {
    await NativeAudioPlayer.stop();
    document.querySelector('#play-pause').setAttribute('disabled', '');
    document.querySelector('#prev').setAttribute('disabled', '');
    document.querySelector('#next').setAttribute('disabled', '');
    document.querySelector('#position').setAttribute('disabled', '');
    document.querySelector('#start-stop').innerHTML = 'START';
    document.querySelector('#select').innerHTML = '';
  }
});
document.querySelector('#position').addEventListener('input', async () => {
  await NativeAudioPlayer.pause();
});
document.querySelector('#position').addEventListener('change', async (e) => {
  const duration = (await NativeAudioPlayer.getDuration()).value;
  // positions are fractional seconds, so the slider hands over what it actually points at
  const position = (e.target.value / 100) * duration;
  // seekTo resumes on its own, so there is no play() to make here
  await NativeAudioPlayer.seekTo({ position });
});
document.querySelector('#select').addEventListener('click', async (e) => {
  const id = e.target.getAttribute('data-id');
  if (id) {
    await NativeAudioPlayer.select({ id });
  }
});

(async () => {
  await NativeAudioPlayer.addListener('audioOutputChange', (data) => {
    setAudioOutput(data.output);
  });

  await NativeAudioPlayer.addListener('audioPlayerChange', async (data) => {
    // recorded before anything acts on it, so the log is the order the plugin reported and
    // not the order this app got round to handling
    const events = document.querySelector('#events');
    events.innerHTML = `${events.innerHTML}${data.state} `;

    if (data.state == 'playing') {
      document.querySelector('#play-pause').innerHTML = 'PAUSE';
      await updatePosition();
    } else if (data.state == 'paused') {
      document.querySelector('#play-pause').innerHTML = 'PLAY';
      // the poller only runs while playing, so the last position it read stands until
      // something asks again -- and a pause does not always leave the player where it
      // was: an item that plays out rewinds itself to the start
      await updatePosition();
    } else if (data.state == 'skip') {
      document.querySelector('#play-pause').innerHTML = 'PLAY';
      await updatePosition();
      setActiveItem(data.id);
    } else if (data.state == 'completed') {
      // the player stops at the end of the item and rewinds it itself, so there is nothing to
      // pause or seek here -- only the button to put back, since completed is the one state
      // reported for this and no paused follows it
      document.querySelector('#play-pause').innerHTML = 'PLAY';
      await updatePosition();
    }
  });

  await load();
})();
