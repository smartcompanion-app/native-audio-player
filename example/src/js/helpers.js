import { Capacitor } from '@capacitor/core';
import { Directory, Filesystem } from '@capacitor/filesystem';

/**
 * Write a blob with Capacitor Filesystem API
 * to the Data directory with the given filename.
 */
export const writeFile = async (filename, data) => {
  return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = async () => {
          await Filesystem.writeFile({
              path: filename,
              directory: Directory.Data,
              data: reader.result
          });
          resolve();
      };               
      reader.onerror = () => {
          reject();
      };
      reader.readAsDataURL(data);
  });
};

/**
 * Download a file from the given URI and
 * return it as a blob.
 */
export const downloadFile = async (uri) => {
    const response = await fetch(uri);
    const blob = await response.blob();    
    return blob;
};

/**
 * Download a file from the given URI on Android and iOS
 * and write it to the Data directory with the given filename.
 * Do nothing on the web.
 */
export const downloadAndWrite = async (uri, filename) => {
  if (Capacitor.getPlatform() !== 'web') {
    const blob = await downloadFile(uri);
    await writeFile(filename, blob);

    return (await Filesystem.getUri({
      path: filename,
      directory: Directory.Data
    })).uri;
  } else {
    return uri;
  }
};

/**
 * Get URI from filesystem or fallback to web path.
 */
export const resolveUri = async (filename, basepath) => {
    if (Capacitor.getPlatform() !== 'web') {
        return (await Filesystem.getUri({
            path: filename,
            directory: Directory.Data
        })).uri;
    } else {
        return `${basepath}${filename}`;
    }
};

