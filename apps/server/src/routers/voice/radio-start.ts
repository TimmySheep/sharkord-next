import { ChannelPermission, ServerEvents, StreamKind } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { getCurrentVoiceRuntime } from '../../helpers/get-current-voice-runtime';
import {
  getWatchRadioBridge,
  startWatchRadioBridge
} from '../../runtimes/watch-radio';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const radioStartRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.voiceTransport.maxRequests,
  windowMs: config.rateLimiters.voiceTransport.windowMs,
  logLabel: 'watchRadioStart'
})
  .input(z.object({ channelId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    const { runtime, channelId } = await getCurrentVoiceRuntime(ctx);

    invariant(channelId === input.channelId, {
      code: 'FORBIDDEN',
      message: 'Watch radio channel does not match the current voice channel'
    });

    await ctx.needsChannelPermission(channelId, ChannelPermission.SPEAK);

    invariant(!getWatchRadioBridge(channelId, ctx.user.id), {
      code: 'BAD_REQUEST',
      message: 'Watch radio is already active'
    });

    await startWatchRadioBridge(runtime, ctx.user.id);

    ctx.pubsub.publishForChannel(channelId, ServerEvents.VOICE_NEW_PRODUCER, {
      channelId,
      remoteId: ctx.user.id,
      kind: StreamKind.AUDIO
    });
  });

export { radioStartRoute };
