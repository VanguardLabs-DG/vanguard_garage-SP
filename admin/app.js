/* ==========================================================================
   VANGUARD GARAGE - ADMIN UI SCRIPT
   1:1 Functional & UX Parity with Legacy CallAdmin Garages
   Engineered for mri_Qadmin / Qbox Architecture
   ========================================================================== */

(function () {
  'use strict';

  // --- STATE ---
  let allGarages = [];
  let catalogTypes = [];
  let currentRevision = '';
  let currentFilter = 'all'; // 'all' | 'public' | 'job' | 'paid'
  let searchQuery = '';
  let viewMode = 'table'; // 'table' | 'cards'
  let isBusy = false;

  // Active Editing/Creating State
  let editingGarage = null;
  let formMarker = null; // { x, y, z }
  let formSpawns = []; // [ { x, y, z, heading } ]
  let pendingDelete = null; // Garage object

  // --------------------------------------------------------------------------
  // NUI Bridge
  // --------------------------------------------------------------------------
  async function fetchNui(eventName, data = {}) {
    try {
      const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'vanguard_garage';
      const response = await fetch(`https://${resourceName}/${eventName}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify(data),
      });
      return await response.json();
    } catch (err) {
      console.warn(`[vanguard_garage/admin] NUI error for ${eventName}:`, err);
      return { ok: false, code: 'fetch_error', message: 'Falha de comunicação com o jogo.' };
    }
  }

  // --------------------------------------------------------------------------
  // Toast Notifications
  // --------------------------------------------------------------------------
  function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;

    let iconSvg = '';
    if (type === 'success') {
      iconSvg = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#10b981" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';
    } else if (type === 'error') {
      iconSvg = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#ef4444" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="15" y1="9" x2="9" y2="15"></line><line x1="9" y1="9" x2="15" y2="15"></line></svg>';
    } else {
      iconSvg = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#3b82f6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" cy="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>';
    }

    toast.innerHTML = `
      ${iconSvg}
      <span style="flex: 1; line-height: 1.4;">${escapeHtml(message)}</span>
    `;

    container.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(10px) scale(0.95)';
      toast.style.transition = 'all 0.2s ease';
      setTimeout(() => toast.remove(), 220);
    }, 4500);
  }

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // --------------------------------------------------------------------------
  // Data Loading & Processing
  // --------------------------------------------------------------------------
  async function loadGarages() {
    isBusy = true;
    const res = await fetchNui('getCityModule', { module: 'garages' });
    isBusy = false;

    if (!res || !res.ok) {
      showToast((res && res.message) || 'Falha ao carregar garagens do servidor.', 'error');
      return;
    }

    const payload = res.data || res;
    allGarages = Array.isArray(payload.records) ? payload.records : [];
    currentRevision = payload.revision || '';

    if (payload.catalog && Array.isArray(payload.catalog.garageTypes)) {
      catalogTypes = payload.catalog.garageTypes;
    }

    updateHeaderStats();
    populateTypeSelect();
    renderGarages();
  }

  function updateHeaderStats() {
    const revEl = document.getElementById('revisionBadge');
    const headerSub = document.getElementById('headerSubtitle');

    if (revEl) {
      revEl.textContent = `rev: ${currentRevision || 'live'}`;
    }

    if (headerSub) {
      headerSub.textContent = `Schema custom_garages validado. ${allGarages.length} garagens sincronizadas ao vivo sem reiniciar o recurso.`;
    }

    // Filter Counts
    const publicCount = allGarages.filter((g) => (!g.permission || g.permission === '' || g.permission === 'false') && g.name === 'Garage').length;
    const jobCount = allGarages.filter((g) => (g.permission && g.permission !== '' && g.permission !== 'false') || g.name !== 'Garage').length;
    const paidCount = allGarages.filter((g) => g.payment === true || g.payment === 'true' || g.payment === 1).length;

    const countAll = document.getElementById('countAll');
    const countPublic = document.getElementById('countPublic');
    const countJob = document.getElementById('countJob');
    const countPaid = document.getElementById('countPaid');

    if (countAll) countAll.textContent = allGarages.length;
    if (countPublic) countPublic.textContent = publicCount;
    if (countJob) countJob.textContent = jobCount;
    if (countPaid) countPaid.textContent = paidCount;
  }

  function populateTypeSelect() {
    const select = document.getElementById('garageTypeSelect');
    if (!select) return;

    select.innerHTML = '<option value="Garage">Garage (Pública / Pessoal)</option>';

    catalogTypes.forEach((t) => {
      if (t.value !== 'Garage') {
        const opt = document.createElement('option');
        opt.value = t.value;
        const countTxt = t.count ? ` (${t.count} veículos)` : '';
        opt.textContent = `${t.label || t.value}${countTxt}`;
        select.appendChild(opt);
      }
    });

    select.addEventListener('change', updatePresetPreview);
  }

  // Preset Preview (Idêntico ao CallAdmin linhas 624-625 e 1022)
  function updatePresetPreview() {
    const select = document.getElementById('garageTypeSelect');
    const preview = document.getElementById('catalogPresetPreview');
    const titleEl = document.getElementById('presetTitle');
    const detailEl = document.getElementById('presetDetail');
    const badgeEl = document.getElementById('presetBadge');

    if (!select || !preview) return;

    const val = select.value;
    if (!val || val === 'Garage') {
      preview.style.display = 'flex';
      titleEl.textContent = 'Garage (Pública / Pessoal)';
      detailEl.textContent = 'Carrega automaticamente os veículos civis próprios que o jogador possui no banco de dados.';
      badgeEl.textContent = 'PUB';
      return;
    }

    const found = catalogTypes.find((t) => t.value.toLowerCase() === val.toLowerCase());
    if (found) {
      preview.style.display = 'flex';
      titleEl.textContent = found.label || found.value;
      badgeEl.textContent = String(found.count || found.vehicles?.length || 0);

      if (found.vehicles && found.vehicles.length > 0) {
        detailEl.textContent = found.vehicles.map((v) => v.model).join(' · ');
      } else {
        detailEl.textContent = 'Categoria sem veículos pré-configurados no Works.';
      }
    } else {
      preview.style.display = 'flex';
      titleEl.textContent = val;
      badgeEl.textContent = 'CST';
      detailEl.textContent = 'Categoria customizada informada manualmente.';
    }
  }

  // --------------------------------------------------------------------------
  // Rendering Table / Cards
  // --------------------------------------------------------------------------
  function renderGarages() {
    const tableBody = document.getElementById('garagesTableBody');
    const cardsGrid = document.getElementById('cardsView');
    const emptyState = document.getElementById('emptyState');
    const tableView = document.getElementById('tableView');

    if (!tableBody || !cardsGrid) return;

    // Filter items
    const filtered = allGarages.filter((g) => {
      // 1. Filter Chip
      const isJob = (g.permission && g.permission !== '' && g.permission !== 'false') || g.name !== 'Garage';
      const isPaid = g.payment === true || g.payment === 'true' || g.payment === 1;

      if (currentFilter === 'public' && isJob) return false;
      if (currentFilter === 'job' && !isJob) return false;
      if (currentFilter === 'paid' && !isPaid) return false;

      // 2. Search Query
      if (searchQuery) {
        const q = searchQuery.toLowerCase();
        const idMatch = String(g.garageId || g.id || '').toLowerCase().includes(q);
        const nameMatch = String(g.name || '').toLowerCase().includes(q);
        const permMatch = String(g.permission || '').toLowerCase().includes(q);
        const coordsMatch = `${g.x}, ${g.y}`.includes(q);
        if (!idMatch && !nameMatch && !permMatch && !coordsMatch) {
          return false;
        }
      }

      return true;
    });

    if (filtered.length === 0) {
      tableBody.innerHTML = '';
      cardsGrid.innerHTML = '';
      if (tableView) tableView.style.display = 'none';
      if (cardsGrid) cardsGrid.style.display = 'none';
      if (emptyState) emptyState.style.display = 'flex';
      return;
    }

    if (emptyState) emptyState.style.display = 'none';
    if (viewMode === 'table') {
      if (tableView) tableView.style.display = 'block';
      if (cardsGrid) cardsGrid.style.display = 'none';
      renderTableRows(filtered);
    } else {
      if (tableView) tableView.style.display = 'none';
      if (cardsGrid) cardsGrid.style.display = 'grid';
      renderCards(filtered);
    }
  }

  function renderTableRows(items) {
    const tableBody = document.getElementById('garagesTableBody');
    tableBody.innerHTML = '';

    items.forEach((g) => {
      const tr = document.createElement('tr');

      const isPaid = g.payment === true || g.payment === 'true' || g.payment === 1;
      const permText = g.permission && g.permission !== '' && g.permission !== 'false' ? g.permission : 'Pública';
      const isPublic = permText === 'Pública';
      const spawnsCount = Array.isArray(g.spawns) ? g.spawns.length : (g.spawn ? 1 : 0);
      const coords = g.marker || { x: g.x, y: g.y, z: g.z };

      tr.innerHTML = `
        <td>
          <span class="badge-id" onclick="window.copyToClipboard('${escapeHtml(g.garageId)}')" title="Clique para copiar">
            #${escapeHtml(g.garageId)}
          </span>
        </td>
        <td>
          <div class="category-cell">
            <span class="category-name">${escapeHtml(g.name || 'Garage')}</span>
            <span class="category-badge">${g.name === 'Garage' ? 'Veículos Pessoais' : 'Categoria de Serviço'}</span>
          </div>
        </td>
        <td>
          <span class="tag-perm ${isPublic ? 'tag-perm--public' : ''}">
            ${escapeHtml(permText)}
          </span>
        </td>
        <td>
          <span class="tag-payment ${isPaid ? 'tag-payment--paid' : 'tag-payment--free'}">
            ${isPaid ? 'Paga' : 'Grátis'}
          </span>
        </td>
        <td>
          <span class="coords-compact">
            ${Number(coords.x || 0).toFixed(2)}, ${Number(coords.y || 0).toFixed(2)}, ${Number(coords.z || 0).toFixed(2)}
          </span>
        </td>
        <td>
          <span class="spawns-count-badge">
            <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <rect x="1" y="3" width="15" height="13"></rect>
              <polygon points="16 8 20 8 23 11 23 16 16 16 16 8"></polygon>
              <circle cx="5.5" cy="18.5" r="2.5"></circle>
              <circle cx="18.5" cy="18.5" r="2.5"></circle>
            </svg>
            ${spawnsCount} vaga${spawnsCount !== 1 ? 's' : ''}
          </span>
        </td>
        <td>
          <div class="actions-group">
            <button class="btn-icon-action btn-icon-action--teleport" onclick="window.teleportToGarage(${g.id})" title="Teleportar até a entrada">
              <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="10"></circle>
                <polygon points="12 8 8 12 12 16 12 8"></polygon>
              </svg>
            </button>
            <button class="btn-icon-action btn-icon-action--edit" onclick="window.openEditModal(${g.id})" title="Editar garagem">
              <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 20h9"></path>
                <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path>
              </svg>
            </button>
            <button class="btn-icon-action btn-icon-action--delete" onclick="window.openDeleteModal(${g.id})" title="Remover garagem">
              <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="3 6 5 6 21 6"></polyline>
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
              </svg>
            </button>
          </div>
        </td>
      `;

      tableBody.appendChild(tr);
    });
  }

  function renderCards(items) {
    const cardsGrid = document.getElementById('cardsView');
    cardsGrid.innerHTML = '';

    items.forEach((g) => {
      const card = document.createElement('div');
      card.className = 'garage-card';

      const isPaid = g.payment === true || g.payment === 'true' || g.payment === 1;
      const permText = g.permission && g.permission !== '' && g.permission !== 'false' ? g.permission : 'Pública';
      const isPublic = permText === 'Pública';
      const spawnsCount = Array.isArray(g.spawns) ? g.spawns.length : (g.spawn ? 1 : 0);
      const coords = g.marker || { x: g.x, y: g.y, z: g.z };

      card.innerHTML = `
        <div class="garage-card__header">
          <div>
            <span class="badge-id">#${escapeHtml(g.garageId)}</span>
            <h3 style="font-size: 15px; margin-top: 4px; font-weight: 700; color: #fff;">${escapeHtml(g.name || 'Garage')}</h3>
          </div>
          <span class="tag-payment ${isPaid ? 'tag-payment--paid' : 'tag-payment--free'}">
            ${isPaid ? 'Paga' : 'Grátis'}
          </span>
        </div>

        <div class="garage-card__tags">
          <span class="tag-perm ${isPublic ? 'tag-perm--public' : ''}">${escapeHtml(permText)}</span>
          <span class="spawns-count-badge">${spawnsCount} vaga${spawnsCount !== 1 ? 's' : ''}</span>
        </div>

        <div class="garage-card__details">
          <div><strong>Entrada:</strong> <code>${Number(coords.x || 0).toFixed(2)}, ${Number(coords.y || 0).toFixed(2)}, ${Number(coords.z || 0).toFixed(2)}</code></div>
        </div>

        <div class="garage-card__actions">
          <button class="btn btn-secondary btn-sm" onclick="window.teleportToGarage(${g.id})">📍 Teleport</button>
          <button class="btn btn-secondary btn-sm" onclick="window.openEditModal(${g.id})">✏️ Editar</button>
          <button class="btn btn-secondary btn-sm" style="color: var(--rose);" onclick="window.openDeleteModal(${g.id})">🗑️ Excluir</button>
        </div>
      `;

      cardsGrid.appendChild(card);
    });
  }

  // --------------------------------------------------------------------------
  // Modal Management: Create & Edit
  // --------------------------------------------------------------------------
  window.openCreateModal = function () {
    editingGarage = null;
    formMarker = null;
    formSpawns = [];

    document.getElementById('modalTitle').textContent = 'Nova Garagem';
    document.getElementById('btnSaveText').textContent = 'Criar registro';

    const idInput = document.getElementById('garageIdInput');
    idInput.value = '';
    idInput.disabled = false;

    document.getElementById('garageTypeSelect').value = 'Garage';
    document.getElementById('garagePermInput').value = '';
    document.getElementById('garagePaymentCheck').checked = false;

    updatePaymentLabel();
    updatePresetPreview();
    updateMarkerDisplay();
    renderSpawnsList();
    clearIdWarning();

    openModal('garageModal');
  };

  window.openEditModal = function (id) {
    const target = allGarages.find((g) => g.id === id);
    if (!target) return;

    editingGarage = target;
    document.getElementById('modalTitle').textContent = `Editar Garagem #${target.garageId}`;
    document.getElementById('btnSaveText').textContent = 'Salvar alterações';

    const idInput = document.getElementById('garageIdInput');
    idInput.value = target.garageId;
    idInput.disabled = true; // ID imutável na edição

    const typeSelect = document.getElementById('garageTypeSelect');
    if (typeSelect) {
      typeSelect.value = target.name || 'Garage';
      if (!typeSelect.value) {
        // Se for um tipo customizado fora do select
        const opt = document.createElement('option');
        opt.value = target.name;
        opt.textContent = `${target.name} (Customizado)`;
        typeSelect.appendChild(opt);
        typeSelect.value = target.name;
      }
    }

    document.getElementById('garagePermInput').value = target.permission || '';
    const isPaid = target.payment === true || target.payment === 'true' || target.payment === 1;
    document.getElementById('garagePaymentCheck').checked = isPaid;

    formMarker = target.marker ? { ...target.marker } : (target.x ? { x: target.x, y: target.y, z: target.z } : null);
    formSpawns = Array.isArray(target.spawns) && target.spawns.length > 0
      ? target.spawns.map((s) => ({ ...s }))
      : (target.spawn ? [{ ...target.spawn }] : []);

    updatePaymentLabel();
    updatePresetPreview();
    updateMarkerDisplay();
    renderSpawnsList();
    clearIdWarning();

    openModal('garageModal');
  };

  window.fillPerm = function (perm) {
    const input = document.getElementById('garagePermInput');
    if (input) input.value = perm;
  };

  function updatePaymentLabel() {
    const check = document.getElementById('garagePaymentCheck');
    const label = document.getElementById('paymentLabelText');
    const sub = document.getElementById('paymentSubText');
    if (!check || !label || !sub) return;

    if (check.checked) {
      label.textContent = 'Cobrança Ativa';
      label.style.color = 'var(--amber)';
      sub.textContent = 'Taxa de retirada cobrada do jogador ao retirar veículos.';
    } else {
      label.textContent = 'Gratuito';
      label.style.color = 'var(--text)';
      sub.textContent = 'Jogadores não pagam taxa ao retirar veículos nesta garagem.';
    }
  }

  // --------------------------------------------------------------------------
  // In-Game Placement Capture
  // --------------------------------------------------------------------------
  window.captureMarkerPosition = async function () {
    if (isBusy) return;
    isBusy = true;
    showToast('Posicione seu personagem na entrada e pressione ENTER no jogo.', 'info');

    const res = await fetchNui('detectWorldObject', { kind: 'marker' });
    isBusy = false;

    if (res && res.ok && res.data && res.data.coords) {
      formMarker = {
        x: Number(res.data.coords.x),
        y: Number(res.data.coords.y),
        z: Number(res.data.coords.z),
      };
      updateMarkerDisplay();
      showToast('Entrada capturada com sucesso!', 'success');
    } else {
      showToast((res && res.message) || 'Captura de entrada cancelada.', 'info');
    }
  };

  window.clearMarkerPosition = function () {
    formMarker = null;
    updateMarkerDisplay();
  };

  function updateMarkerDisplay() {
    const displayBox = document.getElementById('markerDisplayBox');
    const coordsText = document.getElementById('markerCoordsText');
    const btn = document.getElementById('btnCaptureMarker');
    const btnText = document.getElementById('btnMarkerText');

    if (!displayBox || !btn) return;

    if (formMarker) {
      displayBox.style.display = 'flex';
      coordsText.textContent = `${formMarker.x.toFixed(2)}, ${formMarker.y.toFixed(2)}, ${formMarker.z.toFixed(2)}`;
      btn.classList.add('btn-success-active');
      btnText.textContent = '✓ Entrada capturada';
    } else {
      displayBox.style.display = 'none';
      btn.classList.remove('btn-success-active');
      btnText.textContent = 'Capturar entrada';
    }
  }

  window.captureSpawnPoint = async function () {
    if (isBusy) return;
    isBusy = true;
    showToast('Posicione seu personagem ou veículo na vaga e pressione ENTER no jogo.', 'info');

    const res = await fetchNui('detectWorldObject', { kind: 'spawn' });
    isBusy = false;

    if (res && res.ok && res.data && res.data.coords) {
      const newSp = {
        x: Number(res.data.coords.x),
        y: Number(res.data.coords.y),
        z: Number(res.data.coords.z),
        heading: Number(res.data.coords.heading ?? res.data.heading ?? 0),
      };

      // Impede duplicata exata (< 0.5m de distância)
      const isDuplicate = formSpawns.some((sp) => {
        const dx = sp.x - newSp.x;
        const dy = sp.y - newSp.y;
        const dz = sp.z - newSp.z;
        return (dx * dx + dy * dy + dz * dz) < 0.25;
      });

      if (isDuplicate) {
        showToast('Esta vaga já foi adicionada.', 'error');
        return;
      }

      formSpawns.push(newSp);
      renderSpawnsList();
      showToast(`Vaga #${formSpawns.length} adicionada com sucesso!`, 'success');
    } else {
      showToast((res && res.message) || 'Captura de vaga cancelada.', 'info');
    }
  };

  window.removeSpawnPoint = function (index) {
    if (index >= 0 && index < formSpawns.length) {
      formSpawns.splice(index, 1);
      renderSpawnsList();
    }
  };

  function renderSpawnsList() {
    const container = document.getElementById('spawnsListContainer');
    const countEl = document.getElementById('spawnsCount');
    const alertEl = document.getElementById('multiSpawnAlert');
    const multiCountEl = document.getElementById('multiSpawnCount');

    if (!container) return;

    if (countEl) countEl.textContent = formSpawns.length;

    if (formSpawns.length === 0) {
      container.innerHTML = '<div class="table-empty">Nenhuma vaga capturada. Clique em "Adicionar vaga de spawn".</div>';
      if (alertEl) alertEl.style.display = 'none';
      return;
    }

    if (alertEl && multiCountEl) {
      if (formSpawns.length > 1) {
        alertEl.style.display = 'block';
        multiCountEl.textContent = formSpawns.length;
      } else {
        alertEl.style.display = 'none';
      }
    }

    container.innerHTML = '';
    formSpawns.forEach((sp, idx) => {
      const item = document.createElement('div');
      item.className = 'spawn-item';

      const isMain = idx === 0;
      item.innerHTML = `
        <div class="spawn-item__label">
          <span class="spawn-item__badge ${isMain ? 'spawn-item__badge--main' : ''}">
            Vaga ${String(idx + 1).padStart(2, '0')}${isMain ? ' (Principal)' : ''}
          </span>
          <code>${sp.x.toFixed(2)}, ${sp.y.toFixed(2)}, ${sp.z.toFixed(2)} (H: ${Math.round(sp.heading)}°)</code>
        </div>
        <button type="button" class="btn-icon-danger" onclick="window.removeSpawnPoint(${idx})" title="Remover vaga">✕</button>
      `;

      container.appendChild(item);
    });
  }

  // --------------------------------------------------------------------------
  // Form Validation & Save
  // --------------------------------------------------------------------------
  function clearIdWarning() {
    const warning = document.getElementById('idValidationWarning');
    if (warning) warning.style.display = 'none';
  }

  function validateForm() {
    const idInput = document.getElementById('garageIdInput');
    const warning = document.getElementById('idValidationWarning');
    const rawId = (idInput ? idInput.value : '').trim();

    if (!editingGarage) {
      if (!rawId) {
        showToast('Informe o identificador da garagem.', 'error');
        if (warning) {
          warning.textContent = 'ID obrigatório';
          warning.style.display = 'inline';
        }
        return false;
      }

      if (rawId.length > 10 || !/^[\w-]+$/.test(rawId)) {
        showToast('O ID deve ter até 10 caracteres (letras, números, _ ou -).', 'error');
        if (warning) {
          warning.textContent = 'Formato inválido';
          warning.style.display = 'inline';
        }
        return false;
      }

      // Regra da base legada: se for puramente numérico, DEVE ser >= 10000
      if (/^\d+$/.test(rawId)) {
        const numId = parseInt(rawId, 10);
        if (numId < 10000) {
          showToast('IDs numéricos devem ser 10000 ou maiores para proteger garagens públicas.', 'error');
          if (warning) {
            warning.textContent = 'Deve ser >= 10000';
            warning.style.display = 'inline';
          }
          return false;
        }
      }
    }

    if (!formMarker) {
      showToast('Capture a entrada da garagem antes de salvar.', 'error');
      return false;
    }

    if (formSpawns.length === 0) {
      showToast('Adicione ao menos uma vaga de spawn.', 'error');
      return false;
    }

    // Validação de distância máxima de 100 metros das vagas até a entrada
    for (let i = 0; i < formSpawns.length; i++) {
      const sp = formSpawns[i];
      const dx = sp.x - formMarker.x;
      const dy = sp.y - formMarker.y;
      const dz = sp.z - formMarker.z;
      const distSq = dx * dx + dy * dy + dz * dz;
      if (distSq > 100.0 * 100.0) {
        showToast(`A vaga #${i + 1} está a mais de 100 metros da entrada. Aproxime a vaga.`, 'error');
        return false;
      }
    }

    clearIdWarning();
    return true;
  }

  window.saveGarageForm = async function () {
    if (!validateForm() || isBusy) return;

    isBusy = true;
    const saveBtn = document.getElementById('btnSaveGarage');
    const originalText = saveBtn ? saveBtn.innerHTML : '';
    if (saveBtn) saveBtn.innerHTML = 'Salvando...';

    const idInput = document.getElementById('garageIdInput');
    const typeSelect = document.getElementById('garageTypeSelect');
    const permInput = document.getElementById('garagePermInput');
    const paymentCheck = document.getElementById('garagePaymentCheck');

    const payload = {
      garageId: editingGarage ? editingGarage.garageId : idInput.value.trim(),
      name: typeSelect ? typeSelect.value : 'Garage',
      permission: permInput ? permInput.value.trim() : '',
      payment: paymentCheck ? paymentCheck.checked : false,
      marker: formMarker,
      spawn: formSpawns[0],
      spawns: formSpawns,
    };

    if (editingGarage) {
      payload.id = editingGarage.id;
    }

    const res = await fetchNui('executeCityAction', {
      module: 'garages',
      action: editingGarage ? 'update' : 'create',
      data: payload,
      revision: currentRevision,
    });

    isBusy = false;
    if (saveBtn) saveBtn.innerHTML = originalText;

    if (res && res.ok) {
      showToast(res.message || 'Garagem salva com sucesso!', 'success');
      closeModal('garageModal');
      await loadGarages();
    } else {
      showToast((res && res.message) || 'Erro ao salvar garagem no servidor.', 'error');
    }
  };

  // --------------------------------------------------------------------------
  // Delete Garage (Safe Delete)
  // --------------------------------------------------------------------------
  window.openDeleteModal = function (id) {
    const target = allGarages.find((g) => g.id === id);
    if (!target) return;

    pendingDelete = target;
    document.getElementById('deleteTargetId').textContent = `#${target.garageId}`;
    document.getElementById('deleteTargetName').textContent = `Tipo: ${target.name} (${target.permission || 'Pública'})`;

    openModal('deleteModal');
  };

  window.executeDeleteGarage = async function () {
    if (!pendingDelete || isBusy) return;

    isBusy = true;
    const deleteBtn = document.getElementById('btnConfirmDelete');
    if (deleteBtn) deleteBtn.textContent = 'Removendo...';

    const res = await fetchNui('executeCityAction', {
      module: 'garages',
      action: 'delete',
      data: { id: pendingDelete.id },
      revision: currentRevision,
    });

    isBusy = false;
    if (deleteBtn) deleteBtn.textContent = 'Remover em janela segura';

    if (res && res.ok) {
      showToast(res.message || 'Garagem removida com sucesso.', 'success');
      closeModal('deleteModal');
      pendingDelete = null;
      await loadGarages();
    } else {
      showToast((res && res.message) || 'Erro ao remover garagem.', 'error');
    }
  };

  // --------------------------------------------------------------------------
  // Teleport & Reconcile Actions
  // --------------------------------------------------------------------------
  window.teleportToGarage = async function (id) {
    const target = allGarages.find((g) => g.id === id);
    if (!target) return;

    const coords = target.marker || { x: target.x, y: target.y, z: target.z };
    const heading = target.spawn ? target.spawn.heading : 0;

    showToast(`Teleportando para garagem #${target.garageId}...`, 'info');
    const res = await fetchNui('teleportToCoords', {
      coords: {
        x: coords.x,
        y: coords.y,
        z: coords.z,
        heading: heading,
      },
    });

    if (res && res.ok) {
      showToast('Teleportado para a garagem!', 'success');
    } else {
      showToast((res && res.message) || 'Falha ao teleportar.', 'error');
    }
  };

  window.reconcileGarages = async function () {
    if (isBusy) return;
    isBusy = true;

    showToast('Reconciliando garagens com o servidor...', 'info');
    const res = await fetchNui('executeCityAction', {
      module: 'garages',
      action: 'reload',
      data: {},
    });
    isBusy = false;

    if (res && res.ok) {
      showToast('Garagens recarregadas e sincronizadas!', 'success');
      await loadGarages();
    } else {
      showToast((res && res.message) || 'Erro ao reconciliar garagens.', 'error');
    }
  };

  window.copyToClipboard = function (text) {
    if (!text) return;
    navigator.clipboard?.writeText(text).then(() => {
      showToast(`ID #${text} copiado para a área de transferência!`, 'info');
    }).catch(() => {});
  };

  // --------------------------------------------------------------------------
  // Modal Helpers
  // --------------------------------------------------------------------------
  function openModal(id) {
    const modal = document.getElementById(id);
    if (modal) modal.classList.add('open');
  }

  window.closeModal = function (id) {
    const modal = document.getElementById(id);
    if (modal) modal.classList.remove('open');
  };

  window.setViewMode = function (mode) {
    viewMode = mode;
    const btnTable = document.getElementById('viewModeTable');
    const btnCards = document.getElementById('viewModeCards');

    if (btnTable && btnCards) {
      btnTable.classList.toggle('active', mode === 'table');
      btnCards.classList.toggle('active', mode === 'cards');
    }

    renderGarages();
  };

  window.clearFilters = function () {
    currentFilter = 'all';
    searchQuery = '';
    const searchInput = document.getElementById('searchInput');
    const searchClear = document.getElementById('searchClear');
    if (searchInput) searchInput.value = '';
    if (searchClear) searchClear.style.display = 'none';

    document.querySelectorAll('.chip-btn').forEach((c) => {
      c.classList.toggle('active', c.getAttribute('data-filter') === 'all');
    });

    renderGarages();
  };

  // --------------------------------------------------------------------------
  // Event Listeners Setup
  // --------------------------------------------------------------------------
  function setupListeners() {
    // Search input
    const searchInput = document.getElementById('searchInput');
    const searchClear = document.getElementById('searchClear');
    if (searchInput) {
      searchInput.addEventListener('input', (e) => {
        searchQuery = e.target.value.trim();
        if (searchClear) searchClear.style.display = searchQuery ? 'block' : 'none';
        renderGarages();
      });
    }

    if (searchClear) {
      searchClear.addEventListener('click', () => {
        if (searchInput) {
          searchInput.value = '';
          searchQuery = '';
          searchClear.style.display = 'none';
          renderGarages();
        }
      });
    }

    // Filter Chips
    const chips = document.querySelectorAll('.chip-btn');
    chips.forEach((chip) => {
      chip.addEventListener('click', () => {
        chips.forEach((c) => c.classList.remove('active'));
        chip.classList.add('active');
        currentFilter = chip.getAttribute('data-filter') || 'all';
        renderGarages();
      });
    });

    // Payment switch change
    const paymentCheck = document.getElementById('garagePaymentCheck');
    if (paymentCheck) {
      paymentCheck.addEventListener('change', updatePaymentLabel);
    }

    // Live ID Validation Warning
    const idInput = document.getElementById('garageIdInput');
    const warning = document.getElementById('idValidationWarning');
    if (idInput && warning) {
      idInput.addEventListener('input', (e) => {
        const val = e.target.value.trim();
        if (/^\d+$/.test(val)) {
          const num = parseInt(val, 10);
          if (num < 10000) {
            warning.textContent = 'IDs numéricos devem ser >= 10000';
            warning.style.display = 'inline';
            return;
          }
        }
        warning.style.display = 'none';
      });
    }

    // Keyboard navigation (ESC closes modals)
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeModal('garageModal');
        closeModal('deleteModal');
      }
    });

    // Backdrop click closes modals
    document.querySelectorAll('.modal-overlay').forEach((overlay) => {
      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) {
          overlay.classList.remove('open');
        }
      });
    });
  }

  // --------------------------------------------------------------------------
  // mri_Qadmin Plugin Handshake & Lifecycle
  // --------------------------------------------------------------------------
  function initHostHandshake() {
    const notifyReady = () => {
      if (typeof window !== 'undefined' && window.parent && window.self !== window.top) {
        window.parent.postMessage({ type: 'mri-plugin/ready' }, '*');
      }
    };

    notifyReady();
    setTimeout(notifyReady, 50);
    setTimeout(notifyReady, 150);
    setTimeout(notifyReady, 400);

    window.addEventListener('message', (event) => {
      const data = event.data;
      if (typeof data === 'object' && data !== null && typeof data.type === 'string') {
        if (data.type === 'mri-plugin/init' || data.type === 'mri-plugin/theme-changed') {
          if (data.accentColor) {
            document.documentElement.style.setProperty('--primary', data.accentColor);
            document.documentElement.style.setProperty('--primary-hover', data.accentColor);
            document.documentElement.style.setProperty('--primary-glow', `${data.accentColor}40`);
          }
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // Boot
  // --------------------------------------------------------------------------
  window.addEventListener('DOMContentLoaded', () => {
    initHostHandshake();
    setupListeners();
    loadGarages();
  });
})();
