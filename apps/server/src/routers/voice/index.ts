import { t } from '../../utils/trpc';
import { closeProducerRoute } from './close-producer';
import { connectConsumerTransportRoute } from './connect-consumer-transport';
import { connectProducerTransportRoute } from './connect-producer-transport';
import { consumeRoute } from './consume';
import { createConsumerTransportRoute } from './create-consumer-transport';
import { createProducerTransportRoute } from './create-producer-transport';
import {
  onRadioFrameRoute,
  onUserJoinVoiceRoute,
  onUserLeaveVoiceRoute,
  onUserUpdateVoiceStateRoute,
  onUserVoiceMovedRoute,
  onUserVoiceReactionRoute,
  onVoiceAddExternalStreamRoute,
  onVoiceNewProducerRoute,
  onVoiceProducerClosedRoute,
  onVoiceRemoveExternalStreamRoute,
  onVoiceUpdateExternalStreamRoute
} from './events';
import { getProducersRoute } from './get-producers';
import { joinVoiceRoute } from './join';
import { leaveVoiceRoute } from './leave';
import { moveUserRoute } from './move';
import { produceRoute } from './produce';
import { radioFrameRoute } from './radio-frame';
import { radioStartRoute } from './radio-start';
import { radioStopRoute } from './radio-stop';
import { sendVoiceReactionRoute } from './send-reaction';
import { setConsumerQualityRoute } from './set-consumer-quality';
import { updateVoiceStateRoute } from './update-state';

export const voiceRouter = t.router({
  join: joinVoiceRoute,
  leave: leaveVoiceRoute,
  moveUser: moveUserRoute,
  updateState: updateVoiceStateRoute,
  sendReaction: sendVoiceReactionRoute,
  createProducerTransport: createProducerTransportRoute,
  connectProducerTransport: connectProducerTransportRoute,
  createConsumerTransport: createConsumerTransportRoute,
  connectConsumerTransport: connectConsumerTransportRoute,
  closeProducer: closeProducerRoute,
  produce: produceRoute,
  radioStart: radioStartRoute,
  radioFrame: radioFrameRoute,
  radioStop: radioStopRoute,
  consume: consumeRoute,
  setConsumerQuality: setConsumerQualityRoute,
  getProducers: getProducersRoute,
  onJoin: onUserJoinVoiceRoute,
  onLeave: onUserLeaveVoiceRoute,
  onUpdateState: onUserUpdateVoiceStateRoute,
  onMoved: onUserVoiceMovedRoute,
  onReaction: onUserVoiceReactionRoute,
  onNewProducer: onVoiceNewProducerRoute,
  onProducerClosed: onVoiceProducerClosedRoute,
  onRadioFrame: onRadioFrameRoute,
  onAddExternalStream: onVoiceAddExternalStreamRoute,
  onUpdateExternalStream: onVoiceUpdateExternalStreamRoute,
  onRemoveExternalStream: onVoiceRemoveExternalStreamRoute
});
