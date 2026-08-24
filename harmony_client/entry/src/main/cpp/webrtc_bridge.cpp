#include "napi/native_api.h"
#include <map>
#include <mutex>
#include <string>
#include <vector>

/**
 * WebRTC NDK bridge for HarmonyOS.
 * Integrate ohos_webrtc (https://gitee.com/han_jin_fei/ohos_webrtc) by replacing
 * stub implementations with real RTCPeerConnection / RTCDataChannel calls.
 */

namespace {

std::mutex g_mutex;
int g_nextHandle = 1;
std::map<int, std::string> g_handles;

napi_threadsafe_function g_onBinaryCallback = nullptr;
napi_threadsafe_function g_onReadyCallback = nullptr;

std::string ReadJsString(napi_env env, napi_value value)
{
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    if (len == 0) {
        return std::string();
    }
    std::vector<char> buf(len + 1, '\0');
    napi_get_value_string_utf8(env, value, buf.data(), len + 1, &len);
    return std::string(buf.data(), len);
}

struct BinaryCallbackData {
    int channelHandle;
    std::vector<uint8_t> data;
};

void CallJsOnBinary(napi_env env, napi_value js_callback, void *context, void *data)
{
    auto *payload = static_cast<BinaryCallbackData *>(data);
    if (payload == nullptr) {
        return;
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    napi_value channelHandle;
    napi_create_int32(env, payload->channelHandle, &channelHandle);
    void *copyData = nullptr;
    napi_value arrayBuffer;
    napi_create_arraybuffer(env, payload->data.size(), &copyData, &arrayBuffer);
    if (copyData != nullptr && !payload->data.empty()) {
        memcpy(copyData, payload->data.data(), payload->data.size());
    }
    napi_value argv[2] = {channelHandle, arrayBuffer};
    napi_value result;
    napi_call_function(env, undefined, js_callback, 2, argv, &result);
    delete payload;
}

void CallJsOnReady(napi_env env, napi_value js_callback, void *, void *data)
{
    auto *channelName = static_cast<std::string *>(data);
    if (channelName == nullptr) {
        return;
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    napi_value nameValue;
    napi_create_string_utf8(env, channelName->c_str(), channelName->size(), &nameValue);
    napi_value result;
    napi_call_function(env, undefined, js_callback, 1, &nameValue, &result);
    delete channelName;
}

napi_value CreatePeerConnection(napi_env env, napi_callback_info info)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    int handle = g_nextHandle++;
    g_handles[handle] = "pc";
    napi_value result;
    napi_create_int32(env, handle, &result);
    return result;
}

napi_value CreateDataChannel(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t pcHandle = 0;
    napi_get_value_int32(env, args[0], &pcHandle);
    std::string label = ReadJsString(env, args[1]);
    std::lock_guard<std::mutex> lock(g_mutex);
    int handle = g_nextHandle++;
    g_handles[handle] = label;
    napi_value result;
    napi_create_int32(env, handle, &result);
    return result;
}

napi_value SendBinary(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t channelHandle = 0;
    napi_get_value_int32(env, args[0], &channelHandle);
    void *data = nullptr;
    size_t byteLength = 0;
    napi_get_arraybuffer_info(env, args[1], &data, &byteLength);
    (void)channelHandle;
    (void)data;
    (void)byteLength;
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

napi_value SetOnBinaryMessage(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (g_onBinaryCallback != nullptr) {
        napi_release_threadsafe_function(g_onBinaryCallback, napi_tsfn_release);
        g_onBinaryCallback = nullptr;
    }
    napi_value resourceName;
    napi_create_string_utf8(env, "onBinary", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_threadsafe_function(env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr, nullptr,
                                   CallJsOnBinary, &g_onBinaryCallback);
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value SetOnChannelReady(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (g_onReadyCallback != nullptr) {
        napi_release_threadsafe_function(g_onReadyCallback, napi_tsfn_release);
        g_onReadyCallback = nullptr;
    }
    napi_value resourceName;
    napi_create_string_utf8(env, "onReady", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_threadsafe_function(env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr, nullptr,
                                   CallJsOnReady, &g_onReadyCallback);
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value CreateOffer(napi_env env, napi_callback_info info)
{
    napi_value result;
    napi_create_object(env, &result);
    napi_value typeVal;
    napi_create_string_utf8(env, "offer", NAPI_AUTO_LENGTH, &typeVal);
    napi_set_named_property(env, result, "type", typeVal);
    napi_value sdpVal;
    napi_create_string_utf8(env, "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\n", NAPI_AUTO_LENGTH, &sdpVal);
    napi_set_named_property(env, result, "sdp", sdpVal);
    return result;
}

napi_value SetRemoteDescription(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    (void)args;
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

napi_value AddIceCandidate(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    (void)args;
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

napi_value ClosePeerConnection(napi_env env, napi_callback_info info)
{
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

napi_value SimulateChannelReady(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string label = ReadJsString(env, args[0]);
    if (g_onReadyCallback != nullptr) {
        auto *copy = new std::string(label);
        napi_call_threadsafe_function(g_onReadyCallback, copy, napi_tsfn_blocking);
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

} // namespace

napi_value InitWebRTCBridge(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"createPeerConnection", nullptr, CreatePeerConnection, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createDataChannel", nullptr, CreateDataChannel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendBinary", nullptr, SendBinary, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setOnBinaryMessage", nullptr, SetOnBinaryMessage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setOnChannelReady", nullptr, SetOnChannelReady, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createOffer", nullptr, CreateOffer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setRemoteDescription", nullptr, SetRemoteDescription, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"addIceCandidate", nullptr, AddIceCandidate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"closePeerConnection", nullptr, ClosePeerConnection, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"simulateChannelReady", nullptr, SimulateChannelReady, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
