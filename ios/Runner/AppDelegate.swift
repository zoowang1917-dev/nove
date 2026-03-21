// ios/Runner/AppDelegate.swift
import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let CHANNEL = "com.novel.ai/platform"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        setupMethodChannel()
        requestNotificationPermission()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func setupMethodChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else { return }
        FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)
            .setMethodCallHandler { (call, result) in
                switch call.method {
                case "setKeepScreenOn":
                    let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
                    UIApplication.shared.isIdleTimerDisabled = on
                    result(true)
                case "getDeviceInfo":
                    result([
                        "model":         UIDevice.current.model,
                        "systemVersion": UIDevice.current.systemVersion,
                    ])
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }
}
