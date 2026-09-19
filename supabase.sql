-- BRANGKAS ESPORT / Supabase schema
-- Jalankan seluruh file ini di Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text default 'Pegawai Baru',
  role text not null default 'employee' check (role in ('admin','employee')),
  permissions text[] not null default array['dashboard','attendance','reports']::text[],
  created_at timestamptz not null default now()
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  work_date date not null,
  clock_in timestamptz not null,
  clock_out timestamptz,
  duty boolean not null default false,
  created_at timestamptz not null default now()
);


-- IZINKAN ABSENSI BERULANG DALAM HARI YANG SAMA.
-- Setiap klik MULAI DUTY setelah sesi sebelumnya selesai akan membuat
-- baris absensi baru (clock_in/clock_out) pada tanggal yang sama.
-- Jalankan migrasi ini jika database lama sudah memiliki unique(user_id, work_date).
alter table public.attendance drop constraint if exists attendance_user_id_work_date_key;
alter table public.attendance drop constraint if exists attendance_user_id_work_date_unique;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  brand text,
  price numeric(14,2) not null default 0,
  stock integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.self_services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price numeric(14,2) not null default 0,
  stock integer not null default 0 check (stock >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete set null,
  self_service_id uuid references public.self_services(id) on delete set null,
  product_name text not null,
  qty integer not null check(qty > 0),
  total numeric(14,2) not null default 0,
  cashier_id uuid references public.profiles(id) on delete set null,
  cashier_name text,
  sold_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id,email,full_name) values (new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name','Pegawai Baru')) on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.attendance enable row level security;
alter table public.products enable row level security;
alter table public.self_services enable row level security;
alter table public.sales enable row level security;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $$;

drop policy if exists attendance_select on public.attendance;
create policy attendance_select on public.attendance for select using (user_id=auth.uid() or public.is_admin());
drop policy if exists attendance_insert on public.attendance;
create policy attendance_insert on public.attendance for insert with check (user_id=auth.uid());
drop policy if exists attendance_update on public.attendance;
create policy attendance_update on public.attendance for update using (user_id=auth.uid() or public.is_admin());

drop policy if exists self_services_select on public.self_services;
create policy self_services_select on public.self_services for select using (auth.uid() is not null);
drop policy if exists self_services_write on public.self_services;
create policy self_services_write on public.self_services for all using (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions))) with check (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions)));

drop policy if exists products_select on public.products;
create policy products_select on public.products for select using (auth.uid() is not null);
drop policy if exists products_write on public.products;
create policy products_write on public.products for all using (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions))) with check (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions)));

drop policy if exists sales_select on public.sales;
create policy sales_select on public.sales for select using (auth.uid() is not null);
drop policy if exists sales_insert on public.sales;
create policy sales_insert on public.sales for insert with check (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'sales'=any(permissions)));

-- Setelah akun admin pertama mendaftar, jadikan admin dengan query berikut:
-- update public.profiles set role='admin', permissions=array['dashboard','attendance','reports','products','sales','finance','employees','settings'] where email='EMAIL_ADMIN_ANDA';

insert into public.products(name,brand,price,stock)
select * from (values
('iPhone 17 Pro Max','Apple',28999000,5),
('Galaxy S26 Ultra','Samsung',21999000,7),
('Xiaomi 16 Ultra','Xiaomi',16999000,8),
('OPPO Find X9 Pro','OPPO',14999000,6)
) v(name,brand,price,stock)
where not exists(select 1 from public.products);


-- LOGIN TANPA EMAIL:
-- Website memetakan username ke email internal @brangkasesport.com.
-- Tidak diperlukan email asli dari pegawai.


-- ==============================
-- BAHAN & CRAFTING PRODUK BRANGKAS ESPORT
-- Jalankan bagian ini setelah schema utama.
create table if not exists public.materials (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  stock integer not null default 0 check (stock >= 0),
  created_at timestamptz not null default now()
);

create unique index if not exists materials_name_unique on public.materials(lower(name));

create table if not exists public.crafting_recipes (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  material_id uuid not null references public.materials(id) on delete cascade,
  qty integer not null check (qty > 0),
  unique(product_id, material_id)
);

alter table public.materials enable row level security;
alter table public.crafting_recipes enable row level security;

drop policy if exists materials_select on public.materials;
create policy materials_select on public.materials for select using (auth.uid() is not null);
drop policy if exists materials_write on public.materials;
create policy materials_write on public.materials for all using (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions))) with check (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions)));

drop policy if exists recipes_select on public.crafting_recipes;
create policy recipes_select on public.crafting_recipes for select using (auth.uid() is not null);
drop policy if exists recipes_write on public.crafting_recipes;
create policy recipes_write on public.crafting_recipes for all using (public.is_admin()) with check (public.is_admin());

-- Atomic crafting: cek bahan -> kurangi bahan -> tambah stok produk.
create or replace function public.craft_product(p_product_id uuid, p_qty integer default 1)
returns text language plpgsql security definer set search_path=public as $$
declare r record; needed integer; current_stock integer; product_name text;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions))) then raise exception 'Anda tidak memiliki akses crafting.'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Jumlah craft harus minimal 1.'; end if;
  select name into product_name from public.products where id=p_product_id;
  if product_name is null then raise exception 'Produk tidak ditemukan.'; end if;
  if not exists(select 1 from public.crafting_recipes where product_id=p_product_id) then raise exception 'Resep produk belum dibuat.'; end if;
  for r in select cr.material_id, cr.qty, m.name, m.stock from public.crafting_recipes cr join public.materials m on m.id=cr.material_id where cr.product_id=p_product_id for update of m loop
    needed := r.qty * p_qty;
    if r.stock < needed then raise exception 'Stock % tidak cukup. Butuh %, tersedia %.', r.name, needed, r.stock; end if;
  end loop;
  for r in select material_id, qty from public.crafting_recipes where product_id=p_product_id loop
    update public.materials set stock=stock-(r.qty*p_qty) where id=r.material_id;
  end loop;
  update public.products set stock=stock+p_qty where id=p_product_id;
  return format('%s x%s berhasil dibuat.', product_name, p_qty);
end; $$;

grant execute on function public.craft_product(uuid,integer) to authenticated;

-- Produk crafting
insert into public.products(name,brand,price,stock)
select v.name,'Brangkas Esport',0,0 from (values
('Box phone'),('Exclusive Phone'),('Radio'),('USB Merah'),('Power Bank'),('Fast Power Bank'),('Speaker'),('Toolkit Phone'),('Toolkit Brick Phone')
) v(name) where not exists(select 1 from public.products p where lower(p.name)=lower(v.name));

-- Stock awal bahan (silakan ubah dari menu Bahan & Crafting setelah login).
insert into public.materials(name,stock)
select v.name,v.stock from (values
('Plastik',0),('Metal Scrap',0),('Gold',0),('Steel',0),('Copper',0),('Silver',0)
) v(name,stock) where not exists(select 1 from public.materials m where lower(m.name)=lower(v.name));

-- Resep crafting sesuai permintaan.
insert into public.crafting_recipes(product_id,material_id,qty)
select p.id,m.id,v.qty from (values
('Box phone','Plastik',6),('Box phone','Metal Scrap',6),('Box phone','Gold',22),('Box phone','Steel',22),
('Exclusive Phone','Plastik',100),('Exclusive Phone','Metal Scrap',100),('Exclusive Phone','Gold',152),('Exclusive Phone','Steel',152),
('Radio','Plastik',8),('Radio','Metal Scrap',8),('Radio','Copper',24),('Radio','Steel',24),
('USB Merah','Plastik',2),('USB Merah','Metal Scrap',2),('USB Merah','Copper',23),('USB Merah','Steel',23),
('Power Bank','Plastik',4),('Power Bank','Metal Scrap',4),('Power Bank','Copper',14),('Power Bank','Steel',14),
('Fast Power Bank','Plastik',8),('Fast Power Bank','Metal Scrap',8),('Fast Power Bank','Copper',12),('Fast Power Bank','Steel',12),
('Speaker','Plastik',33),('Speaker','Metal Scrap',33),('Speaker','Steel',27),
('Toolkit Phone','Plastik',7),('Toolkit Phone','Metal Scrap',7),('Toolkit Phone','Steel',6),('Toolkit Phone','Silver',6),
('Toolkit Brick Phone','Plastik',40),('Toolkit Brick Phone','Metal Scrap',40),('Toolkit Brick Phone','Steel',40),('Toolkit Brick Phone','Silver',40)
) v(product_name,material_name,qty) join public.products p on lower(p.name)=lower(v.product_name) join public.materials m on lower(m.name)=lower(v.material_name) on conflict (product_id,material_id) do update set qty=excluded.qty;


-- ==============================
-- PEMBUKUAN & KAS BRANGKAS ESPORT
-- Deposit = kas masuk manual.
-- Withdraw = kas keluar.
-- Sale = pemasukan otomatis dari penjualan.
create table if not exists public.finance_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_type text not null check (transaction_type in ('deposit','withdraw','sale')),
  amount numeric(14,2) not null check (amount > 0),
  description text not null default '',
  reference_id uuid,
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now()
);

create index if not exists finance_transactions_created_at_idx on public.finance_transactions(created_at desc);
create index if not exists finance_transactions_type_idx on public.finance_transactions(transaction_type);

-- Migrasikan penjualan lama ke pembukuan agar total kas mencakup transaksi yang sudah ada.
insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name,created_at)
select 'sale',s.total,format('Penjualan lama %s x%s',s.product_name,s.qty),s.id,s.cashier_id,s.cashier_name,s.sold_at
from public.sales s
where not exists(select 1 from public.finance_transactions f where f.transaction_type='sale' and f.reference_id=s.id);

alter table public.finance_transactions enable row level security;
drop policy if exists finance_select on public.finance_transactions;
create policy finance_select on public.finance_transactions for select
using (
  public.is_admin()
  or exists(select 1 from public.profiles where id=auth.uid() and 'finance'=any(permissions))
);

-- Hanya RPC yang boleh membuat transaksi kas dari aplikasi.
drop policy if exists finance_insert on public.finance_transactions;
create policy finance_insert on public.finance_transactions for insert
with check (false);

drop policy if exists finance_update on public.finance_transactions;
create policy finance_update on public.finance_transactions for update using (false);
drop policy if exists finance_delete on public.finance_transactions;
create policy finance_delete on public.finance_transactions for delete using (false);

-- Deposit / withdraw: validasi akses dan nominal.
create or replace function public.cash_transaction(p_type text, p_amount numeric, p_description text)
returns text language plpgsql security definer set search_path=public as $$
declare n text; current_cash numeric;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if p_type not in ('deposit','withdraw') then raise exception 'Jenis transaksi tidak valid.'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Nominal harus lebih dari 0.'; end if;
  if coalesce(trim(p_description),'')='' then raise exception 'Keterangan wajib diisi.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'finance'=any(permissions))) then raise exception 'Anda tidak memiliki akses pembukuan.'; end if;
  if p_type='withdraw' then
    select coalesce(sum(case when transaction_type in ('sale','deposit') then amount else -amount end),0) into current_cash from public.finance_transactions;
    if p_amount > current_cash then raise exception 'Kas tidak cukup. Kas tersedia %.', current_cash; end if;
  end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  insert into public.finance_transactions(transaction_type,amount,description,created_by,created_by_name)
  values(p_type,p_amount,trim(p_description),auth.uid(),n);
  return case when p_type='deposit' then 'Deposit berhasil dicatat.' else 'Withdraw berhasil dicatat.' end;
end; $$;

grant execute on function public.cash_transaction(text,numeric,text) to authenticated;

-- Penjualan atomic: lock stock -> cek -> kurangi stock -> insert sale -> tambah kas.
create or replace function public.record_sale(p_product_id uuid, p_qty integer default 1)
returns text language plpgsql security definer set search_path=public as $$
declare p record; total numeric; n text; sale_id uuid;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'sales'=any(permissions))) then raise exception 'Anda tidak memiliki akses penjualan.'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Jumlah penjualan minimal 1.'; end if;
  select * into p from public.products where id=p_product_id for update;
  if p.id is null then raise exception 'Produk tidak ditemukan.'; end if;
  if p.stock < p_qty then raise exception 'Stock % tidak cukup. Tersedia %.',p.name,p.stock; end if;
  total := coalesce(p.price,0) * p_qty;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  update public.products set stock=stock-p_qty where id=p_product_id;
  insert into public.sales(product_id,product_name,qty,total,cashier_id,cashier_name)
  values(p.id,p.name,p_qty,total,auth.uid(),n) returning id into sale_id;
  insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name)
  values('sale',total,format('Penjualan %s x%s',p.name,p_qty),sale_id,auth.uid(),n);
  return format('Penjualan %s x%s berhasil.',p.name,p_qty);
end; $$;

grant execute on function public.record_sale(uuid,integer) to authenticated;

-- Penjualan Self Service atomic: lock stock -> cek -> kurangi stock -> insert sale -> tambah kas.
alter table public.sales add column if not exists self_service_id uuid references public.self_services(id) on delete set null;

create or replace function public.record_self_service_sale(p_self_service_id uuid, p_qty integer default 1)
returns text language plpgsql security definer set search_path=public as $$
declare s record; total numeric; n text; sale_id uuid;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'sales'=any(permissions))) then raise exception 'Anda tidak memiliki akses penjualan.'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Jumlah penjualan minimal 1.'; end if;
  select * into s from public.self_services where id=p_self_service_id for update;
  if s.id is null then raise exception 'Self service tidak ditemukan.'; end if;
  if s.stock < p_qty then raise exception 'Stock % tidak cukup. Tersedia %.',s.name,s.stock; end if;
  total := coalesce(s.price,0) * p_qty;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  update public.self_services set stock=stock-p_qty where id=p_self_service_id;
  insert into public.sales(product_id,self_service_id,product_name,qty,total,cashier_id,cashier_name)
  values(null,s.id,s.name,p_qty,total,auth.uid(),n) returning id into sale_id;
  insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name)
  values('sale',total,format('Penjualan Self Service %s x%s',s.name,p_qty),sale_id,auth.uid(),n);
  return format('Penjualan Self Service %s x%s berhasil.',s.name,p_qty);
end; $$;

grant execute on function public.record_self_service_sale(uuid,integer) to authenticated;


-- BRANGKAS ESPORT: JABATAN PEGAWAI
-- Role akses (admin/employee) tetap dipisahkan dari jabatan.
alter table public.profiles
  add column if not exists position text not null default 'trainee';

alter table public.profiles
  drop constraint if exists profiles_position_check;

alter table public.profiles
  add constraint profiles_position_check
  check (position in (
    'owner',
    'co_owner',
    'manager',
    'technical',
    'it_specialist',
    'sales_specialist',
    'junior',
    'trainee'
  ));

-- Owner dapat dipakai sebagai akun dengan akses penuh.
-- Hak akses menu tetap dikontrol oleh kolom permissions.


-- BRANGKAS ESPORT V8
-- Jabatan tetap terpisah dari role akses admin/employee.
alter table public.profiles
  add column if not exists position text not null default 'trainee';

alter table public.profiles
  drop constraint if exists profiles_position_check;

alter table public.profiles
  add constraint profiles_position_check
  check (position in (
    'owner','co_owner','manager','technical',
    'it_specialist','sales_specialist','junior','trainee'
  ));

-- OWNER / CO OWNER / MANAGER dapat melihat dan mengatur profile serta jabatan.
-- Didefinisikan setelah kolom position dibuat agar SQL aman dijalankan dari awal.
create or replace function public.can_manage_positions()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.profiles
    where id=auth.uid()
      and (role='admin' or position in ('owner','co_owner','manager'))
  );
$$;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
for select using (id=auth.uid() or public.can_manage_positions());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
for update using (public.can_manage_positions())
with check (public.can_manage_positions());

-- Hak reset manual absensi hanya untuk Owner, Co Owner, Manager, atau Admin.
create or replace function public.can_reset_attendance()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.profiles
    where id=auth.uid()
      and (
        role='admin'
        or position in ('owner','co_owner','manager')
      )
  );
$$;

-- Reset mingguan: arsipkan status duty aktif dan mulai siklus minggu baru.
create table if not exists public.attendance_weeks (
  id uuid primary key default gen_random_uuid(),
  week_start date not null unique,
  reset_at timestamptz not null default now(),
  reset_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function public.ensure_current_attendance_week()
returns void language plpgsql security definer set search_path=public as $$
declare ws date;
begin
  ws := date_trunc('week', current_date)::date;
  insert into public.attendance_weeks(week_start, reset_by)
  values(ws, auth.uid())
  on conflict(week_start) do nothing;

  -- Duty yang masih ON dari minggu sebelumnya ditutup saat siklus baru dimulai.
  update public.attendance
  set duty=false,
      clock_out=coalesce(clock_out, now())
  where duty=true
    and work_date < ws;
end; $$;

alter table public.attendance_weeks enable row level security;

drop policy if exists attendance_weeks_select on public.attendance_weeks;
create policy attendance_weeks_select on public.attendance_weeks
for select using (auth.uid() is not null);

-- Jalankan ensure_current_attendance_week() setiap kali halaman absensi dibuka.
-- Untuk reset terjadwal walaupun tidak ada user membuka halaman, gunakan pg_cron
-- jika tersedia di project Supabase:
-- select cron.schedule(
--   'brangkas-weekly-attendance-reset',
--   '0 0 * * 1',
--   $$select public.ensure_current_attendance_week();$$
-- );

-- ================== Auto-kurangi stock produk saat tambah stock Self Service ==================
alter table public.self_services add column if not exists source_product_id uuid references public.products(id) on delete set null;

create or replace function public.add_self_service_stock(p_self_service_id uuid, p_qty integer)
returns text language plpgsql security definer set search_path=public as $$
declare s record; p record; n text;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions))) then raise exception 'Anda tidak memiliki akses produk.'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Jumlah tambahan minimal 1.'; end if;
  select * into s from public.self_services where id=p_self_service_id for update;
  if s.id is null then raise exception 'Self service tidak ditemukan.'; end if;
  if s.source_product_id is null then raise exception 'Self service ini belum ditautkan ke produk sumber.'; end if;
  select * into p from public.products where id=s.source_product_id for update;
  if p.id is null then raise exception 'Produk sumber tidak ditemukan.'; end if;
  if p.stock < p_qty then raise exception 'Stock produk % hanya %.',p.name,p.stock; end if;
  update public.products set stock=stock-p_qty where id=p.id;
  update public.self_services set stock=stock+p_qty where id=s.id;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  return format('Stock %s bertambah %s (diambil dari stock produk %s).',s.name,p_qty,p.name);
end; $$;

grant execute on function public.add_self_service_stock(uuid,integer) to authenticated;


-- ==============================
-- PESANAN (ORDERS) BRANGKAS ESPORT
-- Pesanan dibuat dengan status pending (belum mempengaruhi stock/kas).
-- Saat pesanan diselesaikan (SELESAIKAN), sistem otomatis:
--   1) mengecek & mengurangi stock produk,
--   2) mencatat penjualan,
--   3) menambah pembukuan & kas.
-- Semua langkah berjalan atomic lewat function complete_order.
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  qty integer not null check (qty > 0),
  price numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  customer_name text,
  keterangan text,
  status text not null default 'pending' check (status in ('pending','selesai','batal')),
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now(),
  completed_by uuid references public.profiles(id) on delete set null,
  completed_by_name text,
  completed_at timestamptz,
  sale_id uuid references public.sales(id) on delete set null
);

create index if not exists orders_status_idx on public.orders(status);
create index if not exists orders_created_at_idx on public.orders(created_at desc);

alter table public.orders enable row level security;

drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders for select using (auth.uid() is not null);

drop policy if exists orders_insert on public.orders;
create policy orders_insert on public.orders for insert
with check (false);

drop policy if exists orders_update on public.orders;
create policy orders_update on public.orders for update using (false);
drop policy if exists orders_delete on public.orders;
create policy orders_delete on public.orders for delete using (false);

-- Hanya RPC (security definer) yang boleh membuat / mengubah pesanan,
-- agar validasi akses & perhitungan total selalu konsisten.

-- Buat pesanan baru (belum mengurangi stock, belum masuk kas).
create or replace function public.create_order(p_product_id uuid, p_qty integer, p_keterangan text, p_customer_name text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare p record; n text; total numeric; order_id uuid;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'sales'=any(permissions))) then raise exception 'Anda tidak memiliki akses penjualan.'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Jumlah pesanan minimal 1.'; end if;
  select * into p from public.products where id=p_product_id;
  if p.id is null then raise exception 'Produk tidak ditemukan.'; end if;
  total := coalesce(p.price,0) * p_qty;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  insert into public.orders(product_id,product_name,qty,price,total,customer_name,keterangan,status,created_by,created_by_name)
  values(p.id,p.name,p_qty,p.price,total,nullif(trim(coalesce(p_customer_name,'')),''),nullif(trim(coalesce(p_keterangan,'')),''),'pending',auth.uid(),n)
  returning id into order_id;
  return order_id;
end; $$;

grant execute on function public.create_order(uuid,integer,text,text) to authenticated;

-- Selesaikan pesanan: atomic cek stock -> kurangi stock -> catat penjualan -> tambah kas -> tandai pesanan selesai.
create or replace function public.complete_order(p_order_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare o record; p record; n text; sale_id uuid;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'sales'=any(permissions))) then raise exception 'Anda tidak memiliki akses penjualan.'; end if;
  select * into o from public.orders where id=p_order_id for update;
  if o.id is null then raise exception 'Pesanan tidak ditemukan.'; end if;
  if o.status <> 'pending' then raise exception 'Pesanan sudah % dan tidak dapat diselesaikan lagi.', o.status; end if;
  if o.product_id is null then raise exception 'Produk pesanan tidak valid.'; end if;
  select * into p from public.products where id=o.product_id for update;
  if p.id is null then raise exception 'Produk tidak ditemukan.'; end if;
  if p.stock < o.qty then raise exception 'Stock % tidak cukup. Butuh %, tersedia %.', p.name, o.qty, p.stock; end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  update public.products set stock=stock-o.qty where id=p.id;
  insert into public.sales(product_id,product_name,qty,total,cashier_id,cashier_name)
  values(p.id,p.name,o.qty,o.total,auth.uid(),n) returning id into sale_id;
  insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name)
  values('sale',o.total,format('Pesanan %s x%s%s',p.name,o.qty,case when o.keterangan is not null then ' - '||o.keterangan else '' end),sale_id,auth.uid(),n);
  update public.orders set status='selesai',completed_at=now(),completed_by=auth.uid(),completed_by_name=n,sale_id=sale_id where id=o.id;
  return format('Pesanan %s x%s berhasil diselesaikan.',p.name,o.qty);
end; $$;

grant execute on function public.complete_order(uuid) to authenticated;

-- Batalkan pesanan yang masih pending (tidak mempengaruhi stock/kas).
create or replace function public.cancel_order(p_order_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare o record; n text;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  select * into o from public.orders where id=p_order_id for update;
  if o.id is null then raise exception 'Pesanan tidak ditemukan.'; end if;
  if o.status <> 'pending' then raise exception 'Pesanan sudah % dan tidak dapat dibatalkan.', o.status; end if;
  if not (public.is_admin() or o.created_by=auth.uid() or exists(select 1 from public.profiles where id=auth.uid() and 'sales'=any(permissions))) then raise exception 'Anda tidak memiliki akses untuk membatalkan pesanan ini.'; end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  update public.orders set status='batal',completed_at=now(),completed_by=auth.uid(),completed_by_name=n where id=o.id;
  return 'Pesanan dibatalkan.';
end; $$;

grant execute on function public.cancel_order(uuid) to authenticated;


-- ==============================
-- HARGA BAHAN & PEMBELIAN BAHAN (BRANGKAS ESPORT)
-- Setiap bahan sekarang punya harga acuan (bisa diubah dari menu Bahan & Crafting).
-- Sistem pembelian bahan: harga per pembelian bisa disesuaikan (tidak harus sama
-- dengan harga acuan), otomatis menambah stock bahan DAN otomatis mengurangi kas
-- (tercatat sebagai transaksi 'purchase' di Pembukuan & Kas).
alter table public.materials add column if not exists price numeric(14,2) not null default 0;

-- Perluas jenis transaksi pembukuan agar mencakup pembelian bahan.
alter table public.finance_transactions drop constraint if exists finance_transactions_transaction_type_check;
alter table public.finance_transactions add constraint finance_transactions_transaction_type_check
  check (transaction_type in ('deposit','withdraw','sale','purchase'));

-- Pembelian bahan: atomic cek kas -> kurangi kas -> tambah stock bahan -> update harga acuan.
create or replace function public.purchase_material(p_material_id uuid, p_qty integer, p_price numeric, p_description text default null)
returns text language plpgsql security definer set search_path=public as $$
declare m record; n text; total numeric; current_cash numeric;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'products'=any(permissions))) then raise exception 'Anda tidak memiliki akses bahan.'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Jumlah pembelian minimal 1.'; end if;
  if p_price is null or p_price < 0 then raise exception 'Harga tidak boleh negatif.'; end if;
  select * into m from public.materials where id=p_material_id for update;
  if m.id is null then raise exception 'Bahan tidak ditemukan.'; end if;
  total := p_price * p_qty;
  if total > 0 then
    select coalesce(sum(case when transaction_type in ('sale','deposit') then amount else -amount end),0) into current_cash from public.finance_transactions;
    if total > current_cash then raise exception 'Kas tidak cukup untuk pembelian ini. Kas tersedia %, dibutuhkan %.', current_cash, total; end if;
  end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  update public.materials set stock=stock+p_qty, price=p_price where id=m.id;
  if total > 0 then
    insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name)
    values('purchase',total,coalesce(nullif(trim(p_description),''),format('Pembelian bahan %s x%s @ %s',m.name,p_qty,p_price)),m.id,auth.uid(),n);
  end if;
  return format('Pembelian %s x%s berhasil. Stock sekarang %s.',m.name,p_qty,m.stock+p_qty);
end; $$;

grant execute on function public.purchase_material(uuid,integer,numeric,text) to authenticated;


-- ==============================
-- PENGGAJIAN (PAYROLL / SLIP GAJI) BRANGKAS ESPORT
-- Slip gaji dibuat berstatus draft, lalu saat ditekan BAYAR, sistem otomatis
-- mengecek kas, mencatat pengeluaran gaji ke Pembukuan & Kas, dan menandai
-- slip sebagai sudah dibayar.
alter table public.finance_transactions drop constraint if exists finance_transactions_transaction_type_check;
alter table public.finance_transactions add constraint finance_transactions_transaction_type_check
  check (transaction_type in ('deposit','withdraw','sale','purchase','payroll'));

create table if not exists public.payroll_slips (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid references public.profiles(id) on delete set null,
  employee_name text not null,
  position text,
  period text not null,
  base_salary numeric(14,2) not null default 0,
  allowance numeric(14,2) not null default 0,
  bonus numeric(14,2) not null default 0,
  deduction numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  notes text,
  status text not null default 'draft' check (status in ('draft','paid','batal')),
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now(),
  paid_by uuid references public.profiles(id) on delete set null,
  paid_by_name text,
  paid_at timestamptz,
  finance_reference_id uuid references public.finance_transactions(id) on delete set null
);

create index if not exists payroll_slips_status_idx on public.payroll_slips(status);
create index if not exists payroll_slips_period_idx on public.payroll_slips(period);
create index if not exists payroll_slips_employee_idx on public.payroll_slips(employee_id);

alter table public.payroll_slips enable row level security;

-- Karyawan boleh melihat slip miliknya sendiri; admin/pemegang akses payroll lihat semua.
drop policy if exists payroll_select on public.payroll_slips;
create policy payroll_select on public.payroll_slips for select
using (
  employee_id = auth.uid()
  or public.is_admin()
  or exists(select 1 from public.profiles where id=auth.uid() and 'payroll'=any(permissions))
);

-- Hanya RPC (security definer) yang boleh membuat/mengubah slip.
drop policy if exists payroll_insert on public.payroll_slips;
create policy payroll_insert on public.payroll_slips for insert with check (false);
drop policy if exists payroll_update on public.payroll_slips;
create policy payroll_update on public.payroll_slips for update using (false);
drop policy if exists payroll_delete on public.payroll_slips;
create policy payroll_delete on public.payroll_slips for delete using (false);

-- Buat slip gaji baru berstatus draft (belum memotong kas).
create or replace function public.create_payroll_slip(
  p_employee_id uuid, p_period text, p_base_salary numeric,
  p_allowance numeric default 0, p_bonus numeric default 0,
  p_deduction numeric default 0, p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare e record; n text; total numeric; slip_id uuid;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'payroll'=any(permissions))) then raise exception 'Anda tidak memiliki akses penggajian.'; end if;
  if coalesce(trim(p_period),'')='' then raise exception 'Periode wajib diisi.'; end if;
  if p_base_salary is null or p_base_salary < 0 then raise exception 'Gaji pokok tidak boleh negatif.'; end if;
  if coalesce(p_allowance,0) < 0 or coalesce(p_bonus,0) < 0 or coalesce(p_deduction,0) < 0 then raise exception 'Nominal tidak boleh negatif.'; end if;
  select * into e from public.profiles where id=p_employee_id;
  if e.id is null then raise exception 'Karyawan tidak ditemukan.'; end if;
  total := p_base_salary + coalesce(p_allowance,0) + coalesce(p_bonus,0) - coalesce(p_deduction,0);
  if total < 0 then raise exception 'Total gaji tidak boleh negatif. Periksa kembali potongan.'; end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  insert into public.payroll_slips(employee_id,employee_name,position,period,base_salary,allowance,bonus,deduction,total,notes,status,created_by,created_by_name)
  values(e.id,coalesce(e.full_name,e.email),e.position,trim(p_period),p_base_salary,coalesce(p_allowance,0),coalesce(p_bonus,0),coalesce(p_deduction,0),total,nullif(trim(coalesce(p_notes,'')),''),'draft',auth.uid(),n)
  returning id into slip_id;
  return slip_id;
end; $$;

grant execute on function public.create_payroll_slip(uuid,text,numeric,numeric,numeric,numeric,text) to authenticated;

-- Bayar slip gaji: atomic cek kas -> catat pengeluaran gaji -> tandai slip dibayar.
create or replace function public.pay_payroll_slip(p_slip_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare s record; n text; current_cash numeric; fin_id uuid;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'payroll'=any(permissions))) then raise exception 'Anda tidak memiliki akses penggajian.'; end if;
  select * into s from public.payroll_slips where id=p_slip_id for update;
  if s.id is null then raise exception 'Slip gaji tidak ditemukan.'; end if;
  if s.status <> 'draft' then raise exception 'Slip sudah % dan tidak dapat dibayar lagi.', s.status; end if;
  if s.total > 0 then
    select coalesce(sum(case when transaction_type in ('sale','deposit') then amount else -amount end),0) into current_cash from public.finance_transactions;
    if s.total > current_cash then raise exception 'Kas tidak cukup untuk membayar gaji ini. Kas tersedia %, dibutuhkan %.', current_cash, s.total; end if;
  end if;
  select coalesce(full_name,'Pegawai') into n from public.profiles where id=auth.uid();
  if s.total > 0 then
    insert into public.finance_transactions(transaction_type,amount,description,reference_id,created_by,created_by_name)
    values('payroll',s.total,format('Gaji %s periode %s',s.employee_name,s.period),s.id,auth.uid(),n)
    returning id into fin_id;
  end if;
  update public.payroll_slips set status='paid',paid_at=now(),paid_by=auth.uid(),paid_by_name=n,finance_reference_id=fin_id where id=s.id;
  return format('Gaji %s periode %s berhasil dibayar.',s.employee_name,s.period);
end; $$;

grant execute on function public.pay_payroll_slip(uuid) to authenticated;

-- Batalkan slip yang masih draft.
create or replace function public.cancel_payroll_slip(p_slip_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare s record;
begin
  if auth.uid() is null then raise exception 'Anda belum login.'; end if;
  if not (public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and 'payroll'=any(permissions))) then raise exception 'Anda tidak memiliki akses penggajian.'; end if;
  select * into s from public.payroll_slips where id=p_slip_id for update;
  if s.id is null then raise exception 'Slip gaji tidak ditemukan.'; end if;
  if s.status <> 'draft' then raise exception 'Slip sudah % dan tidak dapat dibatalkan.', s.status; end if;
  update public.payroll_slips set status='batal' where id=s.id;
  return 'Slip gaji dibatalkan.';
end; $$;

grant execute on function public.cancel_payroll_slip(uuid) to authenticated;
