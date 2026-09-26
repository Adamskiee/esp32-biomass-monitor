// File generated for biomass_iot_app
// Replace with your actual Firebase configuration via 'flutterfire configure'
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'placeholder-api-key',
    appId: '1:123456789012:web:abcdef123456',
    messagingSenderId: '123456789012',
    projectId: 'biomass-iot-app',
    authDomain: 'biomass-iot-app.firebaseapp.com',
    storageBucket: 'biomass-iot-app.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'placeholder-api-key',
    appId: '1:123456789012:android:abcdef123456',
    messagingSenderId: '123456789012',
    projectId: 'biomass-iot-app',
    storageBucket: 'biomass-iot-app.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'placeholder-api-key',
    appId: '1:123456789012:ios:abcdef123456',
    messagingSenderId: '123456789012',
    projectId: 'biomass-iot-app',
    storageBucket: 'biomass-iot-app.appspot.com',
    iosBundleId: 'com.example.biomassIotApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'placeholder-api-key',
    appId: '1:123456789012:ios:abcdef123456',
    messagingSenderId: '123456789012',
    projectId: 'biomass-iot-app',
    storageBucket: 'biomass-iot-app.appspot.com',
    iosBundleId: 'com.example.biomassIotApp',
  );
}
