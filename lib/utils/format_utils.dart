class FormatUtils {
  static String formatRupiah(double amount) {
    String res = amount.toStringAsFixed(0);
    String formatted = res.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.'
    );
    return 'Rp $formatted';
  }
}
