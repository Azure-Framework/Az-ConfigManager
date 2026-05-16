function debounce(fn, wait = 120) {
    let timer = null;
    return function debouncedHandler(...args) {
        if (timer) clearTimeout(timer);
        timer = setTimeout(() => fn.apply(this, args), wait);
    };
}

const app = document.getElementById('app');
const resourceList = document.getElementById('resourceList');
const fileList = document.getElementById('fileList');
const fieldList = document.getElementById('fieldList');
const backupList = document.getElementById('backupList');
const rawEditor = document.getElementById('rawEditor');
const emptyState = document.getElementById('emptyState');
const workspace = document.getElementById('workspace');
const resourceSearch = document.getElementById('resourceSearch');
const fieldSearch = document.getElementById('fieldSearch');
const editableOnly = document.getElementById('editableOnly');
const pageTitle = document.getElementById('pageTitle');
const pageSubtitle = document.getElementById('pageSubtitle');
const resourceTitle = document.getElementById('resourceTitle');
const resourceState = document.getElementById('resourceState');
const fileTitle = document.getElementById('fileTitle');
const fileMeta = document.getElementById('fileMeta');
const rawStatus = document.getElementById('rawStatus');
const saveRawBtn = document.getElementById('saveRawBtn');
const restartBtn = document.getElementById('restartBtn');
const statResources = document.getElementById('statResources');
const statFiles = document.getElementById('statFiles');
const statFields = document.getElementById('statFields');
const confirmModal = document.getElementById('confirmModal');
const confirmTitle = document.getElementById('confirmTitle');
const confirmMessage = document.getElementById('confirmMessage');
const confirmCancel = document.getElementById('confirmCancel');
const confirmOk = document.getElementById('confirmOk');

let scanData = { resources: [], totals: { resources: 0, files: 0, fields: 0 }, pendingRestart: {} };
let activeResource = null;
let activeFile = null;
let activeFilePayload = null;
let activeKind = 'all';
let activeTab = 'fields';
let dirtyRaw = false;
let confirmResolver = null;
let currentFields = [];

if (!window.CSS) window.CSS = {};
if (!CSS.escape) {
    CSS.escape = (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, (char) => `\\${char}`);
}


function post(name, data = {}) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).then((r) => r.json());
}

function serverRequest(action, payload = {}) {
    return post('serverRequest', { action, payload }).then((res) => {
        if (!res || res.ok !== true) {
            const msg = res && res.data ? String(res.data) : 'Request failed.';
            throw new Error(msg);
        }
        return res.data;
    });
}

function escapeHtml(value) {
    return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}

function bytes(size) {
    const n = Number(size || 0);
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
    return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

function toast(message, type = 'info') {
    const root = document.getElementById('toastRoot');
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.textContent = message;
    root.appendChild(el);
    setTimeout(() => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(-6px)';
        setTimeout(() => el.remove(), 220);
    }, 3500);
}

function confirmBox(title, message, okText = 'Confirm') {
    confirmTitle.textContent = title;
    confirmMessage.textContent = message;
    confirmOk.textContent = okText;
    confirmModal.classList.remove('hidden');
    return new Promise((resolve) => { confirmResolver = resolve; });
}

function closeConfirm(result) {
    confirmModal.classList.add('hidden');
    if (confirmResolver) confirmResolver(result === true);
    confirmResolver = null;
}

confirmCancel.addEventListener('click', () => closeConfirm(false));
confirmOk.addEventListener('click', () => closeConfirm(true));

function setStats() {
    const totals = scanData.totals || {};
    statResources.textContent = totals.resources || 0;
    statFiles.textContent = totals.files || 0;
    statFields.textContent = totals.fields || 0;
}

function matchesFilter(resource) {
    const query = resourceSearch.value.trim().toLowerCase();
    if (!query) return true;
    if (resource.name.toLowerCase().includes(query) || String(resource.state || '').toLowerCase().includes(query)) return true;
    return (resource.files || []).some((file) => file.path.toLowerCase().includes(query) || file.kind.toLowerCase().includes(query));
}

function renderResources() {
    setStats();
    resourceList.innerHTML = '';
    const resources = (scanData.resources || []).filter(matchesFilter);
    if (!resources.length) {
        resourceList.innerHTML = '<div class="helper-card">No matching resources with editable config files.</div>';
        return;
    }
    const frag = document.createDocumentFragment();
    for (const res of resources) {
        const item = document.createElement('div');
        item.className = `resource-item ${activeResource && activeResource.name === res.name ? 'active' : ''}`;
        item.innerHTML = `
            <div class="resource-name">${escapeHtml(res.name)}</div>
            <div class="resource-meta">
                <span class="state-dot ${escapeHtml(res.state || '')}"></span>
                <span>${escapeHtml(res.state || 'unknown')}</span>
                <span>•</span>
                <span>${res.fileCount || 0} files</span>
            </div>`;
        item.addEventListener('click', () => selectResource(res.name));
        frag.appendChild(item);
    }
    resourceList.appendChild(frag);
}

function getResource(name) {
    return (scanData.resources || []).find((res) => res.name === name) || null;
}

function selectResource(name) {
    const res = getResource(name);
    if (!res) return;
    activeResource = res;
    activeFile = null;
    activeFilePayload = null;
    currentFields = [];
    dirtyRaw = false;

    emptyState.classList.add('hidden');
    workspace.classList.remove('hidden');
    saveRawBtn.classList.add('hidden');
    restartBtn.classList.toggle('hidden', !(scanData.allowRestart && scanData.pendingRestart && scanData.pendingRestart[res.name]));

    pageTitle.textContent = res.name;
    pageSubtitle.textContent = `${res.fileCount} editable config file(s) detected`;
    resourceTitle.textContent = res.name;
    resourceState.textContent = `State: ${res.state || 'unknown'}`;
    fileTitle.textContent = 'Pick a config file';
    fileMeta.textContent = 'Fields will load after selecting a file.';
    rawEditor.value = '';
    if (fieldSearch) fieldSearch.value = '';
    fieldList.innerHTML = '<div class="helper-card">Choose a file from this resource.</div>';
    backupList.innerHTML = '';

    renderResources();
    renderFiles();

    const firstMatchingFile = activeKind === 'all' ? null : res.files.find((file) => file.kind === activeKind);
    const firstFile = firstMatchingFile || res.files[0];
    if (firstFile) selectFile(firstFile.id);
}

function renderFiles() {
    fileList.innerHTML = '';
    if (!activeResource) return;
    const allFiles = activeResource.files || [];
    const matching = activeKind === 'all' ? allFiles : allFiles.filter((file) => file.kind === activeKind);
    const nonMatching = activeKind === 'all' ? [] : allFiles.filter((file) => file.kind !== activeKind);
    const files = [...matching, ...nonMatching];
    if (!files.length) {
        fileList.innerHTML = '<div class="helper-card">No config files detected for this resource yet. Use Raw scan settings in config.lua or rescan after the resource starts.</div>';
        return;
    }
    const frag = document.createDocumentFragment();
    for (const file of files) {
        const item = document.createElement('div');
        item.className = `file-item ${activeFile && activeFile.id === file.id ? 'active' : ''}`;
        item.innerHTML = `
            <div class="file-name">${escapeHtml(file.path)}</div>
            <div class="file-meta">
                <span class="kind-badge">${escapeHtml(file.kind)}</span>
                <span>${bytes(file.size)}</span>
                <span>•</span>
                <span>${file.fields || 0} fields</span>
            </div>`;
        item.addEventListener('click', () => selectFile(file.id));
        frag.appendChild(item);
    }
    fileList.appendChild(frag);
}

async function selectFile(fileId) {
    if (dirtyRaw) {
        const keepGoing = await confirmBox('Unsaved raw changes', 'You have unsaved raw text. Continue and lose those changes?', 'Continue');
        if (!keepGoing) return;
    }
    try {
        setBusy(true);
        const payload = await serverRequest('getFile', { fileId });
        activeFilePayload = payload;
        activeFile = payload.info;
        dirtyRaw = false;
        if (fieldSearch) fieldSearch.value = '';
        renderFiles();
        renderFilePayload(payload);
        await loadBackups();
    } catch (err) {
        toast(err.message, 'error');
    } finally {
        setBusy(false);
    }
}

function renderFilePayload(payload) {
    const info = payload.info;
    fileTitle.textContent = info.path;
    fileMeta.textContent = `${info.resource} • ${info.kind} • ${bytes(info.size)} • ${payload.fieldCount || 0} parsed fields`;
    rawStatus.textContent = `${info.path} loaded`;
    rawEditor.value = payload.content || '';
    saveRawBtn.classList.remove('hidden');
    saveRawBtn.classList.toggle('soft-hidden', activeTab !== 'raw');
    restartBtn.classList.toggle('hidden', !(scanData.allowRestart && (payload.pendingRestart || (scanData.pendingRestart && scanData.pendingRestart[info.resource]))));
    currentFields = payload.fields || [];
    renderFields();
}

function fieldMatches(field) {
    if (editableOnly && editableOnly.checked && field.editable === false) return false;
    const query = fieldSearch ? fieldSearch.value.trim().toLowerCase() : '';
    if (!query) return true;
    const haystack = `${field.key || ''} ${field.type || ''} ${field.value ?? ''} ${field.raw ?? ''}`.toLowerCase();
    return haystack.includes(query);
}

function renderFields(fields) {
    if (Array.isArray(fields)) currentFields = fields;
    fieldList.innerHTML = '';
    if (!activeFile) {
        fieldList.innerHTML = '<div class="helper-card">Select a file first.</div>';
        return;
    }
    if (!currentFields.length) {
        fieldList.innerHTML = '<div class="helper-card warning">No simple fields were parsed. Use Raw mode for this config file.</div>';
        return;
    }

    const visibleFields = currentFields.filter(fieldMatches);
    if (!visibleFields.length) {
        fieldList.innerHTML = '<div class="helper-card">No fields match that search/filter.</div>';
        return;
    }

    const frag = document.createDocumentFragment();
    for (const field of visibleFields) {
        const card = document.createElement('div');
        card.className = `field-card ${field.editable === false ? 'view-only' : ''}`;
        card.dataset.fieldId = field.id;
        card.dataset.fieldType = field.type;
        const prettyType = typeLabel(field.type);
        card.innerHTML = `
            <div class="field-top">
                <div>
                    <div class="field-key">${escapeHtml(field.key)}</div>
                    <div class="muted">${field.startLine ? `Line ${field.startLine}${field.endLine && field.endLine !== field.startLine ? `-${field.endLine}` : ''}` : 'JSON path'}</div>
                </div>
                <span class="type-badge ${field.type === 'color' || field.type === 'rgba_table' ? 'color-type' : ''}">${escapeHtml(prettyType)}</span>
            </div>
            ${renderFieldInput(field)}`;
        const saveButton = card.querySelector('[data-save-field]');
        if (saveButton) saveButton.addEventListener('click', () => saveField(field.id));
        const coordsButton = card.querySelector('[data-use-coords]');
        if (coordsButton) coordsButton.addEventListener('click', () => useCurrentCoords(field.id));
        bindColorControls(card);
        bindRgbaControls(card);
        frag.appendChild(card);
    }
    fieldList.appendChild(frag);
}

function typeLabel(type) {
    if (type === 'color' || type === 'rgba_table') return 'color';
    if (type === 'json-table') return 'table';
    return String(type || 'raw');
}

function colorTextToHex(value) {
    const text = String(value || '').trim();
    const shortHex = text.match(/^#([0-9a-f]{3})$/i);
    if (shortHex) return '#' + shortHex[1].split('').map((c) => c + c).join('').toLowerCase();
    const fullHex = text.match(/^#([0-9a-f]{6})/i);
    if (fullHex) return '#' + fullHex[1].toLowerCase();
    const rgba = text.match(/^rgba?\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})/i);
    if (rgba) {
        const toHex = (n) => Math.max(0, Math.min(255, Number(n) || 0)).toString(16).padStart(2, '0');
        return `#${toHex(rgba[1])}${toHex(rgba[2])}${toHex(rgba[3])}`;
    }
    return '#229bff';
}

function hexToRgb(hex) {
    const clean = String(hex || '').replace('#', '').trim();
    if (!/^[0-9a-f]{6}$/i.test(clean)) return { r: 34, g: 155, b: 255 };
    return {
        r: parseInt(clean.slice(0, 2), 16),
        g: parseInt(clean.slice(2, 4), 16),
        b: parseInt(clean.slice(4, 6), 16),
    };
}

function clampByte(value, fallback = 0) {
    const n = Number(value);
    if (!Number.isFinite(n)) return fallback;
    return Math.max(0, Math.min(255, Math.round(n)));
}

function bindColorControls(card) {
    const picker = card.querySelector('.field-color-picker');
    const text = card.querySelector('.field-color-text');
    if (!picker || !text) return;
    picker.addEventListener('input', () => { text.value = picker.value; });
    text.addEventListener('input', () => {
        const hex = colorTextToHex(text.value);
        if (/^#[0-9a-f]{6}$/i.test(hex)) picker.value = hex;
    });
}

function bindRgbaControls(card) {
    const picker = card.querySelector('.rgba-color-picker');
    const hex = card.querySelector('.rgba-hex');
    const r = card.querySelector('.rgba-r');
    const g = card.querySelector('.rgba-g');
    const b = card.querySelector('.rgba-b');
    if (!picker || !hex || !r || !g || !b) return;

    const refreshHexFromBoxes = () => {
        const toHex = (n) => clampByte(n).toString(16).padStart(2, '0');
        const next = `#${toHex(r.value)}${toHex(g.value)}${toHex(b.value)}`;
        picker.value = next;
        hex.value = next;
    };

    picker.addEventListener('input', () => {
        const rgb = hexToRgb(picker.value);
        r.value = rgb.r;
        g.value = rgb.g;
        b.value = rgb.b;
        hex.value = picker.value;
    });

    hex.addEventListener('input', () => {
        const parsed = colorTextToHex(hex.value);
        if (/^#[0-9a-f]{6}$/i.test(parsed)) {
            const rgb = hexToRgb(parsed);
            picker.value = parsed;
            r.value = rgb.r;
            g.value = rgb.g;
            b.value = rgb.b;
        }
    });

    [r, g, b].forEach((input) => input.addEventListener('input', refreshHexFromBoxes));
}

function looksLikeCoordField(field) {
    const text = `${field && field.key ? field.key : ''} ${field && field.raw ? field.raw : ''}`.toLowerCase();
    return /\b(?:vec|vector)[234]\s*\(/i.test(text)
        || /(location|coord|coords|position|pos|spawn|depot|garage|route|point|drop|pickup|blip)/i.test(text);
}

function fmtCoord(value) {
    const n = Number(value || 0);
    return Number.isFinite(n) ? n.toFixed(3).replace(/\.?0+$/, '') : '0';
}

function replaceFirstVector(text, values) {
    const re = /\b(vec|vector)([234])\s*\(([^)]*)\)/i;
    if (!re.test(text)) return null;
    return text.replace(re, (match, ctor, countText) => {
        const count = Math.max(2, Math.min(4, Number(countText) || 3));
        const nums = values.slice(0, count).map(fmtCoord).join(', ');
        return `${ctor}${count}(${nums})`;
    });
}

function renderFieldInput(field) {
    if (field.editable === false) {
        return `
            <div class="field-value-row">
                <input class="field-input" value="${escapeHtml(field.value)}" disabled />
                <button class="btn btn-small btn-ghost" disabled>View Only</button>
            </div>`;
    }

    if (field.type === 'boolean') {
        return `
            <div class="field-value-row">
                <label class="switch-row"><input type="checkbox" class="field-bool" ${field.value ? 'checked' : ''} /><span></span><b>${field.value ? 'Enabled' : 'Disabled'}</b></label>
                <button class="btn btn-small btn-blue" data-save-field>Save</button>
            </div>`;
    }

    if (field.type === 'number') {
        return `
            <div class="field-value-row">
                <input class="field-input field-number" type="number" step="any" value="${escapeHtml(field.value)}" />
                <button class="btn btn-small btn-blue" data-save-field>Save</button>
            </div>`;
    }

    if (field.type === 'rgba_table') {
        const value = field.value || {};
        const r = clampByte(value.r ?? value.R ?? value[0] ?? value[1] ?? 0);
        const g = clampByte(value.g ?? value.G ?? value[1] ?? value[2] ?? 150);
        const b = clampByte(value.b ?? value.B ?? value[2] ?? value[3] ?? 255);
        const a = clampByte(value.a ?? value.A ?? value[3] ?? value[4] ?? 180, 180);
        const hex = `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
        return `
            <div class="field-value-row">
                <div class="rgba-editor">
                    <div class="rgba-main">
                        <input class="rgba-color-picker" type="color" value="${escapeHtml(hex)}" />
                        <input class="field-input rgba-hex" type="text" value="${escapeHtml(hex)}" placeholder="#0096ff" />
                    </div>
                    <div class="rgba-grid">
                        <label class="rgba-box"><span>R</span><input class="rgba-r" type="number" min="0" max="255" step="1" value="${r}" /></label>
                        <label class="rgba-box"><span>G</span><input class="rgba-g" type="number" min="0" max="255" step="1" value="${g}" /></label>
                        <label class="rgba-box"><span>B</span><input class="rgba-b" type="number" min="0" max="255" step="1" value="${b}" /></label>
                        <label class="rgba-box"><span>A</span><input class="rgba-a" type="number" min="0" max="255" step="1" value="${a}" /></label>
                    </div>
                </div>
                <button class="btn btn-small btn-blue" data-save-field>Save</button>
            </div>`;
    }

    if (field.type === 'color') {
        const textValue = String(field.value ?? '');
        const hex = colorTextToHex(textValue);
        return `
            <div class="field-value-row">
                <div class="color-editor">
                    <input class="field-color-picker" type="color" value="${escapeHtml(hex)}" />
                    <input class="field-input field-color-text" type="text" value="${escapeHtml(textValue)}" placeholder="#229bff or rgba(34,155,255,0.85)" />
                </div>
                <button class="btn btn-small btn-blue" data-save-field>Save</button>
            </div>`;
    }

    if (field.type === 'string') {
        return `
            <div class="field-value-row">
                <input class="field-input field-string" type="text" value="${escapeHtml(field.value)}" />
                <button class="btn btn-small btn-blue" data-save-field>Save</button>
            </div>`;
    }

    if (field.type === 'vector2' || field.type === 'vector3' || field.type === 'vector4') {
        const count = Number(String(field.type).replace('vector', '')) || 3;
        const values = Array.isArray(field.value) ? field.value : [];
        const labels = ['X', 'Y', 'Z', count === 4 ? 'Heading / W' : 'W'];
        const boxes = ['x', 'y', 'z', 'w'].slice(0, count).map((label, idx) => `
            <label class="vector-box">
                <span>${escapeHtml(labels[idx] || label.toUpperCase())}</span>
                <input class="vector-input" data-index="${idx}" type="number" step="any" value="${escapeHtml(values[idx] ?? 0)}" />
            </label>`).join('');
        return `
            <div class="field-value-row vector-row">
                <div>
                    <div class="vector-grid count-${count}">${boxes}</div>
                    <div class="quick-actions">
                        <button class="btn btn-small btn-ghost" data-use-coords>${count === 4 ? 'Use Current Pos + Heading' : 'Use Current Pos'}</button>
                    </div>
                </div>
                <button class="btn btn-small btn-blue" data-save-field>Save</button>
            </div>`;
    }

    if (field.type === 'table' || field.type === 'raw') {
        const coordButton = looksLikeCoordField(field)
            ? `<button class="btn btn-small btn-ghost" data-use-coords>Use Current Pos in Raw</button>`
            : '';
        return `
            <div class="field-value-row raw-field-row">
                <div>
                    <textarea class="field-textarea field-raw" spellcheck="false">${escapeHtml(field.raw || field.value || '')}</textarea>
                    ${coordButton ? `<div class="quick-actions">${coordButton}</div>` : ''}
                </div>
                <button class="btn btn-small btn-blue" data-save-field>Save</button>
            </div>`;
    }

    return `
        <div class="field-value-row">
            <input class="field-input" value="${escapeHtml(field.value)}" disabled />
            <button class="btn btn-small btn-ghost" disabled>Raw Only</button>
        </div>`;
}

window.saveField = async function saveField(fieldId) {
    if (!activeFile) return;
    const card = fieldList.querySelector(`[data-field-id="${CSS.escape(fieldId)}"]`);
    if (!card) return;
    const type = card.dataset.fieldType;
    let value = null;
    let raw = null;

    if (type === 'boolean') {
        value = card.querySelector('.field-bool').checked;
    } else if (type === 'number') {
        value = card.querySelector('.field-number').value;
    } else if (type === 'string') {
        value = card.querySelector('.field-string').value;
    } else if (type === 'color') {
        value = card.querySelector('.field-color-text').value.trim();
    } else if (type === 'rgba_table') {
        value = {
            r: clampByte(card.querySelector('.rgba-r').value),
            g: clampByte(card.querySelector('.rgba-g').value),
            b: clampByte(card.querySelector('.rgba-b').value),
            a: clampByte(card.querySelector('.rgba-a').value, 255),
        };
    } else if (type.startsWith('vector')) {
        value = Array.from(card.querySelectorAll('.vector-input')).map((input) => Number(input.value || 0));
    } else if (type === 'table' || type === 'raw') {
        raw = card.querySelector('.field-raw').value;
    } else {
        toast('This field type must be edited in Raw mode.', 'warn');
        return;
    }

    try {
        setBusy(true);
        const msg = await serverRequest('saveField', { fileId: activeFile.id, fieldId, type, value, raw });
        toast(String(msg || 'Saved.'), 'success');
        await reloadScanKeepSelection();
        await selectFile(activeFile.id);
    } catch (err) {
        toast(err.message, 'error');
    } finally {
        setBusy(false);
    }
};

window.useCurrentCoords = async function useCurrentCoords(fieldId) {
    const card = fieldList.querySelector(`[data-field-id="${CSS.escape(fieldId)}"]`);
    if (!card) return;
    try {
        const res = await post('getPlayerCoords', {});
        if (!res || res.ok !== true) throw new Error('Could not read player coordinates.');
        const values = [res.data.x, res.data.y, res.data.z, res.data.w];
        const inputs = Array.from(card.querySelectorAll('.vector-input'));
        if (inputs.length) {
            inputs.forEach((input, idx) => input.value = values[idx] ?? 0);
            toast(inputs.length >= 4 ? 'Current position and heading inserted.' : 'Current position inserted.', 'success');
            return;
        }

        const textarea = card.querySelector('.field-raw');
        if (textarea) {
            const replaced = replaceFirstVector(textarea.value, values);
            if (!replaced) {
                toast('No vec2/vec3/vec4 was found in this raw field. Use Raw mode for this one.', 'warn');
                return;
            }
            textarea.value = replaced;
            toast('Current position inserted into the raw vector line. Press Save to write it.', 'success');
            return;
        }

        toast('This field does not support player coords.', 'warn');
    } catch (err) {
        toast(err.message, 'error');
    }
};

async function loadBackups() {
    backupList.innerHTML = '<div class="helper-card">Loading backups...</div>';
    if (!activeFile) return;
    try {
        const backups = await serverRequest('getBackups', { fileId: activeFile.id });
        renderBackups(backups || []);
    } catch (err) {
        backupList.innerHTML = `<div class="helper-card warning">${escapeHtml(err.message)}</div>`;
    }
}

function renderBackups(backups) {
    if (!backups.length) {
        backupList.innerHTML = '<div class="helper-card">No backups for this file yet. One will be created automatically on the first save.</div>';
        return;
    }
    backupList.innerHTML = '';
    for (const backup of backups) {
        const card = document.createElement('div');
        card.className = 'backup-card';
        card.innerHTML = `
            <div class="backup-top">
                <div>
                    <div class="backup-name">${escapeHtml(backup.createdAt || 'Backup')}</div>
                    <p>${escapeHtml(backup.resource)} / ${escapeHtml(backup.path)}</p>
                    <p>${bytes(backup.size)} • by ${escapeHtml(backup.sourceName || 'unknown')}</p>
                </div>
                <button class="btn btn-small btn-warn">Restore</button>
            </div>`;
        card.querySelector('button').addEventListener('click', async () => {
            const ok = await confirmBox('Restore backup?', `Restore ${backup.resource}/${backup.path} from ${backup.createdAt}?`, 'Restore');
            if (!ok) return;
            try {
                setBusy(true);
                const msg = await serverRequest('restoreBackup', { backupPath: backup.backupPath });
                toast(String(msg || 'Backup restored.'), 'success');
                await reloadScanKeepSelection();
                if (activeFile) await selectFile(activeFile.id);
            } catch (err) {
                toast(err.message, 'error');
            } finally {
                setBusy(false);
            }
        });
        backupList.appendChild(card);
    }
}

function setTab(tabName) {
    activeTab = tabName;
    document.querySelectorAll('.tab').forEach((tab) => tab.classList.toggle('active', tab.dataset.tab === tabName));
    document.querySelectorAll('.tab-panel').forEach((panel) => panel.classList.remove('active'));
    document.getElementById(`${tabName}Tab`).classList.add('active');
    saveRawBtn.classList.toggle('soft-hidden', tabName !== 'raw');
    if (tabName === 'backups' && activeFile) loadBackups();
}

function setBusy(busy) {
    document.body.classList.toggle('busy', busy === true);
}

async function reloadScanKeepSelection() {
    const selectedResource = activeResource ? activeResource.name : null;
    scanData = await serverRequest('getResources', {});
    if (selectedResource) activeResource = getResource(selectedResource);
    setStats();
    renderResources();
    renderFiles();
}

async function rescan() {
    try {
        setBusy(true);
        const selectedResource = activeResource ? activeResource.name : null;
        scanData = await serverRequest('rescan', {});
        if (selectedResource) activeResource = getResource(selectedResource);
        renderResources();
        renderFiles();
        setStats();
        toast('Resources rescanned.', 'success');
    } catch (err) {
        toast(err.message, 'error');
    } finally {
        setBusy(false);
    }
}

saveRawBtn.addEventListener('click', async () => {
    if (!activeFile) return;
    const ok = await confirmBox('Save raw file?', 'This will overwrite the target config file. A backup will be created first.', 'Save');
    if (!ok) return;
    try {
        setBusy(true);
        const msg = await serverRequest('saveRaw', { fileId: activeFile.id, content: rawEditor.value });
        dirtyRaw = false;
        toast(String(msg || 'Saved.'), 'success');
        await reloadScanKeepSelection();
        await selectFile(activeFile.id);
    } catch (err) {
        toast(err.message, 'error');
    } finally {
        setBusy(false);
    }
});

restartBtn.addEventListener('click', async () => {
    const resource = activeResource ? activeResource.name : (activeFile ? activeFile.resource : null);
    if (!resource) return;
    const ok = await confirmBox('Restart resource?', `Restart ${resource}? Players using this resource may see it reload.`, 'Restart');
    if (!ok) return;
    try {
        setBusy(true);
        const msg = await serverRequest('restartResource', { resource });
        toast(String(msg || 'Restart sent.'), 'success');
        await new Promise((resolve) => setTimeout(resolve, 900));
        await reloadScanKeepSelection();
    } catch (err) {
        toast(err.message, 'error');
    } finally {
        setBusy(false);
    }
});

document.getElementById('rescanBtn').addEventListener('click', rescan);
document.getElementById('closeBtn').addEventListener('click', () => post('close', {}));
document.getElementById('reloadFileBtn').addEventListener('click', () => activeFile && selectFile(activeFile.id));
rawEditor.addEventListener('input', () => dirtyRaw = true);
resourceSearch.addEventListener('input', (typeof debounce === 'function' ? debounce(renderResources, 90) : renderResources));
if (fieldSearch) fieldSearch.addEventListener('input', (typeof debounce === 'function' ? debounce(() => renderFields(), 90) : () => renderFields()));
if (editableOnly) editableOnly.addEventListener('change', () => renderFields());

document.querySelectorAll('.pill').forEach((pill) => {
    pill.addEventListener('click', () => {
        document.querySelectorAll('.pill').forEach((p) => p.classList.remove('active'));
        pill.classList.add('active');
        activeKind = pill.dataset.kind || 'all';
        renderResources();
        renderFiles();
    });
});

document.querySelectorAll('.tab').forEach((tab) => tab.addEventListener('click', () => setTab(tab.dataset.tab)));

function bindManualScroll(id) {
    const el = document.getElementById(id);
    if (!el) return;
    el.addEventListener('wheel', (e) => {
        const nestedText = e.target && e.target.closest ? e.target.closest('textarea, #rawEditor') : null;
        if (nestedText && nestedText !== el && nestedText.scrollHeight > nestedText.clientHeight) {
            e.stopPropagation();
            return;
        }
        if (!(el.scrollHeight > el.clientHeight)) return;
        e.preventDefault();
        e.stopPropagation();
        el.scrollTop += e.deltaY;
    }, { passive: false });
}

['resourceList', 'fileList', 'fieldList', 'backupList'].forEach(bindManualScroll);
if (rawEditor) rawEditor.addEventListener('wheel', (e) => e.stopPropagation(), { passive: true });

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (!confirmModal.classList.contains('hidden')) closeConfirm(false);
        else post('close', {});
    }
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
        e.preventDefault();
        if (!saveRawBtn.classList.contains('hidden') && activeTab === 'raw') saveRawBtn.click();
    }
});

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') {
        scanData = data.payload || scanData;
        app.classList.remove('hidden');
        setStats();
        renderResources();
        if (!activeResource) {
            emptyState.classList.remove('hidden');
            workspace.classList.add('hidden');
        }
    } else if (data.action === 'close') {
        app.classList.add('hidden');
        dirtyRaw = false;
    } else if (data.action === 'toast') {
        toast(data.payload && data.payload.message ? data.payload.message : 'Notification', data.payload && data.payload.type ? data.payload.type : 'info');
    }
});

console.log('Az-ConfigManager v6 recursive scanner loaded');
