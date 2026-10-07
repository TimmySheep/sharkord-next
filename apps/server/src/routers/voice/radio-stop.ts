import { ServerEvents, StreamKind } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { getCurrentVoiceRuntime } from '../../helpers/get-current-voice-runtime';
import { stopWatchRadioBridge } from '../../runtimes/watch-radio';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const radioStopRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.voiceTransport.maxRequests,
  windowMs: config.rateLimiters.voiceTransport.windowMs,
  logLabel: 'watchRadioStop'
})
  .input(z.object({ channelId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    const { channelId } = await getCurrentVoiceRuntime(ctx);
    if (channelId !== input.channelId) {
      return;
    }

    const stopped = stopWatchRadioBridge(channelId, ctx.user.id);
    if (!stopped) {
      return;
    }

    ctx.pubsub.publishForChannel(
      channelId,
      ServerEvents.VOICE_PRODUCER_CLOSED,
      {
        channelId,
        remoteId: ctx.user.id,
        kind: StreamKind.AUDIO
      }
    );
  });

export { radioStopRoute };
