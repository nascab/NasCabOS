#include "napi/native_api.h"

extern napi_value InitWebRTCBridge(napi_env env, napi_value exports);

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    return InitWebRTCBridge(env, exports);
}
EXTERN_C_END

static napi_module nascabWebrtcModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "nascab_webrtc",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterNascabWebrtcModule(void)
{
    napi_module_register(&nascabWebrtcModule);
}
