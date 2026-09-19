AZURA DIGITAL — PHONE STORE MANAGEMENT

Isi ZIP:
- index.html : dashboard toko HP + login Supabase + absensi/duty + rekap harian/mingguan/bulanan + produk/stok + penjualan + role/akses.
- assets/azura-digital.png : logo yang diberikan pengguna.
- supabase.sql : schema tabel, trigger profile, RLS, dan data produk contoh.

INSTALASI:
1. Buat project Supabase.
2. Buka SQL Editor dan jalankan supabase.sql.
3. Daftarkan akun admin melalui dashboard.
4. Di SQL Editor, jalankan query admin terakhir di file supabase.sql dengan email admin Anda.
5. Upload folder ini ke Netlify/Vercel/hosting statis.
6. Buka website. Masukkan Project URL + anon/publishable key pada modal konfigurasi.
7. Pegawai daftar dengan email/password, lalu profile otomatis dibuat oleh trigger. Admin dapat mengatur role dan permissions dari menu Pegawai & Akses.

CATATAN:
- RLS membatasi perubahan profile/akses hanya admin.
- Jam absensi menggunakan waktu browser/ISO timestamp.
- Duty: klik MULAI DUTY untuk membuat absensi hari itu; klik lagi setelah selesai untuk clock-out.
- Rekap menyediakan filter harian, 7 hari terakhir, dan bulan berjalan.


LOGIN TANPA EMAIL
- Pengguna cukup memasukkan username dan password.
- Username dipetakan ke email internal @azura.local hanya untuk kebutuhan Supabase Auth.
- Pengguna tidak perlu memiliki email asli.
- Untuk akun baru, gunakan username unik seperti admin, brandon, budi.
- Karena tidak ada email konfirmasi/reset, password sebaiknya dikelola oleh admin.


BAHAN & CRAFTING
1. Jalankan SQL terbaru di supabase.sql.
2. Menu baru: Bahan & Crafting.
3. Isi stock bahan melalui tombol + BAHAN atau EDIT.
4. Resep 9 produk sudah dibuat sesuai daftar permintaan.
5. Klik CRAFT PRODUK, pilih produk dan jumlah. Sistem akan mengecek stock, mengurangi semua bahan, lalu menambah stock produk secara atomic.
6. Permission yang dipakai adalah products; admin selalu punya akses.
7. Menu MANAGEMENT sekarang dapat discroll sehingga Pegawai & Akses dan Pengaturan tidak tertutup panel user.

UPDATE STOCK & CRAFTING
- Menu Bahan & Crafting menyediakan tombol + STOCK untuk menambah bahan tanpa mengganti stock lama.
- Tombol EDIT dapat mengatur stock bahan ke angka tertentu.
- Saat CRAFT PRODUK berhasil, Supabase function craft_product mengurangi semua bahan sesuai resep secara atomic dan langsung menambah stock produk sesuai jumlah craft.
- Pastikan supabase.sql versi terbaru sudah dijalankan agar function craft_product tersedia.


PEMBUKUAN & KAS
- Menu Pembukuan & Kas membutuhkan permission finance (admin otomatis punya akses).
- Deposit menambah total pemasukan dan total kas.
- Withdraw mengurangi total kas.
- Penjualan otomatis mengurangi stock produk dan menambah pemasukan/kas melalui transaksi atomic.
- Total pemasukan = penjualan + deposit.
- Total kas = total pemasukan - total withdraw.
- Jalankan supabase.sql terbaru setelah update ini.


JABATAN AZURA DIGITAL
- Owner
- Co Owner
- Manager
- Technical
- IT Specialist
- Sales Specialist
- Junior
- Trainee

Catatan: Jabatan (position) dipisahkan dari role akses admin/employee.
Permission menu tetap dapat diatur oleh Admin.

AZURA DIGITAL V8 - ABSENSI & JABATAN
- Jabatan tampil pada data absensi.
- Role admin tetap dipertahankan.
- Akses menu pegawai mengikuti jabatan; admin tetap memiliki akses penuh.
- Owner, Co Owner, Manager dapat melakukan reset absensi manual.
- Sistem menutup duty yang masih aktif dari minggu sebelumnya saat siklus minggu baru dijalankan.
- Supabase pg_cron dapat digunakan untuk menjalankan reset otomatis setiap Senin 00:00.

V9: Pesan "Absensi hari ini sudah selesai" dihilangkan dari tampilan.


UPDATE V10 - ABSENSI BERULANG
- Pegawai dapat MULAI DUTY -> SELESAI DUTY berkali-kali pada tanggal yang sama.
- Setiap sesi disimpan sebagai record absensi terpisah.
- Durasi hari ini menjumlahkan seluruh sesi pegawai.
- Riwayat menampilkan seluruh sesi terbaru.
- Jalankan ulang supabase.sql agar constraint unique(user_id, work_date) pada database lama dihapus.

PENGGAJIAN (PAYROLL / SLIP GAJI)
- Menu baru "Penggajian" di sidebar (izin `payroll`; Owner/Co Owner/Manager/Admin
  otomatis punya akses, bisa diberikan ke jabatan lain lewat Pegawai & Akses).
- Tombol + BUAT SLIP GAJI: pilih karyawan, periode (bulan), Gaji Pokok, Tunjangan,
  Bonus, dan Potongan. Total dihitung otomatis dan slip dibuat berstatus DRAFT
  (belum memotong kas).
- Tombol LIHAT SLIP menampilkan slip gaji rapi (rincian komponen + total diterima)
  dan bisa dicetak lewat tombol CETAK SLIP.
- Tombol BAYAR pada slip draft akan, secara atomic lewat function pay_payroll_slip:
  1) mengecek kas mencukupi,
  2) mencatat pengeluaran "GAJI" di Pembukuan & Kas,
  3) menandai slip menjadi DIBAYAR beserta waktu & petugas yang membayar.
- Tombol BATAL pada slip draft membatalkan slip tanpa memotong kas.
- Total Kas di Pembukuan & Kas kini = Pemasukan − Withdraw − Pembelian Bahan − Gaji,
  dengan KPI tambahan "Gaji Karyawan".
- Karyawan tetap bisa melihat slip gajinya sendiri (RLS), sementara hanya
  pemegang izin payroll/admin yang bisa membuat & membayar slip.
- Jalankan supabase.sql terbaru untuk membuat tabel payroll_slips dan
  function create_payroll_slip / pay_payroll_slip / cancel_payroll_slip.

RAPIKAN BAHAN & CRAFTING
- Ditambahkan 3 KPI ringkas di atas: Total Bahan, Bahan Habis, dan Nilai Stock
  Bahan (stock × harga) agar kondisi gudang bahan terlihat sekilas.
- Ditambahkan kolom pencarian bahan agar mudah menemukan bahan tertentu di
  daftar yang panjang.
- Tombol aksi per baris (BELI, + STOCK, EDIT) dirapikan dengan spacing yang
  konsisten (sebelumnya tombol bisa menumpuk karena style .actions belum ada).
- Tombol CRAFT dipindah ke kartu Resep Crafting agar lebih dekat dengan
  konteksnya, sementara toolbar Stock Bahan hanya berisi + BAHAN dan BELI.

HARGA BAHAN & PEMBELIAN BAHAN
- Setiap bahan sekarang punya field Harga, tampil di tabel Bahan & Crafting.
- Tombol + BAHAN: mengisi nama, stock awal, dan harga bahan.
- Tombol EDIT: mengubah stock DAN harga acuan bahan.
- Tombol BELI BAHAN (di toolbar) atau tombol BELI per-baris: buka form pembelian —
  pilih bahan, qty, dan Harga Satuan yang BISA DISESUAIKAN bebas per transaksi
  (tidak harus sama dengan harga acuan). Total otomatis dihitung.
- Saat pembelian disimpan, sistem (function purchase_material) otomatis:
  1) mengecek kas mencukupi,
  2) mengurangi kas (tercatat sebagai "BELI BAHAN" di Pembukuan & Kas),
  3) menambah stock bahan,
  4) memperbarui harga acuan bahan sesuai harga pembelian terakhir.
- Tombol + STOCK tetap ada untuk menambah stock manual TANPA memotong kas
  (misalnya untuk koreksi/stock opname), berbeda dari BELI yang otomatis potong kas.
- Total Kas di Pembukuan & Kas kini = Pemasukan − Withdraw − Pembelian Bahan.
- Jalankan supabase.sql terbaru untuk menambah kolom materials.price dan function purchase_material.

PESANAN (ORDERS)
- Menu baru "Pesanan" di bawah TOKO HP, memakai permission `sales` (sama seperti Penjualan).
- Tombol + PESANAN: pilih produk, qty, nama pelanggan (opsional), dan Keterangan bebas.
- Pesanan baru dibuat dengan status PENDING dan BELUM mengurangi stok / kas.
- Tombol SELESAIKAN pada pesanan pending akan, secara atomic lewat function complete_order:
  1) mengecek stok produk cukup,
  2) mengurangi stok produk,
  3) mencatat baris di Penjualan,
  4) menambah pemasukan & kas di Pembukuan & Kas.
- Tombol BATAL pada pesanan pending akan membatalkan pesanan tanpa mengubah stok/kas.
- Pesanan yang sudah SELESAI atau BATAL tidak dapat diubah lagi.
- Jalankan supabase.sql terbaru untuk membuat tabel `orders` dan function create_order/complete_order/cancel_order.

UPDATE: SELF SERVICE
- Added menu Self Service under TOKO HP.
- Same management style as Produk & Stok: tambah, edit harga, edit stock, and status TERSEDIA/HABIS.
- Uses permission `products`, so users who can manage Produk & Stok can manage Self Service.
- Run the updated supabase.sql in Supabase SQL Editor to create table `self_services` and its RLS policies.

UPDATE: BRANGKAS ESPORT — JABATAN, RESEP, STOK, KAS KOTOR
- WAJIB: jalankan file migration_update_brangkas.sql di Supabase SQL Editor
  (setelah supabase.sql pernah dijalankan sebelumnya) agar fitur di bawah ini aktif.
- Jabatan disederhanakan jadi 2: PETINGGI (akses penuh, setara Owner/Co Owner/Manager
  lama) dan MEMBER (akses dasar: dashboard, produk, penjualan). Akun lama otomatis
  dipetakan: owner/co_owner/manager -> petinggi, sisanya -> member.
- Menu "Atur Pegawai" berganti nama jadi "Atur Member"; menu Pegawai & Akses kini
  memakai istilah "Member" di seluruh teksnya.
- Sidebar "TOKO HP" berganti nama menjadi "BRANGKAS ESPORT".
- Resep Crafting kini bisa diatur dari aplikasi: tombol "⚙ ATUR RESEP" di menu
  Bahan & Crafting membuka form untuk memilih produk lalu menambah/mengubah/menghapus
  bahan+qty resepnya. Menyimpan akan mengganti seluruh resep produk tsb
  (function set_crafting_recipe).
- Penjualan kini punya kolom Keterangan (opsional, diketik manual) yang tersimpan
  di tabel sales dan riwayat Pembukuan & Kas.
- Menu Produk & Stok punya sistem Barang Masuk / Barang Keluar: tombol
  "+ BARANG MASUK" dan "− BARANG KELUAR" mengubah stok produk secara otomatis dan
  WAJIB diisi Keterangan manual. Semua pergerakan tercatat di tabel riwayat baru
  di bawah daftar produk (function record_stock_movement, tabel stock_movements).
- Pembukuan & Kas punya bagian baru "Arus Kas Kotor": catat uang masuk manual
  (nominal + keterangan) sebagai "kas kotor" dulu, lalu tekan BERSIHKAN untuk
  memindahkannya resmi ke Kas Bersih (tabel dirty_cash, function add_dirty_cash
  dan clear_dirty_cash).
- Semua sebutan "Azura" pada aplikasi dan skema database sudah diganti menjadi
  "Brangkas Esport", termasuk email internal login (sekarang @brangkasesport.com)
  dan localStorage key konfigurasi Supabase.


UPDATE: PENGELUARAN, REKAP PEMESAN, REKAP TANGGAL, ARSIP (ala kapakbisnis)
- WAJIB: jalankan file migration_kapakbisnis_features.sql di Supabase SQL Editor
  (setelah supabase.sql dan migration_update_brangkas.sql pernah dijalankan).
- Menu baru di sidebar (grup "LAPORAN", izin `finance` — sama seperti Pembukuan & Kas):
  Pengeluaran, Rekap Pemesan, Rekap Tanggal, Arsip.
- PENGELUARAN: catat pengeluaran non-bahan (sewa, listrik, dll) lewat tombol
  + PENGELUARAN (tanggal, keterangan, nominal). Tersimpan atomic lewat function
  record_expense: mengecek kas cukup, mencatat baris di tabel expenses, dan
  otomatis memotong Total Kas di Pembukuan & Kas (jenis transaksi "PENGELUARAN").
  Total Kas kini = Pemasukan − Withdraw − Pembelian Bahan − Gaji − Pengeluaran.
- REKAP PEMESAN: rekap total belanja per nama pelanggan dari Pesanan, diurutkan
  dari belanja terbesar, sudah termasuk data yang sudah diarsipkan. Ada filter
  tanggal & nama pemesan, dan klik baris untuk lihat rincian pesanan pelanggan
  tsb (tanggal, item, qty, harga, total, status).
- REKAP TANGGAL: rekap total belanja per tanggal (jumlah order & total belanja),
  diurutkan dari tanggal terbaru, termasuk data arsip. Klik baris untuk lihat
  rincian pesanan pada tanggal tsb.
- ARSIP: pilih "Arsipkan Pesanan Sebelum Tanggal" lalu tekan ARSIPKAN SEKARANG.
  Semua pesanan (semua status) yang dibuat sebelum tanggal tsb dipindahkan dari
  Pesanan ke Arsip secara atomic lewat function archive_orders (baris disalin ke
  order_archives + ringkasan batch dicatat di archive_batches, lalu dihapus dari
  orders). Data yang sudah diarsipkan tetap terhitung di Rekap Pemesan & Rekap
  Tanggal, dan bisa dilihat rinciannya lagi lewat menu Arsip (klik baris batch).
- Rekap Pemesan/Tanggal & Arsip mengikuti perilaku kapakbisnis: hanya pesanan
  berstatus BATAL yang dikecualikan dari rekap; pesanan PENDING & SELESAI tetap
  dihitung sebagai "belanja" pada rekap (sesuai perilaku asli kapakbisnis).
