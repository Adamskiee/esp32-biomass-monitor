import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void mockAppFonts() {
  final assets = [
    for (final weight in ['Regular', 'Medium', 'Bold'])
      'google_fonts/Inter-$weight.ttf',
  ];
  final manifest = const StandardMessageCodec().encodeMessage({
    for (final asset in assets)
      asset: [
        {'asset': asset},
      ],
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final asset = utf8.decode(message!.buffer.asUint8List());
        if (asset == 'AssetManifest.bin') return manifest;
        // Color and layout checks do not need real font outlines.
        if (assets.contains(asset)) return ByteData(0);
        return null;
      });
}
