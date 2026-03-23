import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateManager {
  // 这是您的 GitHub 仓库的专属发版监测地址！
  static const String githubApiUrl = 'https://api.github.com/repos/zoowang1917-dev/nove/releases/latest';

  static Future<void> checkUpdate(BuildContext context, {bool showNoUpdateToast = false}) async {
    try {
      // 1. 获取当前手机上装的 App 版本
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      // 2. 去 GitHub 问问最新发到了哪个版本
      var response = await Dio().get(githubApiUrl);
      String latestVersion = response.data['tag_name'].toString().replaceAll('v', '');
      
      // 在 Release 里面翻找 .apk 后缀的下载链接
      List assets = response.data['assets'];
      String? downloadUrl;
      for (var asset in assets) {
        if (asset['name'].toString().endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'];
          break;
        }
      }

      // 3. 对比版本号，如果线上的比手里的大，就弹窗！
      if (latestVersion != currentVersion && downloadUrl != null) {
        _showUpdateDialog(context, latestVersion, downloadUrl, response.data['body'] ?? '修复了一些已知问题，提升了稳定性。');
      } else if (showNoUpdateToast) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已经是最新版本 🎉')));
      }
    } catch (e) {
      print("检查更新失败: $e");
    }
  }

  static void _showUpdateDialog(BuildContext context, String newVersion, String url, String releaseNotes) {
    showDialog(
      context: context,
      barrierDismissible: false, // 设为 false 就是强制更新，点外面关不掉
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 V$newVersion 🚀'),
        content: SingleChildScrollView(child: Text('更新内容：\n$releaseNotes')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstall(context, url, newVersion);
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  static Future<void> _downloadAndInstall(BuildContext context, String url, String version) async {
    // 弹出一个不可取消的下载进度提示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在拼命下载新版本，请勿退出...'),
          ],
        ),
      ),
    );

    try {
      // 在手机里找个临时的抽屉放下载好的 APK
      Directory tempDir = await getTemporaryDirectory();
      String savePath = '${tempDir.path}/update_v$version.apk';

      // 派 Dio 去把 APK 搬回来
      await Dio().download(url, savePath);

      // 下载完，关掉那个进度条弹窗
      Navigator.pop(context);

      // 呼叫安卓系统：大哥，帮我安装这个包！
      await OpenFilex.open(savePath);

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('哎呀，下载失败了: $e')));
    }
  }
}
