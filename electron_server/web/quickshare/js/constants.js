/** Quick Share / P2P protocol constants */
export const QUICK_SHARE_AES_KEY = '!N@S#CB1298AS3HADSF!@';
export const SIGNAL_API_BASE = 'https://nas.cab';

export const QSB_MAGIC = new Uint8Array([0x51, 0x53, 0x42, 0x01]);
export const QSB_MSG_AUTH_REQ = 0x01;
export const QSB_MSG_AUTH_RES = 0x81;
export const QSB_MSG_LIST_RES = 0x82;

export const NPC_MAGIC = new Uint8Array([0x4e, 0x50, 0x43, 0x01]);
export const NPC_TYPE_READY = 0x01;
export const NPC_TYPE_PING = 0x02;
export const NPC_TYPE_PONG = 0x03;
export const NPC_TYPE_REQ = 0x10;
export const NPC_TYPE_REQ_BEGIN = 0x11;
export const NPC_TYPE_REQ_END = 0x12;
export const NPC_TYPE_REQ_CANCEL = 0x13;
export const NPC_TYPE_CANCEL = 0x14;
export const NPC_TYPE_RES_BEGIN = 0x20;
export const NPC_TYPE_RES_END = 0x21;
export const NPC_TYPE_FLOW = 0x22;
export const NPC_TYPE_RES = 0x23;
export const NPC_TYPE_ACK = 0x30;

export const SIGNAL_MAGIC = new Uint8Array([0x4e, 0x50, 0x53, 0x01]);
export const SIG_PING = 0x01;
export const SIG_PONG = 0x02;
export const SIG_SESSION_READY = 0x10;
export const SIG_SESSION_CLOSED = 0x11;
export const SIG_WEBRTC_OFFER = 0x20;
export const SIG_WEBRTC_ANSWER = 0x21;
export const SIG_WEBRTC_CANDIDATE = 0x22;
export const SIG_ERROR = 0x23;
export const SIG_WEBRTC_DEVICE_READY = 0x33;
