import 'package:flutter/material.dart';

class OurPayScreen extends StatefulWidget {
  const OurPayScreen({super.key});

  @override
  State<OurPayScreen> createState() => _OurPayScreenState();
}

class _OurPayScreenState extends State<OurPayScreen> {
  // Palette warna dompet digital modern
  static const Color primaryBlue = Color(0xFF00AED6);
  static const Color darkNavy = Color(0xFF0C2444);
  static const Color surfaceBg = Color(0xFFF3F4F6);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF1F2937);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color accentGreen = Color(0xFF00A651);

  bool _isBalanceVisible = true;
  String _activeFilter = 'Semua';

  final List<Map<String, dynamic>> _transactions = [
    {
      'title': 'Isi Saldo via BCA Virtual Account',
      'date': 'Hari ini, 10:24',
      'amount': 250000,
      'isIncome': true,
      'status': 'Berhasil',
      'category': 'Top Up',
      'icon': Icons.arrow_downward_rounded,
      'color': Colors.blue,
    },
    {
      'title': 'Kirim Uang ke Zharfan',
      'date': 'Kemarin, 19:10',
      'amount': 150000,
      'isIncome': false,
      'status': 'Berhasil',
      'category': 'Transfer',
      'icon': Icons.arrow_upward_rounded,
      'color': Colors.indigo,
    },
    {
      'title': 'Pembayaran QRIS Merchant Kafe Kopi',
      'date': '23 Nov 2026, 14:32',
      'amount': 42000,
      'isIncome': false,
      'status': 'Berhasil',
      'category': 'Pembayaran QR',
      'icon': Icons.qr_code_2_rounded,
      'color': primaryBlue,
    },
    {
      'title': 'Cashback Transaksi Our Media Post',
      'date': '22 Nov 2026, 09:15',
      'amount': 12500,
      'isIncome': true,
      'status': 'Berhasil',
      'category': 'Reward',
      'icon': Icons.stars_rounded,
      'color': Colors.amber.shade700,
    },
    {
      'title': 'Beli Paket Data Telkomsel 50GB',
      'date': '20 Nov 2026, 11:05',
      'amount': 85000,
      'isIncome': false,
      'status': 'Berhasil',
      'category': 'Tagihan & Pulsa',
      'icon': Icons.phone_android_rounded,
      'color': Colors.redAccent,
    },
    {
      'title': 'Token Listrik PLN Prabayar',
      'date': '18 Nov 2026, 20:41',
      'amount': 102500,
      'isIncome': false,
      'status': 'Berhasil',
      'category': 'Tagihan Listrik',
      'icon': Icons.bolt_rounded,
      'color': Colors.amber.shade800,
    },
  ];

  void _showNoticeDialog(String title, String detail) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded, color: primaryBlue, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
              ),
            ),
          ],
        ),
        content: Text(
          detail,
          style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.4),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _transactions.where((t) {
      if (_activeFilter == 'Masuk') return t['isIncome'] == true;
      if (_activeFilter == 'Keluar') return t['isIncome'] == false;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: surfaceBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Atas: Search Bar + Profile / Notifikasi
              _buildTopHeader(),

              // 2. Kotak Saldo Utama & 4 Aksi Cepat
              _buildWalletBox(),

              const SizedBox(height: 12),

              // 3. Tabungan & Limit PayLater
              _buildFinancialHub(),

              const SizedBox(height: 14),

              // 4. Grid Layanan Pembayaran PPOB
              _buildServicesGrid(),

              const SizedBox(height: 14),

              // 5. Promo & Keuntungan Pengguna
              _buildPromoSection(),

              const SizedBox(height: 14),

              // 6. Riwayat Transaksi
              _buildRecentTransactions(filteredList),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // --- 1. Top Header ---
  Widget _buildTopHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Tombol Kembali
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: surfaceBg,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.arrow_back, color: textDark, size: 20),
            ),
          ),
          const SizedBox(width: 10),

          // Search Box
          Expanded(
            child: InkWell(
              onTap: () => _showNoticeDialog('Pencarian', 'Ketik nama merchant, kontak penerima, atau jenis tagihan yang ingin dibayar.'),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, size: 18, color: textMuted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cari layanan, tagihan & promo...',
                        style: TextStyle(color: textMuted, fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Bantuan
          InkWell(
            onTap: () => _showNoticeDialog('Pusat Bantuan', 'Layanan bantuan dan FAQ dompet digital Our Pay aktif 24 jam.'),
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: surfaceBg,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.help_outline_rounded, color: textDark, size: 20),
            ),
          ),
          const SizedBox(width: 6),

          // Badge Verified User
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_rounded, color: primaryBlue, size: 14),
                SizedBox(width: 4),
                Text(
                  'Plus',
                  style: TextStyle(color: primaryBlue, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. Main Wallet Card & 4 Core Action Buttons ---
  Widget _buildWalletBox() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Baris Info Saldo & Poin
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                // Sisi Kiri: Saldo Utama
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_rounded, size: 16, color: primaryBlue),
                          const SizedBox(width: 6),
                          const Text(
                            'Saldo Our Pay',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _isBalanceVisible = !_isBalanceVisible;
                              });
                            },
                            borderRadius: BorderRadius.circular(5),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                _isBalanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 16,
                                color: textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isBalanceVisible ? 'Rp 1.453.000' : 'Rp ••••••••',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: textDark,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _showNoticeDialog('Riwayat Saldo', 'Riwayat pergerakan saldo tunai lengkap.'),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Klik untuk riwayat saldo',
                              style: TextStyle(fontSize: 11, color: primaryBlue, fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.chevron_right, size: 14, color: primaryBlue),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Pemisah Vertikal
                Container(
                  height: 48,
                  width: 1,
                  color: const Color(0xFFE5E7EB),
                ),

                // Sisi Kanan: Koin & Reward
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.stars_rounded, size: 16, color: Color(0xFFF59E0B)),
                            SizedBox(width: 4),
                            Text(
                              'Our Coins',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '12.450',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _showNoticeDialog('Tukar Koin', 'Koin dapat ditukarkan dengan voucher diskon dan potongan harga transaksi.'),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tukar Koin',
                                style: TextStyle(fontSize: 11, color: primaryBlue, fontWeight: FontWeight.w600),
                              ),
                              Icon(Icons.chevron_right, size: 14, color: primaryBlue),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF3F4F6)),

          // Baris 4 Aksi Ikonik: Bayar, Top Up, Kirim, Eksplor
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionButton(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Bayar',
                  color: primaryBlue,
                  onTap: () => _showNoticeDialog('Bayar via QRIS', 'Arahkan kamera ke kode QRIS pembayaran toko atau merchant.'),
                ),
                _buildActionButton(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Top Up',
                  color: primaryBlue,
                  onTap: () => _showNoticeDialog('Isi Saldo', 'Pilih metode top up: Transfer Bank (BCA, Mandiri, BRI, BNI), Alfamart, Indomaret.'),
                ),
                _buildActionButton(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Kirim',
                  color: primaryBlue,
                  onTap: () => _showNoticeDialog('Kirim Uang', 'Kirim saldo gratis tanpa biaya admin ke sesama pengguna Our Chat atau rekening bank.'),
                ),
                _buildActionButton(
                  icon: Icons.grid_view_rounded,
                  label: 'Eksplor',
                  color: primaryBlue,
                  onTap: () => _showNoticeDialog('Eksplor Fitur', 'Menu lengkap: Minta Dana, Tarik Tunai Tanpa Kartu, Pembagian Tagihan (Split Bill).'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 3. Financial Hub: Tabungan & PayLater Limit ---
  Widget _buildFinancialHub() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Tabungan
          Expanded(
            child: InkWell(
              onTap: () => _showNoticeDialog('Our Pay Tabungan', 'Tabungan dengan bunga kompetitif harian, terdaftar & diawasi, bebas biaya admin bulanan.'),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Icon(Icons.savings_outlined, color: accentGreen, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tabungan',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textDark),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Bunga 5.5% p.a.',
                            style: TextStyle(fontSize: 10.5, color: accentGreen, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // PayLater
          Expanded(
            child: InkWell(
              onTap: () => _showNoticeDialog('PayLater', 'Beli sekarang bayar nanti dengan tenor 1 hingga 12 bulan. Limit disetujui hingga Rp 10.000.000.'),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Icon(Icons.credit_card_rounded, color: primaryBlue, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PayLater',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textDark),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Limit s.d 10 Jt',
                            style: TextStyle(fontSize: 10.5, color: primaryBlue, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 4. Services Grid (PPOB & Pembayaran Tagihan) ---
  Widget _buildServicesGrid() {
    final services = [
      {'icon': Icons.phone_android_rounded, 'name': 'Pulsa & Data', 'color': const Color(0xFF0284C7)},
      {'icon': Icons.bolt_rounded, 'name': 'Listrik PLN', 'color': const Color(0xFFD97706)},
      {'icon': Icons.water_drop_rounded, 'name': 'Air PDAM', 'color': const Color(0xFF06B6D4)},
      {'icon': Icons.health_and_safety_rounded, 'name': 'BPJS Kesehatan', 'color': const Color(0xFF16A34A)},
      {'icon': Icons.router_rounded, 'name': 'Internet & TV', 'color': const Color(0xFFDC2626)},
      {'icon': Icons.sports_esports_rounded, 'name': 'Voucher Game', 'color': const Color(0xFF9333EA)},
      {'icon': Icons.volunteer_activism_rounded, 'name': 'Donasi & Zakat', 'color': const Color(0xFF059669)},
      {'icon': Icons.more_horiz_rounded, 'name': 'Lihat Semua', 'color': const Color(0xFF4B5563)},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Layanan & Pembayaran',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: services.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 8,
              childAspectRatio: 0.9,
            ),
            itemBuilder: (context, idx) {
              final item = services[idx];
              final col = item['color'] as Color;
              return InkWell(
                onTap: () => _showNoticeDialog(item['name'] as String, 'Layanan "${item['name']}" dapat langsung digunakan untuk pembelian dan pelunasan tagihan online.'),
                borderRadius: BorderRadius.circular(5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: col.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Icon(item['icon'] as IconData, color: col, size: 22),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item['name'] as String,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // --- 5. Promo Section ---
  Widget _buildPromoSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF7DD3FC)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryBlue,
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(Icons.local_offer_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gratis Transfer 100x Antar Bank',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0369A1),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Kirim uang ke bank mana saja tanpa potongan biaya admin.',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _showNoticeDialog('Klaim Promo', 'Voucher gratis transfer 100x sudah otomatis aktif di akun Anda.'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            child: const Text('Klaim'),
          ),
        ],
      ),
    );
  }

  // --- 6. Recent Transactions List ---
  Widget _buildRecentTransactions(List<Map<String, dynamic>> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Riwayat Transaksi',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              InkWell(
                onTap: () => _showNoticeDialog('Semua Riwayat', 'Menampilkan arsip lengkap transaksi masuk dan keluar Anda.'),
                borderRadius: BorderRadius.circular(5),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Lihat Semua',
                    style: TextStyle(fontSize: 12, color: primaryBlue, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Filter Tabs (Semua, Masuk, Keluar) dengan border radius <= 5px
          Row(
            children: ['Semua', 'Masuk', 'Keluar'].map((f) {
              final isSelected = _activeFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _activeFilter = f;
                    });
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? primaryBlue : surfaceBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : textMuted,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Belum ada transaksi $_activeFilter',
                  style: const TextStyle(fontSize: 12, color: textMuted),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 16, color: Color(0xFFF3F4F6)),
              itemBuilder: (context, index) {
                final tx = items[index];
                final isIncome = tx['isIncome'] as bool;
                final amount = tx['amount'] as int;
                final iconColor = tx['color'] as Color;

                return InkWell(
                  onTap: () => _showNoticeDialog(
                    tx['title'] as String,
                    'Kategori: ${tx['category']}\nWaktu: ${tx['date']}\nStatus: ${tx['status']}\nTotal: Rp ${_formatNumber(amount)}',
                  ),
                  borderRadius: BorderRadius.circular(5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        // Ikon Kategori Transaksi
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: iconColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(tx['icon'] as IconData, color: iconColor, size: 20),
                        ),
                        const SizedBox(width: 12),

                        // Judul & Tanggal
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx['title'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tx['date'] as String,
                                style: const TextStyle(fontSize: 11, color: textMuted),
                              ),
                            ],
                          ),
                        ),

                        // Nominal & Status
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${isIncome ? '+' : '-'} Rp ${_formatNumber(amount)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isIncome ? accentGreen : const Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tx['status'] as String,
                              style: const TextStyle(fontSize: 10, color: textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }
}
