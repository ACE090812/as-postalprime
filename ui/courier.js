/* Postal Prime courier UI: depot window, notifications, progress bar and run HUD.
   Driven by SendNUIMessage from client/courier.lua (which only reaches this resource's own ui_page frame,
   not the copy sd-phone embeds for the phone app - that copy just keeps an empty, hidden overlay).
   Talks back through the as-postalprime/courier:* NUI callbacks.
   NOTE: FiveM loads a resource's ui_page inside an iframe, so don't guard on window.top. */
(function () {
    'use strict';

    var RES = 'as-postalprime';
    function sizeLabel(k) { return ({ s: t('size.s'), m: t('size.m'), l: t('size.l'), xl: t('size.xl') })[k] || k; }

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
    function money(n) { return '$' + Number(n || 0).toLocaleString(t('meta.numberLocale')); }

    function post(name, data) {
        return fetch('https://' + RES + '/' + RES + '/courier:' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (r) { return r.json(); }).catch(function () { return { ok: false, error: t('err.noResponse') }; });
    }

    // ── skeleton ────────────────────────────────────────────────────────────
    var root = document.createElement('div');
    root.id = 'ppc';
    root.innerHTML =
        '<div id="pcToasts"></div>' +
        '<div id="pcHud" class="pc-off"><div class="pc-hh"><span data-i18n="hud.run">RUN</span> <span id="pcHudCount"></span></div><div id="pcHudRows"></div>' +
        '<div class="pc-kb pc-off" id="pcHudKb"><span class="pc-key">X</span> <span data-i18n="hud.putDown">Put parcel down</span></div></div>' +
        '<div id="pcProg" class="pc-off"><div class="pc-top"><span id="pcProgLabel"></span><span class="pc-pct" id="pcProgPct">0%</span></div>' +
        '<div class="pc-track"><div class="pc-fill" id="pcProgFill"></div></div><div class="pc-hint" id="pcProgHint" data-i18n="depot.cancelHint">Press X to cancel</div></div>' +
        '<div id="pcDepot" class="pc-off"><div class="pc-win">' +
        '<div class="pc-head"><img class="pc-logo" src="logo.png" alt="Postal Prime"><span class="pc-title" data-i18n="depot.title">Depot</span><span class="pc-sub" id="pcSub"></span>' +
        '<button class="pc-x" id="pcClose" title="Close (Esc)" data-i18n-title="depot.close">' + ic('close') + '</button></div>' +
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
        $('pcHudCount').textContent = hud.rows.length ? (hud.rows.length > 1 ? t('hud.parcel.other', hud.rows.length) : t('hud.parcel.one', hud.rows.length)) : '';
        $('pcHudKb').classList.toggle('pc-off', !hud.carry);
        $('pcHudRows').innerHTML = hud.rows.map(function (r) {
            var cls = 'dim', txt = t('hud.atDepot');
            if (r.state === 'loaded') {
                var left = hudLeft(r) || 0;
                if (left >= 0) { txt = fmt(left); cls = left < 30 ? 'warn' : ''; }
                else { txt = t('depot.late', fmt(-left)); cls = 'late'; }
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
        return { txt: left >= 0 ? fmt(left) : t('depot.late', fmt(-left)), cls: left < 0 ? 't-late' : (left < 30 ? 't-warn' : 't-ok') };
    }
    function kindTag(k) { return '<span class="pc-tag ' + k + '">' + (k === 'home' ? t('depot.kind.home') : t('depot.kind.locker')) + '</span>'; }
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
        var items = [['shift', t('depot.nav.shift'), 0], ['veh', t('depot.nav.vehicles'), 0], ['board', t('depot.nav.board'), st.onDuty ? (st.boardCount || 0) : 0], ['run', t('depot.nav.run'), claims.length]];
        $('pcNav').innerHTML = items.map(function (nv) {
            return '<button data-tab="' + nv[0] + '" class="' + (tab === nv[0] ? 'on' : '') + '">' + ic(nv[0]) + esc(nv[1]) + (nv[2] ? '<span class="pc-n">' + nv[2] + '</span>' : '') + '</button>';
        }).join('');
        var top = st.nextXp == null;
        var pct = top ? 100 : Math.round(((st.xp - st.levelXp) / Math.max(1, st.nextXp - st.levelXp)) * 100);
        $('pcProf').innerHTML = '<div class="r1"><span>' + esc(t('depot.prof.level', st.level)) + '</span><span class="pc-mono">' + pct + '%</span></div>' +
            '<div class="r2">' + esc(top ? t('depot.prof.maxXp', st.xp) : t('depot.prof.xp', st.xp, st.nextXp)) + '</div><div class="pc-meter"><i style="width:' + pct + '%"></i></div>';
    }

    function viewShift() {
        var r = st.rental, info = st.info || {};
        var h = '<h2 class="pc-h1">' + esc(t('depot.nav.shift')) + '</h2><p class="pc-lead">' + esc(t('depot.shift.lead')) + '</p><div class="pc-cols"><div>';
        h += '<div class="pc-box"><div class="pc-box-h">' + esc(t('depot.shift.status')) + '</div><div class="pc-status"><span class="pc-dot' + (st.onDuty ? ' on' : '') + '"></span>' +
            '<div style="flex:1"><b>' + esc(st.onDuty ? t('depot.onShift') : t('depot.offShift')) + '</b><div class="pc-muted">' + esc(st.onDuty ? t('depot.shift.newOrders') : t('depot.shift.clockOnToReceive')) + '</div></div>' +
            '<button class="pc-btn ' + (st.onDuty ? '' : 'primary') + '" data-act="duty">' + esc(st.onDuty ? t('depot.shift.clockOff') : t('depot.shift.clockOn')) + '</button></div></div>';
        h += '<div class="pc-box"><div class="pc-box-h">' + esc(t('depot.shift.performance')) + '</div><div class="pc-box-b">' +
            '<div class="pc-kv"><span>' + esc(t('depot.shift.level')) + '</span><b>' + st.level + '</b></div>' +
            '<div class="pc-kv"><span>' + esc(t('depot.shift.deliveries')) + '</span><b class="pc-mono">' + (st.deliveries || 0) + '</b></div>' +
            '<div class="pc-kv"><span>' + esc(t('depot.shift.earned')) + '</span><b class="pc-mono">' + money(st.earned) + '</b></div>' +
            '<div class="pc-kv"><span>' + esc(t('depot.shift.atOnce')) + '</span><b class="pc-mono">' + st.batch + '</b></div></div></div>';
        h += '</div><div>';
        if (r) {
            h += '<div class="pc-box"><div class="pc-box-h">' + esc(t('depot.veh.box')) + '<span class="pc-tag ok" style="margin-left:auto">' + esc(t('depot.veh.out')) + '</span></div><div class="pc-box-b">' +
                '<div class="pc-kv"><span>' + esc(t('depot.veh.vehicle')) + '</span><b>' + esc(r.label) + '</b></div><div class="pc-kv"><span>' + esc(t('depot.veh.plate')) + '</span><b class="pc-mono">' + esc(r.plate) + '</b></div>' +
                '<div class="pc-kv"><span>' + esc(t('depot.veh.deposit')) + '</span><b class="pc-mono">' + money(r.deposit) + '</b></div>' +
                '<div class="pc-kv"><span>' + esc(t('depot.veh.capacity')) + '</span><b class="pc-mono">' + esc(t('depot.veh.capacityUsed', st.usedUnits || 0, r.capacity)) + '</b></div></div>' +
                '<div class="pc-pad"><button class="pc-btn danger" style="width:100%" data-act="return">' + esc(t('depot.veh.return')) + '</button></div>' +
                '<div class="pc-note">' + esc(t('depot.veh.parkFirst')) + (info.damageTolerance != null ? ' ' + esc(t('depot.veh.damageNote', info.damageTolerance)) : '') + '</div></div>';
        } else {
            h += '<div class="pc-box"><div class="pc-box-h">' + esc(t('depot.veh.box')) + '</div><div class="pc-empty tight"><b>' + esc(t('depot.veh.none')) + '</b>' + esc(t('depot.veh.noneText')) + '</div></div>';
        }
        return h + '</div></div>';
    }

    function viewVeh() {
        var h = '<h2 class="pc-h1">' + esc(t('depot.vehicles.title')) + '</h2><p class="pc-lead">' + esc(((st.info || {}).damageTolerance != null) ? t('depot.vehicles.leadDamage') : t('depot.vehicles.lead')) + '</p>';
        h += '<div class="pc-box pc-tblbox"><table>' + tblHead([[t('depot.vehicles.colVehicle')], [t('depot.vehicles.colCapacity')], [t('depot.vehicles.colLargest')], [t('depot.vehicles.colDeposit'), 1], ['', 0]]) + '<tbody>';
        (st.vehicles || []).forEach(function (v) {
            var locked = !v.unlocked, cant = locked || !!st.rental || !st.onDuty;
            var label = locked ? t('depot.vehicles.level', v.level) : (st.rental ? t('depot.vehicles.inUse') : (!st.onDuty ? t('depot.vehicles.clockOn') : t('depot.vehicles.rent')));
            h += '<tr class="' + (locked ? 'dim' : '') + '"><td><span class="pc-dest">' + esc(v.label) + '</span></td><td class="pc-mono">' + esc(t('depot.units', v.capacity)) + '</td><td>' + esc(sizeLabel(v.maxBox)) + '</td>' +
                '<td class="r pc-mono">' + money(v.deposit) + '</td><td class="r"><button class="pc-btn sm ' + (cant ? '' : 'primary') + '" data-rent="' + esc(v.key) + '" ' + (cant ? 'disabled' : '') + '>' + esc(label) + '</button></td></tr>';
        });
        return h + '</tbody></table></div>';
    }

    function viewBoard() {
        var mins = (st.info || {}).boardMinutes;
        var h = '<h2 class="pc-h1">' + esc(t('depot.board.title')) + '</h2><p class="pc-lead">' + esc(t('depot.board.lead')) + (mins ? ' ' + esc(t('depot.board.leadMinutes', mins)) : '') + '</p>';
        if (!st.onDuty) return h + '<div class="pc-box"><div class="pc-empty">' + ic('shift') + '<b>' + esc(t('depot.board.offShift')) + '</b>' + esc(t('depot.board.offShiftText')) + '</div></div>';
        if (!board) return h + '<div class="pc-box"><div class="pc-empty"><b>' + esc(t('depot.board.loading')) + '</b></div></div>';
        if (!board.length) return h + '<div class="pc-box"><div class="pc-empty">' + ic('empty') + '<b>' + esc(t('depot.board.empty')) + '</b>' + esc(t('depot.board.emptyText')) + '</div></div>';
        h += '<div class="pc-box pc-tblbox"><table>' + tblHead([[t('depot.board.colType')], [t('depot.board.colDestination')], [t('depot.board.colBox')], [t('depot.board.colDistance'), 1], [t('depot.board.colPay'), 1], ['', 0]]) + '<tbody>';
        board.forEach(function (o) {
            var b = o.blocked;
            h += '<tr class="' + (b ? 'dim' : '') + '"><td>' + kindTag(o.kind) + '</td><td><div class="pc-dest">' + esc(o.label) + '</div>' + (b ? '<div class="pc-why">' + esc(b) + '</div>' : '') + '</td>' +
                '<td>' + esc(sizeLabel(o.size)) + '</td><td class="r pc-mono">' + esc(t('depot.km', Number(o.km).toFixed(1))) + '</td><td class="r pc-mono">' + money(o.pay) + '</td>' +
                '<td class="r"><button class="pc-btn sm ' + (b ? '' : 'primary') + '" data-claim="' + esc(o.orderId) + '" ' + (b ? 'disabled' : '') + '>' + esc(t('depot.board.claim')) + '</button></td></tr>';
        });
        return h + '</tbody></table></div>';
    }

    function viewRun() {
        var claims = st.claims || [];
        var h = '<h2 class="pc-h1">' + esc(t('depot.run.title')) + '</h2><p class="pc-lead">' + esc(t('depot.run.lead')) + '</p>';
        if (!claims.length) return h + '<div class="pc-box"><div class="pc-empty">' + ic('empty') + '<b>' + esc(t('depot.run.empty')) + '</b>' + esc(t('depot.run.emptyText')) + '</div></div>';
        h += '<div class="pc-box pc-tblbox"><table>' + tblHead([[t('depot.board.colDestination')], [t('depot.board.colType')], [t('depot.board.colBox')], [t('depot.run.colStatus')], [t('depot.run.colTimeLeft'), 1], ['', 0]]) + '<tbody>';
        claims.forEach(function (c) {
            var loaded = c.state === 'loaded', tc = timeCell(c);
            h += '<tr><td class="pc-dest">' + esc(c.label) + '</td><td>' + kindTag(c.kind) + '</td><td>' + esc(sizeLabel(c.size)) + '</td>' +
                '<td>' + (loaded ? '<span class="pc-tag ok">' + esc(t('depot.run.outForDelivery')) + '</span>' : '<span class="pc-tag">' + esc(t('depot.run.atPile')) + '</span>') + '</td>' +
                '<td class="r pc-mono ' + (loaded ? tc.cls : '') + '"' + (loaded ? ' data-cid="' + esc(c.orderId) + '"' : '') + '>' + (loaded ? tc.txt : '-') + '</td>' +
                '<td class="r">' + (loaded ? '' : '<button class="pc-btn sm" data-put="' + esc(c.orderId) + '">' + esc(t('depot.run.putBack')) + '</button>') + '</td></tr>';
        });
        h += '</tbody></table></div><div class="pc-foot"><span>' + t('depot.run.capacity', '<b class="pc-mono">' + esc((st.usedUnits || 0) + ' / ' + (st.rental ? st.rental.capacity : '-')) + '</b>') + '</span>' +
            '<span>' + t('depot.run.parcels', '<b class="pc-mono">' + esc(claims.length + ' / ' + st.batch) + '</b>') + '</span><span class="sp"></span><button class="pc-btn danger" data-act="abandon">' + esc(t('depot.run.abandon')) + '</button></div>';
        return h;
    }

    function render() {
        if (!isOpen || !st) return;
        $('pcDepot').classList.remove('pc-off');
        $('pcSub').textContent = st.onDuty ? t('depot.onShift') : t('depot.offShift');
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
            var tc = timeCell(c);
            cells[i].textContent = tc.txt;
            cells[i].className = 'r pc-mono ' + tc.cls;
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
        if (!I18N_LOADED) loadLocale(function () { if (isOpen && st) render(); });
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
            return confirmDlg(t('depot.run.abandonTitle'), t('depot.run.abandonText'), t('depot.run.abandon'), function () { act('abandon', {}); });
        }
        var rent = b.getAttribute('data-rent');
        if (rent) {
            b.textContent = t('depot.vehicles.signing');
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
            '<div class="pc-acts"><button class="pc-btn" id="pcNo">' + esc(t('depot.dlg.cancel')) + '</button><button class="pc-btn primary" id="pcYes">' + esc(yesLabel) + '</button></div></div>';
        d.classList.remove('pc-off');
        dlgCancel = function () { };
        $('pcNo').onclick = function () { closeDlg(); };
        $('pcYes').onclick = function () { dlgCancel = null; closeDlg(true); yes(); };
    }
    function pickDlg(title, items) {
        var d = $('pcDlg');
        var at = Date.now();
        d.innerHTML = '<div class="pc-dlg"><div class="pc-b"><h3>' + esc(title) + '</h3><p>' + esc(t('depot.pick.nearest')) + '</p><div class="pc-pick">' +
            items.map(function (it) {
                var left = it.left == null ? null : it.left - (Date.now() - at) / 1000;
                var tmTxt = left == null ? '' : (left >= 0 ? fmt(left) : t('depot.late', fmt(-left)));
                var cls = left != null && left < 0 ? 'late' : (left != null && left < 30 ? 'warn' : '');
                return '<button data-id="' + esc(it.orderId) + '"><span class="nm">' + esc(it.label) + '<span class="mt">' + esc(t('depot.pick.meta', sizeLabel(it.size), it.km != null ? Number(it.km).toFixed(1) : '')) + '</span></span><span class="tm ' + cls + '">' + tmTxt + '</span></button>';
            }).join('') + '</div></div><div class="pc-acts"><button class="pc-btn" id="pcNo">' + esc(t('depot.dlg.cancel')) + '</button></div></div>';
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

    // Language dictionary (ui/i18n.js): the English defaults above/in the markup stay if it never arrives.
    loadLocale(function () {
        renderHud();
        if (isOpen && st) render();
    });

    // ── messages from client/courier.lua ────────────────────────────────────
    window.addEventListener('message', function (event) {
        var d = event.data;
        if (!d || typeof d !== 'object' || typeof d.action !== 'string') return;
        switch (d.action) {
            case 'as-postalprime:courier:open': openDepot(d.state); break;
            case 'as-postalprime:courier:close': closeDepot(); break;
            case 'as-postalprime:courier:state': if (isOpen) setState(d.state); break;
            case 'as-postalprime:toast': toast(d.title || t('app.name'), d.description || '', d.type); break;
            case 'as-postalprime:courier:progress': progressStart(d.label, d.duration, d.cancellable); break;
            case 'as-postalprime:courier:progressStop': progressStop(); break;
            case 'as-postalprime:courier:hud': setHud(d); break;
            case 'as-postalprime:courier:pick': pickDlg(d.title || t('courier.pick.title'), d.items || []); break;
        }
    });
})();
