-- nakolog: 個人トーク申請の重複防止・受信側に申請を表示する修正
-- Supabase Dashboard > SQL Editor で全体を一度実行してください。

-- 1) すでにある同じ2人間の重複申請を整理する（acceptedを優先、同じ状態なら新しいものを残す）
with ranked as (
  select id,
         row_number() over (
           partition by least(requester_id, recipient_id), greatest(requester_id, recipient_id)
           order by (status = 'accepted') desc, created_at desc, id
         ) as rn
  from public.direct_chat_requests
  where status in ('pending','accepted')
)
delete from public.direct_chat_requests r
using ranked d
where r.id = d.id and d.rn > 1;

-- 2) 同じ2人の有効な申請が複数できないようにする
create unique index if not exists direct_chat_requests_one_active_pair_idx
on public.direct_chat_requests (
  least(requester_id, recipient_id),
  greatest(requester_id, recipient_id)
)
where status in ('pending','accepted');

-- 3) 申請の作成を安全に一本化（連打・同時申請でも既存申請を返す）
create or replace function public.request_direct_chat(target_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  req_id uuid;
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'ログインしてください'; end if;
  if target_user is null or uid = target_user then raise exception '自分自身には個人トーク申請を送れません'; end if;
  if not exists (select 1 from public.profiles where id = target_user) then raise exception 'ユーザーが見つかりません'; end if;

  -- 同じ2人の処理を直列化
  perform pg_advisory_xact_lock(hashtextextended(least(uid::text, target_user::text) || ':' || greatest(uid::text, target_user::text), 0));

  select id into req_id
  from public.direct_chat_requests
  where ((requester_id = uid and recipient_id = target_user)
      or (requester_id = target_user and recipient_id = uid))
    and status in ('pending','accepted')
  order by (status = 'accepted') desc, created_at desc
  limit 1;

  if req_id is not null then return req_id; end if;

  insert into public.direct_chat_requests(requester_id, recipient_id, requester_approved, recipient_approved, status)
  values (uid, target_user, false, false, 'pending')
  returning id into req_id;
  return req_id;
end;
$$;

grant execute on function public.request_direct_chat(uuid) to authenticated;

-- 4) 送信者と受信者の両方が申請を読めるRLSを明示的に設定
alter table public.direct_chat_requests enable row level security;
drop policy if exists "Participants can read requests" on public.direct_chat_requests;
create policy "Participants can read requests"
on public.direct_chat_requests for select to authenticated
using (auth.uid() = requester_id or auth.uid() = recipient_id);

-- 5) 申請が作られたら相手の画面にもリアルタイム通知する
-- すでにpublicationに入っている場合はそのままスキップ
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'direct_chat_requests'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.direct_chat_requests;
  END IF;
END $$;
