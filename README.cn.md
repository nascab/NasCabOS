# NasCab OS

> **简体中文** | [English](README.md)

本项目是 NasCab OS 官方代码库，本项目官方网站：<https://nas.cab>

NasCabOS 是一款跨平台 NAS 软件，支持远程管理照片、影音、音乐、图书和文件，还支持文件分享、Transmission 下载、Docker 管理、远程终端等功能。


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
先要将项目中releases中提供的依赖库和插件（https://github.com/nascab/NasCabOS/releases）下载到本地，然后将对应平台的libs以及onnx_models解压缩后放到electron_server根目录下，libs中是第三方相关插件，onnx_models中是ocr相关模型文件，用于图像识别
```bash
npm i;
npm start;
```

客户端运行方式：

```bash
flutter pub get;
flutter run -d win/ios/android/mac
```

如何把网页端编译后放到服务端下，实现静态网页端的访问：
```bash
将flutter打包web端后放入electron_server/web/main目录下
```

## 捐助支持

如果 NasCab OS 对您有帮助，欢迎捐助支持我们：

<div align="center">

| 微信扫码捐助 | PayPal |
| --- | --- |
| <img src="qrcode-wx.webp" width="200" alt="微信捐助二维码" /> | [PayPal.Me/nascabos](https://paypal.me/nascabos) |

</div>

商务合作/联系我们：ypptec@126.com / ypptec@gmail.com
