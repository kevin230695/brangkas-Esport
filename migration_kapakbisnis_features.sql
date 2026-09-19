-- ============================================================
-- MIGRASI: PENGELUARAN, REKAP PEMESAN, REKAP TANGGAL, ARSIP
-- (menyamakan fitur BRANGKAS ESPORT dengan PT KAPAK KOMPAK / kapakbisnis)
--
-- WAJIB: jalankan file ini SETELAH supabase.sql dan
-- migration_update_brangkas.sql pernah dijalankan sebelumnya.
-- ============================================================

-- ------------------------------------------------------------
-- 1) PENGELUARAN
--    Catatan pengeluaran non-bahan (sewa server, listrik, dll)
--    yang otomatis memotong Total Kas di Pembukuan & Kas.
-- ------------------------------------------------------------
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  tanggal date not null default current_date,
  keterangan text not null,
  nominal numeric(14,2) not null check (nominal > 0),
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now()
);
create index if not exists expenses_tanggal_idx on public.expenses(tanggal desc);

alter table public.expenses enable row level security;
drop policy if exists expenses_select on public.expenses;
create policy expenses_select on public.expenses for select
using (
  public.is_admin()
  or exists(select 1 from public.profiles where id=auth.uid() and 'finance'=any(permissions))
);
drop policy if exists expenses_write on public.expenses;
create policy expenses_write on public.expenses for all using (false) with check (false);

-- Izinkan jenis transaksi kas baru: 'expense'
alter table public.finance_transactions drop constraint if exists finance_transactions_transaction_type_check;
alter table public.finance_transactions add constraint finance_transactions_transaction_type_check
  check (transaction_type in ('deposit','withdraw','sale','purchase','payroll','expense'));

-- Catat pengeluaran secara atomic: cek akses -> cek kas cukup -> insert expenses -> potong kas.
create or replace function public.record_expense(p_tanggal date, p_keterangan text, p_nominal numeric)
returns text language plpgsql security definer set search_path=public as $$
declare n text; current_cash numeric; exp_id uuid;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'finance'=any(permissions))) then
    raise exception 'Anda tidak memiliki akses pembukuan.';
  end if;
  if coalesce(trim(p_keterangan),'')='' then raise exception 'Keterangan wajib diisi.'; end if;
  if p_nominal is null or p_nominal <= 0 then raise exception 'Nominal harus lebih dari 0.'; end if;

  select coalesce(sum(case when transaction_type in ('sale','deposit') then amount else -amount end),0)
    into current_cash from public.finance_transactions;
  if p_nominal > current_cash then raise exception 'Kas tidak cukup. Kas tersedia %.', current_cash; end if;

  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  insert into public.expenses(tanggal,keterangan,nominal,created_by,created_by_name)
  values(coalesce(p_tanggal, current_date), trim(p_keterangan), p_nominal, auth.uid(), n)
  returning id into exp_id;

  insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name)
  values('expense', p_nominal, format('Pengeluaran — %s', trim(p_keterangan)), exp_id, auth.uid(), n);

  return 'Pengeluaran berhasil dicatat.';
end; $$;
grant execute on function public.record_expense(date,text,numeric) to authenticated;

-- ------------------------------------------------------------
-- 2) ARSIP PESANAN (+ REKAP PEMESAN / REKAP TANGGAL)
--    Rekap dibangun dari tabel `orders` (aktif) digabung dengan
--    `order_archives` (sudah diarsipkan) — persis seperti kapakbisnis
--    yang menyebut "termasuk data yang sudah diarsipkan".
-- ------------------------------------------------------------
create table if not exists public.archive_batches (
  id uuid primary key default gen_random_uuid(),
  cutoff_date date not null,
  jumlah_order integer not null default 0,
  total_belanja numeric(14,2) not null default 0,
  archived_by uuid references public.profiles(id) on delete set null,
  archived_by_name text,
  archived_at timestamptz not null default now()
);
create index if not exists archive_batches_archived_at_idx on public.archive_batches(archived_at desc);

alter table public.archive_batches enable row level security;
drop policy if exists archive_batches_select on public.archive_batches;
create policy archive_batches_select on public.archive_batches for select
using (
  public.is_admin()
  or exists(select 1 from public.profiles where id=auth.uid() and 'finance'=any(permissions))
);
drop policy if exists archive_batches_write on public.archive_batches;
create policy archive_batches_write on public.archive_batches for all using (false) with check (false);

create table if not exists public.order_archives (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid references public.archive_batches(id) on delete cascade,
  order_id uuid,
  product_name text,
  qty integer,
  price numeric(14,2),
  total numeric(14,2),
  customer_name text,
  keterangan text,
  status text,
  created_at timestamptz,
  completed_at timestamptz
);
create index if not exists order_archives_batch_idx on public.order_archives(batch_id);
create index if not exists order_archives_created_at_idx on public.order_archives(created_at desc);
create index if not exists order_archives_customer_idx on public.order_archives(customer_name);

alter table public.order_archives enable row level security;
drop policy if exists order_archives_select on public.order_archives;
create policy order_archives_select on public.order_archives for select using (auth.uid() is not null);
drop policy if exists order_archives_write on public.order_archives;
create policy order_archives_write on public.order_archives for all using (false) with check (false);

-- Arsipkan seluruh pesanan (semua status, mengikuti perilaku kapakbisnis)
-- yang dibuat SEBELUM tanggal cutoff. Baris dipindah ke order_archives lalu
-- dihapus dari orders; ringkasan batch dicatat di archive_batches.
create or replace function public.archive_orders(p_cutoff date)
returns text language plpgsql security definer set search_path=public as $$
declare n text; new_batch_id uuid; cnt integer; total_sum numeric;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'finance'=any(permissions))) then
    raise exception 'Anda tidak memiliki akses pembukuan.';
  end if;
  if p_cutoff is null then raise exception 'Tanggal batas arsip wajib diisi.'; end if;

  select count(*), coalesce(sum(total),0) into cnt, total_sum
  from public.orders
  where created_at::date < p_cutoff;

  if cnt = 0 then raise exception 'Tidak ada pesanan sebelum tanggal tersebut.'; end if;

  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();

  insert into public.archive_batches(cutoff_date,jumlah_order,total_belanja,archived_by,archived_by_name)
  values(p_cutoff, cnt, total_sum, auth.uid(), n)
  returning id into new_batch_id;

  insert into public.order_archives(batch_id,order_id,product_name,qty,price,total,customer_name,keterangan,status,created_at,completed_at)
  select new_batch_id, id, product_name, qty, price, total, customer_name, keterangan, status, created_at, completed_at
  from public.orders
  where created_at::date < p_cutoff;

  delete from public.orders where created_at::date < p_cutoff;

  return format('%s pesanan berhasil diarsipkan.', cnt);
end; $$;
grant execute on function public.archive_orders(date) to authenticated;
