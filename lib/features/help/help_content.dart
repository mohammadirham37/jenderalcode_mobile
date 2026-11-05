import 'package:flutter/material.dart';

/// Topics of the in-app guide. Screens open the guide at the topic that
/// fits them (`HelpButton(topic: …)`).
enum HelpTopic { start, chat, modes, agents, terminals, project, browser, usage, trouble, security }

class HelpSection {
  const HelpSection({
    required this.topic,
    required this.icon,
    required this.title,
    required this.summary,
    this.steps = const [],
    this.tips = const [],
  });
  final HelpTopic topic;
  final IconData icon;
  final String title;
  final String summary;

  /// Numbered steps.
  final List<String> steps;

  /// Extra notes shown after the steps.
  final List<String> tips;
}

/// The guide, in the order it is shown.
const helpSections = <HelpSection>[
  HelpSection(
    topic: HelpTopic.start,
    icon: Icons.qr_code_scanner,
    title: 'Memulai: hubungkan ke desktop',
    summary: 'JenderalCode Mobile mengendalikan JenderalCode Desktop di komputer Anda. '
        'Desktop harus terbuka dan tersambung ke internet.',
    steps: [
      'Di desktop, buka Settings → Remote control lalu aktifkan "Allow remote control".',
      'Tekan "Pair a phone". Desktop menampilkan QR code.',
      'Di HP, tekan "Pair a desktop" lalu scan QR code tersebut.',
      'Cocokkan kode 6 digit di HP dan di desktop. Kalau sama, tekan Connect di HP lalu Allow di desktop.',
      'Desktop muncul di daftar. Titik hijau berarti desktop sedang online.',
    ],
    tips: [
      'Kode 6 digit harus sama persis. Kalau berbeda, batalkan: ada yang mencoba menyusup.',
      'Satu HP bisa dipasangkan ke beberapa desktop.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.chat,
    icon: Icons.chat_bubble_outline,
    title: 'Chat dengan agent',
    summary: 'Sesi chat sama dengan yang ada di desktop: riwayatnya tersinkron di kedua layar.',
    steps: [
      'Pilih desktop, lalu pilih proyek.',
      'Buka sesi yang ada, atau tekan "New session" → JenderalCode chat.',
      'Tulis pesan lalu kirim. Jawaban agent muncul langsung saat diketik.',
      'Kalau agent meminta izin (approval), tekan Approve atau Deny pada kartunya.',
      'Tekan tombol Stop untuk menghentikan agent.',
    ],
    tips: [
      'Pesan yang dikirim selagi agent bekerja langsung mengarahkan (steer) pekerjaan yang sedang berjalan.',
      'Ganti agent (Build, Plan, Review) dan model dari baris di atas kolom pesan.',
      'Lampirkan file proyek dengan @, atau kirim foto dari kamera/galeri bila modelnya mendukung gambar.',
      'Tombol Enhance prompt (ikon catatan di sebelah kolom pesan) menulis ulang draf Anda menjadi prompt yang lebih jelas dan lengkap dengan model sesi itu. Periksa hasilnya sebelum mengirim; tekan Undo untuk kembali ke draf semula.',
      'Menu ⋮ → Checkpoints untuk membatalkan perubahan file yang dibuat agent.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.modes,
    icon: Icons.shield_outlined,
    title: 'Mode izin dan Full access',
    summary: 'Mode menentukan kapan agent harus meminta izin sebelum bertindak.',
    steps: [
      'Tekan lencana mode di kanan atas layar chat.',
      'Safe: agent meminta izin sebelum setiap perubahan dan perintah.',
      'Balanced: agent meminta izin sebelum perintah dan perubahan yang berisiko.',
      'Full access: agent menjalankan semuanya tanpa bertanya (kecuali perintah berbahaya).',
    ],
    tips: [
      'Full access, terminal, dan semua aksi tulis (edit file, git commit, dll.) dari HP hanya bisa dipakai '
          'bila di desktop diaktifkan: Settings → Remote control → "Allow Full access & terminal from phone".',
      'Approval dari HP hanya berlaku sekali dan tidak pernah menjadi izin permanen.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.agents,
    icon: Icons.smart_toy_outlined,
    title: 'Agent CLI: Claude Code, Codex, OpenCode, dll.',
    summary: 'Jalankan agent CLI yang terpasang di desktop, langsung dari HP.',
    steps: [
      'Di proyek, tekan "New session" lalu pilih agent CLI di bagian bawah.',
      'Pilih opsi: lanjutkan percakapan terakhir, atau bypass permissions (tanpa konfirmasi).',
      'Tekan Start. Agent berjalan di desktop; Anda mengetik dan melihat hasilnya di HP.',
      'Agent yang dibuka dari HP juga muncul sebagai tab di desktop (ikon HP), jadi bisa dilanjutkan dari sana.',
    ],
    tips: [
      'Untuk melanjutkan agent yang sudah berjalan di desktop, buka dari bagian "Agent CLI sessions" di daftar sesi, '
          'bukan dari "New session" (itu selalu membuat agent baru).',
      'Butuh izin "Allow Full access & terminal from phone" di desktop.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.terminals,
    icon: Icons.terminal,
    title: 'Terminal',
    summary: 'Pakai terminal desktop dari HP: tab yang sudah terbuka di desktop atau shell baru.',
    steps: [
      'Buka desktop → Terminals, atau tombol Terminal di halaman proyek.',
      'Pilih terminal yang sedang berjalan, atau tekan "New terminal".',
      'Gunakan baris tombol di atas keyboard untuk Esc, Tab, Ctrl, dan panah.',
    ],
    tips: [
      'Tab desktop ditampilkan dengan ukuran desktop; geser ke samping untuk melihat seluruh baris.',
      'Shell yang dibuka dari HP hanya bisa ditutup dari HP atau dengan menutup tabnya di desktop.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.project,
    icon: Icons.folder_open_outlined,
    title: 'Changes, Files, Editor, dan Git',
    summary: 'Lihat dan ubah isi proyek tanpa membuka laptop.',
    steps: [
      'Changes: perubahan yang belum di-commit, lengkap dengan diff.',
      'Files: jelajahi folder proyek; ketuk file untuk membukanya di Editor.',
      'Editor: ubah file lalu simpan langsung ke desktop.',
      'Git: stage, commit, ganti branch, dan buat branch baru.',
    ],
    tips: [
      'Mengubah file dan aksi git butuh izin "Allow Full access & terminal from phone" di desktop.',
      'File rahasia seperti .env tidak bisa dibuka dari HP.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.browser,
    icon: Icons.public,
    title: 'Browser: lihat aplikasi yang sedang dikembangkan',
    summary: 'Buka server dev yang berjalan di komputer (mis. localhost:5173) dari HP, di mana saja.',
    steps: [
      'Jalankan server dev di komputer seperti biasa (npm run dev, php artisan serve, dll.).',
      'Di HP, buka proyek lalu tekan Browser.',
      'Ketik alamatnya, mis. localhost:5173 atau cukup 5173, lalu tekan Open. Halaman yang sedang terbuka di browser desktop juga muncul sebagai pilihan.',
      'Setelah mengubah kode, tekan Reload.',
    ],
    tips: [
      'Halaman dimuat lewat desktop, jadi lebih lambat dari di komputer, terutama saat pertama dibuka.',
      'Live reload (HMR) belum berjalan; muat ulang secara manual.',
      'Hanya alamat di komputer itu sendiri (localhost) yang bisa dibuka. Tautan ke internet dibuka di browser HP.',
      'Butuh izin "Allow Full access & terminal from phone" di desktop dan JenderalCode Desktop v0.1.11 atau lebih baru.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.usage,
    icon: Icons.speed,
    title: 'Pemakaian agent (usage)',
    summary: 'Lihat sisa kuota langganan Claude Code, Codex, Antigravity, dan OpenCode.',
    steps: [
      'Di halaman desktop atau proyek, tekan Usage.',
      'Tarik layar ke bawah untuk memperbarui angkanya.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.trouble,
    icon: Icons.build_outlined,
    title: 'Mengatasi masalah',
    summary: 'Kalau sesuatu tidak berjalan seperti seharusnya.',
    steps: [
      'Desktop offline: pastikan aplikasi desktop terbuka, Remote control aktif, dan komputer tersambung internet.',
      'Strip "Relay offline": HP kehilangan koneksi. Ketuk strip itu untuk mencoba lagi.',
      '"Allow it on the desktop": fitur itu perlu diizinkan di Settings → Remote control pada desktop.',
      'Daftar tidak muncul: tarik layar ke bawah untuk memuat ulang.',
      'Tidak bisa terhubung lagi: hapus desktop dari daftar (⋯ → Unpair) lalu pairing ulang.',
    ],
    tips: [
      'Update aplikasi: menu ⋮ → About / Updates → Check for updates.',
    ],
  ),
  HelpSection(
    topic: HelpTopic.security,
    icon: Icons.lock_outline,
    title: 'Keamanan',
    summary: 'Pesan antara HP dan desktop dienkripsi end-to-end.',
    tips: [
      'Server relay hanya meneruskan data terenkripsi dan tidak bisa membaca isi chat, file, atau terminal.',
      'Desktop hanya menerima perintah dari HP yang sudah Anda izinkan dengan kode 6 digit.',
      'Cabut akses HP kapan saja dari desktop (Settings → Remote control) atau dengan Sign out di HP.',
    ],
  ),
];
