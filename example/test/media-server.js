import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

/**
 * Serves the example's media over plain HTTP, so the remote spec can hand the player URLs it has
 * to fetch over the network rather than files the app wrote to its own storage. Byte ranges are
 * answered, since AVPlayer asks for one before anything else and gives up on a server that
 * ignores it.
 *
 * `/__requests` lists every media path that was asked for, which is how a spec tells audio that
 * was streamed from audio that was quietly read from somewhere else.
 */

export const MEDIA_SERVER_PORT = 4180;

const root = new URL('../src/public', import.meta.url).pathname;

const contentTypes = {
  '.mp3': 'audio/mpeg',
  '.jpg': 'image/jpeg',
};

export const startMediaServer = () => {
  const requests = [];

  const server = createServer(async (request, response) => {
    const path = normalize(decodeURIComponent(new URL(request.url, 'http://localhost').pathname));

    if (path === '/__requests') {
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify(requests));
      return;
    }

    requests.push(path);

    let body;
    try {
      body = await readFile(join(root, path));
    } catch {
      response.statusCode = 404;
      response.end();
      return;
    }

    response.setHeader('Content-Type', contentTypes[extname(path)] ?? 'application/octet-stream');
    response.setHeader('Accept-Ranges', 'bytes');
    // the browser run loads these from another origin
    response.setHeader('Access-Control-Allow-Origin', '*');

    const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.range ?? '');
    if (range) {
      const start = range[1] === '' ? Math.max(0, body.length - Number(range[2])) : Number(range[1]);
      const end = range[1] !== '' && range[2] !== '' ? Math.min(Number(range[2]), body.length - 1) : body.length - 1;

      response.statusCode = 206;
      response.setHeader('Content-Range', `bytes ${start}-${end}/${body.length}`);
      response.setHeader('Content-Length', end - start + 1);
      response.end(request.method === 'HEAD' ? undefined : body.subarray(start, end + 1));
      return;
    }

    response.setHeader('Content-Length', body.length);
    response.end(request.method === 'HEAD' ? undefined : body);
  });

  return new Promise((resolve) => {
    // every interface, so an Android emulator reaches it through 10.0.2.2
    server.listen(MEDIA_SERVER_PORT, '0.0.0.0', () => resolve(server));
  });
};
