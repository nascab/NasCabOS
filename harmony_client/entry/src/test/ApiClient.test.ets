import { describe, it, expect } from '@ohos/hypium';
import { APIState } from '../main/ets/core/network/APIState';
import { NetworkConfig } from '../main/ets/core/network/NetworkConfig';
import { AuthService } from '../main/ets/auth/AuthService';
import { P2pSignalingBinary } from '../main/ets/p2p/P2pSignalingBinary';
import { P2pChannelUtil, P2pRtcChannel } from '../main/ets/p2p/P2pProtocol';

export default function apiClientTest() {
  describe('NasCabHarmonyInfraTest', () => {
    it('apiState_p2pMode', 0, () => {
      const state = new APIState();
      state.baseUrl = NetworkConfig.P2P_BASE_URL;
      expect(state.isP2pMode()).assertTrue();
    });

    it('auth_obfuscatePassword', 0, () => {
      const obf = AuthService.obfuscatePassword('secret');
      expect(obf.startsWith('b64:')).assertTrue();
    });

    it('p2p_signaling_roundtrip_ping', 0, () => {
      const encoded = P2pSignalingBinary.encodePing(12345);
      expect(encoded !== undefined).assertTrue();
      const decoded = P2pSignalingBinary.decodeSignaling(encoded!);
      expect(decoded?.type).assertEqual('ping');
      expect(decoded?.ts).assertEqual(12345);
    });

    it('p2p_channel_resolve', 0, () => {
      expect(P2pChannelUtil.resolvePath('/api/file/upload')).assertEqual(P2pRtcChannel.UPLOAD);
      expect(P2pChannelUtil.resolvePath('/api/auth/login')).assertEqual(P2pRtcChannel.API);
    });
  });
}
