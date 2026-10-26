import { Capacitor } from '@capacitor/core';
import { NativeAudioPlayer } from '@smartcompanion/native-audio-player';
import { downloadAndWrite } from './helpers';

// The media files ship with the app (see src/public/media). Loading them from
// the app's own origin instead of a remote host keeps the e2e tests off the
// network, which is the main source of startup flakiness.
const basePath = '/media/';

const filenames = ['elephant', 'leopard', 'crocodile'];

// The same media streamed over HTTP from the server the e2e suite starts, see
// test/media-server.js. An Android emulator reaches the machine it runs on through 10.0.2.2.
const remoteBase = `http://${Capacitor.getPlatform() === 'android' ? '10.0.2.2' : 'localhost'}:4180/media/`;

/**
 * Puts a position on the slider. The slider is a percentage and rounds to its step, so the seconds
 * the player reported are kept next to it -- the e2e suite has no other way to see what the
 * plugin actually returns.
 */
const showPosition = (position, duration) => {
  const slider = document.querySelector('#position');
  slider.value = duration > 0 ? (position / duration) * 100 : 0;
  slider.dataset.position = position;
  slider.dataset.duration = duration;
};

/**
 * Asks once, for the changes the progress event does not cover: it only reports while the audio
 * runs, and a pause does not always leave the player where it was -- an item that plays out
 * rewinds itself to the start, and a skip lands on the start of another.
 */
const updatePosition = async () => {
  showPosition((await NativeAudioPlayer.getPosition()).value, (await NativeAudioPlayer.getDuration()).value);
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

/**
 * Where the items come from: `local` downloads them into the app's storage first, which is all
 * the native players could read before remote items were supported; `remote` hands the player
 * http URLs to stream; `missing` hands it one that is not there.
 */
const itemsFrom = async (source) => {
  return Promise.all(
    filenames.map(async (filename, index) => ({
      id: (index + 1).toString(),
      title: filename.charAt(0).toUpperCase() + filename.slice(1),
      subtitle: 'Animals',
      audioUri:
        source === 'local'
          ? await downloadAndWrite(`${basePath}${filename}.mp3`, `${filename}.mp3`)
          : `${remoteBase}${source === 'missing' ? 'missing' : filename}.mp3`,
      imageUri:
        source === 'local'
          ? await downloadAndWrite(`${basePath}${filename}.jpg`, `${filename}.jpg`)
          : `${remoteBase}${filename}.jpg`,
    })),
  );
};

const load = async (source = 'local') => {
  const items = await itemsFrom(source);

  try {
    await NativeAudioPlayer.start({
      items: items,
    });
    document.querySelector('#start-error').innerText = '';
  } catch (error) {
    // a playlist that could not be started leaves the controls disabled, and says why
    document.querySelector('#start-error').innerText = `error: ${String(error)}`;
    document.querySelector('#start-stop').removeAttribute('disabled');
    document.querySelector('#start-stop').innerHTML = 'START';
    return false;
  }

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
  // last, once everything above is in place: the e2e suite waits for this to know which
  // playlist the controls belong to
  document.body.dataset.playlist = source;
  return true;
};

const unload = async () => {
  delete document.body.dataset.playlist;
  await NativeAudioPlayer.stop();
  document.querySelector('#play-pause').setAttribute('disabled', '');
  document.querySelector('#prev').setAttribute('disabled', '');
  document.querySelector('#next').setAttribute('disabled', '');
  document.querySelector('#position').setAttribute('disabled', '');
  document.querySelector('#start-stop').innerHTML = 'START';
  document.querySelector('#select').innerHTML = '';
};

/** Replaces whatever is playing with a playlist from somewhere else. */
const reload = async (source) => {
  await unload();
  if (await load(source)) {
    document.querySelector('#start-stop').innerHTML = 'STOP';
  }
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
    if (await load()) {
      document.querySelector('#start-stop').innerHTML = 'STOP';
    }
  } else {
    await unload();
  }
});
document.querySelector('#start-remote').addEventListener('click', () => reload('remote'));
document.querySelector('#start-missing').addEventListener('click', () => reload('missing'));
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
document.querySelector('#rate').addEventListener('click', async (e) => {
  const rate = e.target.getAttribute('data-rate');
  if (!rate) {
    return;
  }

  const display = document.querySelector('#rate-value');
  try {
    await NativeAudioPlayer.setRate({ value: Number(rate) });
    display.innerText = String((await NativeAudioPlayer.getRate()).value);
  } catch (error) {
    // with the rate still in force, so a refusal can be seen to have left it alone
    display.innerText = `error: ${String(error)} (rate ${(await NativeAudioPlayer.getRate()).value})`;
  }
});
document.querySelector('#get-state').addEventListener('click', async () => {
  const state = document.querySelector('#state');
  try {
    state.innerText = JSON.stringify(await NativeAudioPlayer.getState());
  } catch (error) {
    state.innerText = JSON.stringify({ error: String(error) });
  }
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

  // follows the playhead while the audio runs, which this app used to poll getPosition() for.
  // Every event is counted on #progress, so the e2e suite can tell a player that stopped
  // reporting from one that keeps reporting the same position.
  await NativeAudioPlayer.addListener('progress', (data) => {
    const progress = document.querySelector('#progress');
    progress.dataset.count = Number(progress.dataset.count ?? 0) + 1;
    progress.dataset.id = data.id;
    progress.dataset.position = data.position;
    progress.dataset.duration = data.duration;
    // when it arrived, so the e2e suite can work out how fast the playhead moves in real time
    progress.dataset.at = Date.now();

    showPosition(data.position, data.duration);
  });

  await NativeAudioPlayer.addListener('audioPlayerChange', async (data) => {
    // recorded before anything acts on it, so the log is the order the plugin reported and
    // not the order this app got round to handling
    const events = document.querySelector('#events');
    events.innerHTML = `${events.innerHTML}${data.state} `;

    if (data.state == 'playing') {
      document.querySelector('#play-pause').innerHTML = 'PAUSE';
    } else if (data.state == 'paused') {
      document.querySelector('#play-pause').innerHTML = 'PLAY';
      await updatePosition();
    } else if (data.state == 'stopped') {
      // stop() can come mid-playback, and no paused comes with it -- so the button is put back
      // here. There is nothing loaded to ask a position of.
      document.querySelector('#play-pause').innerHTML = 'PLAY';
    } else if (data.state == 'skipped') {
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
