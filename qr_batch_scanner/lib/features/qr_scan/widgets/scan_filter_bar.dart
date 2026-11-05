import 'package:flutter/material.dart';
import '../scan_list_filter.dart';

class ScanSearchRow extends StatefulWidget {
  final ValueChanged<String> onChanged;

  const ScanSearchRow({super.key, required this.onChanged});

  @override
  State<ScanSearchRow> createState() => _ScanSearchRowState();
}

class _ScanSearchRowState extends State<ScanSearchRow> {
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  // İlaç adı, GTIN veya seri no ile arama yapılan kutuyu gösterir
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        focusNode: _searchFocusNode,
        onChanged: widget.onChanged,
        onTapOutside: (event) => _searchFocusNode.unfocus(),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'İlaç adı, GTIN veya Seri No ara...',
          prefixIcon: const Icon(Icons.search_rounded, color: const Color(0xFFE53935), size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class ScanTimeFilterBar extends StatelessWidget {
  final TimeFilterPreset selected;
  final ValueChanged<TimeFilterPreset> onSelected;
  final bool hasItems;
  final VoidCallback onClearHistory;

  const ScanTimeFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.hasItems,
    required this.onClearHistory,
  });

  // Zaman filtresi çiplerini ve liste doluysa geçmişi temizle butonunu gösterir
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 1. Satır: Filtreler
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _filterChip(TimeFilterPreset.all, 'Tümü'),
                _filterChip(TimeFilterPreset.last1Hour, 'Son 1 Saat'),
                _filterChip(TimeFilterPreset.today, 'Bugün'),
                _filterChip(TimeFilterPreset.yesterday, 'Dün'),
              ],
            ),
          ),

          // 2. Satır: Koşullu Temizle Butonu
          if (hasItems)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: InkWell(
                onTap: onClearHistory,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded,
                        size: 14,
                        color: Colors.redAccent.withOpacity(0.7)
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Geçmişi Temizle",
                        style: TextStyle(
                          color: Colors.redAccent.withOpacity(0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 18), // Buton yokken kayma olmaması için
        ],
      ),
    );
  }

  // Tek bir zaman filtresi çipini seçili ya da seçili değil haliyle çizer
  Widget _filterChip(TimeFilterPreset preset, String label) {
    final isSelected = selected == preset;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          if (val) onSelected(preset);
        },
        selectedColor: const Color(0xFFE53935),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFFD32F2F),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: isSelected ? Colors.transparent : const Color(0xFFFFCDD2)),
      ),
    );
  }
}
