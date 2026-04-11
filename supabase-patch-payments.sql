-- ═══════════════════════════════════════════════════════════════════
-- PAYMENT PATCH — run this against your live Supabase database
-- ═══════════════════════════════════════════════════════════════════
-- Paste the WHOLE file into the Supabase SQL editor and Run.
-- Safe to re-run; every statement is idempotent.
-- This patch gives you:
--   1. paid_at / paid_by columns on booking_requests
--   2. Mock venmo/zelle app_config rows (replace with real values later)
--   3. Rewritten dal_notify_client_of_decision:
--        - Venmo button with amount pre-filled (no reference copy-paste)
--        - Zelle card with clean identifier + "open your bank" copy
--        - Reference callout removed
--   4. dal_notify_client_of_payment (fires "You're all set" email)
--   5. dal_list_awaiting_payment (admin queue fetch)
--   6. dal_mark_booking_paid (admin action)
--   7. dal_cancel_booking_request (admin cancel + frees calendar dates)
--   8. Grants for anon/authenticated

-- 1. Columns + index
alter table public.booking_requests add column if not exists paid_at timestamptz;
alter table public.booking_requests add column if not exists paid_by text;
create index if not exists booking_requests_paid_idx
  on public.booking_requests(paid_at)
  where paid_at is null;

-- 2. Mock app_config rows. REPLACE the right-hand values with real
-- Venmo + Zelle info when your accounts are registered. These values
-- should live ONLY in Supabase — never commit the real ones to git.
insert into public.app_config(key, value) values
  ('venmo_handle',       'dogsandllamas'),
  ('zelle_display',      'dogsandllamasservice@gmail.com'),
  ('zelle_display_type', 'email')
on conflict (key) do update set value = excluded.value;

-- 3. Updated dal_notify_client_of_decision — Venmo/Zelle payment cards,
-- no reference code clutter. Simplified Venmo note = "Dog's stay with
-- Dogs & Llamas" so the client doesn't have to copy anything.
create or replace function public.dal_notify_client_of_decision(
  v_req     public.booking_requests,
  p_action  text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sender_email     text;
  v_sender_name      text;
  v_fn_url           text;
  v_fn_secret        text;
  v_pgnet_ok         boolean;
  v_subject          text;
  v_html             text;
  v_payload          jsonb;
  v_service_label    text;
  v_unit_price       integer;
  v_unit_label       text;
  v_quantity         integer;
  v_total            integer;
  v_total_line       text;
  v_venmo_handle     text;
  v_zelle_display    text;
  v_zelle_type       text;
  v_venmo_url        text;
  v_venmo_block      text;
  v_zelle_block      text;
  v_zelle_label      text;
  v_schedule_url     text := 'https://llllamas.github.io/Dog-Newsletter-and-Store/schedule.html';
begin
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('net','extensions') and p.proname = 'http_post'
  ) into v_pgnet_ok;
  if not v_pgnet_ok then return; end if;

  select value into v_sender_email from public.app_config where key = 'sender_email';
  select value into v_sender_name  from public.app_config where key = 'sender_name';
  select value into v_fn_url       from public.app_config where key = 'email_fn_url';
  select value into v_fn_secret    from public.app_config where key = 'email_fn_secret';
  select value into v_venmo_handle  from public.app_config where key = 'venmo_handle';
  select value into v_zelle_display from public.app_config where key = 'zelle_display';
  select value into v_zelle_type    from public.app_config where key = 'zelle_display_type';
  if v_fn_url is null or v_fn_secret is null or v_req.client_email is null then
    return;
  end if;

  v_service_label := case lower(coalesce(v_req.service, ''))
    when 'boarding'     then 'Overnight boarding'
    when 'daycare'      then 'Daycare'
    when 'dropin'       then 'Drop-in visit'
    when 'walking'      then 'Dog walk'
    when 'housesitting' then 'House-sitting'
    else coalesce(initcap(v_req.service), '—')
  end;

  case lower(coalesce(v_req.service, ''))
    when 'boarding' then
      v_unit_price := 90;  v_unit_label := 'night'; v_quantity := greatest(v_req.end_date - v_req.start_date, 1);
    when 'housesitting' then
      v_unit_price := 100; v_unit_label := 'night'; v_quantity := greatest(v_req.end_date - v_req.start_date, 1);
    when 'daycare' then
      v_unit_price := 50;  v_unit_label := 'day';   v_quantity := (v_req.end_date - v_req.start_date) + 1;
    when 'dropin' then
      v_unit_price := 45;  v_unit_label := 'visit'; v_quantity := (v_req.end_date - v_req.start_date) + 1;
    when 'walking' then
      v_unit_price := 25;  v_unit_label := 'walk';  v_quantity := (v_req.end_date - v_req.start_date) + 1;
    else
      v_unit_price := 0;   v_unit_label := '';      v_quantity := 0;
  end case;
  v_total := v_unit_price * v_quantity;

  if v_total > 0 then
    v_total_line :=
      $H$<tr><td style="padding:10px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Total</td><td style="padding:10px 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:18px;color:#1B4F8C;font-weight:700;">&#36;$H$
      || v_total::text
      || $H$<span style="display:block;font-size:12px;font-weight:500;color:#8C94B0;margin-top:2px;">$H$
      || v_quantity::text
      || $H$ $H$ || v_unit_label || case when v_quantity = 1 then '' else 's' end
      || $H$ &times; &#36;$H$ || v_unit_price::text || $H$/$H$ || v_unit_label || $H$</span></td></tr>$H$;
  else
    v_total_line := '';
  end if;

  -- Venmo deep-link: pre-fills amount + friendly note (dog name).
  -- The client just taps the button — no copying required.
  if v_venmo_handle is not null and length(trim(v_venmo_handle)) > 0 then
    v_venmo_url :=
      'https://venmo.com/' || v_venmo_handle
      || '?txn=pay'
      || '&amount=' || coalesce(v_total, 0)::text
      || '&note=' || replace(
                       replace(
                         coalesce(v_req.dog_name, 'Dog') || $Z$'s stay with Dogs & Llamas$Z$,
                         ' ', '%20'),
                       '&', '%26');
    v_venmo_block :=
      $H$<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 12px;background-color:#FFFFFF;border:1.5px solid #E4EAFA;border-left:4px solid #D4A017;border-radius:8px;"><tr><td style="padding:18px 20px;font-family:Arial,Helvetica,sans-serif;"><p style="margin:0 0 4px;font-size:10px;font-weight:bold;letter-spacing:1.4px;text-transform:uppercase;color:#D4A017;">Option 1 &middot; Venmo</p><p style="margin:0 0 14px;font-size:17px;font-weight:700;color:#1A1D26;">@$H$
      || v_venmo_handle
      || $H$</p><p style="margin:0 0 14px;font-size:13px;color:#4C5470;line-height:1.55;">Tap the button below &mdash; it opens the Venmo app (or venmo.com) with the amount and reference pre-filled.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0"><tr><td><a href="$H$
      || v_venmo_url
      || $H$" style="display:inline-block;background-color:#3D95CE;background-image:linear-gradient(150deg,#3D95CE 0%,#2775C9 100%);color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;text-decoration:none;padding:12px 26px;border-radius:99px;letter-spacing:0.3px;">Pay &#36;$H$
      || v_total::text
      || $H$ on Venmo &rarr;</a></td></tr></table></td></tr></table>$H$;
  else
    v_venmo_block := '';
  end if;

  -- Zelle: identifier + "open your bank" copy. No reference-code ask.
  if v_zelle_display is not null and length(trim(v_zelle_display)) > 0 then
    v_zelle_label := case lower(coalesce(v_zelle_type, 'email'))
      when 'phone' then 'Phone number'
      else 'Email'
    end;
    v_zelle_block :=
      $H$<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 12px;background-color:#FFFFFF;border:1.5px solid #E4EAFA;border-left:4px solid #1B4F8C;border-radius:8px;"><tr><td style="padding:18px 20px;font-family:Arial,Helvetica,sans-serif;"><p style="margin:0 0 4px;font-size:10px;font-weight:bold;letter-spacing:1.4px;text-transform:uppercase;color:#1B4F8C;">Option 2 &middot; Zelle</p><p style="margin:0 0 10px;font-size:11px;font-weight:600;letter-spacing:0.3px;color:#8C94B0;text-transform:uppercase;">$H$
      || v_zelle_label
      || $H$</p><p style="margin:0 0 12px;font-size:17px;font-weight:700;color:#1A1D26;word-break:break-all;">$H$
      || v_zelle_display
      || $H$</p><p style="margin:0;font-size:13px;color:#4C5470;line-height:1.55;">Open your bank&rsquo;s app and send <strong>&#36;$H$
      || v_total::text
      || $H$</strong> via Zelle to the address above. No account setup needed on our end &mdash; we&rsquo;ll see it land right away.</p></td></tr></table>$H$;
  else
    v_zelle_block := '';
  end if;

  if p_action = 'approve' then
    v_subject := 'Almost there — complete payment to confirm your stay';
    v_html :=
      $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>Almost confirmed</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Lorenzo approved your booking for $H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$ &mdash; one last step: complete payment to lock it in.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Almost Confirmed</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">One last step &mdash; complete payment to lock it in</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi $H$
      || coalesce(v_req.client_name, 'there')
      || $H$,</p><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Lorenzo has <strong>approved</strong> your booking request for <strong>$H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$</strong> &mdash; you&rsquo;re almost set! One last step: complete payment using the link below, and we&rsquo;ll send a final confirmation as soon as it clears.</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Booking Summary</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;border-left:4px solid #D4A017;"><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;width:92px;vertical-align:top;">Service</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || v_service_label
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dog</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(v_req.dog_name, '—')
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dates</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
      || $H$ &nbsp;&rarr;&nbsp; $H$
      || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Drop-off</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.drop_off, 'FMHH12:MI AM'), '—')
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Pick-up</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.pick_up, 'FMHH12:MI AM'), '—')
      || $H$</td></tr>$H$
      || v_total_line
      || $H$</table><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">How to Pay</p><p style="margin:0 0 16px;font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.65;color:#4C5470;">Pick whichever you&rsquo;re already set up for &mdash; Venmo or Zelle. Either one locks in your booking the moment Lorenzo sees it land.</p>$H$
      || v_venmo_block
      || v_zelle_block
      || $H$<p style="margin:16px 0 20px;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#8C94B0;text-align:center;line-height:1.55;font-style:italic;">That&rsquo;s all &mdash; pick whichever is easier for you and we&rsquo;ll take it from there.</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">What Happens Next</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;"><tr><td style="padding:18px 22px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1A1D26;line-height:1.7;"><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">1.</strong> &nbsp;<strong>Send payment</strong> via Venmo or Zelle above &mdash; your dates are held while we wait for it.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">2.</strong> &nbsp;As soon as Lorenzo sees the payment land, you&rsquo;ll get a <strong>final confirmation email</strong> with the address and drop-off details.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">3.</strong> &nbsp;Reply to either email with anything Lorenzo should know &mdash; feeding schedule, meds, routines, quirks.</p><p style="margin:0;"><strong style="color:#1B4F8C;">4.</strong> &nbsp;Bring food, leash, and any comfort item &mdash; we&rsquo;ll handle the rest.</p></td></tr></table><p style="margin:0 0 4px;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;line-height:1.7;">Can&rsquo;t wait to host $H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$!</p><p style="margin:0 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;
  else
    v_subject := 'About your booking request with Dogs & Llamas';
    v_html :=
      $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>About your booking request</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Sorry &mdash; Lorenzo isn&rsquo;t able to take this booking. Try another window?</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Booking Update</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">About your recent request</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi $H$
      || coalesce(v_req.client_name, 'there')
      || $H$,</p><p style="margin:0 0 20px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Thank you so much for reaching out about <strong>$H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$</strong>. Unfortunately Lorenzo isn&rsquo;t able to take this booking &mdash; we&rsquo;re genuinely sorry to miss it.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;border-left:4px solid #D4A017;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#4C5470;line-height:1.6;"><p style="margin:0 0 4px;font-size:11px;font-weight:bold;letter-spacing:0.8px;text-transform:uppercase;color:#8C94B0;">Requested Window</p><p style="margin:0;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
      || $H$ &nbsp;&rarr;&nbsp; $H$
      || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
      || $H$</p></td></tr></table><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Please feel free to check the calendar again and request another window &mdash; we&rsquo;d love to host $H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$ on a different date.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 10px;"><tr><td align="center"><a href="$H$
      || v_schedule_url
      || $H$" style="display:inline-block;background-color:#1B4F8C;background-image:linear-gradient(150deg,#1B4F8C 0%,#2B6CB0 100%);color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;text-decoration:none;padding:14px 32px;border-radius:99px;letter-spacing:0.5px;">Check other dates &rarr;</a></td></tr></table><p style="margin:24px 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;
  end if;

  v_payload := jsonb_build_object(
    'sender',  jsonb_build_object('name', coalesce(v_sender_name, 'Dogs & Llamas'),
                                   'email', coalesce(v_sender_email, 'no-reply@dogsandllamas.com')),
    'to',      jsonb_build_array(jsonb_build_object('email', v_req.client_email,
                                                    'name',  coalesce(v_req.client_name, ''))),
    'subject', v_subject,
    'htmlContent', v_html
  );

  begin
    perform net.http_post(
      url     := v_fn_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-edge-secret', v_fn_secret),
      body    := v_payload
    );
  exception when others then
    raise warning 'dal_notify_client_of_decision: edge POST failed: %', SQLERRM;
  end;
end;
$$;

revoke all on function public.dal_notify_client_of_decision(public.booking_requests, text) from anon, authenticated;


-- 4. dal_notify_client_of_payment — fires the "You're all set" email
create or replace function public.dal_notify_client_of_payment(
  v_req public.booking_requests
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sender_email  text;
  v_sender_name   text;
  v_fn_url        text;
  v_fn_secret     text;
  v_pgnet_ok      boolean;
  v_subject       text;
  v_html          text;
  v_payload       jsonb;
  v_service_label text;
begin
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('net','extensions') and p.proname = 'http_post'
  ) into v_pgnet_ok;
  if not v_pgnet_ok then return; end if;

  select value into v_sender_email from public.app_config where key = 'sender_email';
  select value into v_sender_name  from public.app_config where key = 'sender_name';
  select value into v_fn_url       from public.app_config where key = 'email_fn_url';
  select value into v_fn_secret    from public.app_config where key = 'email_fn_secret';
  if v_fn_url is null or v_fn_secret is null or v_req.client_email is null then
    return;
  end if;

  v_service_label := case lower(coalesce(v_req.service, ''))
    when 'boarding'     then 'Overnight boarding'
    when 'daycare'      then 'Daycare'
    when 'dropin'       then 'Drop-in visit'
    when 'walking'      then 'Dog walk'
    when 'housesitting' then 'House-sitting'
    else coalesce(initcap(v_req.service), '—')
  end;

  v_subject := 'You''re all set! Your stay with Dogs & Llamas is confirmed';

  v_html :=
    $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>Booking confirmed</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Payment received &mdash; $H$
    || coalesce(v_req.dog_name, 'your dog')
    || $H$&rsquo;s stay with Dogs &amp; Llamas is fully confirmed.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Booking Confirmed</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">You&rsquo;re all set &mdash; we can&rsquo;t wait to meet $H$
    || coalesce(v_req.dog_name, 'your pup')
    || $H$</p></td></tr><tr><td style="padding:36px 40px 8px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;"><tr><td align="center"><div style="display:inline-block;width:68px;height:68px;border-radius:50%;background-image:linear-gradient(150deg,#D4A017 0%,#b8880f 100%);color:#ffffff;font-size:36px;line-height:68px;font-weight:bold;text-align:center;box-shadow:0 6px 22px rgba(212,160,23,0.35);">&#10003;</div></td></tr></table><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;text-align:center;">Hi $H$
    || coalesce(v_req.client_name, 'there')
    || $H$,</p><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;text-align:center;">Your payment came through &mdash; <strong>$H$
    || coalesce(v_req.dog_name, 'your dog')
    || $H$&rsquo;s</strong> stay with us is officially on the books. We&rsquo;re so excited!</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Confirmed Booking</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;border-left:4px solid #D4A017;"><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;width:92px;vertical-align:top;">Service</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || v_service_label
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dog</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(v_req.dog_name, '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dates</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
    || $H$ &nbsp;&rarr;&nbsp; $H$
    || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Drop-off</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.drop_off, 'FMHH12:MI AM'), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Pick-up</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.pick_up, 'FMHH12:MI AM'), '—')
    || $H$</td></tr></table><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Before You Drop Off</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;"><tr><td style="padding:18px 22px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1A1D26;line-height:1.7;"><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Lorenzo will reach out the day before drop-off with the address and any last-minute details.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Reply to this email with anything we should know &mdash; feeding schedule, meds, routines, quirks.</p><p style="margin:0;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Bring food, leash, and any comfort item. We&rsquo;ll handle the rest.</p></td></tr></table><p style="margin:0 0 4px;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;line-height:1.7;text-align:center;">Thank you for trusting us with $H$
    || coalesce(v_req.dog_name, 'your dog')
    || $H$!</p><p style="margin:0 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;text-align:center;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;

  v_payload := jsonb_build_object(
    'sender',  jsonb_build_object('name', coalesce(v_sender_name, 'Dogs & Llamas'),
                                   'email', coalesce(v_sender_email, 'no-reply@dogsandllamas.com')),
    'to',      jsonb_build_array(jsonb_build_object('email', v_req.client_email,
                                                    'name',  coalesce(v_req.client_name, ''))),
    'subject', v_subject,
    'htmlContent', v_html
  );

  begin
    perform net.http_post(
      url     := v_fn_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-edge-secret', v_fn_secret),
      body    := v_payload
    );
  exception when others then
    raise warning 'dal_notify_client_of_payment: edge POST failed: %', SQLERRM;
  end;
end;
$$;

revoke all on function public.dal_notify_client_of_payment(public.booking_requests) from anon, authenticated;


-- 5. dal_list_awaiting_payment — admin queue fetch
drop function if exists public.dal_list_awaiting_payment(text);

create or replace function public.dal_list_awaiting_payment(p_pin text)
returns setof public.booking_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_pin text := '1234';
begin
  if p_pin is null or p_pin <> v_admin_pin then
    return;
  end if;
  return query
    select *
    from public.booking_requests
    where status = 'approved'
      and paid_at is null
    order by decided_at desc nulls last, created_at desc;
end;
$$;

comment on function public.dal_list_awaiting_payment(text)
  is 'Admin-only: returns approved bookings that have not yet been marked paid.';


-- 6. dal_mark_booking_paid — flip approved → paid, fire confirmation email
drop function if exists public.dal_mark_booking_paid(text, uuid);

create or replace function public.dal_mark_booking_paid(
  p_pin text,
  p_id  uuid
)
returns public.booking_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_pin text := '1234';
  v_req       public.booking_requests;
begin
  if p_pin is null or p_pin <> v_admin_pin then
    raise exception 'unauthorized';
  end if;

  select * into v_req
    from public.booking_requests
    where id = p_id
    for update;

  if not found then
    raise exception 'booking % not found', p_id;
  end if;
  if v_req.status <> 'approved' then
    raise exception 'booking % is not approved (status=%)', p_id, v_req.status;
  end if;
  if v_req.paid_at is not null then
    return v_req;
  end if;

  update public.booking_requests
    set paid_at = now(),
        paid_by = 'owner'
    where id = p_id
    returning * into v_req;

  begin
    perform public.dal_notify_client_of_payment(v_req);
  exception when others then
    raise warning 'dal_mark_booking_paid: notify failed: %', SQLERRM;
  end;

  return v_req;
end;
$$;

comment on function public.dal_mark_booking_paid(text, uuid)
  is 'Admin-only: flips an approved booking to paid, fires the final confirmation email.';


-- 7. dal_cancel_booking_request — soft-cancel + free availability dates
drop function if exists public.dal_cancel_booking_request(text, uuid);

create or replace function public.dal_cancel_booking_request(
  p_pin text,
  p_id  uuid
)
returns public.booking_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_pin text := '1234';
  v_req       public.booking_requests;
  v_short     text;
begin
  if p_pin is null or p_pin <> v_admin_pin then
    raise exception 'unauthorized';
  end if;

  select * into v_req
    from public.booking_requests
    where id = p_id
    for update;

  if not found then
    raise exception 'booking % not found', p_id;
  end if;
  if v_req.status not in ('pending', 'approved') then
    raise exception 'booking % is already %, cannot cancel', p_id, v_req.status;
  end if;

  -- Free the calendar dates that dal_decide_booking_request locked in on approve.
  v_short := substring(v_req.id::text, 1, 8);
  delete from public.availability
    where day between v_req.start_date and v_req.end_date
      and notes = 'Booking #' || v_short;

  update public.booking_requests
    set status     = 'cancelled',
        decided_at = coalesce(decided_at, now()),
        decided_by = coalesce(decided_by, 'owner')
    where id = p_id
    returning * into v_req;

  return v_req;
end;
$$;

comment on function public.dal_cancel_booking_request(text, uuid)
  is 'Admin-only: soft-cancels a pending/approved booking and frees any locked calendar dates.';


-- 8. Grants
grant execute on function public.dal_list_awaiting_payment(text)        to anon, authenticated;
grant execute on function public.dal_mark_booking_paid(text, uuid)      to anon, authenticated;
grant execute on function public.dal_cancel_booking_request(text, uuid) to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- Verify the patch applied cleanly:
--
--   select column_name from information_schema.columns
--   where table_name = 'booking_requests' and column_name in ('paid_at','paid_by');
--   -- should return 2 rows
--
--   select proname from pg_proc where proname in (
--     'dal_notify_client_of_decision','dal_notify_client_of_payment',
--     'dal_list_awaiting_payment','dal_mark_booking_paid','dal_cancel_booking_request'
--   );
--   -- should return 5 rows
-- ═══════════════════════════════════════════════════════════════════
