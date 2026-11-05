import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/qr_lookup_result.dart';

class ExcelService {
  static final ExcelService instance = ExcelService();

  // Kullanıcının seçtiği Excel'den barkod ve miktarları okur, dosya seçilmezse null döner
  Future<Map<String, int>?> pickStockFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: false,
      );

      if (result == null || result.files.single.path == null) return null;

      final file = File(result.files.single.path!);
      final bytes = file.readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      final Map<String, int> inventory = {};

      for (var table in excel.tables.keys) {
        var rows = excel.tables[table]!.rows;
        if (rows.isEmpty) continue;

        int barkodIndex = -1;
        int miktarIndex = -1;

        var headerRow = rows.first;
        for (int i = 0; i < headerRow.length; i++) {
          String val = headerRow[i]?.value?.toString().toLowerCase().trim() ?? "";
          if (val.contains("barkod") || val.contains("gtin")) barkodIndex = i;
          if (val.contains("miktar") || val.contains("adet")) miktarIndex = i;
        }

        if (barkodIndex == -1 || miktarIndex == -1) {
          throw "Excel'de 'Barkod' ve 'Miktar' sütunları bulunamadı!";
        }

        for (int i = 1; i < rows.length; i++) {
          var row = rows[i];

          if (row.length <= barkodIndex || row.length <= miktarIndex) continue;

          var barkod = (row[barkodIndex]?.value?.toString() ?? "").trim();
          int miktar = int.tryParse(row[miktarIndex]?.value?.toString() ?? "0") ?? 0;

          if (barkod.isNotEmpty && miktar > 0) {
            inventory[barkod] = miktar;
          }
        }
      }

      return inventory;
    } catch (e) {
      debugPrint("Excel okuma hatası detayı: $e");
      rethrow;
    }
  }

  // Stok sayım sonuçlarını Excel raporu yapıp paylaşır
  Future<void> shareComparisonReport(Map<String, dynamic> results) async {
    try {
      final stats = results['stats'];
      final List missing = results['missing'] ?? [];
      final List extra = results['extra'] ?? [];
      final List matched = results['matched'] ?? [];

      var excel = Excel.createExcel();
      String sheetName = "Stok Analiz Raporu";
      excel.rename("Sheet1", sheetName);
      Sheet sheetObject = excel[sheetName];

      CellStyle headerStyle = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Calibri),
        backgroundColorHex: ExcelColor.fromHexString("#0F4C75"),
        fontColorHex: ExcelColor.fromHexString("#FFFFFF"),
        horizontalAlign: HorizontalAlign.Center,
      );

      CellStyle subHeaderStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString("#F1F5F9"),
        horizontalAlign: HorizontalAlign.Center,
      );

      sheetObject.merge(CellIndex.indexByString("A1"), CellIndex.indexByString("F1"));
      var cellA1 = sheetObject.cell(CellIndex.indexByString("A1"));
      cellA1.value = TextCellValue("ECZANE STOK SAYIM ANALİZ RAPORU");
      cellA1.cellStyle = headerStyle;

      sheetObject.cell(CellIndex.indexByString("A2")).value = TextCellValue("Tarih:");
      sheetObject.cell(CellIndex.indexByString("B2")).value = TextCellValue(DateTime.now().toString().substring(0, 16));

      sheetObject.cell(CellIndex.indexByString("A3")).value = TextCellValue("Beklenen Toplam:");
      sheetObject.cell(CellIndex.indexByString("B3")).value = IntCellValue(stats['expected'] ?? 0);
      sheetObject.cell(CellIndex.indexByString("C3")).value = TextCellValue("Okunan:");
      sheetObject.cell(CellIndex.indexByString("D3")).value = IntCellValue(stats['scanned'] ?? 0);
      sheetObject.cell(CellIndex.indexByString("E3")).value = TextCellValue("Doğruluk:");
      sheetObject.cell(CellIndex.indexByString("F3")).value = TextCellValue("%${stats['accuracy']}");

      List<String> headers = ["DURUM", "ÜRÜN ADI", "BARKOD", "BEKLENEN", "OKUNAN", "FARK"];
      for (var i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = subHeaderStyle;
      }

      int currentRow = 6;

      void addRows(List items, String status) {
        for (var item in items) {
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow)).value = TextCellValue(status);
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow)).value = TextCellValue(item['name']?.toString() ?? "Bilinmeyen Ürün");
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow)).value = TextCellValue(item['barcode']?.toString() ?? "-");
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow)).value = IntCellValue(item['expected'] ?? 0);
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow)).value = IntCellValue(item['scanned'] ?? 0);

          int diff = (item['scanned'] ?? 0) - (item['expected'] ?? 0);
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).value = IntCellValue(diff);

          currentRow++;
        }
      }

      addRows(missing, "EKSIK");
      addRows(extra, "FAZLA/TANIMSIZ");
      addRows(matched, "TAMAM");

      final directory = await getTemporaryDirectory();
      final String filePath = "${directory.path}/stok_analiz_raporu.xlsx";
      final fileBytes = excel.save();

      if (fileBytes != null) {
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);

        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Stok Sayım Analiz Raporu',
        );
      }
    } catch (e) {
      debugPrint("Excel Export Hatası: $e");
      rethrow;
    }
  }

  // Verilen kayıtları her karekod ayrı satır olacak şekilde Excel yapıp paylaşır
  Future<void> shareInventoryList(List<QrLookupResultWithCount> items, {String type = 'all'}) async {
    try {
      final now = DateTime.now();

      var excel = Excel.createExcel();
      String sheetName = "Envanter Listesi";

      var defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, sheetName);
      }
      Sheet sheet = excel[sheetName];

      CellStyle headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString("#CCCCCC"),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        fontColorHex: ExcelColor.fromHexString("#000000"),
      );

      List<String> headers = ["BARKOD", "İLAÇ ADI", "S.K.T", "PARTİ NO", "KAREKOD"];
      for (int i = 0; i < headers.length; i++) {
        var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final qrData = item.qr.data;
        final rowIndex = i + 1;

        bool isExpired = qrData?.isExpired ?? false;
        bool isNearExpiry = false;
        if (!isExpired && qrData?.expiryDate != null) {
          if (qrData!.expiryDate!.difference(now).inDays <= 90) isNearExpiry = true;
        }

        String formattedDate = qrData?.expiryDate != null
            ? "${qrData!.expiryDate!.day.toString().padLeft(2, '0')}.${qrData.expiryDate!.month.toString().padLeft(2, '0')}.${qrData.expiryDate!.year}"
            : "-";

        CellStyle rowStyle = CellStyle(
          backgroundColorHex: isExpired
              ? ExcelColor.fromHexString("#FFCDD2")
              : isNearExpiry
                  ? ExcelColor.fromHexString("#FFEB3B")
                  : ExcelColor.fromHexString("#FFFFFF"),
        );

        List<String> rowData = [
          qrData?.gtin ?? "-",
          qrData?.productName ?? "-",
          formattedDate,
          qrData?.batchNo ?? "-",
          item.qr.value.replaceAll('\x1D', ' '),
        ];

        for (int j = 0; j < rowData.length; j++) {
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIndex));
          cell.value = TextCellValue(rowData[j]);
          cell.cellStyle = rowStyle;
        }
      }

      final directory = await getTemporaryDirectory();
      String baseFileName = "envanter_listesi";
      if (type == 'return') baseFileName = "DepoIadelistesi";
      if (type == 'expired') baseFileName = "miadi_gecenler_listesi";

      final String fullFileName = "${baseFileName}_${DateTime.now().millisecondsSinceEpoch}.xlsx";
      final String path = "${directory.path}/$fullFileName";

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(path);
        await file.writeAsBytes(fileBytes);

        await Share.shareXFiles(
          [
            XFile(
              path,
              name: fullFileName,
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            )
          ],
          text: 'Eczane Envanter Listesi',
        );
      }
    } catch (e) {
      debugPrint("Excel Hatası: $e");
      rethrow;
    }
  }
}
