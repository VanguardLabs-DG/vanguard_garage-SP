/* ==========================================================================
   VANGUARD GARAGE - ADMIN UI JAVASCRIPT
   Clean, modern, unminified logic for managing custom garages
   ========================================================================== */

(function () {
  'use strict';

  // State
  let allGarages = [];
  let catalogTypes = [];
  let currentFilter = 'all'; // 'all' | 'public' | 'job' | 'paid'
  let searchQuery = '';
  let editingGarage = null;
  let garageToDelete = null;

  // Form Temp State during Edit/Create
  let formMarker = null; // { x, y, z }
  let formSpawns = []; // [ { x, y, z, heading } ]

  // --------------------------------------------------------------------------
  // NUI Bridge
  // --------------------------------------------------------------------------
  async function fetchNui(eventName, data = {}) {
    try {
      const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'vanguard_garage';
      const resp = await fetch(`https://${resourceName}/${eventName}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify(data),
      });
      return await resp.json();
    } catch (err) {
      console.error(`[vanguard_garage] NUI callback error (${eventName}):`, err);
      return { ok: false, code: 'fetch_error', message: 'Erro de comunicação NUI.' };
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
      iconSvg = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#3b82f6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>';
    }

    toast.innerHTML = `
      ${iconSvg}
      <span style="flex: 1;">${escapeHtml(message)}</span>
    `;

    container.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(10px)';
      toast.style.transition = 'all 0.2s ease';
      setTimeout(() => toast.remove(), 250);
    }, 4000);
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
  // Data Loading
  // --------------------------------------------------------------------------
  async function loadGarages() {
    const res = await fetchNui('getCityModule', { module: 'garages' });
    if (!res) {
      showToast('Falha ao obter lista de garagens.', 'error');
      return;
    }

    const data = res.data || res;
    allGarages = Array.isArray(data.records) ? data.records : [];
    if (data.catalog && Array.isArray(data.catalog.garageTypes)) {
      catalogTypes = data.catalog.garageTypes;
    }

    updateStats();
    populateTypeSelect();
    renderGarages();
  }

  function updateStats() {
    const totalEl = document.getElementById('totalGaragesCount');
    const headerSub = document.getElementById('headerSubtitle');
    if (totalEl) totalEl.textContent = allGarages.length;
    if (headerSub) {
      headerSub.textContent = `${allGarages.length} garagens cadastradas no servidor`;
    }
  }

  function populateTypeSelect() {
    const select = document.getElementById('garageTypeSelect');
    if (!select) return;

    select.innerHTML = '<option value="Garage">Garage (Pública / Pessoal)</option>';
    catalogTypes.forEach((t) => {
      if (t.value !== 'Garage') {
        const opt = document.createElement('option');
        opt.value = t.value;
        opt.textContent = t.label || t.value;
        select.appendChild(opt);
      }
    });
  }

  // --------------------------------------------------------------------------
  // Rendering
  // --------------------------------------------------------------------------
  function renderGarages() {
    const grid = document.getElementById('garagesGrid');
    if (!grid) return;

    const filtered = allGarages.filter((g) => {
      // 1. Filter Chip
      if (currentFilter === 'public') {
        const isWork = g.permission && g.permission !== '' && g.permission !== 'false';
        if (isWork) return false;
      } else if (currentFilter === 'job') {
        const isWork = g.permission && g.permission !== '' && g.permission !== 'false';
        if (!isWork) return false;
      } else if (currentFilter === 'paid') {
        if (!g.payment) return false;
      }

      // 2. Search query
      if (searchQuery) {
        const q = searchQuery.toLowerCase();
        const idMatch = (g.garageId || '').toLowerCase().includes(q);
        const nameMatch = (g.name || '').toLowerCase().includes(q);
        const permMatch = (g.permission || '').toLowerCase().includes(q);
        if (!idMatch && !nameMatch && !permMatch) return false;
      }

      return true;
    });

    if (filtered.length === 0) {
      grid.innerHTML = `
        <div class="empty-state">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect>
            <line x1="9" y1="3" x2="9" y2="21"></line>
          </svg>
          <h3>Nenhuma garagem encontrada</h3>
          <p>Tente alterar o filtro ou o termo de busca.</p>
        </div>
      `;
      return;
    }

    grid.innerHTML = filtered
      .map((g) => {
        const isJob = g.permission && g.permission !== '' && g.permission !== 'false';
        const isPaid = g.payment === true;
        const spawnsCount = Array.isArray(g.spawns) ? g.spawns.length : (g.spawn ? 1 : 0);

        const markerX = g.marker?.x !== undefined ? g.marker.x.toFixed(2) : (g.x ? Number(g.x).toFixed(2) : '0.00');
        const markerY = g.marker?.y !== undefined ? g.marker.y.toFixed(2) : (g.y ? Number(g.y).toFixed(2) : '0.00');
        const markerZ = g.marker?.z !== undefined ? g.marker.z.toFixed(2) : (g.z ? Number(g.z).toFixed(2) : '0.00');

        return `
          <div class="garage-card" data-id="${g.id}">
            <div class="garage-card__top">
              <div class="garage-card__id-title">
                <span class="garage-id-badge">${escapeHtml(g.garageId || g.id)}</span>
                <span class="garage-card__name">${escapeHtml(g.name || 'Garage')}</span>
              </div>
              <div class="badge-row">
                ${
                  isJob
                    ? `<span class="badge badge-job">Trabalho: ${escapeHtml(g.permission)}</span>`
                    : '<span class="badge badge-public">Pública</span>'
                }
                ${
                  isPaid
                    ? '<span class="badge badge-paid">Taxa Ativa</span>'
                    : '<span class="badge badge-free">Gratuita</span>'
                }
              </div>
            </div>

            <div class="garage-card__details">
              <div class="detail-row">
                <span class="detail-label">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path>
                    <circle cx="12" cy="10" r="3"></circle>
                  </svg>
                  Entrada:
                </span>
                <span class="detail-value">${markerX}, ${markerY}, ${markerZ}</span>
              </div>
              <div class="detail-row">
                <span class="detail-label">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="1" y="3" width="15" height="13"></rect>
                    <polygon points="16 8 20 8 23 11 23 16 16 16 16 8"></polygon>
                    <circle cx="5.5" cy="18.5" r="2.5"></circle>
                    <circle cx="18.5" cy="18.5" r="2.5"></circle>
                  </svg>
                  Vagas de Spawn:
                </span>
                <span class="detail-value">${spawnsCount} vaga${spawnsCount !== 1 ? 's' : ''}</span>
              </div>
            </div>

            <div class="garage-card__footer">
              <button class="card-btn card-btn-teleport" onclick="window.teleportGarage(${g.id})">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"></polygon>
                </svg>
                Teleportar
              </button>
              <button class="card-btn" onclick="window.editGarage(${g.id})">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M12 20h9"></path>
                  <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path>
                </svg>
                Editar
              </button>
              <button class="card-btn card-btn-danger" onclick="window.confirmDeleteGarage(${g.id})">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="3 6 5 6 21 6"></polyline>
                  <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                </svg>
              </button>
            </div>
          </div>
        `;
      })
      .join('');
  }

  // --------------------------------------------------------------------------
  // Modal Actions: Create / Edit
  // --------------------------------------------------------------------------
  window.openCreateModal = function () {
    editingGarage = null;
    formMarker = null;
    formSpawns = [];

    document.getElementById('modalTitle').textContent = 'Criar Nova Garagem';
    document.getElementById('garageIdInput').value = '';
    document.getElementById('garageIdInput').disabled = false;
    document.getElementById('garageTypeSelect').value = 'Garage';
    document.getElementById('garagePermInput').value = '';
    document.getElementById('garagePaymentCheck').checked = false;

    updateMarkerDisplay();
    renderSpawnsList();

    openModal('garageModal');
  };

  window.editGarage = function (id) {
    const garage = allGarages.find((g) => g.id === id);
    if (!garage) return;

    editingGarage = garage;
    formMarker = garage.marker ? { ...garage.marker } : (garage.x ? { x: Number(garage.x), y: Number(garage.y), z: Number(garage.z) } : null);
    formSpawns = Array.isArray(garage.spawns) ? garage.spawns.map((s) => ({ ...s })) : (garage.spawn ? [{ ...garage.spawn }] : []);

    document.getElementById('modalTitle').textContent = `Editar Garagem: ${garage.garageId || garage.id}`;
    document.getElementById('garageIdInput').value = garage.garageId || '';
    document.getElementById('garageIdInput').disabled = true; // Cannot rename ID
    document.getElementById('garageTypeSelect').value = garage.name || 'Garage';
    document.getElementById('garagePermInput').value = garage.permission || '';
    document.getElementById('garagePaymentCheck').checked = !!garage.payment;

    updateMarkerDisplay();
    renderSpawnsList();

    openModal('garageModal');
  };

  function updateMarkerDisplay() {
    const el = document.getElementById('markerCoordsDisplay');
    if (!el) return;
    if (formMarker && formMarker.x !== undefined) {
      el.textContent = `X: ${formMarker.x.toFixed(2)}, Y: ${formMarker.y.toFixed(2)}, Z: ${formMarker.z.toFixed(2)}`;
      el.style.color = '#10b981';
      el.style.borderColor = 'rgba(16, 185, 129, 0.4)';
    } else {
      el.textContent = 'Nenhuma posição definida. Clique em "Capturar Entrada".';
      el.style.color = '#9ca3af';
      el.style.borderColor = 'rgba(255, 255, 255, 0.1)';
    }
  }

  function renderSpawnsList() {
    const listEl = document.getElementById('spawnsListContainer');
    if (!listEl) return;

    if (formSpawns.length === 0) {
      listEl.innerHTML = '<div style="font-size: 12px; color: var(--text-dim); text-align: center; padding: 12px 0;">Nenhuma vaga configurada. Adicione ao menos uma vaga de spawn.</div>';
      return;
    }

    listEl.innerHTML = formSpawns
      .map((sp, idx) => {
        const isMain = idx === 0;
        const x = Number(sp.x || 0).toFixed(2);
        const y = Number(sp.y || 0).toFixed(2);
        const z = Number(sp.z || 0).toFixed(2);
        const h = Math.round(Number(sp.heading || sp.h || 0));

        return `
          <div class="spawn-item">
            <div>
              <strong style="color: #fff; font-size: 12px;">Vaga ${idx + 1} ${isMain ? '<span style="color: #10b981; font-size: 10px;">(Principal)</span>' : ''}</strong>
              <code style="display: block; font-size: 11px; margin-top: 2px;">X: ${x}, Y: ${y}, Z: ${z} (H: ${h}°)</code>
            </div>
            <button type="button" class="spawn-delete-btn" onclick="window.removeSpawnPoint(${idx})" title="Remover vaga">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="3 6 5 6 21 6"></polyline>
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
              </svg>
            </button>
          </div>
        `;
      })
      .join('');
  }

  window.removeSpawnPoint = function (idx) {
    formSpawns.splice(idx, 1);
    renderSpawnsList();
  };

  // --------------------------------------------------------------------------
  // World Object Capture (In-Game Walk & Hit Enter)
  // --------------------------------------------------------------------------
  window.captureMarkerPosition = async function () {
    showToast('Posicione seu personagem na entrada e pressione ENTER no jogo...', 'info');

    const res = await fetchNui('detectWorldObject', { kind: 'position' });
    if (res && res.ok && res.data && res.data.coords) {
      formMarker = {
        x: res.data.coords.x,
        y: res.data.coords.y,
        z: res.data.coords.z,
      };
      updateMarkerDisplay();
      showToast('Posição da entrada capturada com sucesso!', 'success');
    } else {
      showToast(res.message || 'Captura cancelada ou tempo limite esgotado.', 'error');
    }
  };

  window.captureSpawnPoint = async function () {
    showToast('Posicione seu veículo/personagem na vaga, alinhe o ângulo e pressione ENTER...', 'info');

    const res = await fetchNui('detectWorldObject', { kind: 'spawn' });
    if (res && res.ok && res.data && res.data.coords) {
      const newSpawn = {
        x: res.data.coords.x,
        y: res.data.coords.y,
        z: res.data.coords.z,
        heading: res.data.heading || res.data.coords.heading || 0.0,
      };
      formSpawns.push(newSpawn);
      renderSpawnsList();
      showToast(`Vaga de spawn #${formSpawns.length} adicionada com sucesso!`, 'success');
    } else {
      showToast(res.message || 'Captura de vaga cancelada ou tempo limite esgotado.', 'error');
    }
  };

  // --------------------------------------------------------------------------
  // Save Garage (Create or Update)
  // --------------------------------------------------------------------------
  window.saveGarageForm = async function () {
    const garageId = (document.getElementById('garageIdInput').value || '').trim();
    const name = document.getElementById('garageTypeSelect').value || 'Garage';
    const permission = (document.getElementById('garagePermInput').value || '').trim();
    const payment = document.getElementById('garagePaymentCheck').checked;

    if (!garageId) {
      showToast('Por favor, informe o ID da garagem.', 'error');
      return;
    }

    if (!/^[a-zA-Z0-9_\-]+$/.test(garageId)) {
      showToast('O ID deve conter apenas letras, números, _ ou - (sem espaços).', 'error');
      return;
    }

    if (!formMarker) {
      showToast('Você deve capturar o ponto de entrada da garagem.', 'error');
      return;
    }

    if (formSpawns.length === 0) {
      showToast('Você deve adicionar pelo menos 1 vaga de spawn.', 'error');
      return;
    }

    const payload = {
      module: 'garages',
      action: editingGarage ? 'update' : 'create',
      data: {
        id: editingGarage ? editingGarage.id : undefined,
        garageId: garageId,
        name: name,
        permission: permission,
        payment: payment,
        marker: formMarker,
        spawn: formSpawns[0],
        spawns: formSpawns,
      },
    };

    const res = await fetchNui('executeCityAction', payload);
    if (res && res.ok) {
      showToast(editingGarage ? 'Garagem atualizada com sucesso!' : 'Garagem criada com sucesso!', 'success');
      closeModal('garageModal');
      await loadGarages();
    } else {
      showToast((res && res.message) || 'Erro ao salvar garagem.', 'error');
    }
  };

  // --------------------------------------------------------------------------
  // Delete Garage
  // --------------------------------------------------------------------------
  window.confirmDeleteGarage = function (id) {
    const garage = allGarages.find((g) => g.id === id);
    if (!garage) return;

    garageToDelete = garage;
    document.getElementById('deleteGarageIdText').textContent = garage.garageId || garage.id;
    openModal('deleteModal');
  };

  window.executeDeleteGarage = async function () {
    if (!garageToDelete) return;

    const payload = {
      module: 'garages',
      action: 'delete',
      data: {
        id: garageToDelete.id,
      },
    };

    const res = await fetchNui('executeCityAction', payload);
    if (res && res.ok) {
      showToast(`Garagem ${garageToDelete.garageId} removida com sucesso!`, 'success');
      closeModal('deleteModal');
      garageToDelete = null;
      await loadGarages();
    } else {
      showToast((res && res.message) || 'Erro ao excluir garagem.', 'error');
    }
  };

  // --------------------------------------------------------------------------
  // Teleport & Reconcile
  // --------------------------------------------------------------------------
  window.teleportGarage = async function (id) {
    const garage = allGarages.find((g) => g.id === id);
    if (!garage) return;

    const coords = garage.marker || (garage.x ? { x: Number(garage.x), y: Number(garage.y), z: Number(garage.z) } : null);
    if (!coords) {
      showToast('Coordenadas não encontradas para teleportar.', 'error');
      return;
    }

    const res = await fetchNui('teleportToCoords', { coords: coords });
    if (res && res.ok) {
      showToast(`Teleportado para a garagem ${garage.garageId || garage.name}!`, 'success');
    } else {
      showToast((res && res.message) || 'Erro ao teleportar.', 'error');
    }
  };

  window.reconcileGarages = async function () {
    showToast('Sincronizando garagens com o servidor...', 'info');
    const res = await fetchNui('executeCityAction', { module: 'garages', action: 'reload' });
    if (res && res.ok) {
      showToast('Garagens recarregadas com sucesso!', 'success');
      await loadGarages();
    } else {
      showToast((res && res.message) || 'Erro ao sincronizar garagens.', 'error');
    }
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

    // Close modal on Escape
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeModal('garageModal');
        closeModal('deleteModal');
      }
    });

    // Close modal on backdrop click
    document.querySelectorAll('.modal-overlay').forEach((overlay) => {
      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) {
          overlay.classList.remove('open');
        }
      });
    });
  }

  // --------------------------------------------------------------------------
  // Handshake with mri_Qadmin Host
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
