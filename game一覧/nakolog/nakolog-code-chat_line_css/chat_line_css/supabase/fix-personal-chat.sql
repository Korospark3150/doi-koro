-- 個人トーク申請・相互承認の修正
-- Supabase SQL Editor で一度実行してください。
-- 既存テーブルに updated_at がない環境でも動くように補完します。
alter table public.direct_chat_requests
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.request_direct_chat(target_user uuid)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare req_id uuid;
begin
  if auth.uid() is null then raise exception 'ログインしてください'; end if;
  if target_user is null or auth.uid() = target_user then raise exception '自分自身には個人トーク申請を送れません'; end if;
  if not exists (select 1 from public.profiles where id = target_user) then raise exception 'ユーザーが見つかりません'; end if;
  select id into req_id from public.direct_chat_requests
   where ((requester_id = auth.uid() and recipient_id = target_user) or (requester_id = target_user and recipient_id = auth.uid()))
   and status in ('pending','accepted') order by created_at desc limit 1;
  if req_id is not null then return req_id; end if;
  insert into public.direct_chat_requests(requester_id, recipient_id, requester_approved, recipient_approved, status)
  values (auth.uid(), target_user, false, false, 'pending') returning id into req_id;
  return req_id;
end; $$;

create or replace function public.approve_direct_chat_request(request_id uuid)
returns text language plpgsql security definer set search_path = public, auth as $$
declare r public.direct_chat_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'ログインしてください'; end if;
  select * into r from public.direct_chat_requests where id = request_id for update;
  if not found then raise exception '申請が見つかりません'; end if;
  if auth.uid() not in (r.requester_id, r.recipient_id) then raise exception 'この申請を承認できません'; end if;
  if r.status = 'rejected' then raise exception 'この申請は断られています'; end if;
  if auth.uid() = r.requester_id then
    update public.direct_chat_requests set requester_approved = true, updated_at = now() where id = request_id returning * into r;
  else
    update public.direct_chat_requests set recipient_approved = true, updated_at = now() where id = request_id returning * into r;
  end if;
  if r.requester_approved and r.recipient_approved then
    update public.direct_chat_requests set status = 'accepted', updated_at = now() where id = request_id;
    return 'accepted';
  end if;
  return 'pending';
end; $$;

create or replace function public.reject_direct_chat_request(request_id uuid)
returns text language plpgsql security definer set search_path = public, auth as $$
declare r public.direct_chat_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'ログインしてください'; end if;
  select * into r from public.direct_chat_requests where id = request_id for update;
  if not found then raise exception '申請が見つかりません'; end if;
  if auth.uid() <> r.recipient_id then raise exception '申請を断れるのは受信した相手だけです'; end if;
  if r.status = 'accepted' then raise exception '承認済みのトークは断れません'; end if;
  update public.direct_chat_requests set status = 'rejected', updated_at = now() where id = request_id;
  return 'rejected';
end; $$;

grant execute on function public.request_direct_chat(uuid) to authenticated;
grant execute on function public.approve_direct_chat_request(uuid) to authenticated;
grant execute on function public.reject_direct_chat_request(uuid) to authenticated;

drop policy if exists "Users can send direct messages as themselves" on public.direct_messages;
create policy "Users can send direct messages as themselves" on public.direct_messages for insert to authenticated
with check (auth.uid() = sender_id and sender_id <> recipient_id and exists (
  select 1 from public.direct_chat_requests r where r.status = 'accepted' and r.requester_approved and r.recipient_approved
  and ((r.requester_id = sender_id and r.recipient_id = recipient_id) or (r.requester_id = recipient_id and r.recipient_id = sender_id))
));
drop policy if exists "Users can read their direct messages" on public.direct_messages;
create policy "Users can read their direct messages" on public.direct_messages for select to authenticated
using ((auth.uid() = sender_id or auth.uid() = recipient_id) and exists (
  select 1 from public.direct_chat_requests r where r.status = 'accepted' and r.requester_approved and r.recipient_approved
  and ((r.requester_id = sender_id and r.recipient_id = recipient_id) or (r.requester_id = recipient_id and r.recipient_id = sender_id))
));
