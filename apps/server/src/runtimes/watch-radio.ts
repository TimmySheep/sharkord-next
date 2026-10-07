import { ServerEvents, StreamKind } from '@sharkord/shared';
import type {
  Consumer,
  DirectTransport,
  Producer,
  RtpParameters
} from 'mediasoup/types';
import { randomInt } from 'node:crypto';
import OpusScript from 'opusscript';
import { logger } from '../logger';
import { pubsub } from '../utils/pubsub';
import { VoiceRuntime } from './voice';

const PCM_FRAME_BYTES = 1_280;
const PCM_FRAME_SAMPLES = PCM_FRAME_BYTES / 2;
const OPUS_SAMPLE_RATE = 16_000;
const RTP_CLOCK_RATE = 48_000;
const RTP_TIMESTAMP_STEP =
  (PCM_FRAME_SAMPLES * RTP_CLOCK_RATE) / OPUS_SAMPLE_RATE;
const MAX_RTP_PAYLOAD_BYTES = 1_275;

type TConsumedAudio = {
  consumer: Consumer;
  decoder: OpusScript;
};

const bridgesByChannel = new Map<number, Map<number, WatchRadioBridge>>();

class WatchRadioBridge {
  private transport?: DirectTransport;
  private producer?: Producer;
  private encoder = new OpusScript(
    OPUS_SAMPLE_RATE,
    1,
    OpusScript.Application.VOIP
  );
  private consumers = new Map<number, TConsumedAudio>();
  private pendingConsumers = new Map<number, Promise<void>>();
  private pendingConsumerProducerIds = new Map<number, string>();
  private unsubscribeProducerChanges?: () => void;
  private sequence = randomInt(0x1_0000);
  private timestamp = randomInt(0x1_0000_0000);
  private readonly ssrc = randomInt(1, 0x1_0000_0000);
  private payloadType = 100;
  private frameSequence = 0;
  private isClosed = false;

  public constructor(
    private readonly runtime: VoiceRuntime,
    private readonly userId: number
  ) {}

  public start = async (): Promise<void> => {
    const router = this.runtime.getRouter();
    const opusCodec = router.rtpCapabilities.codecs?.find(
      (codec) => codec.mimeType.toLowerCase() === 'audio/opus'
    );

    if (opusCodec?.preferredPayloadType === undefined) {
      throw new Error('The voice router does not support Opus');
    }
    this.payloadType = opusCodec.preferredPayloadType;

    this.transport = await router.createDirectTransport();
    const rtpParameters: RtpParameters = {
      codecs: [
        {
          mimeType: opusCodec.mimeType,
          payloadType: opusCodec.preferredPayloadType,
          clockRate: opusCodec.clockRate,
          channels: opusCodec.channels ?? 2,
          parameters: opusCodec.parameters
        }
      ],
      encodings: [{ ssrc: this.ssrc }]
    };

    this.producer = await this.transport.produce({
      kind: 'audio',
      rtpParameters,
      appData: { userId: this.userId, kind: 'watch-radio' }
    });
    this.runtime.addProducer(this.userId, StreamKind.AUDIO, this.producer);
    this.producer.observer.once('close', this.handleProducerClosed);

    this.unsubscribeProducerChanges = this.runtime.subscribeToProducerChanges(
      (change) => {
        if (change.kind !== StreamKind.AUDIO || change.userId === this.userId) {
          return;
        }

        if (change.added) {
          this.consumeAudio(change.userId, change.producerId).catch((error) => {
            logger.warn(
              'Failed to consume Watch radio audio from user %d: %s',
              change.userId,
              error
            );
          });
          return;
        }

        if (
          this.consumers.get(change.userId)?.consumer.producerId ===
          change.producerId
        ) {
          this.closeConsumer(change.userId);
        }
      }
    );

    const initialProducers = this.runtime
      .getAudioProducers()
      .filter(({ userId }) => userId !== this.userId);
    await Promise.all(
      initialProducers.map(({ userId, producer }) =>
        this.consumeAudio(userId, producer.id)
      )
    );
  };

  public sendPcmFrame = (pcm: Buffer): void => {
    if (this.isClosed || !this.producer || pcm.byteLength !== PCM_FRAME_BYTES) {
      return;
    }

    try {
      const encoded = this.encoder.encode(pcm, PCM_FRAME_SAMPLES);
      if (
        encoded.byteLength === 0 ||
        encoded.byteLength > MAX_RTP_PAYLOAD_BYTES
      ) {
        return;
      }

      const packet = Buffer.allocUnsafe(12 + encoded.byteLength);
      packet[0] = 0x80;
      packet[1] = this.payloadType;
      packet.writeUInt16BE(this.sequence, 2);
      packet.writeUInt32BE(this.timestamp, 4);
      packet.writeUInt32BE(this.ssrc, 8);
      encoded.copy(packet, 12);

      this.producer.send(packet);
      this.sequence = (this.sequence + 1) & 0xffff;
      this.timestamp = (this.timestamp + RTP_TIMESTAMP_STEP) >>> 0;
    } catch (error) {
      logger.warn('Failed to encode Watch radio audio: %s', error);
    }
  };

  public close = (removeProducer = true): void => {
    if (this.isClosed) {
      return;
    }

    this.isClosed = true;
    this.unsubscribeProducerChanges?.();
    this.unsubscribeProducerChanges = undefined;

    for (const userId of this.consumers.keys()) {
      this.closeConsumer(userId);
    }

    if (
      removeProducer &&
      this.producer &&
      this.runtime.getProducer(StreamKind.AUDIO, this.userId) === this.producer
    ) {
      this.runtime.removeProducer(this.userId, StreamKind.AUDIO);
    }

    this.transport?.close();
    this.transport = undefined;
    this.producer = undefined;
    this.encoder.delete();
    this.removeFromRegistry();
  };

  private handleProducerClosed = (): void => {
    this.close(false);
  };

  private consumeAudio = (
    userId: number,
    producerId: string
  ): Promise<void> => {
    if (this.consumers.get(userId)?.consumer.producerId === producerId) {
      return Promise.resolve();
    }

    if (this.pendingConsumerProducerIds.get(userId) === producerId) {
      return this.pendingConsumers.get(userId) ?? Promise.resolve();
    }

    this.closeConsumer(userId);

    const task = this.createConsumer(userId, producerId).finally(() => {
      if (this.pendingConsumers.get(userId) === task) {
        this.pendingConsumers.delete(userId);
        this.pendingConsumerProducerIds.delete(userId);
      }
    });

    this.pendingConsumers.set(userId, task);
    this.pendingConsumerProducerIds.set(userId, producerId);
    return task;
  };

  private createConsumer = async (
    userId: number,
    producerId: string
  ): Promise<void> => {
    const router = this.runtime.getRouter();
    const producer = this.runtime.getProducer(StreamKind.AUDIO, userId);
    const transport = this.transport;

    if (
      this.isClosed ||
      !transport ||
      !producer ||
      producer.id !== producerId ||
      !router.canConsume({
        producerId,
        rtpCapabilities: router.rtpCapabilities
      })
    ) {
      return;
    }

    let consumer: Consumer;
    let decoder: OpusScript;

    try {
      consumer = await transport.consume({
        producerId,
        rtpCapabilities: router.rtpCapabilities
      });
      decoder = new OpusScript(
        OPUS_SAMPLE_RATE,
        1,
        OpusScript.Application.VOIP
      );
    } catch (error) {
      logger.warn(
        'Failed to consume Watch radio audio from user %d: %s',
        userId,
        error
      );
      return;
    }

    if (
      this.isClosed ||
      this.runtime.getProducer(StreamKind.AUDIO, userId)?.id !== producerId
    ) {
      consumer.close();
      decoder.delete();
      return;
    }

    this.consumers.set(userId, { consumer, decoder });
    consumer.on('rtp', (packet) => {
      if (this.isClosed || this.consumers.get(userId)?.consumer !== consumer) {
        return;
      }

      const payload = getRtpPayload(packet);
      if (!payload) {
        return;
      }

      try {
        const pcm = decoder.decode(payload);
        if (
          pcm.byteLength === 0 ||
          pcm.byteLength > 3_840 ||
          pcm.byteLength % 2 !== 0
        ) {
          return;
        }

        this.frameSequence += 1;
        pubsub.publishFor(this.userId, ServerEvents.VOICE_RADIO_FRAME, {
          channelId: this.runtime.id,
          userId,
          seq: this.frameSequence,
          payload: pcm.toString('base64')
        });
      } catch {
        // Opus packets can be lost or malformed during a producer transition.
      }
    });
    consumer.on('producerclose', () => {
      if (this.consumers.get(userId)?.consumer === consumer) {
        this.closeConsumer(userId);
      }
    });
  };

  private closeConsumer = (userId: number): void => {
    const consumedAudio = this.consumers.get(userId);
    if (!consumedAudio) {
      return;
    }

    this.consumers.delete(userId);
    consumedAudio.consumer.close();
    consumedAudio.decoder.delete();
  };

  private removeFromRegistry = (): void => {
    const channelBridges = bridgesByChannel.get(this.runtime.id);
    channelBridges?.delete(this.userId);
    if (channelBridges?.size === 0) {
      bridgesByChannel.delete(this.runtime.id);
    }
  };
}

const startWatchRadioBridge = async (
  runtime: VoiceRuntime,
  userId: number
): Promise<WatchRadioBridge> => {
  const channelBridges = bridgesByChannel.get(runtime.id) ?? new Map();
  if (channelBridges.has(userId)) {
    throw new Error('Watch radio is already active');
  }

  const bridge = new WatchRadioBridge(runtime, userId);
  channelBridges.set(userId, bridge);
  bridgesByChannel.set(runtime.id, channelBridges);

  try {
    await bridge.start();
    return bridge;
  } catch (error) {
    bridge.close(false);
    throw error;
  }
};

const getWatchRadioBridge = (
  channelId: number,
  userId: number
): WatchRadioBridge | undefined => bridgesByChannel.get(channelId)?.get(userId);

const stopWatchRadioBridge = (channelId: number, userId: number): boolean => {
  const bridge = getWatchRadioBridge(channelId, userId);
  if (!bridge) {
    return false;
  }

  bridge.close();
  return true;
};

const getRtpPayload = (packet: Buffer): Buffer | undefined => {
  if (
    packet.byteLength < 12 ||
    packet[0] === undefined ||
    packet[1] === undefined
  ) {
    return undefined;
  }

  const version = packet[0] >>> 6;
  if (version !== 2) {
    return undefined;
  }

  let offset = 12 + (packet[0] & 0x0f) * 4;
  if (offset > packet.byteLength) {
    return undefined;
  }

  if ((packet[0] & 0x10) !== 0) {
    if (offset + 4 > packet.byteLength) {
      return undefined;
    }
    const extensionLength = packet.readUInt16BE(offset + 2) * 4;
    offset += 4 + extensionLength;
  }

  let end = packet.byteLength;
  if ((packet[0] & 0x20) !== 0) {
    const paddingLength = packet[end - 1];
    if (!paddingLength || paddingLength > end - offset) {
      return undefined;
    }
    end -= paddingLength;
  }

  return offset < end ? packet.subarray(offset, end) : undefined;
};

export {
  getRtpPayload,
  getWatchRadioBridge,
  startWatchRadioBridge,
  stopWatchRadioBridge
};
