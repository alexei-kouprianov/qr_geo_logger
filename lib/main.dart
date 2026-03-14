import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

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
  final ImagePicker picker = ImagePicker();

  ScanMode mode = ScanMode.qr;

  String detectedText = "";
  bool paused = false;
  bool torch = false;

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
    await Geolocator.requestPermission();

    gpsStream = Geolocator.getPositionStream()
        .listen((pos) {
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

    if (lastPosition == null) return;

    final ts = DateFormat("yyyy-MM-dd HH:mm:ss")
        .format(DateTime.now());

    final line =
        '"$ts","${lastPosition!.longitude}","${lastPosition!.latitude}","${lastPosition!.altitude}","${lastPosition!.accuracy}","$text"';

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

  Future<void> captureOcr() async {

    if (paused) return;

    final photo =
        await picker.pickImage(source: ImageSource.camera);

    if (photo == null) return;

    final input =
        InputImage.fromFilePath(photo.path);

    final result =
        await textRecognizer.processImage(input);

    final text =
        result.text.replaceAll("\n", " | ").trim();

    setState(() {
      detectedText = text;
      paused = true;
    });

    feedback();
  }

  void feedback() async {

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 80);
    }
  }

  void save() async {

    if (detectedText.isEmpty) return;

    await appendCsv(detectedText);

    setState(() {
      detectedText = "";
      paused = false;
    });

    controller.start();
  }

  void toggleTorch() {

    controller.toggleTorch();

    setState(() {
      torch = !torch;
    });
  }

  void openCsvPreview() {

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CsvPreview(
                lines: csvLines,
                onShare: shareCsv)));
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
            ],
          ),

          Expanded(
            child: GestureDetector(

              onTap: () {
                if (mode == ScanMode.ocr) {
                  captureOcr();
                }
              },

              child: Stack(
                children: [

                  MobileScanner(
                    controller: controller,
                    onDetect: (capture) {

                      if (paused) return;
                      if (mode == ScanMode.ocr) return;

                      final raw =
                          capture.barcodes.first.rawValue;

                      if (raw == null) return;

                      setState(() {
                        detectedText = raw;
                        paused = true;
                      });

                      controller.stop();
                      feedback();
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

                  Positioned(
                    top: 20,
                    right: 20,
                    child: IconButton(
                      icon: Icon(
                        torch
                            ? Icons.flash_on
                            : Icons.flash_off,
                        color: Colors.white,
                      ),
                      onPressed: toggleTorch,
                    ),
                  ),
                ],
              ),
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

          if (paused)
            ElevatedButton(
                onPressed: save,
                child: const Text("SAVE")),

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
                    : "±${lastPosition!.accuracy.toStringAsFixed(1)} m"),
                Text("Records ${csvLines.length - 1}"),
                TextButton(
                    onPressed: openCsvPreview,
                    child: const Text("CSV"))
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

  const CsvPreview(
      {super.key,
      required this.lines,
      required this.onShare});

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

          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceEvenly,
            children: [

              ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context),
                  child: const Text("Back")),

              ElevatedButton(
                  onPressed: onShare,
                  child: const Text("Share"))
            ],
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

    canvas.saveLayer(rect, Paint());

    canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.clear);

    canvas.restore();

    canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);

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
