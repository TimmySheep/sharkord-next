import { ChannelPermission } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { getCurrentVoiceRuntime } from '../../helpers/get-current-voice-runtime';
import { getWatchRadioBridge } from '../../runtimes/watch-radio';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const PCM_FRAME_BYTES = 1_280;

const radioFrameRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.voiceRadioFrame.maxRequests,
  windowMs: config.rateLimiters.voiceRadioFrame.windowMs,
  logLabel: 'watchRadioFrame'
})
  .input(
    z.object({
      channelId: z.number().int().positive(),
      payload: z.string().min(1_708).max(1_708)
    })
  )
  .mutation(async ({ ctx, input }) => {
    const { runtime, channelId } = await getCurrentVoiceRuntime(ctx);

    invariant(channelId === input.channelId, {
      code: 'FORBIDDEN',
      message: 'Watch radio channel does not match the current voice channel'
    });

    await ctx.needsChannelPermission(channelId, ChannelPermission.SPEAK);

    const bridge = getWatchRadioBridge(channelId, ctx.user.id);
    invariant(bridge, {
      code: 'BAD_REQUEST',
      message: 'Watch radio is not active'
    });

    invariant(!runtime.getUserState(ctx.user.id).micMuted, {
      code: 'FORBIDDEN',
      message: 'Unmute before sending Watch radio audio'
    });

    const pcm = Buffer.from(input.payload, 'base64');
    invariant(
      pcm.byteLength === PCM_FRAME_BYTES &&
        pcm.toString('base64') === input.payload,
      {
        code: 'BAD_REQUEST',
        message: 'Watch radio audio frame is invalid'
      }
    );

    bridge.sendPcmFrame(pcm);
  });

export { radioFrameRoute };
