import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() {
  runApp(const GeoScannerApp());
}

enum ScanMode { qr, bar, ocr }

class GeoScannerApp extends StatelessWidget {
  const GeoScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ScannerPage());
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with SingleTickerProviderStateMixin {

  final MobileScannerController controller = MobileScannerController();
  final TextRecognizer textRecognizer = TextRecognizer();

  ScanMode mode = ScanMode.qr;

  String detectedText = "";
  String lastDetected = "";

  bool torchOn = false;

  Position? lastPosition;
  StreamSubscription? gpsStream;

  List<String> csvLines = [];
  File? workingFile;

  late AnimationController animation;

  @override
  void initState() {
    super.initState();

    animation = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    initGps();
    loadSession();
  }

  Future<void> initGps() async {

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    gpsStream =
        Geolocator.getPositionStream().listen((pos) {
      setState(() {
        lastPosition = pos;
      });
    });
  }

  Future<void> loadSession() async {

    final dir = await getApplicationDocumentsDirectory();

    workingFile =
        File("${dir.path}/working_session.csv");

    if (await workingFile!.exists()) {
      csvLines = await workingFile!.readAsLines();
    } else {
      csvLines.add(
          '"timestamp","lon","lat","alt","acc","text"');
      await workingFile!
          .writeAsString(csvLines.join("\n"));
    }

    setState(() {});
  }

  Future<void> appendCsv(String text) async {

    final ts = DateFormat("yyyy-MM-dd HH:mm:ss")
        .format(DateTime.now());

    final lon = lastPosition?.longitude ?? 0;
    final lat = lastPosition?.latitude ?? 0;
    final alt = lastPosition?.altitude ?? 0;
    final acc = lastPosition?.accuracy ?? 0;

    final line =
        '"$ts","$lon","$lat","$alt","$acc","$text"';

    csvLines.add(line);

    await workingFile!
        .writeAsString(csvLines.join("\n"));

    setState(() {});
  }

  Future<void> shareCsv() async {

    final dir = await getApplicationDocumentsDirectory();

    final ts =
        DateFormat("yyyy-MM-dd_HH-mm-ss")
            .format(DateTime.now());

    final file =
        File("${dir.path}/scan.$ts.csv");

    await file.writeAsString(csvLines.join("\n"));

    await Share.shareXFiles([XFile(file.path)]);
  }

  void discardCsv() async {

    csvLines = [
      '"timestamp","lon","lat","alt","acc","text"'
    ];

    await workingFile!
        .writeAsString(csvLines.join("\n"));

    setState(() {});
  }

  void feedback() {
    HapticFeedback.mediumImpact();
  }

  void capture() async {

    if (mode == ScanMode.ocr) {
      runOcr();
      return;
    }

    if (lastDetected.isEmpty) return;

    await appendCsv(lastDetected);

    feedback();

    setState(() {
      detectedText = "";
      lastDetected = "";
    });
  }

  void runOcr() async {

    final image = await controller.takePicture();

    if (image == null) return;

    final input =
        InputImage.fromFilePath(image.path);

    final result =
        await textRecognizer.processImage(input);

    final text =
        result.text.replaceAll("\n", " | ").trim();

    if (text.isEmpty) return;

    await appendCsv(text);

    feedback();

    setState(() {
      detectedText = text;
    });
  }

  bool insideFrame(Rect? box, Size size, double frameHeight) {

    if (box == null) return false;

    final frameWidth = size.width * 0.7;

    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2;

    final frame =
        Rect.fromLTWH(left, top, frameWidth, frameHeight);

    final center = box.center;

    return frame.contains(center);
  }

  void openCsvPreview() {

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CsvPreview(
                lines: csvLines,
                onShare: shareCsv,
                onDiscard: discardCsv)));
  }

  @override
  Widget build(BuildContext context) {

    final frameHeight =
        mode == ScanMode.bar ? 120.0 : 250.0;

    return Scaffold(
      body: Column(
        children: [

          const SizedBox(height: 40),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              modeBtn(ScanMode.qr, "QR"),
              const SizedBox(width: 8),
              modeBtn(ScanMode.bar, "BAR"),
              const SizedBox(width: 8),
              modeBtn(ScanMode.ocr, "OCR"),
              const SizedBox(width: 12),

              IconButton(
                icon: Icon(
                    torchOn
                        ? Icons.flashlight_on
                        : Icons.flashlight_off,
                    color: Colors.orange),
                onPressed: () {
                  controller.toggleTorch();
                  setState(() {
                    torchOn = !torchOn;
                  });
                },
              )
            ],
          ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {

                final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight);

                return Stack(
                  children: [

                    MobileScanner(
                      controller: controller,
                      onDetect: (capture) {

                        if (mode == ScanMode.ocr) return;

                        final barcode =
                            capture.barcodes.first;

                        if (!insideFrame(
                            barcode.boundingBox,
                            size,
                            frameHeight)) return;

                        if (mode == ScanMode.qr &&
                            barcode.format !=
                                BarcodeFormat.qrCode) return;

                        if (mode == ScanMode.bar &&
                            barcode.format ==
                                BarcodeFormat.qrCode) return;

                        final raw = barcode.rawValue;

                        if (raw == null) return;

                        if (raw == lastDetected) return;

                        setState(() {
                          lastDetected = raw;
                          detectedText = raw;
                        });
                      },
                    ),

                    AnimatedBuilder(
                      animation: animation,
                      builder: (_, __) {
                        return CustomPaint(
                          painter: ScanFramePainter(
                              frameHeight: frameHeight,
                              progress: animation.value),
                          size: Size.infinite,
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),

          Container(
            color: const Color(0xFFFFF8F0),
            padding: const EdgeInsets.all(10),
            width: double.infinity,
            child: Text(
              detectedText,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16),
            ),
          ),

          const SizedBox(height: 10),

          SizedBox(
            width: 220,
            height: 60,
            child: ElevatedButton(
              onPressed: capture,
              child: const Text(
                "CAPTURE",
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),

          const SizedBox(height: 10),

          Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                Text(lastPosition == null
                    ? "GPS..."
                    : "GPS ±${lastPosition!.accuracy.toStringAsFixed(1)} m"),
                Text("Records ${csvLines.length - 1}"),
                TextButton(
                    onPressed: openCsvPreview,
                    child: const Text("CSV Preview"))
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget modeBtn(ScanMode m, String label) {

    final selected = mode == m;

    return ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor:
                selected ? Colors.green : Colors.grey),
        onPressed: () {
          setState(() {
            mode = m;
          });
        },
        child: Text(label));
  }
}

class CsvPreview extends StatelessWidget {

  final List<String> lines;
  final VoidCallback onShare;
  final VoidCallback onDiscard;

  const CsvPreview(
      {super.key,
      required this.lines,
      required this.onShare,
      required this.onDiscard});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("CSV Preview")),
      body: Column(
        children: [

          Expanded(
              child: ListView(
                  children:
                      lines.map((e) => Text(e)).toList())),

          SizedBox(
            width: double.infinity,
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
              children: [

                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey),
                    onPressed: () =>
                        Navigator.pop(context),
                    child: const Text("Back to Scan")),

                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green),
                    onPressed: onShare,
                    child: const Text("Share CSV")),

                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red),
                    onPressed: () {
                      onDiscard();
                      Navigator.pop(context);
                    },
                    child: const Text("Discard")),
              ],
            ),
          ),

          const SizedBox(height: 20)
        ],
      ),
    );
  }
}

class ScanFramePainter extends CustomPainter {

  final double frameHeight;
  final double progress;

  ScanFramePainter(
      {required this.frameHeight,
      required this.progress});

  @override
  void paint(Canvas canvas, Size size) {

    final frameWidth = size.width * 0.7;

    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2;

    final rect =
        Rect.fromLTWH(left, top, frameWidth, frameHeight);

    final overlay = Paint()
      ..color = Colors.black.withOpacity(0.6);

    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        overlay);

    canvas.drawRect(
        rect,
        Paint()..blendMode = BlendMode.clear);

    final border = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRect(rect, border);

    final y = top + frameHeight * progress;

    canvas.drawLine(
        Offset(left, y),
        Offset(left + frameWidth, y),
        Paint()
          ..color = Colors.greenAccent
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
