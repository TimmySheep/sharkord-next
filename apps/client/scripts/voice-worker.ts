// bundle from the client workspace so both desktop shells share one protocol implementation.
import { Device } from 'mediasoup-client';
import type { Consumer, Producer, Transport } from 'mediasoup-client/types';

type TNativeResponse = {
  id: string;
  result?: unknown;
  error?: string;
};

type TNativeEvent = {
  type: 'producer' | 'rpcResponse' | 'status';
  id?: string;
  result?: unknown;
  error?: string;
  remoteId?: number;
  kind?: string;
  added?: boolean;
  canPublishAudio?: boolean;
  errorContext?: string;
};

type TBridgeWindow = Window & {
  coveVoiceResolve?: (response: TNativeResponse) => void;
  coveVoiceProducerChange?: (
    remoteId: number,
    kind: string,
    added: boolean
  ) => void;
  webkit?: {
    messageHandlers?: {
      coveVoice?: {
        postMessage: (message: unknown) => void;
      };
    };
  };
  chrome?: {
    webview?: {
      postMessage: (message: unknown) => void;
      addEventListener: (
        name: 'message',
        handler: (event: MessageEvent) => void
      ) => void;
    };
  };
};

type TConsumeResult = {
  producerId: string;
  consumerId: string;
  consumerKind: string;
  consumerRtpParameters: unknown;
};

type TRemoteProducerIds = {
  remoteVideoIds?: number[];
  remoteAudioIds?: number[];
  remoteScreenIds?: number[];
  remoteScreenAudioIds?: number[];
};

type TMediaLabels = {
  share: string;
  stop: string;
  local: string;
  screen: string;
  camera: string;
};

type TMediaElement = HTMLAudioElement | HTMLVideoElement;

const defaultMediaLabels: TMediaLabels = {
  share: '',
  stop: '',
  local: 'You',
  screen: 'Screen',
  camera: 'Camera'
};

const bridgeWindow = window as TBridgeWindow;
const pending = new Map<string, (response: TNativeResponse) => void>();
const consumers = new Map<
  string,
  { consumer: Consumer; element: TMediaElement }
>();
const remoteAudioVolumes = new Map<string, number>();
let device: Device | undefined;
let sendTransport: Transport | undefined;
let receiveTransport: Transport | undefined;
let microphoneStream: MediaStream | undefined;
let microphoneProducer: Producer | undefined;
let microphoneTrack: MediaStreamTrack | undefined;
let canSpeak = false;
let canPublishAudio = false;
let cameraStream: MediaStream | undefined;
let cameraProducer: Producer | undefined;
let screenStream: MediaStream | undefined;
let screenProducer: Producer | undefined;
let screenAudioProducer: Producer | undefined;
let microphoneMuted = true;
let outputMuted = false;
let activeChannelId: number | undefined;
let remoteVideoCount = 0;
let mediaGeneration = 0;
let canShareScreen = false;
let isStartingScreenShare = false;
let screenShareEnabled = false;
let shareScreenLabel = '';
let stopScreenShareLabel = '';
let mediaLabels = defaultMediaLabels;

const setGalleryVisible = (visible: boolean) => {
  document.body.classList.toggle('has-video', visible);
  postToNative({ type: 'video', visible });
};

const postToNative = (message: unknown) => {
  if (bridgeWindow.webkit?.messageHandlers?.coveVoice) {
    bridgeWindow.webkit.messageHandlers.coveVoice.postMessage(message);
    return;
  }

  bridgeWindow.chrome?.webview?.postMessage(message);
};

const notify = (state: string, error?: string, errorContext?: string) => {
  postToNative({ type: 'status', state, error, canPublishAudio, errorContext });
  syncScreenShareButton();
};

const syncScreenShareButton = () => {
  const button = document.getElementById(
    'screen-share-button'
  ) as HTMLButtonElement | null;

  if (!button) return;

  button.hidden = activeChannelId === undefined || !canShareScreen;
  button.disabled = isStartingScreenShare;
  button.textContent = screenShareEnabled
    ? stopScreenShareLabel
    : shareScreenLabel;
  button.classList.toggle('active', screenShareEnabled);
};

const callNative = <TResult>(
  path: string,
  input?: unknown
): Promise<TResult> => {
  const id = globalThis.crypto.randomUUID();

  return new Promise((resolve, reject) => {
    pending.set(id, (response) => {
      if (response.error) {
        reject(new Error(response.error));
        return;
      }

      resolve(response.result as TResult);
    });

    postToNative({ type: 'rpc', id, path, input });
  });
};

const resolveNativeCall = (response: TNativeResponse) => {
  const resolve = pending.get(response.id);

  if (!resolve) return;

  pending.delete(response.id);
  resolve(response);
};

const handleNativeEvent = (event: TNativeEvent) => {
  if (event.type === 'rpcResponse' && event.id) {
    resolveNativeCall({
      id: event.id,
      result: event.result,
      error: event.error
    });
    return;
  }

  if (event.type === 'producer' && event.remoteId !== undefined && event.kind) {
    bridgeWindow.coveVoiceProducerChange?.(
      event.remoteId,
      event.kind,
      event.added === true
    );
  }
};

bridgeWindow.coveVoiceResolve = resolveNativeCall;
bridgeWindow.coveVoiceProducerChange = (remoteId, kind, added) => {
  if (added) {
    consume(remoteId, kind);
  } else {
    closeConsumer(remoteId, kind);
  }
};
bridgeWindow.chrome?.webview?.addEventListener('message', (event) => {
  handleNativeEvent(event.data as TNativeEvent);
});

const consume = async (remoteId: number, kind: string) => {
  if (!receiveTransport || !device) return;

  const key = `${remoteId}:${kind}`;
  if (consumers.has(key)) return;

  try {
    const parameters = await callNative<TConsumeResult>('voice.consume', {
      kind,
      remoteId,
      rtpCapabilities: device.recvRtpCapabilities
    });

    if (!receiveTransport || consumers.has(key)) return;

    const consumer = await receiveTransport.consume({
      id: parameters.consumerId,
      producerId: parameters.producerId,
      kind:
        parameters.consumerKind === 'audio' ||
        parameters.consumerKind === 'screen_audio'
          ? 'audio'
          : 'video',
      rtpParameters: parameters.consumerRtpParameters as Parameters<
        Transport['consume']
      >[0]['rtpParameters']
    });

    if (consumer.track.kind === 'audio') {
      const audio = document.createElement('audio');
      audio.autoplay = true;
      audio.srcObject = new MediaStream([consumer.track]);
      audio.muted = outputMuted;
      audio.volume = remoteAudioVolumes.get(key) ?? 1;
      document.body.append(audio);
      consumers.set(key, { consumer, element: audio });
      await audio.play();
      return;
    }

    const tile = document.createElement('div');
    tile.className = 'video-tile';
    const video = document.createElement('video');
    video.autoplay = true;
    video.playsInline = true;
    if (kind === 'screen') video.style.objectFit = 'contain';
    video.srcObject = new MediaStream([consumer.track]);
    const label = document.createElement('span');
    const mediaLabel =
      kind === 'screen' ? mediaLabels.screen : mediaLabels.camera;
    label.textContent = `${mediaLabel} ${remoteId}`;
    tile.append(video, label);
    document.getElementById('video-grid')?.append(tile);
    consumers.set(key, { consumer, element: video });
    remoteVideoCount += 1;
    setGalleryVisible(true);
    await video.play();
  } catch (error) {
    notify(
      'connected',
      error instanceof Error ? error.message : String(error),
      'connection'
    );
  }
};

const closeConsumer = (remoteId: number, kind: string) => {
  const key = `${remoteId}:${kind}`;
  const entry = consumers.get(key);

  if (!entry) return;

  entry.consumer.close();
  entry.element.pause();
  entry.element.srcObject = null;
  entry.element.closest('.video-tile')?.remove();
  entry.element.remove();
  if (entry.consumer.track.kind === 'video') {
    remoteVideoCount = Math.max(0, remoteVideoCount - 1);
    setGalleryVisible(remoteVideoCount > 0 || cameraProducer !== undefined);
  }
  consumers.delete(key);
};

const setRemoteAudioVolume = (
  remoteId: number,
  kind: string,
  volume: number
) => {
  if (kind !== 'audio' && kind !== 'screen_audio') return;

  const key = `${remoteId}:${kind}`;
  const normalized = Number.isFinite(volume)
    ? Math.min(Math.max(volume, 0), 1)
    : 1;
  remoteAudioVolumes.set(key, normalized);

  const entry = consumers.get(key);
  if (entry?.element instanceof HTMLAudioElement) {
    entry.element.volume = normalized;
  }
};

const updateLocalPreview = () => {
  const preview = document.getElementById(
    'local-preview'
  ) as HTMLVideoElement | null;

  if (!preview) return;

  preview.srcObject = cameraStream ?? null;
  preview.hidden = cameraStream === undefined;
  const tile = preview.closest('.video-tile');
  tile?.classList.toggle('hidden', cameraStream === undefined);
  setGalleryVisible(remoteVideoCount > 0 || cameraStream !== undefined);
};

const closeMedia = () => {
  mediaGeneration += 1;
  microphoneProducer?.close();
  microphoneProducer = undefined;
  microphoneTrack = undefined;
  canSpeak = false;
  canPublishAudio = false;
  microphoneStream?.getTracks().forEach((track) => track.stop());
  microphoneStream = undefined;
  cameraProducer?.close();
  cameraProducer = undefined;
  cameraStream?.getTracks().forEach((track) => track.stop());
  cameraStream = undefined;
  screenProducer?.close();
  screenProducer = undefined;
  screenAudioProducer?.close();
  screenAudioProducer = undefined;
  screenStream?.getTracks().forEach((track) => track.stop());
  screenStream = undefined;
  canShareScreen = false;
  isStartingScreenShare = false;
  screenShareEnabled = false;
  consumers.forEach(({ consumer, element }) => {
    consumer.close();
    element.pause();
    element.srcObject = null;
    element.closest('.video-tile')?.remove();
    element.remove();
  });
  consumers.clear();
  const grid = document.getElementById('video-grid');
  const localTile = grid
    ?.querySelector('#local-preview')
    ?.closest('.video-tile');
  grid?.replaceChildren(...(localTile ? [localTile] : []));
  remoteVideoCount = 0;
  updateLocalPreview();
  sendTransport?.close();
  sendTransport = undefined;
  receiveTransport?.close();
  receiveTransport = undefined;
  device = undefined;
  activeChannelId = undefined;
  microphoneMuted = true;
  outputMuted = false;
  pending.clear();
  syncScreenShareButton();
};

const configureTransport = (transport: Transport, isProducer: boolean) => {
  transport.on('connect', ({ dtlsParameters }, callback, errback) => {
    const path = isProducer
      ? 'voice.connectProducerTransport'
      : 'voice.connectConsumerTransport';
    callNative(path, { dtlsParameters })
      .then(() => callback())
      .catch((error: Error) => errback(error));
  });

  if (isProducer) {
    transport.on(
      'produce',
      ({ kind, rtpParameters, appData }, callback, errback) => {
        const streamKind = (appData as { kind?: string }).kind ?? kind;
        callNative<string>('voice.produce', {
          transportId: transport.id,
          kind: streamKind,
          rtpParameters
        })
          .then((id) => callback({ id }))
          .catch((error: Error) => errback(error));
      }
    );
  }
};

const openMicrophone = async () => {
  if (!canSpeak) {
    throw new Error(
      'You do not have permission to speak in this voice channel.'
    );
  }
  if (!sendTransport) {
    throw new Error('Voice media is not connected.');
  }
  if (microphoneProducer && microphoneTrack) return;

  const transport = sendTransport;
  const generation = mediaGeneration;
  let stream: MediaStream | undefined;
  let producer: Producer | undefined;

  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        autoGainControl: true,
        echoCancellation: true,
        noiseSuppression: true
      },
      video: false
    });
    const track = stream.getAudioTracks()[0];

    if (!track) {
      throw new Error('No microphone audio track is available.');
    }

    track.enabled = false;

    if (generation !== mediaGeneration || sendTransport !== transport) {
      throw new Error('Voice media is no longer connected.');
    }

    producer = await transport.produce({
      track,
      appData: { kind: 'audio' },
      codecOptions: { opusDtx: true, opusFec: true }
    });

    if (generation !== mediaGeneration || sendTransport !== transport) {
      producer.close();
      throw new Error('Voice media is no longer connected.');
    }

    microphoneStream = stream;
    microphoneProducer = producer;
    microphoneTrack = track;
    microphoneMuted = true;
    canPublishAudio = true;
  } catch (error) {
    producer?.close();
    stream?.getTracks().forEach((track) => track.stop());
    throw error;
  }
};

const start = async (
  channelId: number,
  routerRtpCapabilities: unknown,
  canProduceAudio = true,
  canPublishScreen = false,
  labels: TMediaLabels = defaultMediaLabels
) => {
  if (activeChannelId === channelId) return;
  closeMedia();
  activeChannelId = channelId;
  canSpeak = canProduceAudio;
  canPublishAudio = canSpeak;
  canShareScreen = canPublishScreen;
  mediaLabels = labels;
  shareScreenLabel = labels.share;
  stopScreenShareLabel = labels.stop;
  const localLabel = document.getElementById('local-label');
  if (localLabel) localLabel.textContent = labels.local;
  syncScreenShareButton();
  notify('connecting');

  try {
    const nextDevice = new Device();
    await nextDevice.load({
      routerRtpCapabilities: routerRtpCapabilities as Parameters<
        Device['load']
      >[0]['routerRtpCapabilities']
    });
    device = nextDevice;

    const [sendParameters, receiveParameters] = await Promise.all([
      callNative<Parameters<Device['createSendTransport']>[0]>(
        'voice.createProducerTransport'
      ),
      callNative<Parameters<Device['createRecvTransport']>[0]>(
        'voice.createConsumerTransport'
      )
    ]);

    const nextSendTransport = nextDevice.createSendTransport(sendParameters);
    const nextReceiveTransport =
      nextDevice.createRecvTransport(receiveParameters);
    sendTransport = nextSendTransport;
    receiveTransport = nextReceiveTransport;
    configureTransport(nextSendTransport, true);
    configureTransport(nextReceiveTransport, false);

    let microphoneError: string | undefined;

    if (canSpeak) {
      try {
        await openMicrophone();
      } catch (error) {
        microphoneError =
          error instanceof Error ? error.message : String(error);
      }
    }

    const remoteProducers =
      await callNative<TRemoteProducerIds>('voice.getProducers');
    const remoteStreams = [
      ...(remoteProducers.remoteAudioIds ?? []).map((remoteId) => ({
        remoteId,
        kind: 'audio'
      })),
      ...(remoteProducers.remoteVideoIds ?? []).map((remoteId) => ({
        remoteId,
        kind: 'video'
      })),
      ...(remoteProducers.remoteScreenIds ?? []).map((remoteId) => ({
        remoteId,
        kind: 'screen'
      })),
      ...(remoteProducers.remoteScreenAudioIds ?? []).map((remoteId) => ({
        remoteId,
        kind: 'screen_audio'
      }))
    ];

    await Promise.all(
      remoteStreams.map(({ remoteId, kind }) => consume(remoteId, kind))
    );
    notify(
      'connected',
      microphoneError,
      microphoneError ? 'microphone' : undefined
    );
  } catch (error) {
    closeMedia();
    const message = error instanceof Error ? error.message : String(error);
    notify('failed', message);
    throw error;
  }
};

const setWebcamEnabled = async (enabled: boolean) => {
  if (!sendTransport) throw new Error('Voice media is not connected.');
  if ((cameraProducer !== undefined) === enabled) return;

  if (enabled) {
    cameraStream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: 'user',
        width: { ideal: 1280 },
        height: { ideal: 720 },
        frameRate: { ideal: 30, max: 30 }
      }
    });
    const track = cameraStream.getVideoTracks()[0];

    if (!track) {
      cameraStream.getTracks().forEach((cameraTrack) => cameraTrack.stop());
      cameraStream = undefined;
      throw new Error('No camera video track is available.');
    }

    try {
      cameraProducer = await sendTransport.produce({
        track,
        appData: { kind: 'video' },
        encodings: [{ maxBitrate: 1_500_000 }]
      });
      updateLocalPreview();
      await callNative('voice.updateState', { webcamEnabled: true });
    } catch (error) {
      cameraProducer?.close();
      cameraProducer = undefined;
      cameraStream.getTracks().forEach((cameraTrack) => cameraTrack.stop());
      cameraStream = undefined;
      updateLocalPreview();
      await callNative('voice.closeProducer', { kind: 'video' }).catch(
        () => undefined
      );
      throw error;
    }

    return;
  }

  cameraProducer?.close();
  cameraProducer = undefined;
  cameraStream?.getTracks().forEach((track) => track.stop());
  cameraStream = undefined;
  updateLocalPreview();

  try {
    await callNative('voice.closeProducer', { kind: 'video' });
    await callNative('voice.updateState', { webcamEnabled: false });
  } catch (error) {
    notify('connected', error instanceof Error ? error.message : String(error));
    throw error;
  }
};

const stopScreenShare = async () => {
  const hadScreenShare =
    screenProducer !== undefined ||
    screenAudioProducer !== undefined ||
    screenStream !== undefined;

  if (!hadScreenShare) return;

  const videoProducer = screenProducer;
  const audioProducer = screenAudioProducer;
  const stream = screenStream;
  screenProducer = undefined;
  screenAudioProducer = undefined;
  screenStream = undefined;
  screenShareEnabled = false;
  videoProducer?.close();
  audioProducer?.close();
  stream?.getTracks().forEach((track) => track.stop());
  syncScreenShareButton();

  if (activeChannelId !== undefined) {
    await Promise.all([
      callNative('voice.closeProducer', { kind: 'screen' }).catch(
        () => undefined
      ),
      callNative('voice.closeProducer', { kind: 'screen_audio' }).catch(
        () => undefined
      )
    ]);
    await callNative('voice.updateState', { sharingScreen: false });
  }
};

const setScreenShareEnabled = async (enabled: boolean) => {
  if (!sendTransport || activeChannelId === undefined) {
    throw new Error('Voice media is not connected.');
  }
  if (!canShareScreen) {
    throw new Error('You do not have permission to share your screen.');
  }
  if (enabled === screenShareEnabled || isStartingScreenShare) return;
  if (!enabled) {
    await stopScreenShare();
    return;
  }

  const generation = mediaGeneration;
  isStartingScreenShare = true;
  syncScreenShareButton();
  let stream: MediaStream | undefined;
  let videoProducer: Producer | undefined;
  let audioProducer: Producer | undefined;

  try {
    stream = await navigator.mediaDevices.getDisplayMedia({
      video: {
        frameRate: { ideal: 30, max: 30 }
      },
      audio: true
    });

    if (generation !== mediaGeneration || !sendTransport) {
      stream.getTracks().forEach((track) => track.stop());
      return;
    }

    const videoTrack = stream.getVideoTracks()[0];
    if (!videoTrack) {
      throw new Error('No screen video track is available.');
    }
    videoTrack.contentHint = 'detail';

    videoProducer = await sendTransport.produce({
      track: videoTrack,
      appData: { kind: 'screen' },
      encodings: [{ maxBitrate: 2_500_000 }]
    });

    const audioTrack = stream.getAudioTracks()[0];
    if (audioTrack) {
      audioProducer = await sendTransport.produce({
        track: audioTrack,
        appData: { kind: 'screen_audio' }
      });
    }

    screenStream = stream;
    screenProducer = videoProducer;
    screenAudioProducer = audioProducer;
    screenShareEnabled = true;
    videoTrack.addEventListener(
      'ended',
      () => {
        stopScreenShare().catch((error: unknown) => {
          notify(
            'connected',
            error instanceof Error ? error.message : String(error),
            'screenShare'
          );
        });
      },
      { once: true }
    );

    await callNative('voice.updateState', { sharingScreen: true });
  } catch (error) {
    videoProducer?.close();
    audioProducer?.close();
    stream?.getTracks().forEach((track) => track.stop());
    if (screenStream === stream) {
      screenStream = undefined;
      screenProducer = undefined;
      screenAudioProducer = undefined;
      screenShareEnabled = false;
    }
    await Promise.all([
      callNative('voice.closeProducer', { kind: 'screen' }).catch(
        () => undefined
      ),
      callNative('voice.closeProducer', { kind: 'screen_audio' }).catch(
        () => undefined
      ),
      callNative('voice.updateState', { sharingScreen: false }).catch(
        () => undefined
      )
    ]);
    throw error;
  } finally {
    isStartingScreenShare = false;
    syncScreenShareButton();
  }
};

const setMicrophoneMuted = async (muted: boolean) => {
  if (!sendTransport || activeChannelId === undefined) {
    throw new Error('Voice media is not connected.');
  }
  if (!canSpeak) {
    throw new Error(
      'You do not have permission to speak in this voice channel.'
    );
  }
  if (!muted && (!microphoneProducer || !microphoneTrack)) {
    await openMicrophone();
  }

  const previous = microphoneMuted;
  if (muted && microphoneTrack) microphoneTrack.enabled = false;
  microphoneMuted = muted;

  try {
    await callNative('voice.updateState', { micMuted: muted });
    if (microphoneTrack) microphoneTrack.enabled = !muted;
    notify('connected');
  } catch (error) {
    if (microphoneTrack) microphoneTrack.enabled = !previous;
    microphoneMuted = previous;
    throw error;
  }
};

const setOutputMuted = async (muted: boolean) => {
  const previousOutputMuted = outputMuted;
  const previousMicrophoneMuted = microphoneMuted;
  const nextMicrophoneMuted = muted ? true : microphoneMuted;
  outputMuted = muted;
  microphoneMuted = nextMicrophoneMuted;
  if (microphoneTrack) {
    microphoneTrack.enabled = !nextMicrophoneMuted;
  }
  consumers.forEach(({ consumer, element }) => {
    if (consumer.track.kind === 'audio') {
      consumer.track.enabled = !muted;
    }
    if (element instanceof HTMLAudioElement) {
      element.muted = muted;
    }
  });

  try {
    await callNative('voice.updateState', {
      micMuted: nextMicrophoneMuted,
      soundMuted: muted
    });
  } catch (error) {
    outputMuted = previousOutputMuted;
    microphoneMuted = previousMicrophoneMuted;
    if (microphoneTrack) {
      microphoneTrack.enabled = !previousMicrophoneMuted;
    }
    consumers.forEach(({ consumer, element }) => {
      if (consumer.track.kind === 'audio') {
        consumer.track.enabled = !previousOutputMuted;
      }
      if (element instanceof HTMLAudioElement) {
        element.muted = previousOutputMuted;
      }
    });
    throw error;
  }
};

const stop = () => {
  closeMedia();
  notify('idle');
};

const reportActionError = async (
  action: () => Promise<void>,
  errorContext: string
) => {
  try {
    await action();
  } catch (error) {
    notify(
      activeChannelId === undefined ? 'failed' : 'connected',
      error instanceof Error ? error.message : String(error),
      errorContext
    );
    throw error;
  }
};

(window as TBridgeWindow & { coveVoice?: unknown }).coveVoice = {
  start,
  stop,
  setRemoteAudioVolume,
  setMicrophoneMuted: (muted: boolean) =>
    reportActionError(() => setMicrophoneMuted(muted), 'microphone'),
  setOutputMuted: (muted: boolean) =>
    reportActionError(() => setOutputMuted(muted), 'audio'),
  setWebcamEnabled: (enabled: boolean) =>
    reportActionError(() => setWebcamEnabled(enabled), 'camera'),
  stopScreenShare: () => reportActionError(stopScreenShare, 'screenShare')
};

document
  .getElementById('screen-share-button')
  ?.addEventListener('click', () => {
    const action = screenShareEnabled
      ? stopScreenShare()
      : setScreenShareEnabled(true);
    action.catch((error: unknown) => {
      notify(
        activeChannelId === undefined ? 'failed' : 'connected',
        error instanceof Error ? error.message : String(error),
        'screenShare'
      );
    });
  });

postToNative({ type: 'ready' });
notify('ready');
