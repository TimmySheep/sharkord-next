// native controls use only the bundled media worker's tracks and transports.
window.coveMediaOptions = { cameraId: "", microphoneId: "", speakerId: "", height: 720, frameRate: 30, screenHeight: 1080, screenFrameRate: 30, echoCancellation: true, autoGainControl: true, simulcast: false, noiseGateEnabled: false, noiseGateThresholdDb: -48, mirrorOwnVideo: false, screenCodec: "auto", screenBitrate: 6000, screenCursor: "always" };
let previewStream;
let previewAudio;
let previewGeneration = 0;
let monitoring = false;
let pinnedMediaKey;
let previewAnalyser;
let previewLevelContext;
const audioDevice = (id) => id ? { exact: id } : undefined;
// mirrors the web meter: rms to decibels, then the -70..0db window mapped to a percentage.
const previewLevel = () => {
  if (!previewAnalyser) return null;
  const samples = new Float32Array(previewAnalyser.fftSize);
  previewAnalyser.getFloatTimeDomainData(samples);
  let sum = 0;
  for (const sample of samples) { sum += sample * sample; }
  const decibels = 20 * Math.log10(Math.sqrt(sum / samples.length) + 1e-8);
  return Math.max(0, Math.min(100, ((Math.max(-70, Math.min(0, decibels)) + 70) / 70) * 100));
};
const stopPreviewLevel = () => {
  previewAnalyser = undefined;
  previewLevelContext?.close().catch(() => {});
  previewLevelContext = undefined;
};
const applyMirror = () => {
  const preview = document.getElementById("local-preview");
  if (preview) preview.style.transform = window.coveMediaOptions.mirrorOwnVideo ? "scaleX(-1)" : "";
};
const videoEncodings = (bitrate) => window.coveMediaOptions.simulcast
  ? [{ scaleResolutionDownBy: 4, maxBitrate: Math.round(bitrate / 8) }, { scaleResolutionDownBy: 2, maxBitrate: Math.round(bitrate / 3) }, { scaleResolutionDownBy: 1, maxBitrate: bitrate }]
  : [{ maxBitrate: bitrate }];
const screenCodec = () => {
  const wanted = window.coveMediaOptions.screenCodec ?? "auto";
  if (wanted === "auto") return undefined;
  // an unavailable codec falls back to the router default rather than failing the share.
  return device.rtpCapabilities.codecs.find((candidate) => candidate.mimeType.toLowerCase() === wanted.toLowerCase());
};
const videoProduceOptions = (track, kind, bitrate) => {
  const encodings = videoEncodings(bitrate);
  const height = track.getSettings().height ?? 720;
  const qualityLayers = encodings.map((encoding, spatialLayer) => ({ spatialLayer, label: `${Math.round(height / (encoding.scaleResolutionDownBy ?? 1))}p` }));
  const simulcastCodec = window.coveMediaOptions.simulcast ? device.rtpCapabilities.codecs.find((candidate) => candidate.mimeType.toLowerCase() === "video/vp8") : undefined;
  if (window.coveMediaOptions.simulcast && !simulcastCodec) throw new Error("VP8 is unavailable for simulcast.");
  // a chosen screen codec only applies to single layer publishing, simulcast stays on vp8.
  let codec;
  if (window.coveMediaOptions.simulcast) { codec = simulcastCodec; }
  else if (kind === "screen") { codec = screenCodec(); }
  const bitrateKbps = Math.round(bitrate / 1000);
  const codecOptions = kind === "screen" ? {
    videoGoogleStartBitrate: Math.min(2000, bitrateKbps),
    videoGoogleMaxBitrate: bitrateKbps,
    videoGoogleMinBitrate: Math.min(200, bitrateKbps)
  } : undefined;
  return { track, encodings, codec, codecOptions, appData: { kind, ...(window.coveMediaOptions.simulcast ? { qualityLayers } : {}) } };
};
const mediaStats = async (key) => {
  const target = key === "local" ? microphoneProducer : consumers.get(key)?.consumer;
  if (!target) return [];
  const stats = await target.getStats();
  return [...stats.values()].filter((entry) => ["inbound-rtp", "outbound-rtp", "media-source", "candidate-pair"].includes(entry.type))
    .map(({ type, kind, bytesReceived, bytesSent, packetsLost, jitter, framesPerSecond, frameWidth, frameHeight, currentRoundTripTime, audioLevel }) =>
      ({ type, kind, bytesReceived, bytesSent, packetsLost, jitter, framesPerSecond, frameWidth, frameHeight, currentRoundTripTime, audioLevel }));
};
const stopPreview = () => {
  previewGeneration += 1;
  previewStream?.getTracks().forEach((track) => track.stop());
  previewStream = undefined;
  if (previewAudio) { previewAudio.pause(); previewAudio.srcObject = null; previewAudio.remove(); previewAudio = undefined; }
  stopPreviewLevel();
  updateLocalPreview();
};
window.coveMedia = {
  devices: async () => (await navigator.mediaDevices.enumerateDevices()).map(({ kind, deviceId, label }) => ({ kind, deviceId, label })),
  options: async (options) => {
    Object.assign(window.coveMediaOptions, options);
    const selected = window.coveMediaOptions;
    await Promise.all([...consumers.values()].filter(({ element }) => element instanceof HTMLAudioElement && element.setSinkId)
      .map(({ element }) => element.setSinkId(selected.speakerId)));
    await setNoiseSuppressionMode(selected.noiseMode ?? "rnnoise");
    // the gate api only exists once the voice worker has loaded.
    if (typeof setNoiseGate === "function") { await setNoiseGate(selected.noiseGateEnabled ?? false, selected.noiseGateThresholdDb ?? -48); }
    applyMirror();
  },
  snapshot: () => ({
    screenSharing: screenShareEnabled,
    streams: [...consumers.entries()].map(([key, { consumer, qualityLayers }]) => ({ key, remoteId: Number(key.split(":")[0]), kind: key.split(":")[1], qualityLayers: qualityLayers ?? [], video: consumer.track.kind === "video" })),
    pictureInPicture: document.pictureInPictureEnabled === true
  }),
  volume: setRemoteAudioVolume,
  level: previewLevel,
  quality: async (key, layer) => {
    const [remoteId, kind] = key.split(":");
    await callNative("voice.setConsumerQuality", { remoteId: Number(remoteId), kind, quality: layer < 0 ? { mode: "auto" } : { mode: "layer", spatialLayer: layer } });
  },
  pin: (key) => {
    pinnedMediaKey = key;
    for (const [id, { element }] of consumers) {
      const tile = element.closest(".video-tile");
      if (tile) tile.style.display = key && key !== id ? "none" : "";
    }
    const local = document.getElementById("local-preview")?.closest(".video-tile");
    if (local) local.style.display = key ? "none" : "";
  },
  consumerClosed: (key) => { if (pinnedMediaKey === key) window.coveMedia.pin(null); },
  zoom: (key, scale) => { const video = consumers.get(key)?.element; if (video?.tagName === "VIDEO") video.style.transform = `scale(${Math.max(1, Math.min(4, scale))})`; },
  picture: async (key) => { const element = consumers.get(key)?.element; if (element instanceof HTMLVideoElement && document.pictureInPictureEnabled) await element.requestPictureInPicture(); },
  statistics: mediaStats,
  screen: async () => reportActionError(() => setScreenShareEnabled(!screenShareEnabled), "screenShare"),
  stopPreview,
  preview: async (kind) => {
    stopPreview();
    const generation = previewGeneration;
    const options = window.coveMediaOptions;
    const stream = await navigator.mediaDevices.getUserMedia(kind === "video"
      ? { video: { deviceId: audioDevice(options.cameraId), height: { ideal: options.height }, frameRate: { ideal: options.frameRate } }, audio: false }
      : { audio: { deviceId: audioDevice(options.microphoneId), echoCancellation: options.echoCancellation }, video: false });
    if (generation !== previewGeneration) { stream.getTracks().forEach((track) => track.stop()); return; }
    previewStream = stream;
    if (kind === "video") {
      const preview = document.getElementById("local-preview");
      preview.srcObject = stream;
      preview.hidden = false;
      preview.closest(".video-tile")?.classList.remove("hidden");
      applyMirror();
      await preview.play();
    } else {
      previewAudio = document.createElement("audio");
      previewAudio.srcObject = stream;
      if (previewAudio.setSinkId) await previewAudio.setSinkId(options.speakerId);
      document.body.append(previewAudio);
      await previewAudio.play();
      // the meter reads the raw preview stream, so it works with or without the voice chain.
      previewLevelContext = new AudioContext();
      const levelSource = previewLevelContext.createMediaStreamSource(stream);
      previewAnalyser = previewLevelContext.createAnalyser();
      previewAnalyser.fftSize = 2048;
      levelSource.connect(previewAnalyser);
    }
  }
};
setInterval(async () => {
  if (monitoring || activeChannelId === undefined) return;
  monitoring = true;
  try {
    const speaking = [];
    if (!microphoneMuted && (await mediaStats("local")).some((entry) => entry.audioLevel > 0.02)) speaking.push(0);
    for (const [key, { consumer }] of consumers) {
      if (consumer.track.kind === "audio" && key.endsWith(":audio") && (await mediaStats(key)).some((entry) => entry.audioLevel > 0.02)) speaking.push(Number(key.split(":")[0]));
    }
    if (activeChannelId !== undefined) postToNative({ type: "mediaState", channelId: activeChannelId, ...window.coveMedia.snapshot(), speaking, microphoneMuted, outputMuted, webcamEnabled: cameraProducer !== undefined });
  } catch (error) {
    // a consumer can close while its statistics request is outstanding.
  } finally { monitoring = false; }
}, 500);
postToNative({ type: "ready" });
