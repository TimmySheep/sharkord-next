import { ChannelPermission, ServerEvents, StreamKind } from '@sharkord/shared';
import { afterEach, describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import type { DirectTransport, Producer } from 'mediasoup/types';
import OpusScript from 'opusscript';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import {
  channelRolePermissions,
  rolePermissions,
  roles
} from '../../db/schema';
import { VoiceRuntime } from '../../runtimes/voice';
import {
  getRtpPayload,
  startWatchRadioBridge,
  stopWatchRadioBridge
} from '../../runtimes/watch-radio';
import { pubsub } from '../../utils/pubsub';

const CHANNEL_ID = 2;
const PRIVATE_CHANNEL_ID = 4;
const PCM_FRAME_BYTES = 1_280;

let runtime: VoiceRuntime | undefined;
let sourceTransport: DirectTransport | undefined;

afterEach(async () => {
  sourceTransport?.close();
  sourceTransport = undefined;
  await runtime?.destroy();
  runtime = undefined;
});

const setupVoice = async (
  userId = 1,
  micMuted = true,
  channelId = CHANNEL_ID
) => {
  runtime = new VoiceRuntime(channelId);
  await runtime.init();
  runtime.addUser(userId, { micMuted, soundMuted: false });

  const { caller } = await initTest(userId, undefined, {
    currentVoiceChannelId: channelId
  });

  return { caller, runtime };
};

const addAudioProducer = async (userId: number): Promise<Producer> => {
  if (!runtime) {
    throw new Error('Voice runtime is not initialized');
  }

  const router = runtime.getRouter();
  const opusCodec = router.rtpCapabilities.codecs?.find(
    (codec) => codec.mimeType.toLowerCase() === 'audio/opus'
  );
  if (!opusCodec?.preferredPayloadType) {
    throw new Error('The voice router does not support Opus');
  }

  sourceTransport = await router.createDirectTransport();
  const producer = await sourceTransport.produce({
    kind: 'audio',
    rtpParameters: {
      codecs: [
        {
          mimeType: opusCodec.mimeType,
          payloadType: opusCodec.preferredPayloadType,
          clockRate: opusCodec.clockRate,
          channels: opusCodec.channels ?? 2,
          parameters: opusCodec.parameters
        }
      ],
      encodings: [{ ssrc: 22_345_678 }]
    }
  });

  runtime.addUser(userId, { micMuted: false, soundMuted: false });
  runtime.addProducer(userId, StreamKind.AUDIO, producer);
  return producer;
};

const sendOpusRtpPacket = (producer: Producer, payloadType: number) => {
  const encoder = new OpusScript(16_000, 1, OpusScript.Application.VOIP);
  const encoded = encoder.encode(Buffer.alloc(PCM_FRAME_BYTES), 640);
  encoder.delete();

  const packet = Buffer.alloc(12 + encoded.byteLength);
  packet[0] = 0x80;
  packet[1] = payloadType;
  packet.writeUInt16BE(1, 2);
  packet.writeUInt32BE(960, 4);
  packet.writeUInt32BE(22_345_678, 8);
  encoded.copy(packet, 12);
  producer.send(packet);
};

const addDefaultRoleSpeakDeny = async (channelId: number) => {
  const defaultRole = await tdb
    .select({ id: roles.id })
    .from(roles)
    .where(eq(roles.isDefault, true))
    .get();

  await tdb
    .insert(channelRolePermissions)
    .values([
      {
        channelId,
        roleId: defaultRole!.id,
        permission: ChannelPermission.VIEW_CHANNEL,
        allow: true,
        createdAt: Date.now()
      },
      {
        channelId,
        roleId: defaultRole!.id,
        permission: ChannelPermission.SPEAK,
        allow: false,
        createdAt: Date.now()
      }
    ])
    .execute();
};

describe('Watch radio voice routes', () => {
  test('should join the voice room, bridge both audio directions, and leave cleanly', async () => {
    const { caller } = await setupVoice(1, true);
    const sourceProducer = await addAudioProducer(2);
    const opusCodec = runtime!
      .getRouter()
      .rtpCapabilities.codecs?.find(
        (codec) => codec.mimeType.toLowerCase() === 'audio/opus'
      );
    const receivedFrames: {
      channelId: number;
      userId: number;
      seq: number;
      payload: string;
    }[] = [];
    const unrelatedFrames: typeof receivedFrames = [];
    const subscription = pubsub
      .subscribeFor(1, ServerEvents.VOICE_RADIO_FRAME)
      .subscribe({ next: (event) => receivedFrames.push(event) });
    const unrelatedSubscription = pubsub
      .subscribeFor(3, ServerEvents.VOICE_RADIO_FRAME)
      .subscribe({ next: (event) => unrelatedFrames.push(event) });

    try {
      await caller.voice.radioStart({ channelId: CHANNEL_ID });
      expect(runtime!.getProducer(StreamKind.AUDIO, 1)).toBeDefined();

      await caller.voice.updateState({ micMuted: false });
      await caller.voice.radioFrame({
        channelId: CHANNEL_ID,
        payload: Buffer.alloc(PCM_FRAME_BYTES).toString('base64')
      });

      sendOpusRtpPacket(sourceProducer, opusCodec!.preferredPayloadType!);

      const deadline = Date.now() + 2_000;
      while (receivedFrames.length === 0 && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 10));
      }

      expect(receivedFrames).toHaveLength(1);
      expect(receivedFrames[0]).toMatchObject({
        channelId: CHANNEL_ID,
        userId: 2
      });
      expect(Buffer.from(receivedFrames[0]!.payload, 'base64')).toHaveLength(
        PCM_FRAME_BYTES
      );
      expect(unrelatedFrames).toHaveLength(0);

      await caller.voice.radioStop({ channelId: CHANNEL_ID });
      expect(runtime!.getProducer(StreamKind.AUDIO, 1)).toBeUndefined();
    } finally {
      subscription.unsubscribe();
      unrelatedSubscription.unsubscribe();
    }
  });

  test('should reject starting without a voice presence', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.voice.radioStart({ channelId: CHANNEL_ID })
    ).rejects.toThrow('User is not in a voice channel');
  });

  test('should reject starting when the current channel differs', async () => {
    const { caller } = await setupVoice();

    await expect(caller.voice.radioStart({ channelId: 4 })).rejects.toThrow(
      'Watch radio channel does not match the current voice channel'
    );
  });

  test('should reject starting when the caller lacks global voice permission', async () => {
    const { caller } = await setupVoice(2);
    const defaultRole = await tdb
      .select({ id: roles.id })
      .from(roles)
      .where(eq(roles.isDefault, true))
      .get();

    await tdb
      .delete(rolePermissions)
      .where(eq(rolePermissions.roleId, defaultRole!.id))
      .execute();

    await expect(
      caller.voice.radioStart({ channelId: CHANNEL_ID })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should reject starting when the voice runtime is missing', async () => {
    const { caller } = await initTest(1, undefined, {
      currentVoiceChannelId: CHANNEL_ID
    });

    await expect(
      caller.voice.radioStart({ channelId: CHANNEL_ID })
    ).rejects.toThrow('Voice runtime not found for this channel');
  });

  test('should reject starting when the caller cannot speak in the channel', async () => {
    const { caller } = await setupVoice(2, true, PRIVATE_CHANNEL_ID);
    await addDefaultRoleSpeakDeny(PRIVATE_CHANNEL_ID);

    await expect(
      caller.voice.radioStart({ channelId: PRIVATE_CHANNEL_ID })
    ).rejects.toThrow('Insufficient channel permissions');
  });

  test('should reject a duplicate radio start', async () => {
    const { caller } = await setupVoice();
    await caller.voice.radioStart({ channelId: CHANNEL_ID });

    await expect(
      caller.voice.radioStart({ channelId: CHANNEL_ID })
    ).rejects.toThrow('Watch radio is already active');
  });

  test('should reject invalid frame payloads', async () => {
    const { caller } = await setupVoice();

    await expect(
      caller.voice.radioFrame({ channelId: CHANNEL_ID, payload: 'invalid' })
    ).rejects.toThrow();
  });

  test('should reject a frame for another channel', async () => {
    const { caller } = await setupVoice();

    await expect(
      caller.voice.radioFrame({
        channelId: 4,
        payload: Buffer.alloc(PCM_FRAME_BYTES).toString('base64')
      })
    ).rejects.toThrow(
      'Watch radio channel does not match the current voice channel'
    );
  });

  test('should reject a frame before radio start', async () => {
    const { caller } = await setupVoice();

    await expect(
      caller.voice.radioFrame({
        channelId: CHANNEL_ID,
        payload: Buffer.alloc(PCM_FRAME_BYTES).toString('base64')
      })
    ).rejects.toThrow('Watch radio is not active');
  });

  test('should reject a frame when the caller cannot speak in the channel', async () => {
    const { caller, runtime } = await setupVoice(2, false, PRIVATE_CHANNEL_ID);
    await addDefaultRoleSpeakDeny(PRIVATE_CHANNEL_ID);
    await startWatchRadioBridge(runtime, 2);

    await expect(
      caller.voice.radioFrame({
        channelId: PRIVATE_CHANNEL_ID,
        payload: Buffer.alloc(PCM_FRAME_BYTES).toString('base64')
      })
    ).rejects.toThrow('Insufficient channel permissions');
  });

  test('should reject frames while the microphone is muted', async () => {
    const { caller } = await setupVoice(1, true);
    await caller.voice.radioStart({ channelId: CHANNEL_ID });

    await expect(
      caller.voice.radioFrame({
        channelId: CHANNEL_ID,
        payload: Buffer.alloc(PCM_FRAME_BYTES).toString('base64')
      })
    ).rejects.toThrow('Unmute before sending Watch radio audio');
  });

  test('should reject a base64 payload with the wrong decoded size', async () => {
    const { caller } = await setupVoice(1, false);
    await caller.voice.radioStart({ channelId: CHANNEL_ID });

    await expect(
      caller.voice.radioFrame({
        channelId: CHANNEL_ID,
        payload: 'A'.repeat(1_708)
      })
    ).rejects.toThrow('Watch radio audio frame is invalid');
  });

  test('should stop idempotently when no radio producer exists', async () => {
    const { caller } = await setupVoice();

    await expect(
      caller.voice.radioStop({ channelId: CHANNEL_ID })
    ).resolves.toBeUndefined();
  });

  test('should reject invalid radio channel ids', async () => {
    const { caller } = await setupVoice();

    await expect(caller.voice.radioStart({ channelId: 0 })).rejects.toThrow();
  });
});

describe('Watch radio RTP parsing', () => {
  test('should return the payload after a header extension and padding', () => {
    const payload = Buffer.from([1, 2, 3, 4]);
    const packet = Buffer.alloc(12 + 8 + payload.length + 2);
    packet[0] = 0xb0;
    packet[1] = 100;
    packet.writeUInt16BE(1, 14);
    packet[16] = 0x10;
    packet[17] = 0x20;
    payload.copy(packet, 20);
    packet[packet.length - 1] = 2;

    expect(getRtpPayload(packet)).toEqual(payload);
  });

  test('should return no payload for malformed RTP packets', () => {
    expect(getRtpPayload(Buffer.alloc(8))).toBeUndefined();
    expect(
      getRtpPayload(Buffer.from([0x40, 100, ...Buffer.alloc(10)]))
    ).toBeUndefined();
  });
});

describe('Watch radio bridge lifecycle', () => {
  test('should close its room producer when explicitly stopped', async () => {
    const { runtime } = await setupVoice();
    const bridge = await startWatchRadioBridge(runtime, 1);

    expect(runtime.getProducer(StreamKind.AUDIO, 1)).toBeDefined();
    expect(stopWatchRadioBridge(CHANNEL_ID, 1)).toBe(true);
    expect(runtime.getProducer(StreamKind.AUDIO, 1)).toBeUndefined();
    expect(bridge).toBeDefined();
  });

  test('should remove itself when the voice runtime removes its user', async () => {
    const { runtime } = await setupVoice();
    await startWatchRadioBridge(runtime, 1);

    runtime.removeUser(1);

    expect(stopWatchRadioBridge(CHANNEL_ID, 1)).toBe(false);
  });
});
