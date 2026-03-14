import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const QRGeoLogger());
}

enum ScanMode { qr, barcode }

class ScanRecord {
  String timestamp;
  double lon;
  double lat;
  double alt;
  double acc;
  String text;

  ScanRecord(
      this.timestamp,
      this.lon,
      this.lat,
      this.alt,
      this.acc,
      this.text
      );

  String csv() =>
      '"$timestamp","$lon","$lat","$alt","$acc","$text"';
}

class QRGeoLogger extends StatelessWidget {
  const QRGeoLogger({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {

  ScanMode mode = ScanMode.qr;

  String? lastDetectedCode;
  String? lastSavedCode;

  DateTime lastScanTime = DateTime.now();

  List<ScanRecord> records = [];

  Position? currentPos;

  final controller = MobileScannerController();

  @override
  void initState() {
    super.initState();
    updateLocation();
  }

  Future updateLocation() async {

    await Geolocator.requestPermission();

    currentPos = await Geolocator.getCurrentPosition();

    setState(() {});
  }

  String timestamp() {
    return DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
  }

  Future saveScan() async {

    if (lastDetectedCode == null) return;

    Position pos = await Geolocator.getCurrentPosition();

    ScanRecord rec = ScanRecord(
        timestamp(),
        pos.longitude,
        pos.latitude,
        pos.altitude,
        pos.accuracy,
        lastDetectedCode!
    );

    setState(() {

      records.add(rec);
      lastSavedCode = lastDetectedCode;
      lastDetectedCode = null;

    });
  }

  Future<File> buildCsv() async {

    final dir = await getTemporaryDirectory();

    final filename =
        "geotagged_qr.${DateFormat("yyyy-MM-dd_HH-mm-ss").format(DateTime.now())}.csv";

    final file = File("${dir.path}/$filename");

    final buffer = StringBuffer();

    buffer.writeln('"timestamp","longitude","latitude","altitude","accuracy","text"');

    for (var r in records) {
      buffer.writeln(r.csv());
    }

    return file.writeAsString(buffer.toString());
  }

  Future shareCsv() async {

    File file = await buildCsv();

    Share.shareXFiles([XFile(file.path)]);
  }

  void discard() {

    setState(() {

      records.clear();
      lastSavedCode = null;

    });

  }

  void onDetect(Barcode barcode) {

    final text = barcode.rawValue;

    if (text == null) return;

    final now = DateTime.now();

    if (text == lastDetectedCode &&
        now.difference(lastScanTime).inSeconds < 3) {
      return;
    }

    lastScanTime = now;

    setState(() {
      lastDetectedCode = text;
    });

  }

  void toggleMode() {

    setState(() {

      if (mode == ScanMode.qr) {
        mode = ScanMode.barcode;
      } else {
        mode = ScanMode.qr;
      }

    });

  }

  void openPreview() {

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => CsvPreviewPage(records: records)
        )
    );

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("QR Geo Logger"),
        actions: [
          IconButton(
              onPressed: openPreview,
              icon: const Icon(Icons.table_view)
          )
        ],
      ),

      body: Column(

        children: [

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              TextButton(
                  onPressed: () {
                    setState(() {
                      mode = ScanMode.qr;
                    });
                  },
                  child: const Text("QR")
              ),

              TextButton(
                  onPressed: () {
                    setState(() {
                      mode = ScanMode.barcode;
                    });
                  },
                  child: const Text("BARCODE")
              ),

            ],
          ),

          Expanded(

            child: Stack(

              children: [

                MobileScanner(

                  controller: MobileScannerController(

                    formats: mode == ScanMode.qr
                        ? [BarcodeFormat.qrCode]
                        : [
                      BarcodeFormat.code128,
                      BarcodeFormat.ean13,
                      BarcodeFormat.ean8
                    ],

                  ),

                  onDetect: (barcode, args) {
                    onDetect(barcode);
                  },

                ),

                Center(

                  child: Container(

                    width: mode == ScanMode.qr ? 250 : 320,
                    height: mode == ScanMode.qr ? 250 : 120,

                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 4),
                    ),

                  ),

                )

              ],

            ),

          ),

          if (lastDetectedCode != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                "Last read: $lastDetectedCode",
                style: const TextStyle(fontSize: 16),
              ),
            ),

          if (currentPos != null)
            Text(
              "GPS: ${currentPos!.latitude}, ${currentPos!.longitude} ±${currentPos!.accuracy}m",
              style: const TextStyle(fontSize: 14),
            ),

          const SizedBox(height: 10),

          ElevatedButton(

            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(
                    horizontal: 60,
                    vertical: 20
                )
            ),

            onPressed: saveScan,

            child: const Text(
              "SAVE",
              style: TextStyle(fontSize: 20),
            ),

          ),

          const SizedBox(height: 15),

        ],

      ),

    );

  }

}

class CsvPreviewPage extends StatelessWidget {

  final List<ScanRecord> records;

  const CsvPreviewPage({super.key, required this.records});

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("CSV Preview"),
      ),

      body: Column(

        children: [

          Expanded(

            child: ListView.builder(

              itemCount: records.length,

              itemBuilder: (c, i) {

                final r = records[i];

                return ListTile(

                  title: Text(r.text),

                  subtitle: Text(
                      "${r.timestamp}  ${r.lat},${r.lon}"
                  ),

                );

              },

            ),

          ),

          Row(

            mainAxisAlignment: MainAxisAlignment.spaceEvenly,

            children: [

              ElevatedButton(
                onPressed: () async {

                  final dir = await getTemporaryDirectory();

                  final filename =
                      "geotagged_qr.${DateFormat("yyyy-MM-dd_HH-mm-ss").format(DateTime.now())}.csv";

                  final file = File("${dir.path}/$filename");

                  final buffer = StringBuffer();

                  buffer.writeln('"timestamp","longitude","latitude","altitude","accuracy","text"');

                  for (var r in records) {
                    buffer.writeln(r.csv());
                  }

                  await file.writeAsString(buffer.toString());

                  Share.shareXFiles([XFile(file.path)]);
                },
                child: const Text("SHARE"),
              ),

              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("BACK"),
              ),

            ],

          ),

          const SizedBox(height: 20)

        ],

      ),

    );

  }

}
