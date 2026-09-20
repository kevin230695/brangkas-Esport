-- =====================================================================
-- BRANGKAS ESPORT — BISNIS FLOW
-- Skema database Supabase (PostgreSQL)
-- =====================================================================
-- Cara pakai:
-- 1. Buat project baru di https://supabase.com (gratis).
-- 2. Buka menu "SQL Editor" di project kamu.
-- 3. Paste seluruh isi file ini, lalu klik "Run".
-- 4. Buka menu Project Settings > API, salin "Project URL" dan
--    "anon public" key.
-- 5. Buka aplikasi index.html, tempel Project URL & anon key di layar
--    "Hubungkan Database" saat pertama kali membuka aplikasi.
-- 6. Selesai — aplikasi akan otomatis mengisi data item default saat
--    pertama kali tersambung.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABEL: items — master barang/senjata & stok
-- ---------------------------------------------------------------------
create table if not exists public.items (
  id       text primary key,
  nama     text not null,
  kategori text not null default '',
  harga_a  numeric not null default 0,   -- harga satuan tipe A
  max_a    numeric not null default 0,   -- batas jumlah tipe A
  harga_n  numeric not null default 0,   -- harga satuan tipe N
  max_n    numeric not null default 0,   -- batas jumlah tipe N
  stok     numeric not null default 0
);

-- ---------------------------------------------------------------------
-- TABEL: orders — buku pesanan aktif
-- ---------------------------------------------------------------------
create table if not exists public.orders (
  id              text primary key,
  seq             integer not null default 0,
  tanggal         date not null,
  pemesan         text not null,
  jenis           text not null default '',
  item_id         text references public.items(id) on delete set null,
  jumlah          numeric not null default 0,
  harga           numeric not null default 0,
  total           numeric not null default 0,
  status          text not null default '',            -- 'OK' / status batas
  status_pesanan  text not null default 'DIPROSES',     -- DIPROSES / SELESAI / DIBATALKAN
  keterangan      text not null default '',
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- TABEL: archive — hasil rekap pesanan yang sudah diarsipkan
-- ---------------------------------------------------------------------
create table if not exists public.archive (
  id              text primary key,
  tanggal_dari    date,
  tanggal_sampai  date,
  jumlah_order    integer not null default 0,
  total_belanja   numeric not null default 0,
  detail_harian   jsonb not null default '[]'::jsonb,
  detail_pesanan  jsonb not null default '[]'::jsonb,
  dibuat_pada     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- TABEL: pengeluaran — pembukuan pengeluaran / restock
-- ---------------------------------------------------------------------
create table if not exists public.pengeluaran (
  id             text primary key,
  tanggal        date not null,
  item_id        text references public.items(id) on delete set null,
  item_nama      text not null default '',
  jumlah         numeric not null default 0,
  harga_satuan   numeric not null default 0,
  total          numeric not null default 0,
  keterangan     text not null default '',
  dibuat_pada    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- TABEL: resep — resep crafting (item hasil + daftar bahan yang dipakai)
-- ---------------------------------------------------------------------
create table if not exists public.resep (
  id              text primary key,
  nama            text not null,
  result_item_id  text references public.items(id) on delete set null,
  result_jumlah   numeric not null default 1,
  bahan           jsonb not null default '[]'::jsonb   -- [{ itemId, jumlah }, ...]
);

-- ---------------------------------------------------------------------
-- TABEL: crafting_log — riwayat setiap kali sebuah resep di-craft
-- ---------------------------------------------------------------------
create table if not exists public.crafting_log (
  id              text primary key,
  recipe_id       text,
  nama_resep      text,
  result_item_id  text,
  nama_hasil      text,
  jumlah_craft    numeric not null default 0,   -- jumlah batch yang di-craft
  hasil_jumlah    numeric not null default 0,   -- total unit hasil (result_jumlah x jumlah_craft)
  bahan_terpakai  jsonb not null default '[]'::jsonb, -- [{ itemId, nama, jumlah }, ...]
  dibuat_pada     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- TABEL: config — pengaturan aplikasi (target, batas stok, webhook, dll)
-- ---------------------------------------------------------------------
create table if not exists public.config (
  key   text primary key,
  value text not null default ''
);

-- ---------------------------------------------------------------------
-- TABEL: webhook_log — riwayat pengiriman notifikasi Discord
-- ---------------------------------------------------------------------
create table if not exists public.webhook_log (
  id          text primary key,
  tipe        text not null default '',
  status      text not null default '',
  percobaan   integer not null default 0,
  url         text,
  payload     jsonb,
  pesan_error text,
  dibuat_pada timestamptz not null default now()
);

-- =====================================================================
-- ROW LEVEL SECURITY
-- Aplikasi ini mengakses database langsung dari browser memakai anon
-- key (tanpa sistem login terpisah), jadi RLS diaktifkan lalu dibuka
-- penuh untuk role anon & authenticated. Catatan keamanan: siapa pun
-- yang memegang Project URL + anon key bisa baca/tulis data ini.
-- Jangan sebarkan anon key ke publik jika data ini sensitif.
-- =====================================================================
alter table public.items        enable row level security;
alter table public.orders       enable row level security;
alter table public.archive      enable row level security;
alter table public.pengeluaran  enable row level security;
alter table public.resep        enable row level security;
alter table public.crafting_log enable row level security;
alter table public.config       enable row level security;
alter table public.webhook_log  enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['items','orders','archive','pengeluaran','resep','crafting_log','config','webhook_log']
  loop
    execute format('drop policy if exists "allow_all_%1$s" on public.%1$s;', t);
    execute format(
      'create policy "allow_all_%1$s" on public.%1$s for all to anon, authenticated using (true) with check (true);',
      t
    );
  end loop;
end $$;

-- =====================================================================
-- SELESAI. Data item default akan otomatis diisi oleh aplikasi saat
-- pertama kali dibuka jika tabel "items" masih kosong.
-- =====================================================================
