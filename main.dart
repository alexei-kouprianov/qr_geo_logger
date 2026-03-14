import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() {
  runApp(const QRGeoLogger());
}

class QRGeoLogger extends StatelessWidget {
  const QRGeoLogger({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ScannerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum ScanMode { qr, bar, ocr }

class ScanRecord {
  final DateTime time;
  final double? lat;
  final double? lon;
  final double? alt;
  final double? acc;
  final String text;

  ScanRecord(this.time, this.lat, this.lon, this.alt, this.acc, this.text);

  String toCSV() {
    final t = DateFormat("yyyy-MM-dd HH:mm:ss").format(time);
    return '"$t","$lon","$lat","$alt","$acc","$text"';
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {

  final MobileScannerController controller = MobileScannerController();
  final TextRecognizer textRecognizer = TextRecognizer();

  ScanMode mode = ScanMode.qr;

  String? detectedText;
  bool cameraPaused = false;

  Position? currentPosition;
  StreamSubscription<Position>? gpsStream;

  final List<ScanRecord> records = [];

  @override
  void initState() {
    super.initState();
    startGPS();
  }

  void startGPS() async {

    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    gpsStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 3,
      ),
    ).listen((pos) {
      currentPosition = pos;
    });
  }

  String normalizeOCR(String text) {
    return text
        .replaceAll(RegExp(r'[\r\n]+'), '|')
        .replaceAll(RegExp(r'\s*\|\s*'), ' | ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void onBarcode(BarcodeCapture capture) {

    if (cameraPaused) return;

    if (capture.barcodes.isEmpty) return;

    final code = capture.barcodes.first.rawValue;

    if (code == null) return;

    setState(() {
      detectedText = code;
      cameraPaused = true;
    });

    controller.stop();
  }

  Future<void> runOCR(InputImage image) async {

    if (cameraPaused) return;

    final result = await textRecognizer.processImage(image);

    if (result.text.isEmpty) return;

    setState(() {
      detectedText = normalizeOCR(result.text);
      cameraPaused = true;
    });

    controller.stop();
  }

  Future<void> saveCurrent() async {

    if (detectedText == null) return;

    final existing = records.where((r) => r.text == detectedText).toList();

    if (existing.isNotEmpty) {

      final prev = DateFormat("yyyy-MM-dd HH:mm:ss")
          .format(existing.first.time);

      final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text("Duplicate"),
                content: Text(
                    "This code was already scanned on\n$prev\n\nSave again?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Cancel")),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Save"))
                ],
              ));

      if (confirm != true) {
        resumeCamera();
        return;
      }
    }

    records.add(ScanRecord(
        DateTime.now(),
        currentPosition?.latitude,
        currentPosition?.longitude,
        currentPosition?.altitude,
        currentPosition?.accuracy,
        detectedText!));

    resumeCamera();
  }

  void resumeCamera() {
    setState(() {
      detectedText = null;
      cameraPaused = false;
    });

    controller.start();
  }

  String buildCSV() {
    return records.map((r) => r.toCSV()).join("\n");
  }

  Future<void> shareCSV() async {

    if (records.isEmpty) return;

    final dir = await getTemporaryDirectory();

    final name =
        "geotagged_qr.${DateFormat("yyyy-MM-dd_HH-mm-ss").format(DateTime.now())}.csv";

    final file = File("${dir.path}/$name");

    final content = '\uFEFF${buildCSV()}';

    await file.writeAsString(content);

    await Share.shareXFiles([XFile(file.path)]);
  }

  void discardCSV() {
    setState(() {
      records.clear();
    });
  }

  Widget frameWidget() {

    double h;

    switch (mode) {
      case ScanMode.qr:
        h = 250;
        break;
      case ScanMode.bar:
        h = 120;
        break;
      case ScanMode.ocr:
        h = 180;
        break;
    }

    return Container(
      width: 260,
      height: h,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green, width: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("QR Geo Logger"),
        actions: [

          IconButton(
              icon: const Icon(Icons.qr_code),
              onPressed: () => setState(() => mode = ScanMode.qr)),

          IconButton(
              icon: const Icon(Icons.view_week),
              onPressed: () => setState(() => mode = ScanMode.bar)),

          IconButton(
              icon: const Icon(Icons.text_fields),
              onPressed: () => setState(() => mode = ScanMode.ocr)),

          IconButton(
              icon: const Icon(Icons.table_view),
              onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CSVScreen(
                              records: records,
                              shareCSV: shareCSV,
                              discardCSV: discardCSV,
                            )),
                  )),
        ],
      ),
      body: Stack(
        children: [

          MobileScanner(
            controller: controller,
            onDetect: mode == ScanMode.ocr ? null : onBarcode,
          ),

          Center(child: frameWidget()),

          if (detectedText != null)
            Positioned(
              bottom: 140,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black87,
                child: Text(
                  detectedText!,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

          if (detectedText != null)
            Positioned(
              bottom: 60,
              left: 40,
              right: 40,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.all(18)),
                onPressed: saveCurrent,
                child: const Text("SAVE", style: TextStyle(fontSize: 24)),
              ),
            )
        ],
      ),
    );
  }
}

class CSVScreen extends StatelessWidget {

  final List<ScanRecord> records;
  final VoidCallback shareCSV;
  final VoidCallback discardCSV;

  const CSVScreen(
      {super.key,
      required this.records,
      required this.shareCSV,
      required this.discardCSV});

  @override
  Widget build(BuildContext context) {

    final csv = records.map((r) => r.toCSV()).join("\n");

    return Scaffold(
      appBar: AppBar(title: const Text("CSV Preview")),
      body: Column(
        children: [

          Expanded(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(csv),
          )),

          Row(
            children: [

              Expanded(
                child: ElevatedButton(
                    onPressed: shareCSV,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green),
                    child: const Text("Share")),
              ),

              Expanded(
                child: ElevatedButton(
                    onPressed: discardCSV,
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text("Discard")),
              )
            ],
          )
        ],
      ),
    );
  }
}
