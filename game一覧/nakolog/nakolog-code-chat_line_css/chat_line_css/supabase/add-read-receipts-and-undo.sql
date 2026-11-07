-- 個人トーク追加機能（既読・送信取り消し）
-- Supabase SQL Editor で一度だけ実行してください。既存データは削除しません。
alter table public.direct_messages add column if not exists read_at timestamptz;

-- 受信者が自分宛てメッセージの read_at だけを更新できるポリシー
drop policy if exists "Recipients can mark direct messages read" on public.direct_messages;
create policy "Recipients can mark direct messages read" on public.direct_messages
for update to authenticated using (auth.uid() = recipient_id)
with check (auth.uid() = recipient_id);

-- 送信者本人だけが自分のメッセージを取り消せる
drop policy if exists "Senders can delete their direct messages" on public.direct_messages;
create policy "Senders can delete their direct messages" on public.direct_messages
for delete to authenticated using (auth.uid() = sender_id);

grant update (read_at) on public.direct_messages to authenticated;
grant delete on public.direct_messages to authenticated;
