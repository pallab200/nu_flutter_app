import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;

/// Simple PDF viewer with download + caching support.
class PdfViewerPage extends StatefulWidget {
  final String url;
  final String? title;
  final bool academicCalendarFix;
  final String? referer;

  const PdfViewerPage({
    super.key,
    required this.url,
    this.title,
    this.academicCalendarFix = false,
    this.referer,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  String? _localPath;
  bool _downloading = false;
  double _progress = 0.0;
  bool _loadError = false;
  String _errorMsg = '';
  int _pages = 0;
  int _currentPage = 0;
  PDFViewController? _pdfController;

  // Use a realistic browser User-Agent for servers that check UA/Referer.
  static const String _browserUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36';

  Map<String, String> _buildHeaders({required bool forPdf}) {
    final headers = <String, String>{
      HttpHeaders.userAgentHeader: _browserUA,
      HttpHeaders.acceptLanguageHeader: 'en-US,en;q=0.9',
      HttpHeaders.acceptEncodingHeader: 'identity',
    };
    headers[HttpHeaders.acceptHeader] = forPdf
        ? 'application/pdf,application/octet-stream,*/*;q=0.8'
        : 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
    if (widget.referer != null && widget.referer!.isNotEmpty) {
      headers[HttpHeaders.refererHeader] = widget.referer!;
    }
    return headers;
  }

  bool _looksLikePdf(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  @override
  void initState() {
    super.initState();
    _preparePdf();
  }

  Future<void> _preparePdf() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filename = 'pdf_${widget.url.hashCode}.pdf';
      final file = File('${dir.path}/$filename');
      if (await file.exists()) {
        setState(() {
          _localPath = file.path;
        });
        return;
      }

      setState(() {
        _downloading = true;
        _progress = 0.0;
        _loadError = false;
      });

      final dio = Dio();
      final savePath = file.path;

      // Configure Dio to allow a host-limited insecure TLS fallback for nu.ac.bd
      try {
        final adapter = dio.httpClientAdapter;
        if (adapter is IOHttpClientAdapter) {
          adapter.createHttpClient = () {
            final client = HttpClient();
            client.badCertificateCallback = (cert, host, port) =>
                host == 'nu.ac.bd' || host == 'www.nu.ac.bd';
            return client;
          };
        }
      } catch (_) {}

      // If this page is known to have strange URL encodings (Academic Calendar), try multiple encoded variants.
      final tried = <String>{};
      final candidates = <String>[];
      candidates.add(widget.url);
      if (widget.academicCalendarFix) {
        final u = widget.url;
        final parenEncoded = u.replaceAll('(', '%28').replaceAll(')', '%29');
        final spaceEncoded = u.replaceAll(' ', '%20');
        final encodedFull = Uri.encodeFull(u);
        for (final s in [parenEncoded, spaceEncoded, encodedFull]) {
          if (s.isNotEmpty && !candidates.contains(s)) candidates.add(s);
        }
        // also try http fallback
        try {
          final uri = Uri.parse(u);
          if (uri.scheme == 'https') {
            final httpScheme = uri.replace(scheme: 'http').toString();
            if (!candidates.contains(httpScheme)) candidates.add(httpScheme);
          }
        } catch (_) {}
        // also try host variants (with/without www)
        try {
          final initial = List<String>.from(candidates);
          for (final s in initial) {
            try {
              final uri = Uri.parse(s);
              if (uri.host == 'www.nu.ac.bd') {
                final alt = uri.replace(host: 'nu.ac.bd').toString();
                if (!candidates.contains(alt)) candidates.add(alt);
              } else if (uri.host == 'nu.ac.bd') {
                final alt = uri.replace(host: 'www.nu.ac.bd').toString();
                if (!candidates.contains(alt)) candidates.add(alt);
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      Exception? lastErr;
      for (final cUrl in candidates) {
        if (!tried.add(cUrl)) continue;
        try {
          final extraHeaders = _buildHeaders(forPdf: true);

          // Quick HEAD check to observe server behavior (status + headers).
          try {
            final headResp = await dio
                .head(cUrl,
                    options: Options(
                        headers: extraHeaders, validateStatus: (s) => true))
                .timeout(const Duration(seconds: 15));
            debugPrint('[PdfViewer] HEAD $cUrl => ${headResp.statusCode}');
            if (headResp.statusCode == 200) {
              final ct = headResp.headers.value('content-type') ?? '';
              debugPrint('[PdfViewer] HEAD content-type: $ct');
              if (ct.toLowerCase().contains('pdf')) {
                // server indicates PDF is available; perform GET to verify magic bytes
                try {
                  final resp = await dio
                      .get<List<int>>(cUrl,
                          options: Options(
                              responseType: ResponseType.bytes,
                              headers: extraHeaders,
                              validateStatus: (s) => true))
                      .timeout(const Duration(seconds: 30));
                  final bytes = resp.data is List<int>
                      ? (resp.data as List<int>)
                      : <int>[];
                  debugPrint(
                      '[PdfViewer] GET after HEAD => ${resp.statusCode}, bytes=${bytes.length}');
                  if (resp.statusCode == 200 && _looksLikePdf(bytes)) {
                    await File(savePath).writeAsBytes(bytes);
                    setState(() {
                      _localPath = savePath;
                      _downloading = false;
                    });
                    return;
                  } else {
                    debugPrint(
                        '[PdfViewer] HEAD indicated PDF but content invalid for $cUrl');
                  }
                } catch (ge) {
                  debugPrint('[PdfViewer] GET after HEAD failed: $ge');
                }
              }
            }
          } catch (he) {
            debugPrint('[PdfViewer] HEAD failed for $cUrl: $he');
            // continue to try download below
          }

          // If HEAD did not confirm availability, attempt a direct GET and verify bytes.
          try {
            final resp = await dio
                .get<List<int>>(cUrl,
                    options: Options(
                        responseType: ResponseType.bytes,
                        headers: extraHeaders,
                        validateStatus: (s) => true))
                .timeout(const Duration(seconds: 30));
            final bytes =
                resp.data is List<int> ? (resp.data as List<int>) : <int>[];
            debugPrint(
                '[PdfViewer] GET $cUrl => ${resp.statusCode}, bytes=${bytes.length}');
            if (resp.statusCode == 200 && _looksLikePdf(bytes)) {
              await File(savePath).writeAsBytes(bytes);
              setState(() {
                _localPath = savePath;
                _downloading = false;
              });
              return;
            } else {
              lastErr =
                  Exception('HTTP ${resp.statusCode} (non-pdf or invalid)');
            }
          } catch (e) {
            // let outer catch handle
            lastErr = e is Exception ? e : Exception(e.toString());
          }
        } catch (e) {
          lastErr = e is Exception ? e : Exception(e.toString());
          final msg = e.toString().toLowerCase();
          if (msg.contains('handshake') ||
              msg.contains('certificate_verify_failed') ||
              msg.contains('handshakeexception')) {
            // try manual HttpClient fallback limited to nu.ac.bd
            try {
              final uri = Uri.parse(cUrl);
              final httpClient = HttpClient();
              httpClient.badCertificateCallback = (cert, host, port) =>
                  host == 'nu.ac.bd' || host == 'www.nu.ac.bd';
              final req = await httpClient.getUrl(uri);
              // set headers similar to Dio attempt
              final h = _buildHeaders(forPdf: true);
              for (final e in h.entries) {
                try {
                  req.headers.set(e.key, e.value);
                } catch (_) {}
              }
              final resp = await req.close();
              debugPrint('[PdfViewer][HttpClient] GET $uri => ${resp.statusCode}');
              try {
                debugPrint('[PdfViewer][HttpClient] headers: ${resp.headers}');
              } catch (_) {}
              if (resp.statusCode == 200) {
                final bytes = await resp.fold<List<int>>(<int>[],
                    (List<int> prev, List<int> element) {
                  prev.addAll(element);
                  return prev;
                });
                debugPrint('[PdfViewer][HttpClient] bytes=${bytes.length}');
                if (_looksLikePdf(bytes)) {
                  await file.writeAsBytes(bytes);
                  setState(() {
                    _localPath = file.path;
                    _downloading = false;
                  });
                  return;
                } else {
                  String snippet = '';
                  try {
                    snippet = utf8.decode(bytes.take(256).toList(),
                        allowMalformed: true);
                  } catch (_) {}
                  debugPrint(
                      '[PdfViewer][HttpClient] non-pdf response (${resp.statusCode}), snippet: $snippet');
                  lastErr = Exception('HTTP ${resp.statusCode} (non-pdf)');
                }
              } else {
                lastErr = Exception('HTTP ${resp.statusCode}');
              }
            } catch (e2) {
              lastErr = e2 is Exception ? e2 : Exception(e2.toString());
            }
          }
          // Additional manual HttpClient attempt for Academic Calendar PDFs (handles servers that require specific headers)
          if (widget.academicCalendarFix) {
            try {
              final parsed = Uri.parse(cUrl);
              final host = parsed.host.toLowerCase();
              if (host == 'nu.ac.bd' || host == 'www.nu.ac.bd') {
                try {
                  final httpClient2 = HttpClient();
                  httpClient2.badCertificateCallback =
                      (cert, h, port) => h == host;
                  final req2 = await httpClient2.getUrl(parsed);
                  final h2 = _buildHeaders(forPdf: true);
                  for (final e in h2.entries) {
                    try {
                      req2.headers.set(e.key, e.value);
                    } catch (_) {}
                  }
                  final resp2 = await req2.close();
                  debugPrint(
                      '[PdfViewer][HttpClient2] GET $parsed => ${resp2.statusCode}');
                  try {
                    debugPrint('[PdfViewer][HttpClient2] headers: ${resp2.headers}');
                  } catch (_) {}
                  if (resp2.statusCode == 200) {
                    final bytes2 = await resp2.fold<List<int>>(<int>[],
                        (List<int> prev, List<int> element) {
                      prev.addAll(element);
                      return prev;
                    });
                    debugPrint('[PdfViewer][HttpClient2] bytes=${bytes2.length}');
                    if (_looksLikePdf(bytes2)) {
                      await file.writeAsBytes(bytes2);
                      setState(() {
                        _localPath = file.path;
                        _downloading = false;
                      });
                      return;
                    } else {
                      String snippet = '';
                      try {
                        snippet = utf8.decode(bytes2.take(256).toList(),
                            allowMalformed: true);
                      } catch (_) {}
                      debugPrint(
                          '[PdfViewer][HttpClient2] non-pdf response (${resp2.statusCode}), snippet: $snippet');
                      lastErr = Exception('HTTP ${resp2.statusCode} (non-pdf)');
                    }
                  } else {
                    lastErr = Exception('HTTP ${resp2.statusCode}');
                  }
                } catch (e3) {
                  lastErr = e3 is Exception ? e3 : Exception(e3.toString());
                }
              }
            } catch (_) {}
          }
          // Academic calendar pages sometimes link to an intermediate PHP page.
          // If download failed and this is the Academic Calendar, try to parse the page
          // and locate an actual PDF link inside it.
          if (widget.academicCalendarFix) {
            try {
              final pdfLink = await _findPdfLinkFromPage(cUrl);
              if (pdfLink != null) {
                // attempt download of discovered pdfLink
                try {
                  final extraHeaders = _buildHeaders(forPdf: true);
                  final resp = await Dio()
                      .get<List<int>>(pdfLink,
                          options: Options(
                              responseType: ResponseType.bytes,
                              headers: extraHeaders,
                              validateStatus: (s) => true))
                      .timeout(const Duration(seconds: 30));
                  final bytes = resp.data is List<int>
                      ? (resp.data as List<int>)
                      : <int>[];
                  debugPrint(
                      '[PdfViewer] discovered GET $pdfLink => ${resp.statusCode}, bytes=${bytes.length}');
                  if (resp.statusCode == 200 && _looksLikePdf(bytes)) {
                    await File(savePath).writeAsBytes(bytes);
                    setState(() {
                      _localPath = savePath;
                      _downloading = false;
                    });
                    return;
                  } else {
                    lastErr = Exception('HTTP ${resp.statusCode} (non-pdf)');
                  }
                } catch (e3) {
                  lastErr = e3 is Exception ? e3 : Exception(e3.toString());
                }
              }
            } catch (_) {}
          }
          // otherwise continue to next candidate
        }
      }

      if (lastErr != null) {
        if (widget.academicCalendarFix) {
          // Open in embedded web viewer as an automatic fallback for Academic Calendar PDFs
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openInWebViewer();
          });
          return;
        }
        throw lastErr;
      }
    } catch (e) {
      setState(() {
        _downloading = false;
        _loadError = true;
        _errorMsg = e.toString();
      });
    }
  }

  Future<String?> _findPdfLinkFromPage(String pageUrl) async {
    try {
      final dio = Dio();
      final headers = _buildHeaders(forPdf: false);

      final resp = await dio
          .get(pageUrl,
              options:
                  Options(responseType: ResponseType.plain, headers: headers))
          .timeout(const Duration(seconds: 20));
      final body = resp.data.toString();
      final doc = html_parser.parse(body);

      final candidates = <String>[];
      for (final a in doc.querySelectorAll('a')) {
        final href = a.attributes['href']?.trim() ?? '';
        if (href.toLowerCase().contains('.pdf')) candidates.add(href);
      }
      for (final e in doc.querySelectorAll('iframe,embed,object')) {
        final src = e.attributes['src'] ?? e.attributes['data'] ?? '';
        if (src.toLowerCase().contains('.pdf')) candidates.add(src);
      }

      // fallback: regex search in body
      final re = RegExp("https?://[^\\s\"']+\\.pdf", caseSensitive: false);
      final m = re.firstMatch(body);
      if (m != null) candidates.add(m.group(0)!);

      if (candidates.isEmpty) return null;

      final base = Uri.parse(pageUrl);
      for (final cand in candidates) {
        try {
          final resolved = base.resolve(cand).toString();
          final r = await dio
              .get<List<int>>(resolved,
                  options: Options(
                      responseType: ResponseType.bytes,
                      headers: headers,
                      validateStatus: (s) => true))
              .timeout(const Duration(seconds: 20));
          if (r.statusCode == 200) {
            // prefer responses with pdf content-type and check magic bytes
            final ct = r.headers.value('content-type') ?? '';
            final bytes = r.data is List<int> ? (r.data as List<int>) : <int>[];
            if (ct.toLowerCase().contains('pdf') ||
                _looksLikePdf(bytes) ||
                bytes.length > 100) {
              return resolved;
            }
          }
        } catch (_) {}
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Removed unused _deleteCache method as it was flagged in analysis.

  Future<void> _openExternally() async {
    if (_localPath != null) {
      await OpenFile.open(_localPath!);
    } else {
      final uri = Uri.tryParse(widget.url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // Removed unused _deleteConfirm method as it was flagged in analysis.

  Widget _buildBody() {
    if (_downloading) {
      final percent = (_progress * 100).toStringAsFixed(0);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('Downloading PDF... $percent%'),
          ],
        ),
      );
    }
    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text('Failed to load PDF'),
              const SizedBox(height: 8),
              Text(_errorMsg, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(
                    onPressed: _openExternally,
                    child: const Text('Open in external app')),
                if (widget.academicCalendarFix)
                  OutlinedButton(
                      onPressed: _openInWebViewer,
                      child: const Text('Open in in-app viewer')),
              ]),
            ],
          ),
        ),
      );
    }

    if (_localPath == null) {
      return const Center(child: Text('Preparing PDF...'));
    }

    return Stack(
      children: [
        PDFView(
          filePath: _localPath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          onRender: (pages) {
            setState(() {
              _pages = pages ?? 0;
            });
          },
          onViewCreated: (controller) {
            _pdfController = controller;
          },
          onPageChanged: (page, total) {
            setState(() {
              _currentPage = (page ?? 0) + 1;
            });
          },
          onError: (error) {
            setState(() {
              _loadError = true;
              _errorMsg = error.toString();
            });
          },
          onPageError: (page, error) {
            setState(() {
              _loadError = true;
              _errorMsg = error.toString();
            });
          },
        ),
        if (_pages > 0)
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    onPressed: () async {
                      final target = (_currentPage - 2).clamp(0, _pages - 1);
                      await _pdfController?.setPage(target);
                    },
                    icon: const Icon(Icons.chevron_left_rounded)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('$_currentPage / $_pages',
                      style: const TextStyle(color: Colors.white)),
                ),
                IconButton(
                    onPressed: () async {
                      final target = (_currentPage).clamp(0, _pages - 1);
                      await _pdfController?.setPage(target);
                    },
                    icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'PDF'),
        actions: [
          IconButton(
              onPressed: _downloadToDevice,
              icon: const Icon(Icons.download_rounded)),
        ],
      ),
      body: _buildBody(),
    );
  }

  Future<void> _downloadToDevice() async {
    try {
      // Ensure local copy exists
      if (_localPath == null) {
        // trigger download and wait
        await _preparePdf();
      }

      if (_localPath == null) throw Exception('No downloaded PDF available');

      final src = File(_localPath!);
      if (!await src.exists()) throw Exception('Downloaded file not found');

      // derive file name from URL or fallback to hash-based name
      String filename = 'document_${widget.url.hashCode}.pdf';
      try {
        final uri = Uri.parse(widget.url);
        final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
        if (seg.isNotEmpty) {
          filename = Uri.decodeComponent(seg.split('?').first);
        }
      } catch (_) {}

      String? targetDirPath;
      if (Platform.isAndroid) {
        // prefer primary public Downloads directory
        final publicDownloads = Directory('/storage/emulated/0/Download');
        if (await publicDownloads.exists()) {
          targetDirPath = publicDownloads.path;
        } else {
          // fallback to app-specific external storage
          final ext = await getExternalStorageDirectory();
          if (ext != null) {
            final d = Directory('${ext.path}/Download');
            if (!await d.exists()) await d.create(recursive: true);
            targetDirPath = d.path;
          }
        }
      } else {
        final docs = await getApplicationDocumentsDirectory();
        targetDirPath = docs.path;
      }

      if (targetDirPath == null) {
        throw Exception('No target directory available');
      }

      final dest = File('$targetDirPath/$filename');
      // if file exists, attempt to create unique name
      if (await dest.exists()) {
        final base = filename.replaceAll('.pdf', '');
        final unique = '${base}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        filename = unique;
      }

      final outPath = '$targetDirPath/$filename';
      await src.copy(outPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved PDF to $outPath'),
          duration: const Duration(seconds: 4)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save PDF: ${e.toString()}')));
    }
  }

  Future<void> _openInWebViewer() async {
    final viewer =
        'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(widget.url)}';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate())
      ..loadRequest(Uri.parse(viewer));

    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(widget.title ?? 'PDF')),
        body: WebViewWidget(controller: controller),
      ),
    ));
  }
}
