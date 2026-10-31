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
  // the Windows shell injects media options through media-controls.js; the
  // macOS shell never sets this object, so every read has to fall back safely.
  coveMediaOptions?: TMediaOptions;
  videoProduceOptions?: (
    track: MediaStreamTrack,
    kind: string,
    bitrate: number
  ) => {
    track: MediaStreamTrack;
    appData: Record<string, unknown>;
    encodings?: Array<Record<string, unknown>>;
    codec?: Record<string, unknown>;
    codecOptions?: Record<string, unknown>;
  };
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

type TMediaOptions = {
  microphoneId?: string;
  cameraId?: string;
  speakerId?: string;
  height?: number;
  frameRate?: number;
  screenHeight?: number;
  screenFrameRate?: number;
  echoCancellation?: boolean;
  autoGainControl?: boolean;
  noiseMode?: TNoiseMode;
  noiseGateEnabled?: boolean;
  noiseGateThresholdDb?: number;
  mirrorOwnVideo?: boolean;
  screenBitrate?: number;
  screenCursor?: string;
  externalStreams?: Record<
    number,
    { audio?: boolean; video?: boolean } | undefined
  >;
};

type TConsumeResult = {
  producerId: string;
  consumerId: string;
  consumerKind: string;
  consumerRtpParameters: unknown;
  qualityLayers?: string[];
};

type TRemoteProducerIds = {
  remoteVideoIds?: number[];
  remoteAudioIds?: number[];
  remoteScreenIds?: number[];
  remoteScreenAudioIds?: number[];
  remoteExternalStreamIds?: number[];
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
  {
    consumer: Consumer;
    element: TMediaElement;
    qualityLayers?: string[];
  }
>();
const remoteAudioVolumes = new Map<string, number>();
let device: Device | undefined;
let sendTransport: Transport | undefined;
let receiveTransport: Transport | undefined;
let microphoneStream: MediaStream | undefined;
let microphoneInputStream: MediaStream | undefined;
let microphoneAudioContext: AudioContext | undefined;
let microphoneNoiseNode: AudioWorkletNode | undefined;
let microphoneGateNode: AudioWorkletNode | undefined;
let microphoneGateEnabled = false;
let microphoneGateThresholdDb = -48;
let microphoneProducer: Producer | undefined;
let microphoneTrack: MediaStreamTrack | undefined;
let microphoneNoiseMix = 1;
type TNoiseMode = 'off' | 'standard' | 'rnnoise' | 'dtln';
let microphoneNoiseMode: TNoiseMode = 'rnnoise';
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
// device selection is applied per capture, so the ids have to outlive a single join
let deviceMicrophoneId: string | undefined;
let devicePlaybackId: string | undefined;
let deviceWebcamId: string | undefined;
let deviceEchoCancellation = true;
let deviceAutoGainControl = true;
let microphoneTestStream: MediaStream | undefined;
let microphoneTestContext: AudioContext | undefined;
let microphoneTestTimer: ReturnType<typeof setInterval> | undefined;

const getNoiseMixParameter = (node: AudioWorkletNode) => {
  let parameter: AudioParam | undefined;
  node.parameters.forEach((value, name) => {
    if (name === 'mix') {
      parameter = value;
    }
  });
  return parameter;
};

// windows-only option channel; every field falls back when the object is absent
const mediaOptions = (): TMediaOptions => bridgeWindow.coveMediaOptions ?? {};

const waitForDtlnReady = (node: AudioWorkletNode) =>
  new Promise<void>((resolve, reject) => {
    const timer = setTimeout(
      () =>
        reject(
          new Error(
            'The DTLN noise suppression processor did not start in time.'
          )
        ),
      10_000
    );
    node.port.onmessage = (event: MessageEvent) => {
      if (
        typeof event.data === 'string' &&
        event.data.startsWith('ready:')
      ) {
        clearTimeout(timer);
        resolve();
      }
    };
    node.onprocessorerror = (error: Event) => {
      clearTimeout(timer);
      reject(error);
    };
  });

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
    const transport = receiveTransport;

    const consumer = await transport.consume({
      id: parameters.consumerId,
      producerId: parameters.producerId,
      kind: [
        'audio',
        'screen_audio',
        'external_audio'
      ].includes(parameters.consumerKind)
        ? 'audio'
        : 'video',
      rtpParameters: parameters.consumerRtpParameters as Parameters<
        Transport['consume']
      >[0]['rtpParameters']
    });

    if (receiveTransport !== transport) {
      consumer.close();
      return;
    }

    if (consumer.track.kind === 'audio') {
      const audio = document.createElement('audio');
      audio.autoplay = true;
      audio.srcObject = new MediaStream([consumer.track]);
      audio.muted = outputMuted;
      audio.volume = remoteAudioVolumes.get(key) ?? 1;
      applyPlaybackSink(audio);
      if (receiveTransport !== transport) {
        consumer.close();
        audio.srcObject = null;
        return;
      }
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
    consumers.set(key, {
      consumer,
      element: video,
      qualityLayers: parameters.qualityLayers ?? []
    });
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
  // mirroring only affects the local view, the published track stays untouched.
  preview.style.transform = mediaOptions().mirrorOwnVideo
    ? 'scaleX(-1)'
    : '';
  const tile = preview.closest('.video-tile');
  tile?.classList.toggle('hidden', cameraStream === undefined);
  setGalleryVisible(remoteVideoCount > 0 || cameraStream !== undefined);
};

const closeMedia = () => {
  mediaGeneration += 1;
  microphoneProducer?.close();
  microphoneProducer = undefined;
  microphoneTrack = undefined;
  microphoneNoiseNode = undefined;
  microphoneGateNode = undefined;
  microphoneAudioContext?.close().catch(() => {});
  microphoneAudioContext = undefined;
  canSpeak = false;
  canPublishAudio = false;
  microphoneStream?.getTracks().forEach((track) => track.stop());
  microphoneStream = undefined;
  microphoneInputStream?.getTracks().forEach((track) => track.stop());
  microphoneInputStream = undefined;
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
  stopMicrophoneTest();
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
          qualityLayers: (appData as { qualityLayers?: string[] })
            .qualityLayers,
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
  const options = mediaOptions();
  const gateEnabled = options.noiseGateEnabled ?? false;
  const gateThresholdDb = Math.min(
    0,
    Math.max(-70, options.noiseGateThresholdDb ?? -48)
  );
  const useDtln = microphoneNoiseMode === 'dtln';
  let inputStream: MediaStream | undefined;
  let outputStream: MediaStream | undefined;
  let audioContext: AudioContext | undefined;
  let producer: Producer | undefined;
  let gateNode: AudioWorkletNode | undefined;

  try {
    const microphoneId = deviceMicrophoneId ?? options.microphoneId;
    inputStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        autoGainControl: options.autoGainControl ?? deviceAutoGainControl,
        echoCancellation:
          options.echoCancellation ?? deviceEchoCancellation,
        noiseSuppression: microphoneNoiseMode === 'standard',
        // dtln models are trained on 16khz mono, ask the device for exactly that.
        ...(useDtln ? { sampleRate: 16000, channelCount: 1 } : {}),
        ...(microphoneId ? { deviceId: { exact: microphoneId } } : {})
      },
      video: false
    });
    const inputTrack = inputStream.getAudioTracks()[0];

    if (!inputTrack) {
      throw new Error('No microphone audio track is available.');
    }

    let noiseNode: AudioWorkletNode | undefined;
    outputStream = inputStream;
    const needsWorklet =
      microphoneNoiseMode === 'rnnoise' || useDtln || gateEnabled;
    if (needsWorklet) {
      audioContext = new AudioContext({
        sampleRate: useDtln ? 16000 : 48000
      });
      const source = audioContext.createMediaStreamSource(inputStream);
      const destination = audioContext.createMediaStreamDestination();
      let chain: AudioNode = source;

      if (gateEnabled) {
        await audioContext.audioWorklet.addModule(
          new URL('./noise-gate-processor.js', document.baseURI)
        );
        gateNode = new AudioWorkletNode(audioContext, 'sharkord-noise-gate');
        gateNode.port.postMessage({
          type: 'config',
          enabled: true,
          thresholdDb: gateThresholdDb,
          holdMs: 100
        });
        chain.connect(gateNode);
        chain = gateNode;
      }

      if (microphoneNoiseMode === 'rnnoise') {
        await audioContext.audioWorklet.addModule(
          new URL('./rnnoise-bundle.js', document.baseURI)
        );
        noiseNode = new AudioWorkletNode(audioContext, 'RnnoiseProcessor', {
          outputChannelCount: [1]
        });
        const mixParameter = getNoiseMixParameter(noiseNode);

        if (!mixParameter) {
          throw new Error('The noise suppression control is unavailable.');
        }

        mixParameter.setValueAtTime(
          microphoneNoiseMix,
          audioContext.currentTime
        );
        chain.connect(noiseNode);
        chain = noiseNode;
      } else if (useDtln) {
        await audioContext.audioWorklet.addModule(
          new URL('./dtln-processor.js', document.baseURI)
        );
        noiseNode = new AudioWorkletNode(audioContext, 'dtln-process');
        await waitForDtlnReady(noiseNode);
        chain.connect(noiseNode);
        chain = noiseNode;
      }

      chain.connect(destination);

      if (audioContext.state === 'suspended') {
        await audioContext.resume();
      }

      outputStream = destination.stream;
    }
    const track = outputStream.getAudioTracks()[0];

    if (!track) {
      throw new Error('The processed microphone audio track is unavailable.');
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

    microphoneInputStream = inputStream;
    microphoneStream = outputStream;
    microphoneAudioContext = audioContext;
    microphoneNoiseNode = noiseNode;
    microphoneGateNode = gateNode;
    microphoneGateEnabled = gateEnabled;
    microphoneGateThresholdDb = gateThresholdDb;
    microphoneProducer = producer;
    microphoneTrack = track;
    microphoneMuted = true;
    canPublishAudio = true;
  } catch (error) {
    producer?.close();
    outputStream?.getTracks().forEach((track) => track.stop());
    inputStream?.getTracks().forEach((track) => track.stop());
    audioContext?.close().catch(() => {});
    throw error;
  }
};

const start = async (
  channelId: number,
  routerRtpCapabilities: unknown,
  canProduceAudio = true,
  canPublishScreen = false,
  labels: TMediaLabels = defaultMediaLabels,
  initialNoiseMix = 1,
  initialNoiseMode: TNoiseMode = mediaOptions().noiseMode ?? 'rnnoise'
) => {
  if (activeChannelId === channelId) return;
  closeMedia();
  const generation = mediaGeneration;
  activeChannelId = channelId;
  canSpeak = canProduceAudio;
  canPublishAudio = canSpeak;
  canShareScreen = canPublishScreen;
  microphoneNoiseMix = Math.min(1, Math.max(0, initialNoiseMix));
  microphoneNoiseMode = initialNoiseMode;
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
    if (generation !== mediaGeneration) return;
    device = nextDevice;

    const [sendParameters, receiveParameters] = await Promise.all([
      callNative<Parameters<Device['createSendTransport']>[0]>(
        'voice.createProducerTransport'
      ),
      callNative<Parameters<Device['createRecvTransport']>[0]>(
        'voice.createConsumerTransport'
      )
    ]);
    if (generation !== mediaGeneration) return;

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
      })),
      ...(remoteProducers.remoteExternalStreamIds ?? []).flatMap(
        (remoteId) =>
          (['audio', 'video'] as const)
            .filter((kind) => mediaOptions().externalStreams?.[remoteId]?.[kind])
            .map((kind) => ({ remoteId, kind: `external_${kind}` }))
      )
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

// windows-only: media-controls.js installs a global encoder helper that knows
// about simulcast/codec selection; other platforms use plain encodings.
const produceVideoOptions = (
  track: MediaStreamTrack,
  kind: string,
  bitrate: number
): Parameters<Transport['produce']>[0] => {
  const external = bridgeWindow.videoProduceOptions;

  if (typeof external === 'function') {
    const options = external(track, kind, bitrate);
    return options as Parameters<Transport['produce']>[0];
  }

  return {
    track,
    appData: { kind },
    encodings: [{ maxBitrate: bitrate }]
  } as unknown as Parameters<Transport['produce']>[0];
};

const setWebcamEnabled = async (enabled: boolean) => {
  if (!sendTransport) throw new Error('Voice media is not connected.');
  if ((cameraProducer !== undefined) === enabled) return;

  if (enabled) {
    const options = mediaOptions();
    const cameraId = deviceWebcamId ?? options.cameraId;
    cameraStream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: 'user',
        width: { ideal: 1280 },
        height: { ideal: options.height ?? 720 },
        frameRate: {
          ideal: options.frameRate ?? 30,
          max: options.frameRate ?? 30
        },
        ...(cameraId ? { deviceId: { exact: cameraId } } : {})
      }
    });
    const track = cameraStream.getVideoTracks()[0];

    if (!track) {
      cameraStream.getTracks().forEach((cameraTrack) => cameraTrack.stop());
      cameraStream = undefined;
      throw new Error('No camera video track is available.');
    }

    try {
      cameraProducer = await sendTransport.produce(
        produceVideoOptions(track, 'video', 1_500_000)
      );
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
    const options = mediaOptions();
    stream = await navigator.mediaDevices.getDisplayMedia({
      video: {
        height: { ideal: options.screenHeight ?? 1080 },
        frameRate: {
          ideal: options.screenFrameRate ?? 30,
          max: options.screenFrameRate ?? 30
        },
        // cursor is a real display-media constraint but missing from the
        // bundled TS lib, so it is asserted rather than typed.
        cursor: (options.screenCursor ?? 'always') as string
      } as MediaTrackConstraints,
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

    videoProducer = await sendTransport.produce(
      produceVideoOptions(
        videoTrack,
        'screen',
        (options.screenBitrate ?? 6000) * 1000
      )
    );

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

const setNoiseSuppressionMode = async (mode: TNoiseMode) => {
  if (!['off', 'standard', 'rnnoise', 'dtln'].includes(mode)) {
    throw new Error('Unknown noise suppression mode.');
  }
  if (microphoneNoiseMode === mode) return;
  const wasMuted = microphoneMuted;
  await releaseMicrophoneProducer();
  microphoneNoiseMode = mode;
  if (!wasMuted) await setMicrophoneMuted(false);
};

const setNoiseGate = async (enabled: boolean, thresholdDb?: number) => {
  const nextEnabled = enabled === true;
  const nextThresholdDb = Math.min(
    0,
    Math.max(-70, thresholdDb ?? microphoneGateThresholdDb)
  );

  if (
    microphoneGateEnabled === nextEnabled &&
    microphoneGateThresholdDb === nextThresholdDb
  ) {
    return;
  }

  microphoneGateEnabled = nextEnabled;
  microphoneGateThresholdDb = nextThresholdDb;

  // a live gate node takes the new config directly, the chain shape does not change.
  if (microphoneGateNode) {
    microphoneGateNode.port.postMessage({
      type: 'config',
      enabled: nextEnabled,
      thresholdDb: nextThresholdDb,
      holdMs: 100
    });
    return;
  }

  // without a gate node only adding one needs a rebuild, so an open mic is reopened once.
  if (!nextEnabled || !microphoneProducer) return;
  const wasMuted = microphoneMuted;
  await releaseMicrophoneProducer();
  if (!wasMuted) await setMicrophoneMuted(false);
};

const setNoiseSuppressionMix = (mix: number) => {
  microphoneNoiseMix = Math.min(1, Math.max(0, mix));
  const parameter = microphoneNoiseNode
    ? getNoiseMixParameter(microphoneNoiseNode)
    : undefined;

  if (parameter && microphoneAudioContext) {
    parameter.setTargetAtTime(
      microphoneNoiseMix,
      microphoneAudioContext.currentTime,
      0.03
    );
  }
};

// setSinkId is unavailable in some engines, so a playback choice is best effort
const applyPlaybackSink = (element: HTMLAudioElement) => {
  const sinkable = element as HTMLAudioElement & {
    setSinkId?: (deviceId: string) => Promise<void>;
  };
  if (typeof sinkable.setSinkId !== 'function') return;
  const target = devicePlaybackId ?? mediaOptions().speakerId ?? '';
  sinkable.setSinkId(target).catch(() => undefined);
};

const applyPlaybackDevice = () => {
  consumers.forEach(({ element }) => {
    if (element instanceof HTMLAudioElement) {
      applyPlaybackSink(element);
    }
  });
};

const enumerateDevices = async () => {
  const entries = await navigator.mediaDevices.enumerateDevices();
  const list = (kind: MediaDeviceKind) =>
    entries
      .filter((entry) => entry.kind === kind)
      .map((entry) => ({ deviceId: entry.deviceId, label: entry.label }));

  return {
    inputs: list('audioinput'),
    outputs: list('audiooutput'),
    videos: list('videoinput')
  };
};

const releaseMicrophoneProducer = async () => {
  if (!microphoneProducer) return;
  await callNative('voice.closeProducer', { kind: 'audio' });
  microphoneProducer.close();
  microphoneProducer = undefined;
  microphoneTrack = undefined;
  microphoneStream?.getTracks().forEach((track) => track.stop());
  microphoneInputStream?.getTracks().forEach((track) => track.stop());
  await microphoneAudioContext?.close();
  microphoneAudioContext = undefined;
  microphoneNoiseNode = undefined;
  microphoneGateNode = undefined;
};

const reopenMicrophone = async () => {
  if (!microphoneProducer) return;
  const wasMuted = microphoneMuted;
  await releaseMicrophoneProducer();
  if (!wasMuted) await setMicrophoneMuted(false);
};

const reopenWebcam = async () => {
  if (!cameraProducer) return;
  await setWebcamEnabled(false);
  await setWebcamEnabled(true);
};

const setDeviceSettings = async (settings: {
  microphoneId?: string;
  playbackId?: string;
  webcamId?: string;
  echoCancellation?: boolean;
  autoGainControl?: boolean;
}) => {
  // an empty id means "platform default", so it is treated as no selection at all
  const normalize = (value: string | undefined) => {
    return value ? value : undefined;
  };
  const nextMicrophoneId = normalize(settings.microphoneId);
  const nextPlaybackId = normalize(settings.playbackId);
  const nextWebcamId = normalize(settings.webcamId);

  const microphoneChanged =
    nextMicrophoneId !== undefined && nextMicrophoneId !== deviceMicrophoneId;
  const echoChanged =
    settings.echoCancellation !== undefined &&
    settings.echoCancellation !== deviceEchoCancellation;
  const gainChanged =
    settings.autoGainControl !== undefined &&
    settings.autoGainControl !== deviceAutoGainControl;
  const webcamChanged =
    nextWebcamId !== undefined && nextWebcamId !== deviceWebcamId;

  if (nextMicrophoneId !== undefined) {
    deviceMicrophoneId = nextMicrophoneId;
  }
  if (nextPlaybackId !== undefined || settings.playbackId !== undefined) {
    devicePlaybackId = nextPlaybackId;
    applyPlaybackDevice();
  }
  if (nextWebcamId !== undefined) {
    deviceWebcamId = nextWebcamId;
  }
  if (settings.echoCancellation !== undefined) {
    deviceEchoCancellation = settings.echoCancellation;
  }
  if (settings.autoGainControl !== undefined) {
    deviceAutoGainControl = settings.autoGainControl;
  }

  if (microphoneChanged || echoChanged || gainChanged) {
    await reopenMicrophone();
  }
  if (webcamChanged) {
    await reopenWebcam();
  }
};

const stopMicrophoneTest = () => {
  if (microphoneTestTimer !== undefined) {
    clearInterval(microphoneTestTimer);
    microphoneTestTimer = undefined;
  }
  microphoneTestContext?.close().catch(() => undefined);
  microphoneTestContext = undefined;
  microphoneTestStream?.getTracks().forEach((track) => track.stop());
  microphoneTestStream = undefined;
  postToNative({ type: 'microphoneTest', level: 0 });
};

const startMicrophoneTest = async (deviceId?: string) => {
  stopMicrophoneTest();
  const targetId = deviceId ?? deviceMicrophoneId;
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      autoGainControl: deviceAutoGainControl,
      echoCancellation: deviceEchoCancellation,
      noiseSuppression: microphoneNoiseMode === 'standard',
      ...(targetId ? { deviceId: { exact: targetId } } : {})
    },
    video: false
  });
  const context = new AudioContext({ sampleRate: 48000 });
  const source = context.createMediaStreamSource(stream);
  const analyser = context.createAnalyser();
  analyser.fftSize = 1024;
  source.connect(analyser);
  if (context.state === 'suspended') await context.resume();

  const buffer = new Float32Array(analyser.fftSize);
  microphoneTestStream = stream;
  microphoneTestContext = context;
  microphoneTestTimer = setInterval(() => {
    analyser.getFloatTimeDomainData(buffer);
    let sum = 0;
    for (const sample of buffer) sum += sample * sample;
    const level = Math.min(1, Math.sqrt(sum / buffer.length) * 6);
    postToNative({ type: 'microphoneTest', level });
  }, 100);
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
  setNoiseSuppressionMix,
  setNoiseSuppressionMode,
  enumerateDevices,
  setDeviceSettings,
  startMicrophoneTest,
  stopMicrophoneTest,
  setMicrophoneMuted: (muted: boolean) =>
    reportActionError(() => setMicrophoneMuted(muted), 'microphone'),
  setNoiseGate: (enabled: boolean, thresholdDb?: number) =>
    reportActionError(() => setNoiseGate(enabled, thresholdDb), 'microphone'),
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
