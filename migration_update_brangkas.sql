-- ============================================================
-- BRANGKAS ESPORT — MIGRASI TAMBAHAN
-- Jalankan file ini di Supabase SQL Editor SETELAH supabase.sql
-- utama sudah pernah dijalankan sebelumnya. Aman dijalankan
-- berulang kali (idempotent).
-- ============================================================

-- ------------------------------------------------------------
-- 1) JABATAN DISEDERHANAKAN: PETINGGI & MEMBER
-- ------------------------------------------------------------
-- Migrasikan data jabatan lama ke skema baru.
update public.profiles
set position = case
  when position in ('owner','co_owner','manager') then 'petinggi'
  else 'member'
end
where position not in ('petinggi','member');

alter table public.profiles drop constraint if exists profiles_position_check;
alter table public.profiles
  add constraint profiles_position_check
  check (position in ('petinggi','member'));

alter table public.profiles alter column position set default 'member';

-- Perbarui fungsi hak akses jabatan agar memakai 'petinggi'.
create or replace function public.can_manage_positions()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.profiles
    where id=auth.uid()
      and (role='admin' or position='petinggi')
  );
$$;

create or replace function public.can_reset_attendance()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.profiles
    where id=auth.uid()
      and (role='admin' or position='petinggi')
  );
$$;

-- ------------------------------------------------------------
-- 2) KETERANGAN MANUAL DI PENJUALAN
-- ------------------------------------------------------------
alter table public.sales add column if not exists keterangan text;

create or replace function public.record_sale(p_product_id uuid, p_qty integer default 1, p_keterangan text default null)
returns text language plpgsql security definer set search_path=public as $$
declare p record; total numeric; n text; sale_id uuid; note text;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'sales'=any(permissions))) then raise exception 'Anda tidak memiliki akses penjualan.'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Jumlah penjualan minimal 1.'; end if;
  select * into p from public.products where id=p_product_id for update;
  if p.id is null then raise exception 'Produk tidak ditemukan.'; end if;
  if p.stock < p_qty then raise exception 'Stock % tidak cukup. Tersedia %.',p.name,p.stock; end if;
  total := coalesce(p.price,0) * p_qty;
  note := nullif(trim(coalesce(p_keterangan,'')),'');
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  update public.products set stock=stock-p_qty where id=p_product_id;
  insert into public.sales(product_id,product_name,qty,total,cashier_id,cashier_name,keterangan)
  values(p.id,p.name,p_qty,total,auth.uid(),n,note) returning id into sale_id;
  insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name)
  values('sale',total,format('Penjualan %s x%s%s',p.name,p_qty, case when note is not null then ' — '||note else '' end),sale_id,auth.uid(),n);
  return format('Penjualan %s x%s berhasil.',p.name,p_qty);
end; $$;

grant execute on function public.record_sale(uuid,integer,text) to authenticated;

-- ------------------------------------------------------------
-- 3) SISTEM PEMASUKAN & PENGELUARAN BARANG (STOCK MOVEMENT)
-- ------------------------------------------------------------
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  product_name text not null,
  movement_type text not null check (movement_type in ('masuk','keluar')),
  qty integer not null check (qty > 0),
  keterangan text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now()
);

alter table public.stock_movements enable row level security;

drop policy if exists stock_movements_select on public.stock_movements;
create policy stock_movements_select on public.stock_movements
for select using (auth.uid() is not null);

-- Insert/update/delete hanya lewat function security definer di bawah.
drop policy if exists stock_movements_insert on public.stock_movements;
create policy stock_movements_insert on public.stock_movements for insert with check (false);
drop policy if exists stock_movements_update on public.stock_movements;
create policy stock_movements_update on public.stock_movements for update using (false);
drop policy if exists stock_movements_delete on public.stock_movements;
create policy stock_movements_delete on public.stock_movements for delete using (false);

create index if not exists stock_movements_created_at_idx on public.stock_movements(created_at desc);

create or replace function public.record_stock_movement(p_product_id uuid, p_type text, p_qty integer, p_keterangan text)
returns text language plpgsql security definer set search_path=public as $$
declare p record; n text; note text;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions))) then raise exception 'Anda tidak memiliki akses stok.'; end if;
  if p_type not in ('masuk','keluar') then raise exception 'Jenis pergerakan stok tidak valid.'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Jumlah minimal 1.'; end if;
  note := nullif(trim(coalesce(p_keterangan,'')),'');
  if note is null then raise exception 'Keterangan wajib diisi.'; end if;
  select * into p from public.products where id=p_product_id for update;
  if p.id is null then raise exception 'Produk tidak ditemukan.'; end if;
  if p_type = 'keluar' and p.stock < p_qty then raise exception 'Stock % tidak cukup. Tersedia %.',p.name,p.stock; end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  update public.products
    set stock = stock + (case when p_type='masuk' then p_qty else -p_qty end)
    where id=p_product_id;
  insert into public.stock_movements(product_id,product_name,movement_type,qty,keterangan,created_by,created_by_name)
  values(p.id,p.name,p_type,p_qty,note,auth.uid(),n);
  return format('Barang %s: %s x%s berhasil dicatat.', case when p_type='masuk' then 'masuk' else 'keluar' end, p.name, p_qty);
end; $$;

grant execute on function public.record_stock_movement(uuid,text,integer,text) to authenticated;

-- ------------------------------------------------------------
-- 4) RESEP CRAFTING BISA DIUBAH / DIATUR DARI APLIKASI
-- ------------------------------------------------------------
create or replace function public.set_crafting_recipe(p_product_id uuid, p_items jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare item jsonb; product_name text;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and ('products'=any(permissions) or 'crafting'=any(permissions)))) then
    raise exception 'Anda tidak memiliki akses mengubah resep.';
  end if;
  select name into product_name from public.products where id=p_product_id;
  if product_name is null then raise exception 'Produk tidak ditemukan.'; end if;

  delete from public.crafting_recipes where product_id = p_product_id;

  for item in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb))
  loop
    if (item->>'material_id') is null or (item->>'qty') is null or (item->>'qty')::integer < 1 then
      raise exception 'Data bahan resep tidak valid.';
    end if;
    insert into public.crafting_recipes(product_id, material_id, qty)
    values (p_product_id, (item->>'material_id')::uuid, (item->>'qty')::integer);
  end loop;

  return format('Resep %s berhasil disimpan.', product_name);
end; $$;

grant execute on function public.set_crafting_recipe(uuid,jsonb) to authenticated;

-- Perbolehkan role dengan permission products/crafting ikut menulis resep langsung juga (opsional, RPC tetap jalur utama).
drop policy if exists recipes_write on public.crafting_recipes;
create policy recipes_write on public.crafting_recipes for all
using (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and ('products'=any(permissions) or 'crafting'=any(permissions))))
with check (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and ('products'=any(permissions) or 'crafting'=any(permissions))));

-- ------------------------------------------------------------
-- 5) ARUS KAS KOTOR (DIRTY MONEY)
-- ------------------------------------------------------------
-- "Kas kotor" = uang masuk yang dicatat manual dulu sebelum resmi
-- masuk ke Kas Bersih (Pembukuan & Kas). Setelah ditekan BERSIHKAN,
-- nominalnya otomatis pindah menjadi transaksi deposit di kas bersih.
create table if not exists public.dirty_cash (
  id uuid primary key default gen_random_uuid(),
  amount numeric(14,2) not null check (amount > 0),
  keterangan text not null,
  status text not null default 'kotor' check (status in ('kotor','bersih')),
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now(),
  cleared_by uuid references public.profiles(id) on delete set null,
  cleared_by_name text,
  cleared_at timestamptz
);

alter table public.dirty_cash enable row level security;

drop policy if exists dirty_cash_select on public.dirty_cash;
create policy dirty_cash_select on public.dirty_cash for select using (auth.uid() is not null);
drop policy if exists dirty_cash_insert on public.dirty_cash;
create policy dirty_cash_insert on public.dirty_cash for insert with check (false);
drop policy if exists dirty_cash_update on public.dirty_cash;
create policy dirty_cash_update on public.dirty_cash for update using (false);
drop policy if exists dirty_cash_delete on public.dirty_cash;
create policy dirty_cash_delete on public.dirty_cash for delete using (false);

create index if not exists dirty_cash_status_idx on public.dirty_cash(status);

create or replace function public.add_dirty_cash(p_amount numeric, p_keterangan text)
returns text language plpgsql security definer set search_path=public as $$
declare n text; note text;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'finance'=any(permissions))) then raise exception 'Anda tidak memiliki akses pembukuan.'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Nominal harus lebih dari 0.'; end if;
  note := nullif(trim(coalesce(p_keterangan,'')),'');
  if note is null then raise exception 'Keterangan wajib diisi.'; end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  insert into public.dirty_cash(amount,keterangan,created_by,created_by_name)
  values(p_amount,note,auth.uid(),n);
  return 'Kas kotor berhasil dicatat.';
end; $$;

grant execute on function public.add_dirty_cash(numeric,text) to authenticated;

create or replace function public.clear_dirty_cash(p_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare d record; n text;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'finance'=any(permissions))) then raise exception 'Anda tidak memiliki akses pembukuan.'; end if;
  select * into d from public.dirty_cash where id=p_id for update;
  if d.id is null then raise exception 'Data kas kotor tidak ditemukan.'; end if;
  if d.status = 'bersih' then raise exception 'Kas ini sudah dibersihkan sebelumnya.'; end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  update public.dirty_cash
    set status='bersih', cleared_by=auth.uid(), cleared_by_name=n, cleared_at=now()
    where id=p_id;
  insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name)
  values('deposit', d.amount, format('Kas kotor dibersihkan — %s', d.keterangan), d.id, auth.uid(), n);
  return 'Kas kotor berhasil dipindahkan ke Kas Bersih.';
end; $$;

grant execute on function public.clear_dirty_cash(uuid) to authenticated;

-- ============================================================
-- SELESAI. Refresh halaman aplikasi (Ctrl+F5) setelah migrasi ini
-- berhasil dijalankan tanpa error.
-- ============================================================
