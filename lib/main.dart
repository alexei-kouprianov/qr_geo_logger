import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const QRGeoLogger());
}

class QRGeoLogger extends StatelessWidget {
  const QRGeoLogger({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "QR Geo Logger",
      theme: ThemeData.dark(),
      home: const ScannerScreen(),
    );
  }
}

class ScanRecord {
  final DateTime time;
  final double? lat;
  final double? lon;
  final double? alt;
  final double? acc;
  final String text;

  ScanRecord(
      {required this.time,
      required this.lat,
      required this.lon,
      required this.alt,
      required this.acc,
      required this.text});

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

  Barcode? lastBarcode;
  String? lastText;

  bool qrMode = true;

  final List<ScanRecord> records = [];

  Future<Position?> getPosition() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best);
    } catch (_) {
      return null;
    }
  }

  void onBarcode(Barcode barcode) {
    final String? value = barcode.rawValue;
    if (value == null) return;

    if (value == lastText) return;

    setState(() {
      lastBarcode = barcode;
      lastText = value;
    });
  }

  Future<void> saveCurrent() async {

    if (lastText == null) return;

    final pos = await getPosition();

    final record = ScanRecord(
      time: DateTime.now(),
      lat: pos?.latitude,
      lon: pos?.longitude,
      alt: pos?.altitude,
      acc: pos?.accuracy,
      text: lastText!,
    );

    if (records.isNotEmpty && records.last.text == record.text) {
      return;
    }

    setState(() {
      records.add(record);
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Saved")));
  }

  String buildCSV() {
    return records.map((r) => r.toCSV()).join("\n");
  }

  Future<void> shareCSV() async {

    if (records.isEmpty) return;

    final dir = await getTemporaryDirectory();

    final now = DateFormat("yyyy-MM-dd_HH-mm-ss").format(DateTime.now());

    final file = File("${dir.path}/geotagged_qr.$now.csv");

    await file.writeAsString(buildCSV());

    await Share.shareXFiles([XFile(file.path)]);
  }

  void discardCSV() {
    setState(() {
      records.clear();
    });
  }

  @override
  Widget build(BuildContext context) {

    final frame = qrMode
        ? const AspectRatio(aspectRatio: 1)
        : const AspectRatio(aspectRatio: 2.5);

    return Scaffold(
      appBar: AppBar(
        title: const Text("QR Geo Logger"),
        actions: [
          IconButton(
              onPressed: () {
                setState(() {
                  qrMode = !qrMode;
                });
              },
              icon: Icon(qrMode ? Icons.qr_code : Icons.view_week)),
          IconButton(
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CSVScreen(
                              records: records,
                              onShare: shareCSV,
                              onDiscard: discardCSV,
                            )));
              },
              icon: const Icon(Icons.table_view))
        ],
      ),
      body: Stack(
        children: [

          MobileScanner(
            controller: controller,
            onDetect: (BarcodeCapture capture) {
              final List<Barcode> barcodes = capture.barcodes;

              if (barcodes.isEmpty) return;

              onBarcode(barcodes.first);
            },
          ),

          Center(
            child: Container(
              width: 250,
              height: qrMode ? 250 : 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
              ),
            ),
          ),

          if (lastText != null)
            Positioned(
              bottom: 120,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black87,
                child: Text(
                  lastText!,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

          Positioned(
            bottom: 30,
            left: 40,
            right: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.all(20)),
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
  final VoidCallback onShare;
  final VoidCallback onDiscard;

  const CSVScreen(
      {super.key,
      required this.records,
      required this.onShare,
      required this.onDiscard});

  @override
  Widget build(BuildContext context) {

    final csv = records.map((r) => r.toCSV()).join("\n");

    return Scaffold(
      appBar: AppBar(title: const Text("CSV Preview")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [

            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(csv),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [

                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green),
                    onPressed: onShare,
                    child: const Text("Send / Share"),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: onDiscard,
                    child: const Text("Discard"),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
