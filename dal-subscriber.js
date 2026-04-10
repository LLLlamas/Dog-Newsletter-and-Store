/*!
 * Dogs & Llamas — Subscriber, Login & Personalization System  v2.0
 * ─────────────────────────────────────────────────────────────────
 *
 * v2 CHANGES (late April 10, 2026):
 *   • Switched from Mailchimp (no free tier anymore) to Supabase
 *   • Added login/unlock flow: visitor enters their email OR username
 *     on any page to activate personalized view (matched via Supabase)
 *   • Added built-in dog profiles (Turbo, Troy) + content-slot system
 *     that swaps tips, latest-issue copy, and store pick per user
 *   • Login strip + styles auto-inject below <nav> on every page
 *   • Dev helper: DAL.devLoginAs('turbo' | 'troy') for testing w/o Supabase
 *
 * QUICK START:
 *   1. Open https://supabase.com/dashboard/project/nizvndjuzyblsewobkru
 *   2. Settings → API → copy "Project URL" and "anon public" key
 *   3. Paste the anon key into CONFIG.supabaseAnonKey below
 *   4. Open the SQL editor → paste + run the contents of supabase-schema.sql
 *   5. You're done. Turbo and Troy are pre-seeded.
 *
 * EMAIL DELIVERY (Mailchimp is no longer free):
 *   Recommended free alternatives for actually sending newsletters:
 *     • Brevo     — 300 emails/day, unlimited contacts, has API + forms
 *     • MailerLite — 1,000 subs, 12,000 emails/month, great editor
 *     • Beehiiv   — 2,500 subs free, newsletter-focused
 *   All of them can import a CSV export from your Supabase "subscribers"
 *   table whenever you want to send a blast.
 */

(function (DAL) {
  'use strict';

  /* ══════════════════════════════════════════════════════════════
   *  CONFIG — fill in the anon key from your Supabase dashboard
   * ══════════════════════════════════════════════════════════════ */
  var CONFIG = {
    storageKey: 'dal_subscriber',

    /* Your Supabase project URL (pre-filled) */
    supabaseUrl: 'https://nizvndjuzyblsewobkru.supabase.co',

    /*
     * Paste your anon public key here (starts with "eyJ...").
     * Dashboard → Settings → API → "anon public"
     * Leaving it empty enables local-only fallback mode.
     */
    supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5penZuZGp1enlibHNld29ia3J1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU4MzEyNjUsImV4cCI6MjA5MTQwNzI2NX0.EJL17l72-Dx8GH2RYPrl34-NUtskY0ldcevgm8dOcpQ'
  };

  /* ══════════════════════════════════════════════════════════════
   *  BUILT-IN DOG PROFILES
   *  Keyed by lowercased dog name. When a subscriber's row in Supabase
   *  has a matching `dog_name`, the site swaps [data-dal-slot] elements
   *  with the values below.
   *
   *  To add a new dog:
   *    1. Add an entry here
   *    2. Add a row in Supabase: insert into subscribers(...) values(...)
   *    3. That's it — the site picks it up automatically
   * ══════════════════════════════════════════════════════════════ */
  var DOG_CONTENT = {
    turbo: {
      name: 'Turbo',
      emoji: '\u26A1',
      greeting: 'Hi, Turbo fam',
      breed: 'Mini Australian Shepherd',
      /* Personalized content slots — referenced via [data-dal-slot="key"] */
      'hero-title':  "Turbo's Corner",
      'hero-sub':    "High-energy mini Aussie life: food, barking, outdoors, and agility.",
      'issue-title': "April 2026 \u2014 Agility & Food Puzzles",
      'issue-desc':  "Turbo's chapter: backyard agility drills for high-drive herders, food-puzzle upgrades that actually challenge her, and how to read a 'bark-at-everything' trigger stack before it snowballs.",
      'issue-body-1': "High-drive Aussies like Turbo need more than walks \u2014 they need jobs. This month we break down a 20-minute weave/jump/tunnel circuit you can build from traffic cones and a pool noodle.",
      'issue-body-2': "Food tip: Turbo is food-motivated enough that we swap 30% of her kibble into a puzzle feeder. It cuts barking at windows by roughly half because her brain has somewhere to go.",
      'issue-body-3': "Outdoor watch: mini Aussies overheat faster than they let on. If you're on a fetch-heavy trail, rotate 5 minutes of fetch with 2 minutes of shade and water.",
      'tip-eyebrow': "Turbo's Top Tips",
      'tip-title':   "This month with Turbo",
      'tip-1':       "Turbo is seriously food-motivated \u2014 use freeze-dried liver to shape new behaviors in days, not weeks.",
      'tip-2':       "Mini Aussies love to bark at movement. Redirect with a firm 'quiet' cue plus an instant chew reward.",
      'tip-3':       "30 minutes of agility burns more than an hour of walking. Set up backyard weave poles with traffic cones.",
      'pick-label':  "Turbo's pick this month",
      'pick-name':   "Chuckit! Sport 26L Launcher",
      'pick-reason': "Turbo needs distance and reps \u2014 this launcher gives her full burn without wearing out your arm."
    },

    troy: {
      name: 'Troy',
      emoji: '\uD83D\uDC3A',
      greeting: 'Hi, Troy fam',
      breed: 'Husky',
      'hero-title':  "Troy's Corner",
      'hero-sub':    "Big husky life: endurance, cold-weather play, and that glorious double coat.",
      'issue-title': "April 2026 \u2014 Blow-Coat Season & Endurance",
      'issue-desc':  "Troy's chapter: spring undercoat grooming that actually works, cooling strategies for warm days, long-trail endurance plans, and how to read husky vocalizations.",
      'issue-body-1': "Huskies like Troy hit their spring 'blow-coat' around now. A 10-minute daily undercoat rake keeps your floors clean AND keeps Troy from overheating as the weeks warm up.",
      'issue-body-2': "Endurance tip: Troy can run for hours. Build up slowly with a 3-2-1 pattern (3 min trot, 2 min walk, 1 min rest) and always end before he wants to stop.",
      'issue-body-3': "Vocal watch: husky 'talking' isn't stress. It's genetic. Reward calm quiet-time with scatter feeding rather than trying to suppress the chatter entirely.",
      'tip-eyebrow': "Troy's Top Tips",
      'tip-title':   "This month with Troy",
      'tip-1':       "Huskies crave mental work \u2014 frozen KONG plus scatter feeding prevents the boredom-digging cycle.",
      'tip-2':       "Spring blow-coat: a daily undercoat rake saves your floors and keeps Troy cool as the days warm up.",
      'tip-3':       "Huskies are born escape artists. Reinforce your fence with dig-stop wire before off-leash yard time.",
      'pick-label':  "Troy's pick this month",
      'pick-name':   "Chris Christensen Big G Slicker Brush",
      'pick-reason': "Troy's double coat needs a proper undercoat rake \u2014 the Big G pulls shed without scratching skin."
    }
  };
  DAL.DOG_CONTENT = DOG_CONTENT;

  /* ══════════════════════════════════════════════════════════════
   *  STORAGE HELPERS
   * ══════════════════════════════════════════════════════════════ */
  function safeGet(key) {
    try { return JSON.parse(localStorage.getItem(key) || 'null'); }
    catch (e) { return null; }
  }
  function safeSet(key, val) {
    try { localStorage.setItem(key, JSON.stringify(val)); } catch (e) {}
  }

  function deriveUsername(email) {
    return String(email || '')
      .split('@')[0]
      .replace(/[^a-z0-9]/gi, '')
      .toLowerCase();
  }

  /* ══════════════════════════════════════════════════════════════
   *  SUPABASE RPC HELPER
   *  Uses fetch() instead of the 100kb SDK — the REST endpoint is
   *  stable and simple enough for our 2 stored-procedure calls.
   * ══════════════════════════════════════════════════════════════ */
  function rpc(fnName, body) {
    if (!CONFIG.supabaseUrl || !CONFIG.supabaseAnonKey) {
      return Promise.reject(new Error('Supabase not configured'));
    }
    return fetch(CONFIG.supabaseUrl + '/rest/v1/rpc/' + fnName, {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'apikey':        CONFIG.supabaseAnonKey,
        'Authorization': 'Bearer ' + CONFIG.supabaseAnonKey,
        'Accept':        'application/json'
      },
      body: JSON.stringify(body || {})
    }).then(function (r) {
      if (!r.ok) {
        return r.text().then(function (t) {
          throw new Error('Supabase ' + r.status + ': ' + t.slice(0, 200));
        });
      }
      return r.json();
    });
  }

  /* Normalize a row from Supabase (snake_case) into our client shape (camelCase) */
  function normalizeRow(row, fallbackEmail) {
    if (!row) return null;
    return {
      email:        row.email || fallbackEmail || '',
      username:     row.username || '',
      discountCode: (row.username || '').toUpperCase(),
      dogName:      row.dog_name  || '',
      dogBreed:     row.dog_breed || '',
      dogSize:      row.dog_size  || '',
      dogTraits:    row.dog_traits || [],
      dogEmoji:     row.dog_emoji || '',
      isNew:        !!row.is_new,
      subscribedAt: new Date().toISOString()
    };
  }

  /* ══════════════════════════════════════════════════════════════
   *  PUBLIC API
   * ══════════════════════════════════════════════════════════════ */

  DAL.getSubscriber = function () {
    return safeGet(CONFIG.storageKey);
  };

  DAL.saveSubscriberLocal = function (data) {
    safeSet(CONFIG.storageKey, data);
    return data;
  };

  DAL.clearSubscriber = function () {
    try { localStorage.removeItem(CONFIG.storageKey); } catch (e) {}
    restoreOriginalContent();
    DAL.initPersonalizeButton();
  };

  /*
   * DAL.handleSubscribe(email)  →  Promise<subscriberData>
   * Called from the subscribe forms. Tries Supabase first,
   * falls back to localStorage-only if not configured / offline.
   */
  DAL.handleSubscribe = function (email) {
    email = String(email || '').trim().toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(email)) {
      return Promise.reject(new Error('Invalid email format'));
    }

    return rpc('dal_subscribe', { p_email: email })
      .then(function (rows) {
        var row = Array.isArray(rows) ? rows[0] : rows;
        var data = normalizeRow(row, email);
        if (!data.username) data.username = deriveUsername(email);
        data.discountCode = data.username.toUpperCase();
        DAL.saveSubscriberLocal(data);
        DAL.initPersonalizeButton();
        return data;
      })
      .catch(function (err) {
        console.warn('[DAL] Supabase unavailable, saving locally only:', err.message);
        var uname = deriveUsername(email);
        var data = {
          email: email,
          username: uname,
          discountCode: uname.toUpperCase(),
          dogName: '', dogBreed: '', dogSize: '', dogTraits: [], dogEmoji: '',
          isNew: true,
          subscribedAt: new Date().toISOString()
        };
        DAL.saveSubscriberLocal(data);
        DAL.initPersonalizeButton();
        return data;
      });
  };

  /*
   * DAL.loginWithKey(key)  →  Promise<subscriberData>
   * `key` can be either an email or a username. Supabase checks both.
   * Rejects if no match is found.
   */
  DAL.loginWithKey = function (key) {
    key = String(key || '').trim().toLowerCase();
    if (!key) return Promise.reject(new Error('Key required'));

    return rpc('dal_lookup', { p_key: key })
      .then(function (rows) {
        var row = Array.isArray(rows) ? rows[0] : rows;
        if (!row || !row.username) throw new Error('Not found');
        var data = normalizeRow(row, key.indexOf('@') > -1 ? key : '');
        DAL.saveSubscriberLocal(data);
        DAL.initPersonalizeButton();
        return data;
      });
  };

  /*
   * DAL.devLoginAs('turbo' | 'troy')
   * Test helper — activates a dog profile locally without hitting Supabase.
   * Open your browser console on any page and run:  DAL.devLoginAs('turbo')
   */
  DAL.devLoginAs = function (key) {
    var dog = DOG_CONTENT[String(key || '').toLowerCase()];
    if (!dog) {
      console.warn('[DAL] No built-in profile for:', key, '— available:', Object.keys(DOG_CONTENT));
      return null;
    }
    var uname = dog.name.toLowerCase() + 'owner';
    var data = {
      email:        uname + '@example.com',
      username:     uname,
      discountCode: uname.toUpperCase(),
      dogName:      dog.name,
      dogBreed:     dog.breed || '',
      dogSize:      '',
      dogTraits:    [],
      dogEmoji:     dog.emoji || '',
      subscribedAt: new Date().toISOString()
    };
    DAL.saveSubscriberLocal(data);
    DAL.initPersonalizeButton();
    console.log('[DAL] Logged in as:', data.username, 'with dog:', data.dogName);
    return data;
  };

  /* ══════════════════════════════════════════════════════════════
   *  CONTENT PERSONALIZATION — swaps [data-dal-slot] elements
   * ══════════════════════════════════════════════════════════════ */
  function applyDogContent() {
    var sub = DAL.getSubscriber();
    if (!sub) return;

    var dogKey = (sub.dogName || '').toLowerCase();
    var dog = DOG_CONTENT[dogKey];
    if (!dog) {
      document.body.classList.remove('dal-has-dog');
      document.body.removeAttribute('data-dal-dog');
      return;
    }

    document.body.classList.add('dal-has-dog');
    document.body.setAttribute('data-dal-dog', dogKey);

    document.querySelectorAll('[data-dal-slot]').forEach(function (el) {
      var key = el.getAttribute('data-dal-slot');
      if (dog[key] !== undefined && dog[key] !== null) {
        if (el.getAttribute('data-dal-original') === null) {
          el.setAttribute('data-dal-original', el.textContent || '');
        }
        el.textContent = dog[key];
      }
    });
  }

  function restoreOriginalContent() {
    document.body.classList.remove('dal-has-dog');
    document.body.removeAttribute('data-dal-dog');
    document.querySelectorAll('[data-dal-slot]').forEach(function (el) {
      var orig = el.getAttribute('data-dal-original');
      if (orig !== null) el.textContent = orig;
    });
  }

  DAL.personalizeContent = applyDogContent;

  /* ══════════════════════════════════════════════════════════════
   *  NAV PERSONALIZE BUTTON
   * ══════════════════════════════════════════════════════════════ */
  DAL.initPersonalizeButton = function () {
    var sub   = DAL.getSubscriber();
    var btn   = document.getElementById('dal-personalize-btn');
    var strip = document.getElementById('dal-login-strip');

    if (sub && sub.username) {
      if (btn) {
        var label = btn.querySelector('.dal-btn-label');
        if (label) label.textContent = sub.username;
        btn.style.display = '';
        btn.classList.add('dal-visible');
      }
      document.body.classList.add('dal-personalized');
      document.body.setAttribute('data-dal-user', sub.username);
      if (strip) strip.style.display = 'none';

      document.querySelectorAll('.dal-personal-only').forEach(function (el) {
        el.style.display = '';
      });
      applyDogContent();
    } else {
      if (btn) {
        btn.style.display = 'none';
        btn.classList.remove('dal-visible', 'dal-active');
      }
      document.body.classList.remove('dal-personalized');
      document.body.removeAttribute('data-dal-user');
      restoreOriginalContent();
      if (strip) strip.style.display = '';
      document.querySelectorAll('.dal-personal-only').forEach(function (el) {
        el.style.display = 'none';
      });
    }
  };

  DAL.onPersonalizeBtnClick = function () {
    var sub = DAL.getSubscriber();
    if (!sub) return;

    var isOn = document.body.classList.toggle('dal-personalized');
    document.body.setAttribute('data-dal-user', isOn ? sub.username : '');

    var btn = document.getElementById('dal-personalize-btn');
    if (btn) btn.classList.toggle('dal-active', isOn);

    document.querySelectorAll('.dal-personal-only').forEach(function (el) {
      el.style.display = isOn ? '' : 'none';
    });

    if (isOn) applyDogContent();
    else restoreOriginalContent();

    var live = document.getElementById('dal-live-region');
    if (live) {
      live.textContent = isOn
        ? 'Personalized view on for ' + sub.username
        : 'Showing default view';
    }
  };

  /* ══════════════════════════════════════════════════════════════
   *  LOGIN STRIP — auto-injects below <nav> on every page
   * ══════════════════════════════════════════════════════════════ */
  function injectLoginStripStyles() {
    if (document.getElementById('dal-login-strip-styles')) return;
    var css = [
      '.dal-login-strip{background:#E4F0FB;border-bottom:1px solid #CCDAEF;padding:9px 18px;font-family:"DM Sans",system-ui,sans-serif;font-size:13px;color:#1B4F8C}',
      '.dal-login-inner{max-width:1100px;margin:0 auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap}',
      '.dal-login-icon{font-size:16px;flex-shrink:0}',
      '.dal-login-label{font-weight:500;flex-shrink:0}',
      '.dal-login-input{flex:1;min-width:180px;padding:7px 14px;border:1px solid #CCDAEF;border-radius:99px;background:#fff;font-family:inherit;font-size:13px;color:#1A1D26;outline:none;transition:border-color .14s,box-shadow .14s}',
      '.dal-login-input:focus{border-color:#2B6CB0;box-shadow:0 0 0 2px rgba(43,108,176,.22)}',
      '.dal-login-btn{background:#D4A017;color:#fff;border:none;border-radius:99px;padding:7px 18px;font-family:inherit;font-size:12px;font-weight:600;cursor:pointer;white-space:nowrap;letter-spacing:.3px;transition:background .14s,transform .14s}',
      '.dal-login-btn:hover{background:#b8880f;transform:translateY(-1px)}',
      '.dal-login-btn:disabled{opacity:.6;cursor:default;transform:none}',
      '.dal-login-close{background:none;border:none;color:#8C94B0;font-size:22px;line-height:1;cursor:pointer;padding:0 6px;flex-shrink:0;transition:color .14s}',
      '.dal-login-close:hover{color:#4C5470}',
      '.dal-login-msg{max-width:1100px;margin:6px auto 0;font-size:12px;min-height:1px;display:none;text-align:center}',
      '.dal-login-msg.dal-err{display:block;color:#B33A3A}',
      '.dal-login-msg.dal-ok{display:block;color:#1B4F8C;font-weight:500}',
      '@media(max-width:640px){.dal-login-label{display:none}.dal-login-input{font-size:12px;padding:6px 12px;min-width:140px}.dal-login-strip{padding:8px 12px}}',
      /* Personal-only elements */
      '.dal-personal-only{display:none}',
      'body.dal-personalized .dal-personal-only{display:block}',
      '.dal-dog-only{display:none}',
      'body.dal-personalized.dal-has-dog .dal-dog-only{display:block}'
    ].join('\n');
    var style = document.createElement('style');
    style.id = 'dal-login-strip-styles';
    style.textContent = css;
    document.head.appendChild(style);
  }

  function injectLoginStrip() {
    if (document.getElementById('dal-login-strip')) return;
    var nav = document.querySelector('nav');
    if (!nav) return;

    var strip = document.createElement('div');
    strip.id = 'dal-login-strip';
    strip.className = 'dal-login-strip';
    strip.setAttribute('role', 'form');
    strip.setAttribute('aria-label', 'Subscriber login');
    strip.innerHTML = [
      '<div class="dal-login-inner">',
        '<span class="dal-login-icon" aria-hidden="true">\uD83D\uDC3E</span>',
        '<span class="dal-login-label">Already subscribed?</span>',
        '<input type="text" id="dal-login-input" class="dal-login-input" ',
               'placeholder="your username or email" autocomplete="off" ',
               'autocapitalize="off" spellcheck="false" ',
               'aria-label="Your username or email">',
        '<button type="button" id="dal-login-btn" class="dal-login-btn">Unlock</button>',
        '<button type="button" id="dal-login-close" class="dal-login-close" ',
                'aria-label="Dismiss login bar" title="Dismiss">&times;</button>',
      '</div>',
      '<div class="dal-login-msg" id="dal-login-msg" role="status" aria-live="polite"></div>'
    ].join('');

    nav.parentNode.insertBefore(strip, nav.nextSibling);

    var input = document.getElementById('dal-login-input');
    var btn   = document.getElementById('dal-login-btn');
    var close = document.getElementById('dal-login-close');
    var msg   = document.getElementById('dal-login-msg');

    function showMsg(text, isError) {
      if (!msg) return;
      msg.textContent = text;
      msg.className = 'dal-login-msg ' + (isError ? 'dal-err' : 'dal-ok');
    }

    function doLogin() {
      var key = (input.value || '').trim();
      if (!key) { showMsg('Please enter your username or email.', true); return; }
      showMsg('Checking\u2026', false);
      btn.disabled = true;
      DAL.loginWithKey(key)
        .then(function (data) {
          showMsg('Welcome back, ' + data.username + '! Loading your picks\u2026', false);
          setTimeout(function () {
            btn.disabled = false;
            DAL.initPersonalizeButton();
          }, 450);
        })
        .catch(function (err) {
          btn.disabled = false;
          var m = err.message || 'Error';
          if (m === 'Not found') {
            showMsg('No subscriber found. Try subscribing first.', true);
          } else if (m === 'Supabase not configured') {
            showMsg('Login system not yet connected. Try DAL.devLoginAs("turbo") in console for a demo.', true);
          } else {
            showMsg('Error: ' + m, true);
          }
        });
    }

    btn.addEventListener('click', doLogin);
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); doLogin(); }
    });
    close.addEventListener('click', function () {
      strip.style.display = 'none';
      try { sessionStorage.setItem('dal_strip_dismissed', '1'); } catch (e) {}
    });

    /* Respect session dismissal */
    try {
      if (sessionStorage.getItem('dal_strip_dismissed') === '1') {
        strip.style.display = 'none';
      }
    } catch (e) {}
  }

  /* ══════════════════════════════════════════════════════════════
   *  AUTO-INIT on DOM ready
   * ══════════════════════════════════════════════════════════════ */
  function init() {
    injectLoginStripStyles();
    injectLoginStrip();
    DAL.initPersonalizeButton();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

}(window.DAL = window.DAL || {}));
