# NasCab OS

> [简体中文](README.md) | **English**

This is the official source repository of NasCab OS. Official website: <https://nas.cab>

## Project Structure

This repository contains the following projects:

| Project | Description |
| --- | --- |
| electron_server | Backend, uses electron + express to provide local services |
| flutter_client | Android + iOS + Windows + Mac clients, built with flutter for cross-platform support |
| tv_android | Android TV client |
| tv_apple | Apple TV client |
| harmony_client | HarmonyOS client, in development |

## Running

Server:

First, download the dependency libraries and plugins provided in the releases (<https://github.com/nascab/NasCabOS/releases>), then extract the `libs` and `onnx_models` of the corresponding platform to the root directory of `electron_server`. `libs` contains third-party plugins, and `onnx_models` contains OCR model files used for image recognition.

```bash
npm i;
npm start;
```

Client:

```bash
flutter pub get;
flutter run -d win/ios/android/mac
```

To serve the compiled web client from the server (static web access):

```bash
Build the flutter web version and place it under the electron_server/web/main directory.
```

## Donations

If NasCab OS is helpful to you, we welcome your support:

<div align="center">

| WeChat Scan to Donate | PayPal |
| --- | --- |
| <img src="qrcode-wx.png" width="200" alt="WeChat donation QR code" /> | [PayPal.Me/nascabos](https://paypal.me/nascabos) |

</div>

Business cooperation / Contact us: ypptec@126.com / ypptec@gmail.com
