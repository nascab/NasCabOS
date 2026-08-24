# NasCab OS

本项目是 NasCab OS 官方代码库，本项目官方网站：<https://nas.cab>

## 项目结构

本代码包含主要以下几个项目：

| 项目 | 说明 |
| --- | --- |
| electron_server | 后端，使用 electron + express 实现本地服务功能 |
| flutter_client | Android + iOS + Windows + Mac 客户端，使用 flutter 实现跨平台客户端 |
| tv_android | Android TV 端 |
| tv_apple | Apple TV 端 |
| harmony_client | 鸿蒙端，开发中 |

## 运行方式

服务端运行方式：
先要将项目中releases中提供的依赖库和插件下载到本地，然后将对应平台的libs以及onnx_models解压缩后放到electron_server根目录下，libs中是第三方相关插件，onnx_models中是ocr相关模型文件，用于图像识别
```bash
npm i;
npm start;
```

客户端运行方式：

```bash
flutter pub get;
flutter run -d win/ios/android/mac
```
