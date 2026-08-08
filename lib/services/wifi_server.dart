import 'dart:convert';
import 'dart:io';

/// 整理整頓フォルダを同一 WiFi 内に HTTP で公開する簡易サーバー。
///
/// パソコンなどのブラウザで `http://<端末IP>:<port>/` を開くと、
/// 形式ごとのフォルダを辿ってファイルをダウンロードできる。
/// アプリを開いている間だけ動作する（バックグラウンド常駐はしない）。
class WifiServer {
  WifiServer(this.rootDir);

  /// 公開するルートフォルダ（例: `/storage/emulated/0/整理整頓`）。
  final String rootDir;

  static const int port = 8080;

  HttpServer? _server;
  bool get isRunning => _server != null;

  /// サーバーを開始し、アクセス用 URL を返す（WiFi 未接続などで IP 不明なら null）。
  Future<String?> start() async {
    if (_server == null) {
      final Directory root = Directory(rootDir);
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen(_handle);
    }
    return url();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// 現在のアクセス URL（IP が取れなければ null）。
  Future<String?> url() async {
    final String? ip = await _localIp();
    if (ip == null) {
      return null;
    }
    return 'http://$ip:$port/';
  }

  /// 端末の WiFi 側 IPv4 アドレスを取得する。
  Future<String?> _localIp() async {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    // wlan を優先し、無ければ最初の非ループバック IPv4 を使う。
    for (final NetworkInterface ni in interfaces) {
      if (ni.name.toLowerCase().contains('wlan')) {
        for (final InternetAddress a in ni.addresses) {
          return a.address;
        }
      }
    }
    for (final NetworkInterface ni in interfaces) {
      for (final InternetAddress a in ni.addresses) {
        return a.address;
      }
    }
    return null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final String rel = Uri.decodeComponent(req.uri.path).replaceAll('..', '');
      final String fsPath = rel == '/' ? rootDir : '$rootDir$rel';
      final FileSystemEntityType type = FileSystemEntity.typeSync(fsPath);

      if (type == FileSystemEntityType.directory) {
        await _serveDir(req, fsPath, rel);
      } else if (type == FileSystemEntityType.file) {
        await _serveFile(req, fsPath);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {
        // 応答済みなどは無視。
      }
    }
  }

  Future<void> _serveDir(HttpRequest req, String fsPath, String rel) async {
    final Directory dir = Directory(fsPath);
    final List<FileSystemEntity> entries = await dir.list().toList();
    entries.sort((FileSystemEntity a, FileSystemEntity b) {
      final bool ad = a is Directory;
      final bool bd = b is Directory;
      if (ad != bd) {
        return ad ? -1 : 1; // フォルダを先に
      }
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    final String base = rel.endsWith('/') ? rel : '$rel/';
    final StringBuffer html = StringBuffer()
      ..write('<!doctype html><html lang="ja"><head><meta charset="utf-8">')
      ..write('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..write('<title>整理整頓</title>')
      ..write('<style>body{font-family:sans-serif;margin:24px;line-height:1.9}'
          'a{text-decoration:none;color:#00695c}h1{font-size:1.2rem}'
          'li{list-style:none}ul{padding-left:0}</style></head><body>')
      ..write('<h1>整理整頓 $base</h1><ul>');

    if (base != '/') {
      final String parent = _parent(base);
      html.write('<li><a href="${_attr(parent)}">../（上へ）</a></li>');
    }

    for (final FileSystemEntity e in entries) {
      final String name = _basename(e.path);
      final bool isDir = e is Directory;
      final String href = '$base${Uri.encodeComponent(name)}${isDir ? '/' : ''}';
      final String label = isDir ? '📁 $name/' : '📄 $name';
      html.write('<li><a href="${_attr(href)}">${_esc(label)}</a></li>');
    }
    html.write('</ul></body></html>');

    req.response.headers.contentType = ContentType.html;
    req.response.write(html.toString());
    await req.response.close();
  }

  Future<void> _serveFile(HttpRequest req, String fsPath) async {
    final File file = File(fsPath);
    final int length = await file.length();
    final String name = _basename(fsPath);

    req.response.headers.contentType = ContentType.binary;
    req.response.headers.set(HttpHeaders.contentLengthHeader, length);
    // 非 ASCII のファイル名でもダウンロードできるよう filename* を使う。
    req.response.headers.set(
      'Content-Disposition',
      "attachment; filename*=UTF-8''${Uri.encodeComponent(name)}",
    );
    await file.openRead().pipe(req.response);
  }

  String _parent(String base) {
    // '/画像/' -> '/'、'/a/b/' -> '/a/'
    final String trimmed = base.substring(0, base.length - 1);
    final int slash = trimmed.lastIndexOf('/');
    return slash <= 0 ? '/' : trimmed.substring(0, slash + 1);
  }

  String _basename(String path) {
    final String p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final int slash = p.lastIndexOf('/');
    return slash < 0 ? p : p.substring(slash + 1);
  }

  String _esc(String s) => const HtmlEscape().convert(s);
  String _attr(String s) => const HtmlEscape(HtmlEscapeMode.attribute).convert(s);
}
