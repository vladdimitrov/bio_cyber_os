package com.example.bio_cyber_os

import io.flutter.embedding.android.FlutterFragmentActivity

/// **Must** extend [FlutterFragmentActivity] (not [FlutterActivity]) for `local_auth` /
/// `BiometricPrompt` — required on Huawei and other OEMs where the prompt attaches to a Fragment.
class MainActivity : FlutterFragmentActivity()
