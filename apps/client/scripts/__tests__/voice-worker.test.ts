import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(
  new URL('../voice-worker.ts', import.meta.url),
  'utf8'
);
const script = new Bun.Transpiler({ loader: 'ts' }).transformSync(
  source.replace("import { Device } from 'mediasoup-client';", '') +
    '\nwindow.coveVoice.setScreenShareEnabled = setScreenShareEnabled;'
);

const createWorker = () => {
  const calls: { path: string; input?: Record<string, unknown> }[] = [];
  const constraints: MediaStreamConstraints[] = [];
  const produced: string[] = [];
  let worklets = 0;
  let displayRequests = 0;
  const tracks: {
    kind: string;
    enabled: boolean;
    stop: () => void;
    addEventListener: () => void;
  }[] = [];
  const makeTrack = (kind: string) => {
    const track = {
      kind,
      enabled: true,
      stop() {
        track.enabled = false;
      },
      addEventListener() {}
    };
    tracks.push(track);
    return track;
  };
  const makeStream = (kind: string) => {
    const track = makeTrack(kind);
    return {
      getTracks: () => [track],
      getAudioTracks: () => (kind === 'audio' ? [track] : []),
      getVideoTracks: () => (kind === 'video' ? [track] : [])
    };
  };
  const transport = {
    on() {},
    close() {},
    async produce(options: { appData: { kind: string } }) {
      produced.push(options.appData.kind);
      return { close() {} };
    }
  };
  const window = {
    coveVoiceResolve: (_response: unknown) => {},
    webkit: {
      messageHandlers: {
        coveVoice: {
          postMessage(message: {
            type: string;
            id: string;
            path: string;
            input?: Record<string, unknown>;
          }) {
            if (message.type !== 'rpc') return;
            calls.push(message);
            window.coveVoiceResolve({ id: message.id, result: {} });
          }
        }
      }
    },
    coveVoice: {} as {
      start: (...args: unknown[]) => Promise<void>;
      setMicrophoneMuted: (muted: boolean) => Promise<void>;
      setNoiseSuppressionMode: (mode: string) => Promise<void>;
      setScreenShareEnabled: (enabled: boolean) => Promise<void>;
      stop: () => void;
    }
  };
  class AudioContext {
    currentTime = 0;
    state = 'running';
    audioWorklet = {
      addModule: async () => {
        worklets += 1;
      }
    };
    createMediaStreamSource() {
      return { connect() {} };
    }
    createMediaStreamDestination() {
      return { stream: makeStream('audio') };
    }
    async close() {}
  }
  runInNewContext(script, {
    window,
    URL,
    crypto,
    console,
    AudioContext,
    AudioWorkletNode: class {
      parameters = new Map([['mix', { setValueAtTime() {} }]]);
      connect() {}
    },
    Device: class {
      async load() {}
      createSendTransport() {
        return transport;
      }
      createRecvTransport() {
        return transport;
      }
    },
    navigator: {
      mediaDevices: {
        async getUserMedia(value: MediaStreamConstraints) {
          constraints.push(value);
          return makeStream('audio');
        },
        async getDisplayMedia() {
          displayRequests += 1;
          return makeStream('video');
        }
      }
    },
    document: {
      baseURI: 'file:///voice-media/index.html',
      getElementById: () => null,
      body: { classList: { toggle() {} } }
    }
  });
  return {
    api: window.coveVoice,
    calls,
    constraints,
    produced,
    tracks,
    worklets: () => worklets,
    displayRequests: () => displayRequests
  };
};

test('off and standard capture raw audio without loading RNNoise', async () => {
  for (const mode of ['off', 'standard']) {
    const worker = createWorker();
    await worker.api.start(1, {}, true, true, undefined, 1, mode);
    expect(worker.worklets()).toBe(0);
    expect(worker.constraints[0]?.audio).toEqual({
      autoGainControl: true,
      echoCancellation: true,
      noiseSuppression: mode === 'standard'
    });
    await worker.api.setMicrophoneMuted(false);
    expect(worker.tracks[0]?.enabled).toBe(true);
    expect(worker.calls.at(-1)).toMatchObject({
      path: 'voice.updateState',
      input: { micMuted: false }
    });
  }
});

test('changing an active microphone to RNNoise replaces its producer and preserves unmuted state', async () => {
  const worker = createWorker();
  await worker.api.start(1, {}, true, true, undefined, 1, 'off');
  await worker.api.setMicrophoneMuted(false);
  await worker.api.setNoiseSuppressionMode('rnnoise');
  expect(worker.worklets()).toBe(1);
  expect(worker.produced).toEqual(['audio', 'audio']);
  expect(worker.tracks[0]?.enabled).toBe(false);
  expect(worker.tracks.at(-1)?.enabled).toBe(true);
  expect(worker.calls).toContainEqual(
    expect.objectContaining({
      path: 'voice.closeProducer',
      input: { kind: 'audio' }
    })
  );
});

test('screen sharing publishes video, updates state and closes on stop', async () => {
  const worker = createWorker();
  await worker.api.start(1, {}, false, true);
  await worker.api.setScreenShareEnabled(true);
  expect(worker.displayRequests()).toBe(1);
  expect(worker.produced).toEqual(['screen']);
  expect(worker.calls.at(-1)).toMatchObject({
    path: 'voice.updateState',
    input: { sharingScreen: true }
  });
  await worker.api.setScreenShareEnabled(false);
  expect(worker.tracks[0]?.enabled).toBe(false);
  expect(worker.calls.at(-1)).toMatchObject({
    path: 'voice.updateState',
    input: { sharingScreen: false }
  });
});

test('screen permission rejection occurs before requesting capture', async () => {
  const worker = createWorker();
  await worker.api.start(1, {}, false, false);
  await expect(worker.api.setScreenShareEnabled(true)).rejects.toThrow(
    'permission'
  );
  expect(worker.displayRequests()).toBe(0);
});
