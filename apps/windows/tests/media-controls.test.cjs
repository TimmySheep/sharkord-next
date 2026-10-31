const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const makeWorker = (overrides = {}) => {
  const calls = [];
  class Audio {
    async setSinkId(id) { this.sinkId = id; }
    async play() {}
    pause() {}
    remove() {}
  }
  const context = {
    window: {}, consumers: new Map(), microphoneProducer: null, activeChannelId: undefined,
    microphoneMuted: true, outputMuted: false, cameraProducer: undefined, screenShareEnabled: false,
    HTMLAudioElement: Audio, HTMLVideoElement: class {},
    navigator: { mediaDevices: { enumerateDevices: async () => [], getUserMedia: async () => ({ getTracks: () => [] }) } },
    document: { pictureInPictureEnabled: false, getElementById: () => null, createElement: () => new Audio(), body: { append() {} } },
    updateLocalPreview() {}, setRemoteAudioVolume() {}, setInterval() {}, postToNative() {},
    setNoiseSuppressionMode: async (mode) => calls.push({ mode }),
    callNative: async (route, input) => calls.push({ route, input }),
    device: { rtpCapabilities: { codecs: [{ mimeType: 'video/VP8' }] } },
    ...overrides
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../src/Sharkord.App/Assets/VoiceMedia/media-controls.js'), 'utf8'), context);
  return { context, api: context.window.coveMedia, calls, Audio };
};

test('receive quality uses the supported mode and remote stream identity', async () => {
  const { api, calls } = makeWorker();
  await api.quality('17:screen', -1);
  await api.quality('18:external_video', 2);
  assert.deepEqual(JSON.parse(JSON.stringify(calls)), [
    { route: 'voice.setConsumerQuality', input: { remoteId: 17, kind: 'screen', quality: { mode: 'auto' } } },
    { route: 'voice.setConsumerQuality', input: { remoteId: 18, kind: 'external_video', quality: { mode: 'layer', spatialLayer: 2 } } }
  ]);
});

test('device options update existing audio outputs and preserve the noise choice', async () => {
  const { api, context, calls, Audio } = makeWorker();
  const audio = new Audio();
  context.consumers.set('7:audio', { element: audio });
  await api.options({ speakerId: 'owned-speaker', noiseMode: 'off' });
  assert.equal(audio.sinkId, 'owned-speaker');
  assert.equal(calls[0].mode, 'off');
});

test('closing a preview while device permission is pending stops the acquired tracks', async () => {
  let resolve;
  let stopped = false;
  const { api } = makeWorker({ navigator: { mediaDevices: { getUserMedia: () => new Promise((done) => { resolve = done; }) } } });
  const opening = api.preview('audio');
  api.stopPreview();
  resolve({ getTracks: () => [{ stop() { stopped = true; } }] });
  await opening;
  assert.equal(stopped, true);
});

test('stream snapshots preserve server supplied quality labels', () => {
  const { api, context } = makeWorker();
  context.consumers.set('17:screen', { consumer: { track: { kind: 'video' } }, qualityLayers: [{ spatialLayer: 2, label: '1080p' }] });
  const stream = api.snapshot().streams[0];
  assert.equal(stream.key, '17:screen');
  assert.equal(stream.qualityLayers[0].label, '1080p');
});

test('simulcast sends matching encoding indexes and a supported VP8 codec', () => {
  const { context } = makeWorker();
  context.window.coveMediaOptions.simulcast = true;
  const result = vm.runInContext('videoProduceOptions({getSettings:()=>({height:1080})}, "video", 1500000)', context);
  assert.equal(result.codec.mimeType, 'video/VP8');
  assert.equal(result.encodings.length, 3);
  assert.deepEqual(JSON.parse(JSON.stringify(result.appData.qualityLayers)), [
    { spatialLayer: 0, label: '270p' }, { spatialLayer: 1, label: '540p' }, { spatialLayer: 2, label: '1080p' }
  ]);
});

test('single layer publishing omits the simulcast only quality metadata', () => {
  const { context } = makeWorker();
  const result = vm.runInContext('videoProduceOptions({getSettings:()=>({height:720})}, "screen", 2500000)', context);
  assert.equal(result.encodings.length, 1);
  assert.equal('qualityLayers' in result.appData, false);
});

test('closing a pinned stream restores the surviving video tiles', () => {
  const { api, context } = makeWorker();
  const first = { style: {} };
  const second = { style: {} };
  context.consumers.set('1:video', { element: { closest: () => first } });
  context.consumers.set('2:video', { element: { closest: () => second } });
  api.pin('1:video');
  assert.equal(second.style.display, 'none');
  context.consumers.delete('1:video');
  api.consumerClosed('1:video');
  assert.equal(second.style.display, '');
});
