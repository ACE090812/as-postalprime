/* Postal Prime courier UI: depot window, notifications, progress bar and run HUD.
   Driven by SendNUIMessage from client/courier.lua (which only reaches this resource's own ui_page frame,
   not the copy sd-phone embeds for the phone app - that copy just keeps an empty, hidden overlay).
   Talks back through the as-postalprime/courier:* NUI callbacks.
   NOTE: FiveM loads a resource's ui_page inside an iframe, so don't guard on window.top. */
(function () {
    'use strict';

    var RES = 'as-postalprime';
    var SIZE = { s: 'Small', m: 'Medium', l: 'Large', xl: 'X-Large' };

    var IC = {
        shift: '<path d="M12 7v5l3 2"/><circle cx="12" cy="12" r="8.5"/>',
        veh: '<path d="M3 16V8h11v8M14 11h4l3 3v2h-7"/><circle cx="7.5" cy="17" r="1.8"/><circle cx="17" cy="17" r="1.8"/>',
        board: '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V3h6v1M9 10h6M9 14h6"/>',
        run: '<path d="M4 8l8-4 8 4v8l-8 4-8-4z"/><path d="M4 8l8 4 8-4M12 12v8"/>',
        close: '<path d="M6 6l12 12M18 6L6 18"/>',
        ok: '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.7 2.7L16 9.5"/>',
        err: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.1"/>',
        info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5.5M12 7.5v.1"/>',
        empty: '<path d="M4 8l8-4 8 4v8l-8 4-8-4z"/><path d="M4 8l8 4 8-4"/>'
    };
    function ic(n) { return '<svg class="pc-i" viewBox="0 0 24 24">' + IC[n] + '</svg>'; }
    function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
    function fmt(sec) { sec = Math.max(0, Math.floor(sec)); return Math.floor(sec / 60) + ':' + ('0' + (sec % 60)).slice(-2); }
    function money(n) { return '$' + Number(n || 0).toLocaleString('en-US'); }

    function post(name, data) {
        return fetch('https://' + RES + '/' + RES + '/courier:' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (r) { return r.json(); }).catch(function () { return { ok: false, error: 'No response' }; });
    }

    // ── skeleton ────────────────────────────────────────────────────────────
    var root = document.createElement('div');
    root.id = 'ppc';
    root.innerHTML =
        '<div id="pcToasts"></div>' +
        '<div id="pcHud" class="pc-off"><div class="pc-hh">RUN <span id="pcHudCount"></span></div><div id="pcHudRows"></div>' +
        '<div class="pc-kb pc-off" id="pcHudKb"><span class="pc-key">X</span> Put parcel down</div></div>' +
        '<div id="pcProg" class="pc-off"><div class="pc-top"><span id="pcProgLabel"></span><span class="pc-pct" id="pcProgPct">0%</span></div>' +
        '<div class="pc-track"><div class="pc-fill" id="pcProgFill"></div></div><div class="pc-hint" id="pcProgHint">Press X to cancel</div></div>' +
        '<div id="pcDepot" class="pc-off"><div class="pc-win">' +
        '<div class="pc-head"><img class="pc-logo" src="logo.png" alt="Postal Prime"><span class="pc-title">Depot</span><span class="pc-sub" id="pcSub"></span>' +
        '<button class="pc-x" id="pcClose" title="Close (Esc)">' + ic('close') + '</button></div>' +
        '<div class="pc-main"><aside class="pc-side"><nav class="pc-nav" id="pcNav"></nav><div class="pc-prof" id="pcProf"></div></aside>' +
        '<main class="pc-content" id="pcBody"></main></div><div id="pcInToasts"></div></div></div>' +
        '<div id="pcDlg" class="pc-off"></div>';
    document.body.appendChild(root);

    function $(id) { return document.getElementById(id); }

    // ── notifications ───────────────────────────────────────────────────────
    function toast(title, desc, kind) {
        // While the depot window is open the message drops down from the top of the window instead of the screen corner.
        var box = $(isOpen ? 'pcInToasts' : 'pcToasts');
        var el = document.createElement('div');
        el.className = 'pc-toast ' + (kind || 'inform');
        el.innerHTML = ic(kind === 'success' ? 'ok' : (kind === 'error' ? 'err' : 'info')) +
            '<div><div class="pc-t">' + esc(title) + '</div><div class="pc-d">' + esc(desc) + '</div></div>';
        box.appendChild(el);
        while (box.children.length > 5) box.removeChild(box.firstChild);
        setTimeout(function () {
            el.classList.add('out');
            setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 220);
        }, 4500);
    }

    // ── progress bar ────────────────────────────────────────────────────────
    var progRaf = null;
    function progressStart(label, ms, cancellable) {
        cancelAnimationFrame(progRaf);
        $('pcProgLabel').textContent = label || '';
        $('pcProgHint').style.display = cancellable ? '' : 'none';
        $('pcProg').classList.remove('pc-off');
        var start = performance.now();
        (function step(now) {
            var p = Math.min(1, (now - start) / Math.max(1, ms));
            $('pcProgFill').style.width = (p * 100) + '%';
            $('pcProgPct').textContent = Math.round(p * 100) + '%';
            if (p < 1) progRaf = requestAnimationFrame(step);
        })(start);
    }
    function progressStop() {
        cancelAnimationFrame(progRaf);
        $('pcProg').classList.add('pc-off');
        $('pcProgFill').style.width = '0';
    }

    // ── run HUD ─────────────────────────────────────────────────────────────
    var hud = { rows: [], carry: false, at: 0 };
    function hudLeft(r) { return r.left == null ? null : r.left - (Date.now() - hud.at) / 1000; }
    function renderHud() {
        var h = $('pcHud');
        var visible = hud.on && (hud.rows.length > 0 || hud.carry);
        h.classList.toggle('pc-off', !visible);
        if (!visible) return;
        $('pcHudCount').textContent = hud.rows.length ? hud.rows.length + ' parcel' + (hud.rows.length > 1 ? 's' : '') : '';
        $('pcHudKb').classList.toggle('pc-off', !hud.carry);
        $('pcHudRows').innerHTML = hud.rows.map(function (r) {
            var cls = 'dim', txt = 'at depot';
            if (r.state === 'loaded') {
                var left = hudLeft(r) || 0;
                if (left >= 0) { txt = fmt(left); cls = left < 30 ? 'warn' : ''; }
                else { txt = 'LATE ' + fmt(-left); cls = 'late'; }
            }
            return '<div class="pc-hr"><span class="n">' + esc(r.label) + '</span><span class="s">' + esc(String(r.size || 'm').toUpperCase()) +
                '</span><span class="t ' + cls + '">' + txt + '</span></div>';
        }).join('');
    }
    function setHud(d) {
        hud.on = d.show !== false;
        hud.rows = d.rows || [];
        hud.carry = !!d.carry;
        hud.at = Date.now();
        if (d.x != null) $('pcHud').style.left = (d.x * 100) + 'vw';
        if (d.y != null) $('pcHud').style.top = (d.y * 100) + 'vh';
        renderHud();
    }
    setInterval(renderHud, 1000);

    // ── depot window ────────────────────────────────────────────────────────
    var st = null, stAt = 0, tab = 'shift', isOpen = false, board = null, pending = false, poll = null;

    function claimLeft(c) { return c.secondsLeft == null ? null : c.secondsLeft - (Date.now() - stAt) / 1000; }
    function timeCell(c) {
        var left = claimLeft(c);
        if (left == null) return { txt: '-', cls: '' };
        return { txt: left >= 0 ? fmt(left) : 'LATE ' + fmt(-left), cls: left < 0 ? 't-late' : (left < 30 ? 't-warn' : 't-ok') };
    }
    function kindTag(k) { return '<span class="pc-tag ' + k + '">' + (k === 'home' ? 'Home' : 'Locker') + '</span>'; }
    function tblHead(cols) {
        return '<thead><tr>' + cols.map(function (c) { return '<th' + (c[1] ? ' class="r"' : '') + '>' + c[0] + '</th>'; }).join('') + '</tr></thead>';
    }

    function setState(s) {
        if (!s) return;
        st = s; stAt = Date.now();
        if (s.isCourier === false) { closeDepot(); return; }
        render();
    }

    function renderNav() {
        var claims = st.claims || [];
        var items = [['shift', 'Shift', 0], ['veh', 'Vehicles', 0], ['board', 'Order board', st.onDuty ? (st.boardCount || 0) : 0], ['run', 'My run', claims.length]];
        $('pcNav').innerHTML = items.map(function (t) {
            return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + ic(t[0]) + t[1] + (t[2] ? '<span class="pc-n">' + t[2] + '</span>' : '') + '</button>';
        }).join('');
        var top = st.nextXp == null;
        var pct = top ? 100 : Math.round(((st.xp - st.levelXp) / Math.max(1, st.nextXp - st.levelXp)) * 100);
        $('pcProf').innerHTML = '<div class="r1"><span>Level ' + st.level + '</span><span class="pc-mono">' + pct + '%</span></div>' +
            '<div class="r2">' + (top ? st.xp + ' XP - max level' : st.xp + ' / ' + st.nextXp + ' XP') + '</div><div class="pc-meter"><i style="width:' + pct + '%"></i></div>';
    }

    function viewShift() {
        var r = st.rental, info = st.info || {};
        var h = '<h2 class="pc-h1">Shift</h2><p class="pc-lead">Clock on, sign out a vehicle, then take orders from the board.</p><div class="pc-cols"><div>';
        h += '<div class="pc-box"><div class="pc-box-h">Status</div><div class="pc-status"><span class="pc-dot' + (st.onDuty ? ' on' : '') + '"></span>' +
            '<div style="flex:1"><b>' + (st.onDuty ? 'On shift' : 'Off shift') + '</b><div class="pc-muted">' + (st.onDuty ? 'New orders appear on the board' : 'Clock on to receive orders') + '</div></div>' +
            '<button class="pc-btn ' + (st.onDuty ? '' : 'primary') + '" data-act="duty">' + (st.onDuty ? 'Clock off' : 'Clock on') + '</button></div></div>';
        h += '<div class="pc-box"><div class="pc-box-h">Performance</div><div class="pc-box-b">' +
            '<div class="pc-kv"><span>Courier level</span><b>' + st.level + '</b></div>' +
            '<div class="pc-kv"><span>Deliveries</span><b class="pc-mono">' + (st.deliveries || 0) + '</b></div>' +
            '<div class="pc-kv"><span>Total earned</span><b class="pc-mono">' + money(st.earned) + '</b></div>' +
            '<div class="pc-kv"><span>Parcels at once</span><b class="pc-mono">' + st.batch + '</b></div></div></div>';
        h += '</div><div>';
        if (r) {
            h += '<div class="pc-box"><div class="pc-box-h">Company vehicle<span class="pc-tag ok" style="margin-left:auto">Out</span></div><div class="pc-box-b">' +
                '<div class="pc-kv"><span>Vehicle</span><b>' + esc(r.label) + '</b></div><div class="pc-kv"><span>Plate</span><b class="pc-mono">' + esc(r.plate) + '</b></div>' +
                '<div class="pc-kv"><span>Deposit</span><b class="pc-mono">' + money(r.deposit) + '</b></div>' +
                '<div class="pc-kv"><span>Capacity</span><b class="pc-mono">' + (st.usedUnits || 0) + ' / ' + r.capacity + ' units</b></div></div>' +
                '<div class="pc-pad"><button class="pc-btn danger" style="width:100%" data-act="return">Return vehicle</button></div>' +
                '<div class="pc-note">Park at the depot first.' + (info.damageTolerance != null ? ' Damage over ' + info.damageTolerance + '% is deducted from the deposit.' : '') + '</div></div>';
        } else {
            h += '<div class="pc-box"><div class="pc-box-h">Company vehicle</div><div class="pc-empty tight"><b>No vehicle</b>Rent one from the Vehicles page. The deposit is refunded when you return it.</div></div>';
        }
        return h + '</div></div>';
    }

    function viewVeh() {
        var h = '<h2 class="pc-h1">Vehicles</h2><p class="pc-lead">Deposits are refunded on return' + ((st.info || {}).damageTolerance != null ? ', minus any damage' : '') + '. Higher levels unlock larger vehicles.</p>';
        h += '<div class="pc-box pc-tblbox"><table>' + tblHead([['Vehicle'], ['Capacity'], ['Largest box'], ['Deposit', 1], ['', 0]]) + '<tbody>';
        (st.vehicles || []).forEach(function (v) {
            var locked = !v.unlocked, cant = locked || !!st.rental || !st.onDuty;
            var label = locked ? 'Level ' + v.level : (st.rental ? 'In use' : (!st.onDuty ? 'Clock on' : 'Rent'));
            h += '<tr class="' + (locked ? 'dim' : '') + '"><td><span class="pc-dest">' + esc(v.label) + '</span></td><td class="pc-mono">' + v.capacity + ' units</td><td>' + (SIZE[v.maxBox] || v.maxBox) + '</td>' +
                '<td class="r pc-mono">' + money(v.deposit) + '</td><td class="r"><button class="pc-btn sm ' + (cant ? '' : 'primary') + '" data-rent="' + esc(v.key) + '" ' + (cant ? 'disabled' : '') + '>' + label + '</button></td></tr>';
        });
        return h + '</tbody></table></div>';
    }

    function viewBoard() {
        var mins = (st.info || {}).boardMinutes;
        var h = '<h2 class="pc-h1">Order board</h2><p class="pc-lead">Ready orders waiting for a courier.' + (mins ? ' Unclaimed orders fall back to the NPC courier after ' + mins + ' minutes.' : '') + '</p>';
        if (!st.onDuty) return h + '<div class="pc-box"><div class="pc-empty">' + ic('shift') + '<b>You\'re off shift</b>Clock on to see the order board.</div></div>';
        if (!board) return h + '<div class="pc-box"><div class="pc-empty"><b>Loading</b></div></div>';
        if (!board.length) return h + '<div class="pc-box"><div class="pc-empty">' + ic('empty') + '<b>No orders right now</b>New orders appear as customer parcels become ready.</div></div>';
        h += '<div class="pc-box pc-tblbox"><table>' + tblHead([['Type'], ['Destination'], ['Box'], ['Distance', 1], ['Est. pay', 1], ['', 0]]) + '<tbody>';
        board.forEach(function (o) {
            var b = o.blocked;
            h += '<tr class="' + (b ? 'dim' : '') + '"><td>' + kindTag(o.kind) + '</td><td><div class="pc-dest">' + esc(o.label) + '</div>' + (b ? '<div class="pc-why">' + esc(b) + '</div>' : '') + '</td>' +
                '<td>' + (SIZE[o.size] || o.size) + '</td><td class="r pc-mono">' + Number(o.km).toFixed(1) + ' km</td><td class="r pc-mono">' + money(o.pay) + '</td>' +
                '<td class="r"><button class="pc-btn sm ' + (b ? '' : 'primary') + '" data-claim="' + esc(o.orderId) + '" ' + (b ? 'disabled' : '') + '>Claim</button></td></tr>';
        });
        return h + '</tbody></table></div>';
    }

    function viewRun() {
        var claims = st.claims || [];
        var h = '<h2 class="pc-h1">My run</h2><p class="pc-lead">Collect each parcel from the depot pile, load it into your vehicle, then deliver before the timer runs out.</p>';
        if (!claims.length) return h + '<div class="pc-box"><div class="pc-empty">' + ic('empty') + '<b>No parcels on your run</b>Claim some from the order board.</div></div>';
        h += '<div class="pc-box pc-tblbox"><table>' + tblHead([['Destination'], ['Type'], ['Box'], ['Status'], ['Time left', 1], ['', 0]]) + '<tbody>';
        claims.forEach(function (c) {
            var loaded = c.state === 'loaded', tc = timeCell(c);
            h += '<tr><td class="pc-dest">' + esc(c.label) + '</td><td>' + kindTag(c.kind) + '</td><td>' + (SIZE[c.size] || c.size) + '</td>' +
                '<td>' + (loaded ? '<span class="pc-tag ok">Out for delivery</span>' : '<span class="pc-tag">At depot pile</span>') + '</td>' +
                '<td class="r pc-mono ' + (loaded ? tc.cls : '') + '"' + (loaded ? ' data-cid="' + esc(c.orderId) + '"' : '') + '>' + (loaded ? tc.txt : '-') + '</td>' +
                '<td class="r">' + (loaded ? '' : '<button class="pc-btn sm" data-put="' + esc(c.orderId) + '">Put back</button>') + '</td></tr>';
        });
        h += '</tbody></table></div><div class="pc-foot"><span>Capacity <b class="pc-mono">' + (st.usedUnits || 0) + ' / ' + (st.rental ? st.rental.capacity : '-') + '</b> units</span>' +
            '<span>Parcels <b class="pc-mono">' + claims.length + ' / ' + st.batch + '</b></span><span class="sp"></span><button class="pc-btn danger" data-act="abandon">Abandon run</button></div>';
        return h;
    }

    function render() {
        if (!isOpen || !st) return;
        $('pcDepot').classList.remove('pc-off');
        $('pcSub').textContent = st.onDuty ? 'On shift' : 'Off shift';
        renderNav();
        var body = $('pcBody'), keep = body.scrollTop;
        body.innerHTML = ({ shift: viewShift, veh: viewVeh, board: viewBoard, run: viewRun }[tab] || viewShift)();
        body.scrollTop = keep;
    }

    // live time-left cells without re-rendering the whole table
    setInterval(function () {
        if (!isOpen || !st) return;
        var cells = document.querySelectorAll('#pcBody td[data-cid]');
        for (var i = 0; i < cells.length; i++) {
            var id = cells[i].getAttribute('data-cid');
            var c = (st.claims || []).filter(function (x) { return String(x.orderId) === id; })[0];
            if (!c) continue;
            var t = timeCell(c);
            cells[i].textContent = t.txt;
            cells[i].className = 'r pc-mono ' + t.cls;
        }
    }, 1000);

    function loadBoard() {
        return post('board').then(function (res) {
            if (res && res.ok) board = res.orders || [];
            else if (res && !res.ok) board = board || [];
            if (isOpen && tab === 'board') render();
        });
    }

    function refreshState() {
        return post('state').then(function (res) { if (res && res.state) setState(res.state); });
    }

    function startPoll() {
        clearInterval(poll);
        poll = setInterval(function () {
            if (!isOpen || pending) return;
            refreshState();
            if (tab === 'board' && st && st.onDuty) loadBoard();
        }, 4000);
    }

    function openDepot(state) {
        isOpen = true; tab = 'shift'; board = null; pending = false;
        setState(state);
        isOpen = true;
        render();
        startPoll();
    }

    function closeDepot() {
        if (!isOpen) return;
        isOpen = false;
        clearInterval(poll);
        closeDlg(true);
        $('pcDepot').classList.add('pc-off');
        post('close');
    }

    // Runs a server action through Lua, then re-renders from the fresh state it returns.
    function act(name, data, btn) {
        if (pending) return Promise.resolve(null);
        pending = true;
        if (btn) btn.classList.add('busy');
        return post(name, data).then(function (res) {
            pending = false;
            if (res && res.state) setState(res.state);
            if (isOpen && tab === 'board' && st && st.onDuty) loadBoard(); else render();
            return res;
        });
    }

    $('pcNav').addEventListener('click', function (e) {
        var b = e.target.closest('button'); if (!b) return;
        tab = b.getAttribute('data-tab');
        render();
        if (tab === 'board' && st && st.onDuty) loadBoard();
    });
    $('pcClose').addEventListener('click', closeDepot);

    $('pcBody').addEventListener('click', function (e) {
        var b = e.target.closest('button'); if (!b || b.disabled) return;
        var act_ = b.getAttribute('data-act');
        if (act_ === 'duty') return act('duty', { on: !st.onDuty }, b);
        if (act_ === 'return') return act('return', {}, b);
        if (act_ === 'abandon') {
            return confirmDlg('Abandon run?', 'Every parcel on your run goes back to the NPC courier and you earn nothing for them. You keep your vehicle.', 'Abandon run', function () { act('abandon', {}); });
        }
        var rent = b.getAttribute('data-rent');
        if (rent) {
            b.textContent = 'Signing out...';
            return act('rent', { key: rent }, b).then(function (res) { if (res && res.ok) { tab = 'shift'; render(); } });
        }
        var claim = b.getAttribute('data-claim');
        if (claim) return act('claim', { orderId: claim }, b);
        var put = b.getAttribute('data-put');
        if (put) return act('unclaim', { orderId: put }, b);
    });

    // ── dialogs ─────────────────────────────────────────────────────────────
    var dlgCancel = null;
    function closeDlg(silent) {
        var cb = dlgCancel; dlgCancel = null;
        $('pcDlg').classList.add('pc-off');
        $('pcDlg').innerHTML = '';
        if (cb && !silent) cb();
    }
    function confirmDlg(title, text, yesLabel, yes) {
        var d = $('pcDlg');
        d.innerHTML = '<div class="pc-dlg"><div class="pc-b"><h3>' + esc(title) + '</h3><p>' + esc(text) + '</p></div>' +
            '<div class="pc-acts"><button class="pc-btn" id="pcNo">Cancel</button><button class="pc-btn primary" id="pcYes">' + esc(yesLabel) + '</button></div></div>';
        d.classList.remove('pc-off');
        dlgCancel = function () { };
        $('pcNo').onclick = function () { closeDlg(); };
        $('pcYes').onclick = function () { dlgCancel = null; closeDlg(true); yes(); };
    }
    function pickDlg(title, items) {
        var d = $('pcDlg');
        var at = Date.now();
        d.innerHTML = '<div class="pc-dlg"><div class="pc-b"><h3>' + esc(title) + '</h3><p>Nearest first.</p><div class="pc-pick">' +
            items.map(function (it) {
                var left = it.left == null ? null : it.left - (Date.now() - at) / 1000;
                var t = left == null ? '' : (left >= 0 ? fmt(left) : 'LATE ' + fmt(-left));
                var cls = left != null && left < 0 ? 'late' : (left != null && left < 30 ? 'warn' : '');
                return '<button data-id="' + esc(it.orderId) + '"><span class="nm">' + esc(it.label) + '<span class="mt">' + (SIZE[it.size] || it.size) + ' box  -  ' +
                    (it.km != null ? Number(it.km).toFixed(1) + ' km away' : '') + '</span></span><span class="tm ' + cls + '">' + t + '</span></button>';
            }).join('') + '</div></div><div class="pc-acts"><button class="pc-btn" id="pcNo">Cancel</button></div></div>';
        d.classList.remove('pc-off');
        dlgCancel = function () { post('pick', { orderId: null }); };
        $('pcNo').onclick = function () { closeDlg(); };
        d.querySelectorAll('.pc-pick button').forEach(function (b) {
            b.onclick = function () {
                var id = b.getAttribute('data-id');
                dlgCancel = null; closeDlg(true);
                post('pick', { orderId: id });
            };
        });
    }

    document.addEventListener('keydown', function (e) {
        if (e.key !== 'Escape') return;
        if (!$('pcDlg').classList.contains('pc-off')) { closeDlg(); return; }
        if (isOpen) closeDepot();
    });

    // ── messages from client/courier.lua ────────────────────────────────────
    window.addEventListener('message', function (event) {
        var d = event.data;
        if (!d || typeof d !== 'object' || typeof d.action !== 'string') return;
        switch (d.action) {
            case 'as-postalprime:courier:open': openDepot(d.state); break;
            case 'as-postalprime:courier:close': closeDepot(); break;
            case 'as-postalprime:courier:state': if (isOpen) setState(d.state); break;
            case 'as-postalprime:toast': toast(d.title || 'Postal Prime', d.description || '', d.type); break;
            case 'as-postalprime:courier:progress': progressStart(d.label, d.duration, d.cancellable); break;
            case 'as-postalprime:courier:progressStop': progressStop(); break;
            case 'as-postalprime:courier:hud': setHud(d); break;
            case 'as-postalprime:courier:pick': pickDlg(d.title || 'Take which parcel?', d.items || []); break;
        }
    });
})();
