import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras));
}

enum ScanMode { code, ocr }

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp(this.cameras, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ScannerPage(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScannerPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const ScannerPage({super.key, required this.cameras});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {

  final MobileScannerController scannerController =
      MobileScannerController(autoStart: false);

  CameraController? cameraController;

  final TextRecognizer textRecognizer = TextRecognizer();

  ScanMode mode = ScanMode.code;

  bool torch = false;

  String detected = "";
  String preview = "";

  List<String> csv = [];
  Map<String, String> history = {};

  File? sessionFile;

  Position? lastPosition;

  bool previewVisible = false;

  @override
  void initState() {
    super.initState();
    initCamera();
    initGps();
    initSession();
  }

  Future<void> initCamera() async {

    cameraController =
        CameraController(widget.cameras.first, ResolutionPreset.medium);

    await cameraController!.initialize();

    scannerController.start();

    setState(() {});
  }

  Future<void> initGps() async {

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    Geolocator.getPositionStream().listen((pos) {
      lastPosition = pos;
    });
  }

  Future<void> initSession() async {

    final dir = await getApplicationDocumentsDirectory();

    sessionFile = File("${dir.path}/working_session.csv");

    if (await sessionFile!.exists()) {

      csv = await sessionFile!.readAsLines();

      for (var l in csv.skip(1)) {
        final parts = l.split(",");
        history[parts.last.replaceAll('"', '')] = parts[0];
      }

    } else {

      csv = ['"timestamp","lon","lat","alt","acc","text"'];
      await sessionFile!.writeAsString(csv.join("\n"));
    }

    setState(() {});
  }

  Future<void> appendCsv(String text) async {

    final ts = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());

    final lon = lastPosition?.longitude ?? 0;
    final lat = lastPosition?.latitude ?? 0;
    final alt = lastPosition?.altitude ?? 0;
    final acc = lastPosition?.accuracy ?? 0;

    final line = '"$ts","$lon","$lat","$alt","$acc","$text"';

    csv.add(line);
    history[text] = ts;

    await sessionFile!.writeAsString(csv.join("\n"));
  }

  void onCapture() async {

    if (mode == ScanMode.code) {
      scannerController.start();
    } else {
      runOcr();
    }
  }

  void onBarcode(BarcodeCapture capture) {

    if (previewVisible) return;

    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    scannerController.stop();

    if (raw == detected) return;

    detected = raw;

    String warning = "";

    if (history.containsKey(raw)) {
      warning =
          '"$raw"\nhas already been added on\n${history[raw]}';
    }

    HapticFeedback.mediumImpact();

    setState(() {
      preview = warning.isEmpty ? raw : warning;
      previewVisible = true;
    });
  }

  Future<void> runOcr() async {

    final file = await cameraController!.takePicture();

    final input = InputImage.fromFilePath(file.path);

    final result = await textRecognizer.processImage(input);

    final text = result.text.replaceAll("\n", " ");

    if (text.isEmpty) return;

    detected = text;

    String warning = "";

    if (history.containsKey(text)) {
      warning =
          '"$text"\nhas already been added on\n${history[text]}';
    }

    HapticFeedback.mediumImpact();

    setState(() {
      preview = warning.isEmpty ? text : warning;
      previewVisible = true;
    });
  }

  void saveResult() async {

    await appendCsv(detected);

    setState(() {
      previewVisible = false;
      detected = "";
      preview = "";
    });
  }

  void resumeScan() {

    setState(() {
      previewVisible = false;
      preview = "";
      detected = "";
    });
  }

  Future<void> toggleTorch() async {

    torch = !torch;

    if (mode == ScanMode.code) {

      await scannerController.toggleTorch();

    } else {

      if (torch) {
        await cameraController?.setFlashMode(FlashMode.torch);
      } else {
        await cameraController?.setFlashMode(FlashMode.off);
      }

    }

    setState(() {});
  }

  void openCsvPreview() {

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CsvScreen(
          csv: csv,
          onShare: shareCsv,
          onDelete: deleteCsv,
        ),
      ),
    );
  }

  Future<void> shareCsv() async {

    final dir = await getApplicationDocumentsDirectory();

    final name =
        "scan.${DateFormat("yyyy-MM-dd_HH-mm-ss").format(DateTime.now())}.csv";

    final file = File("${dir.path}/$name");

    await file.writeAsString(csv.join("\n"));

    await Share.shareXFiles([XFile(file.path)]);
  }

  void deleteCsv() async {

    csv = ['"timestamp","lon","lat","alt","acc","text"'];
    history.clear();

    await sessionFile!.writeAsString(csv.join("\n"));
  }

  @override
  Widget build(BuildContext context) {

    if (cameraController == null ||
        !cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Column(
        children: [

          const SizedBox(height: 40),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              modeButton("QR/BAR", ScanMode.code),

              const SizedBox(width: 10),

              modeButton("OCR", ScanMode.ocr),

              const SizedBox(width: 20),

              IconButton(
                icon: Icon(
                  torch ? Icons.flashlight_on : Icons.flashlight_off,
                ),
                onPressed: toggleTorch,
              ),
            ],
          ),

          Expanded(
            child: Stack(
              children: [

                mode == ScanMode.code
                    ? MobileScanner(
                        controller: scannerController,
                        onDetect: onBarcode,
                      )
                    : CameraPreview(cameraController!),

                const ScanFrame(),
              ],
            ),
          ),

          Container(
            color: const Color(0xFFFFF8F0),
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            child: Text(preview),
          ),

          if (previewVisible)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                ElevatedButton(
                  onPressed: saveResult,
                  child: const Text("Save"),
                ),

                const SizedBox(width: 20),

                ElevatedButton(
                  onPressed: resumeScan,
                  child: const Text("Resume"),
                ),
              ],
            ),

          const SizedBox(height: 10),

          ElevatedButton(
            onPressed: onCapture,
            child: const Text("CAPTURE"),
          ),

          const SizedBox(height: 10),

          Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [

                Text(lastPosition == null
                    ? "GPS..."
                    : "GPS ±${lastPosition!.accuracy.toStringAsFixed(1)} m"),

                Text("Records ${csv.length - 1}"),

                TextButton(
                  onPressed: openCsvPreview,
                  child: const Text("CSV"),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget modeButton(String label, ScanMode m) {

    final selected = mode == m;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.green : Colors.grey,
      ),
      onPressed: () => setState(() => mode = m),
      child: Text(label),
    );
  }
}

class CsvScreen extends StatelessWidget {

  final List<String> csv;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const CsvScreen({
    super.key,
    required this.csv,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("CSV Preview")),
      body: Column(
        children: [

          Expanded(
            child: ListView(
              children: csv.map((e) => Text(e)).toList(),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: onShare,
                child: const Text("Share"),
              ),

              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Resume scanning"),
              ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: onDelete,
                child: const Text("Delete"),
              ),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class ScanFrame extends StatelessWidget {
  const ScanFrame({super.key});

  @override
  Widget build(BuildContext context) {

    return IgnorePointer(
      child: CustomPaint(
        painter: FramePainter(),
        size: Size.infinite,
      ),
    );
  }
}

class FramePainter extends CustomPainter {

  @override
  void paint(Canvas canvas, Size size) {

    final frameWidth = size.width * 0.7;
    final frameHeight = size.height * 0.35;

    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2;

    final rect = Rect.fromLTWH(left, top, frameWidth, frameHeight);

    final paint = Paint()..color = Colors.black.withOpacity(0.6);

    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, top), paint);
    canvas.drawRect(Rect.fromLTRB(0, top, left, top + frameHeight), paint);
    canvas.drawRect(Rect.fromLTRB(left + frameWidth, top, size.width, top + frameHeight), paint);
    canvas.drawRect(Rect.fromLTRB(0, top + frameHeight, size.width, size.height), paint);

    final border = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
