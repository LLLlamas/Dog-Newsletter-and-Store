/*!
 * Dogs & Llamas — Subscriber & Personalization System v1.0
 * ─────────────────────────────────────────────────────────
 * What this does:
 *   1. Stores subscriber email + derived username in localStorage.
 *   2. Renders a "Hi, [username] 🐾" button in the nav (only when subscribed).
 *   3. Clicking it toggles personalized view on the current page.
 *   4. The username IS the discount code for Rover bookings.
 *   5. (Optional) Posts the email to your Mailchimp list — see CONFIG below.
 *
 * HOW TO CONNECT MAILCHIMP:
 *   a. Log in to Mailchimp → Audience → Signup forms → Embedded forms.
 *   b. Copy the form action URL (looks like:
 *      https://yourdomain.us1.list-manage.com/subscribe/post?u=XXXXX&id=XXXXX)
 *   c. Paste it as the value of CONFIG.mailchimpUrl below.
 *   d. That's it — this file handles the silent background POST.
 *
 * HOW TO UPGRADE TO SUPABASE:
 *   Replace the saveSubscriber() localStorage block with a Supabase insert:
 *     supabase.from('subscribers').insert({ email, username, dog_name })
 *   And replace getSubscriber() with a Supabase select query on page load.
 *   The rest of the UI code stays identical.
 *
 * DISCOUNT CODE LOGIC:
 *   username = email prefix before the @ sign (lowercased, stripped of symbols).
 *   Example: "jane.doe@gmail.com" → username "janedoe" → discount code "JANEDOE"
 *   Lorenzo & Catalina apply the code manually on Rover when booking is confirmed.
 */

/* global DAL */
(function (DAL) {
  'use strict';

  /* ── CONFIG ─────────────────────────────────────────────── */
  var CONFIG = {
    storageKey: 'dal_subscriber',

    /*
     * MAILCHIMP: paste your list's embedded-form action URL here.
     * Leave null to skip the Mailchimp POST (still saves locally).
     * Example: 'https://yoursite.us1.list-manage.com/subscribe/post?u=abc123&id=def456'
     */
    mailchimpUrl: null
  };

  /* ── SAFE STORAGE HELPERS ───────────────────────────────── */
  function safeGet(key) {
    try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch (e) { return null; }
  }
  function safeSet(key, val) {
    try { localStorage.setItem(key, JSON.stringify(val)); } catch (e) {}
  }

  /* ── PUBLIC: getSubscriber ──────────────────────────────── */
  DAL.getSubscriber = function () {
    return safeGet(CONFIG.storageKey);
  };

  /* ── PUBLIC: saveSubscriber ─────────────────────────────── */
  /*
   * Derives username from email: "jane.doe@gmail.com" → "janedoe"
   * username also serves as the Rover booking discount code.
   * dogName is optional — used for personalizing the store picks section.
   */
  DAL.saveSubscriber = function (email, dogName) {
    var username = email
      .split('@')[0]
      .replace(/[^a-z0-9]/gi, '')   // keep only letters + numbers
      .toLowerCase();

    var data = {
      email:        email,
      username:     username,
      discountCode: username.toUpperCase(),   /* shown as coupon code */
      dogName:      dogName || '',
      subscribedAt: new Date().toISOString()
    };
    safeSet(CONFIG.storageKey, data);
    return data;
  };

  /* ── PUBLIC: clearSubscriber ────────────────────────────── */
  DAL.clearSubscriber = function () {
    try { localStorage.removeItem(CONFIG.storageKey); } catch (e) {}
  };

  /* ── MAILCHIMP: silent background POST ─────────────────── */
  function postToMailchimp(email) {
    if (!CONFIG.mailchimpUrl) return;
    var frameName = 'dal_mc_' + Date.now();
    var iframe = document.createElement('iframe');
    iframe.name = frameName;
    iframe.style.cssText = 'position:absolute;width:1px;height:1px;opacity:0;pointer-events:none;';
    document.body.appendChild(iframe);

    var form = document.createElement('form');
    form.action  = CONFIG.mailchimpUrl;
    form.method  = 'post';
    form.target  = frameName;
    form.style.display = 'none';

    var emailField = document.createElement('input');
    emailField.type  = 'email';
    emailField.name  = 'EMAIL';
    emailField.value = email;
    form.appendChild(emailField);

    /* Mailchimp anti-bot honeypot field — required for embedded forms */
    var honey = document.createElement('input');
    honey.type  = 'text';
    honey.name  = 'b_' + (CONFIG.mailchimpUrl.match(/[?&]u=([^&]+)/) || ['',''])[1]
                     + '_' + (CONFIG.mailchimpUrl.match(/[?&]id=([^&]+)/) || ['',''])[1];
    honey.value = '';
    honey.setAttribute('aria-hidden', 'true');
    honey.style.display = 'none';
    form.appendChild(honey);

    document.body.appendChild(form);
    form.submit();

    setTimeout(function () {
      if (form.parentNode) form.parentNode.removeChild(form);
      if (iframe.parentNode) iframe.parentNode.removeChild(iframe);
    }, 4000);
  }

  /* ── PUBLIC: handleSubscribe ────────────────────────────── */
  /*
   * Call this from each page's subscribe-form submit handler.
   * Returns the subscriber object so the page can display a personalised toast.
   *
   * Usage:
   *   var sub = DAL.handleSubscribe(email, optionalDogName);
   *   showToast('Welcome, ' + sub.username + '! Your code: ' + sub.discountCode);
   */
  DAL.handleSubscribe = function (email, dogName) {
    var sub = DAL.saveSubscriber(email, dogName);
    postToMailchimp(email);
    DAL.initPersonalizeButton();
    return sub;
  };

  /* ── NAV PERSONALIZE BUTTON ─────────────────────────────── */
  DAL.initPersonalizeButton = function () {
    var sub = DAL.getSubscriber();
    var btn = document.getElementById('dal-personalize-btn');
    if (!btn) return;

    if (sub && sub.username) {
      /* Update label */
      var label = btn.querySelector('.dal-btn-label');
      if (label) label.textContent = sub.username;
      btn.style.display = '';
      btn.classList.add('dal-visible');
      /* Mark body for CSS personalization hooks */
      document.body.classList.add('dal-personalized');
      document.body.setAttribute('data-dal-user', sub.username);
      /* Show any .dal-personal-only elements */
      document.querySelectorAll('.dal-personal-only').forEach(function (el) {
        el.style.display = '';
      });
    } else {
      btn.style.display = 'none';
      btn.classList.remove('dal-visible', 'dal-active');
      document.body.classList.remove('dal-personalized');
      document.querySelectorAll('.dal-personal-only').forEach(function (el) {
        el.style.display = 'none';
      });
    }
  };

  /* ── PUBLIC: onPersonalizeBtnClick ─────────────────────── */
  /*
   * Attached to the nav button's onclick.
   * Toggles the .dal-personalized class on <body> so CSS can show/hide
   * personalized sections (e.g. store picks filtered for the subscriber's dog).
   */
  DAL.onPersonalizeBtnClick = function () {
    var sub = DAL.getSubscriber();
    if (!sub) return;

    var isOn = document.body.classList.toggle('dal-personalized');
    document.body.setAttribute('data-dal-user', isOn ? sub.username : '');

    var btn = document.getElementById('dal-personalize-btn');
    if (btn) btn.classList.toggle('dal-active', isOn);

    /* Toggle personalized-only sections */
    document.querySelectorAll('.dal-personal-only').forEach(function (el) {
      el.style.display = isOn ? '' : 'none';
    });

    /* Announce to screen-readers */
    var liveRgn = document.getElementById('dal-live-region');
    if (liveRgn) {
      liveRgn.textContent = isOn
        ? 'Personalized view on for ' + sub.username
        : 'Showing default view';
    }
  };

  /* ── AUTO-INIT ──────────────────────────────────────────── */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', DAL.initPersonalizeButton);
  } else {
    DAL.initPersonalizeButton();
  }

}(window.DAL = window.DAL || {}));
