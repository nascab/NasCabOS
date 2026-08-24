// ignore_for_file: implementation_imports

import 'package:NasCabOS/modules/transfer/controllers/download_controller.dart';
import 'package:flutter/cupertino.dart' show showCupertinoModalPopup;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/internal.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter_quill_extensions/src/common/utils/element_utils/element_utils.dart';
import 'package:flutter_quill_extensions/src/common/utils/string.dart';
import 'package:flutter_quill_extensions/src/editor/image/image_load_utils.dart';
import 'package:flutter_quill_extensions/src/editor/image/widgets/image.dart'
    show
        ImageTapWrapper,
        getImageStyleString,
        getImageWidgetByImageSource,
        standardizeImageUrl;
import 'package:flutter_quill_extensions/src/editor/image/widgets/image_resizer.dart';
import 'package:get/get.dart';

class NotesQuillImageEmbedBuilder extends EmbedBuilder {
  NotesQuillImageEmbedBuilder({
    required this.config,
  });

  final QuillEditorImageEmbedConfig config;

  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(
    BuildContext context,
    EmbedContext embedContext,
  ) {
    final imageSource = standardizeImageUrl(embedContext.node.value.data);
    final ((imageSize), margin, alignment) = getElementAttributes(
      embedContext.node,
      context,
    );

    final imageWidget = getImageWidgetByImageSource(
      imageSource,
      context: context,
      imageProviderBuilder: config.imageProviderBuilder,
      imageErrorWidgetBuilder: config.imageErrorWidgetBuilder,
      alignment: alignment,
      height: imageSize.height,
      width: imageSize.width,
    );

    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (_) => _NotesImageOptionsMenu(
            controller: embedContext.controller,
            config: config,
            imageSource: imageSource,
            imageSize: imageSize,
            readOnly: embedContext.readOnly,
            imageProvider: imageWidget.image,
          ),
        );
      },
      child: Builder(
        builder: (context) {
          if (margin != null) {
            return Padding(
              padding: EdgeInsets.all(margin),
              child: imageWidget,
            );
          }
          return imageWidget;
        },
      ),
    );
  }
}

class _NotesImageOptionsMenu extends StatelessWidget {
  const _NotesImageOptionsMenu({
    required this.controller,
    required this.config,
    required this.imageSource,
    required this.imageSize,
    required this.readOnly,
    required this.imageProvider,
  });

  final QuillController controller;
  final QuillEditorImageEmbedConfig config;
  final String imageSource;
  final ElementSize imageSize;
  final bool readOnly;
  final ImageProvider imageProvider;

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(50, 0, 50, 0),
      child: SimpleDialog(
        title: Text(context.loc.image),
        children: [
          if (!readOnly)
            ListTile(
              title: Text(context.loc.resize),
              leading: const Icon(Icons.settings_outlined),
              onTap: () {
                Navigator.pop(context);
                showCupertinoModalPopup<void>(
                  context: context,
                  builder: (modalContext) {
                    final screenSize = MediaQuery.sizeOf(modalContext);
                    return ImageResizer(
                      onImageResize: (width, height) {
                        final res = getEmbedNode(
                          controller,
                          controller.selection.start,
                        );
                        final attr = replaceStyleStringWithSize(
                          getImageStyleString(controller),
                          width: width,
                          height: height,
                        );
                        controller
                          ..skipRequestKeyboard = true
                          ..formatText(
                            res.offset,
                            1,
                            StyleAttribute(attr),
                          );
                      },
                      imageWidth: imageSize.width,
                      imageHeight: imageSize.height,
                      maxWidth: screenSize.width,
                      maxHeight: screenSize.height,
                    );
                  },
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: Text(context.loc.copy),
            onTap: () async {
              Navigator.of(context).pop();
              controller.copiedImageUrl = ImageUrl(
                imageSource,
                getImageStyleString(controller),
              );

              final imageBytes = await ImageLoader.instance.loadImageBytesFromImageProvider(
                imageProvider: imageProvider,
              );
              if (imageBytes != null) {
                await ClipboardServiceProvider.instance.copyImage(imageBytes);
              }
            },
          ),
          if (!readOnly)
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: materialTheme.colorScheme.error,
              ),
              title: Text(context.loc.remove),
              onTap: () async {
                Navigator.of(context).pop();
                if (await config.shouldRemoveImageCallback?.call(imageSource) == false) {
                  return;
                }

                final offset = getEmbedNode(
                  controller,
                  controller.selection.start,
                ).offset;
                controller.replaceText(
                  offset,
                  1,
                  '',
                  TextSelection.collapsed(offset: offset),
                );
                await config.onImageRemovedCallback.call(imageSource);
              },
            ),
          ListTile(
            leading: const Icon(Icons.save),
            title: Text(context.loc.save),
            onTap: () async {
              Navigator.of(context).pop();
              final messenger = ScaffoldMessenger.of(context);
              final downloadUrl = _buildDownloadUrl(imageSource);
              if (downloadUrl.isEmpty) {
                messenger.showSnackBar(
                  SnackBar(content: Text(context.loc.errorUnexpectedSavingImage)),
                );
                return;
              }
              _ensureDownloadController();
              await Get.find<DownloadController>().handleDownload([downloadUrl]);
            },
          ),
          ListTile(
            leading: const Icon(Icons.zoom_in),
            title: Text(context.loc.zoom),
            onTap: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ImageTapWrapper(
                  imageUrl: imageSource,
                  config: config,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _ensureDownloadController() {
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
  }

  static String _buildDownloadUrl(String imageSource) {
    final trimmed = imageSource.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return '';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '';
    }

    final params = Map<String, String>.from(uri.queryParameters);
    final assetName = (params['name'] ?? '').trim();
    if (assetName.isNotEmpty && (params['fileName'] ?? '').trim().isEmpty) {
      params['fileName'] = assetName;
      return uri.replace(queryParameters: params).toString();
    }
    return trimmed;
  }
}
